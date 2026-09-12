import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/services/insight_notification_detector.dart';
import '../../core/services/notification_service.dart';
import '../../domain/models/transaction.dart' as tx;
import 'app_providers.dart';

const _monthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec'
];
const _dowNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
String _dowLabel(DateTime d) => _dowNames[d.weekday - 1];
String _rm(num v) => 'RM${v.toStringAsFixed(0)}';

// Fixed, single-slot notification ID for the next-day financial summary —
// analogous to how the Daily Expense Reminder always uses id 0. Re-scheduling
// under this id replaces whatever summary was previously pending.
const kNextDaySummaryNotificationId = 2;

// How long after detecting a new unusual-spending day to silently deliver its
// notification, instead of showing it the moment it's found.
const kUnusualSpendingDelay = Duration(minutes: 3);

const _kNextDaySummaryTargetKey = 'next_day_summary_target';
const _kNextDaySummarySigKey = 'next_day_summary_sig';

/// Watches [transactionsProvider] for the lifetime of the app and, whenever
/// the app is unlocked, checks for new unusual-spending days and updated
/// forecast/pace/category insights for the current month. Read once (e.g.
/// `ref.watch(insightNotificationWatcherProvider)`) near the app root so it
/// stays alive regardless of which screen is showing.
///
/// Re-analyzes on every [transactionsProvider] change and on every
/// lock-to-unlock transition (so the first data load after unlocking is
/// covered even if the transaction list itself didn't change while locked).
/// Never analyzes while [isAppUnlockedProvider] is false.
final insightNotificationWatcherProvider = Provider<void>((ref) {
  void maybeCheck() {
    if (!ref.read(isAppUnlockedProvider)) return;
    final list = ref.read(transactionsProvider).valueOrNull;
    if (list == null) return;
    _checkForNewInsights(list);
  }

  ref.listen<AsyncValue<List<tx.Transaction>>>(transactionsProvider,
      (previous, next) {
    maybeCheck();
  }, fireImmediately: true);

  ref.listen<bool>(isAppUnlockedProvider, (previous, next) {
    if (next) maybeCheck();
  }, fireImmediately: true);
});

/// Clears all persisted insight-notification state (unusual-spending
/// signatures, next-day summary target/content) and cancels any
/// notifications already scheduled under it. Call this when the underlying
/// transaction data has been wiped (e.g. Settings' "Delete All Data") so
/// stale schedules referencing deleted transactions don't fire.
Future<void> clearInsightNotificationState() async {
  final prefs = await SharedPreferences.getInstance();
  final notifications = NotificationService();

  await notifications.cancelInsightNotification(kNextDaySummaryNotificationId);
  await prefs.remove(_kNextDaySummaryTargetKey);
  await prefs.remove(_kNextDaySummarySigKey);

  final spikeKeys =
      prefs.getKeys().where((k) => k.startsWith('notified_spikes_')).toList();
  for (final key in spikeKeys) {
    for (final sig in prefs.getStringList(key) ?? const <String>[]) {
      await notifications.cancelInsightNotification(sig.hashCode & 0x7fffffff);
    }
    await prefs.remove(key);
  }
}

Future<void> _checkForNewInsights(List<tx.Transaction> transactions) async {
  final snapshot = computeCurrentMonthSnapshot(transactions, DateTime.now());
  if (snapshot == null) return;

  final notifications = NotificationService();
  final permissions = await notifications.checkPermissions();
  if (!permissions.notification) {
    final granted = await notifications.requestNotificationPermission();
    if (!granted) return;
  }

  final prefs = await SharedPreferences.getInstance();
  final now = DateTime.now();
  final monthKey = '${now.year}-${now.month.toString().padLeft(2, '0')}';

  await _scheduleNewSpikes(notifications, prefs, monthKey, snapshot);
  await _scheduleNextDaySummary(notifications, prefs, snapshot);
}

/// A single unusual-spending notification to schedule (not show immediately).
class SpikeNotificationToSchedule {
  final int id;
  final String title;
  final String body;
  final DateTime scheduledDate;
  const SpikeNotificationToSchedule({
    required this.id,
    required this.title,
    required this.body,
    required this.scheduledDate,
  });
}

/// Pure decision logic for requirement 2 (delayed unusual-spending alerts).
///
/// Compares [snapshot]'s spikes against [alreadyScheduled] (spike-date
/// signatures already scheduled this month) and returns the ones that are
/// new, each due [kUnusualSpendingDelay] after [now], plus the signature set
/// updated to include them. Callers are responsible for actually scheduling
/// the notifications and persisting the updated signatures — this function
/// has no side effects, which is what makes the 3-minute delay and the
/// duplicate-prevention rule independently testable.
class NewSpikesToSchedule {
  final List<SpikeNotificationToSchedule> notifications;
  final Set<String> updatedSignatures;
  const NewSpikesToSchedule(
      {required this.notifications, required this.updatedSignatures});
}

NewSpikesToSchedule computeNewSpikesToSchedule({
  required SpendingSnapshot snapshot,
  required Set<String> alreadyScheduled,
  required DateTime now,
}) {
  final seen = {...alreadyScheduled};
  final toSchedule = <SpikeNotificationToSchedule>[];

  for (final s in snapshot.spikes) {
    final sig = s.date.toIso8601String().substring(0, 10);
    if (!seen.add(sig)) continue;
    final multiplier = snapshot.avgDay > 0 ? s.amount / snapshot.avgDay : 0.0;
    toSchedule.add(SpikeNotificationToSchedule(
      id: sig.hashCode & 0x7fffffff,
      title: 'Unusual spending detected',
      body:
          '${_dowLabel(s.date)}, ${s.date.day} ${_monthNames[s.date.month - 1]} — ${_rm(s.amount)}, '
          'about ${multiplier.toStringAsFixed(1)}x your average. Mostly ${s.topCategory.toLowerCase()}.',
      scheduledDate: now.add(kUnusualSpendingDelay),
    ));
  }

  return NewSpikesToSchedule(
      notifications: toSchedule, updatedSignatures: seen);
}

// Unusual-spending alerts aren't shown the moment they're detected — they're
// silently scheduled ~3 minutes later so the user isn't interrupted mid-entry.
// Signatures are recorded as soon as a spike is scheduled (not when it later
// fires) so re-running this on the next transaction change never re-schedules
// the same day twice.
Future<void> _scheduleNewSpikes(
  NotificationService notifications,
  SharedPreferences prefs,
  String monthKey,
  SpendingSnapshot snapshot,
) async {
  final key = 'notified_spikes_$monthKey';
  final seen = (prefs.getStringList(key) ?? <String>[]).toSet();

  final result = computeNewSpikesToSchedule(
      snapshot: snapshot, alreadyScheduled: seen, now: DateTime.now());
  for (final n in result.notifications) {
    await notifications.scheduleInsightNotification(
      id: n.id,
      title: n.title,
      body: n.body,
      scheduledDate: n.scheduledDate,
    );
  }

  if (result.notifications.isNotEmpty) {
    await prefs.setStringList(key, result.updatedSignatures.toList());
  }
}

/// The next-day financial summary to (re)schedule, or `null` when nothing
/// needs to change (no results are available yet, or the pending
/// notification already matches this content).
class NextDaySummaryUpdate {
  final DateTime scheduledDate; // always 11:00 the day after `now`.
  final List<String> lines;
  final String targetSignature;
  final String contentSignature;
  const NextDaySummaryUpdate({
    required this.scheduledDate,
    required this.lines,
    required this.targetSignature,
    required this.contentSignature,
  });
}

/// Pure decision logic for requirement 3 (combined next-day summary).
///
/// Builds one line per available result (projected month-end spending,
/// spending pace, leading-category change — in that order, only the ones
/// that are non-null), targets delivery for 11:00 local time on the day
/// after [now], and compares against [storedTargetSignature]/
/// [storedContentSignature] (whatever was persisted for the last scheduled
/// summary) to decide whether anything needs to change. Returns `null` when
/// there's nothing available to say yet, or when the would-be notification
/// is identical to the one already pending — this is what prevents
/// re-scheduling (and duplicate-notifying) on every minor recheck.
NextDaySummaryUpdate? computeNextDaySummaryUpdate({
  required SpendingSnapshot snapshot,
  required DateTime now,
  String? storedTargetSignature,
  String? storedContentSignature,
}) {
  final lines = <String>[];
  if (snapshot.forecastProjected != null) {
    lines.add(
        'Projected month-end spending: ${_rm(snapshot.forecastProjected!)}.');
  }
  if (snapshot.pacePct != null) {
    final up = snapshot.pacePct! >= 0;
    lines.add('Spending pace: ${snapshot.pacePct!.abs().toStringAsFixed(0)}% '
        '${up ? 'higher' : 'lower'} than earlier this month.');
  }
  if (snapshot.categoryChange != null) {
    lines.add('Your leading spending category changed from '
        '${snapshot.categoryChange!.previous} to ${snapshot.categoryChange!.current}.');
  }
  if (lines.isEmpty) return null;

  final target = DateTime(now.year, now.month, now.day + 1, 11, 0);
  final targetSignature = target.toIso8601String().substring(0, 10);
  final contentSignature = lines.join('');
  if (storedTargetSignature == targetSignature &&
      storedContentSignature == contentSignature) {
    return null;
  }

  return NextDaySummaryUpdate(
    scheduledDate: target,
    lines: lines,
    targetSignature: targetSignature,
    contentSignature: contentSignature,
  );
}

// Combines whichever of {forecast, pace, leading-category change} are
// currently available into a single expandable notification, scheduled for
// 11:00 AM the next day rather than sent immediately. If the content that
// would be shown changes before that delivery time, the pending notification is
// replaced in place (same fixed id) rather than stacking a second one.
Future<void> _scheduleNextDaySummary(
  NotificationService notifications,
  SharedPreferences prefs,
  SpendingSnapshot snapshot,
) async {
  final update = computeNextDaySummaryUpdate(
    snapshot: snapshot,
    now: DateTime.now(),
    storedTargetSignature: prefs.getString(_kNextDaySummaryTargetKey),
    storedContentSignature: prefs.getString(_kNextDaySummarySigKey),
  );
  if (update == null) return;

  await notifications.cancelInsightNotification(kNextDaySummaryNotificationId);
  await notifications.scheduleInsightNotification(
    id: kNextDaySummaryNotificationId,
    title: 'Your financial summary',
    body: update.lines.join('\n'),
    scheduledDate: update.scheduledDate,
    expandable: true,
  );
  await prefs.setString(_kNextDaySummaryTargetKey, update.targetSignature);
  await prefs.setString(_kNextDaySummarySigKey, update.contentSignature);
}
