import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/services/insight_notification_detector.dart';
import '../../core/services/notification_service.dart';
import '../../core/utils/budget_risk_detector.dart';
import '../../core/utils/category_overspending_detector.dart';
import '../../core/utils/merchant_pattern_detector.dart';
import '../../domain/models/budget.dart' as bg;
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

// Fixed, single-slot notification ID for the 6:00 PM merchant-pattern /
// saving-opportunity digest — same idea as kNextDaySummaryNotificationId.
const kSixPmDigestNotificationId = 3;

// How long after detecting a new unusual-spending day (or budget risk /
// significant category overspending) to silently deliver its notification,
// instead of showing it the moment it's found.
const kUnusualSpendingDelay = Duration(minutes: 3);

const _kNextDaySummaryTargetKey = 'next_day_summary_target';
const _kNextDaySummarySigKey = 'next_day_summary_sig';
const _kSixPmDigestTargetKey = 'six_pm_digest_target';
const _kSixPmDigestSigKey = 'six_pm_digest_sig';

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
///
/// Checks are run through a [LatestOnlySerialRunner] rather than fired off
/// independently: [_checkForNewInsights] does several `await`s (permission
/// checks, prefs, plugin calls), so if rapid transaction edits each spawned
/// their own concurrent run, an older, now-stale run could finish after a
/// newer one and overwrite its result. The runner guarantees at most one run
/// in flight and always resumes with the latest transaction list.
final insightNotificationWatcherProvider = Provider<void>((ref) {
  final runner = LatestOnlySerialRunner<_InsightWatchInputs>(
      (inputs) => _checkForNewInsights(inputs.transactions, inputs.budgets));

  void maybeCheck() {
    if (!ref.read(isAppUnlockedProvider)) return;
    final transactions = ref.read(transactionsProvider).valueOrNull;
    final budgets = ref.read(budgetsProvider).valueOrNull;
    if (transactions == null || budgets == null) return;
    runner.schedule(_InsightWatchInputs(transactions, budgets));
  }

  ref.listen<AsyncValue<List<tx.Transaction>>>(transactionsProvider,
      (previous, next) {
    maybeCheck();
  }, fireImmediately: true);

  // Budget risk depends on the budget list too, so an add/edit/delete there
  // must also trigger an immediate recalculation, not just transaction edits.
  ref.listen<AsyncValue<List<bg.Budget>>>(budgetsProvider, (previous, next) {
    maybeCheck();
  }, fireImmediately: true);

  ref.listen<bool>(isAppUnlockedProvider, (previous, next) {
    if (next) maybeCheck();
  }, fireImmediately: true);
});

class _InsightWatchInputs {
  final List<tx.Transaction> transactions;
  final List<bg.Budget> budgets;
  const _InsightWatchInputs(this.transactions, this.budgets);
}

/// Runs [handler] for the most recently [schedule]d value, one at a time.
///
/// If a new value is scheduled while [handler] is still running for an
/// older one, that older run is left to finish but no new run starts for
/// it; the next run (once the current one completes) uses only the latest
/// scheduled value, skipping any that were superseded in between. This
/// guarantees handler calls never overlap and that a slow, now-stale call
/// can never finish after — and clobber the effects of — a more recent one.
class LatestOnlySerialRunner<T> {
  LatestOnlySerialRunner(this._handler);

  final Future<void> Function(T value) _handler;
  T? _pending;
  bool _hasPending = false;
  bool _running = false;

  void schedule(T value) {
    _pending = value;
    _hasPending = true;
    if (_running) return;
    _running = true;
    unawaited(_drain());
  }

  Future<void> _drain() async {
    while (_hasPending) {
      _hasPending = false;
      final value = _pending as T;
      _pending = null;
      await _handler(value);
    }
    _running = false;
  }
}

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

  await notifications.cancelInsightNotification(kSixPmDigestNotificationId);
  await prefs.remove(_kSixPmDigestTargetKey);
  await prefs.remove(_kSixPmDigestSigKey);

  const signaturePrefixes = [
    'notified_spikes_',
    'notified_budget_risk_',
    'notified_overspend_',
  ];
  for (final prefix in signaturePrefixes) {
    final keys = prefs.getKeys().where((k) => k.startsWith(prefix)).toList();
    for (final key in keys) {
      for (final sig in prefs.getStringList(key) ?? const <String>[]) {
        await notifications
            .cancelInsightNotification(sig.hashCode & 0x7fffffff);
      }
      await prefs.remove(key);
    }
  }
}

Future<void> _checkForNewInsights(
    List<tx.Transaction> transactions, List<bg.Budget> budgets) async {
  final snapshot = computeCurrentMonthSnapshot(transactions, DateTime.now(),
      budgets: budgets);
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

  // Tier A (~3 min delay): unusual spending, budget risk, significant
  // category overspending.
  await _scheduleNewSpikes(notifications, prefs, monthKey, snapshot);
  await _scheduleNewBudgetRisks(notifications, prefs, monthKey, snapshot);
  await _scheduleNewCategoryOverspend(notifications, prefs, monthKey, snapshot);
  // Tier B (6:00 PM): merchant patterns, saving opportunity.
  await _scheduleSixPmDigest(notifications, prefs, snapshot);
  // Tier C (11:00 AM next day): forecast, pace, category change.
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

/// Signatures that were previously scheduled but are no longer present in
/// the latest recalculation — e.g. the transaction behind a spike/budget-risk
/// /overspend signature was edited or deleted before its delayed
/// notification fired. Callers cancel the pending notification for each of
/// these and drop it from the persisted signature set, rather than let it
/// fire with stale content.
Set<String> staleSignaturesToCancel({
  required Set<String> alreadyScheduled,
  required Set<String> currentSignatures,
}) =>
    alreadyScheduled.difference(currentSignatures);

// Unusual-spending alerts aren't shown the moment they're detected — they're
// silently scheduled ~3 minutes later so the user isn't interrupted mid-entry.
// Signatures are recorded as soon as a spike is scheduled (not when it later
// fires) so re-running this on the next transaction change never re-schedules
// the same day twice. Any previously-scheduled day that's no longer flagged
// (e.g. the spike's transaction was edited/deleted) has its pending
// notification cancelled instead of being left to fire.
Future<void> _scheduleNewSpikes(
  NotificationService notifications,
  SharedPreferences prefs,
  String monthKey,
  SpendingSnapshot snapshot,
) async {
  final key = 'notified_spikes_$monthKey';
  final seen = (prefs.getStringList(key) ?? <String>[]).toSet();

  final currentSignatures = snapshot.spikes
      .map((s) => s.date.toIso8601String().substring(0, 10))
      .toSet();
  final stale = staleSignaturesToCancel(
      alreadyScheduled: seen, currentSignatures: currentSignatures);
  for (final sig in stale) {
    await notifications.cancelInsightNotification(sig.hashCode & 0x7fffffff);
  }
  seen.removeAll(stale);

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

  if (result.notifications.isNotEmpty || stale.isNotEmpty) {
    await prefs.setStringList(key, result.updatedSignatures.toList());
  }
}

/// A single budget-risk notification to schedule (not show immediately).
class BudgetRiskNotificationToSchedule {
  final int id;
  final String title;
  final String body;
  final DateTime scheduledDate;
  final String signature;
  const BudgetRiskNotificationToSchedule({
    required this.id,
    required this.title,
    required this.body,
    required this.scheduledDate,
    required this.signature,
  });
}

class NewBudgetRisksToSchedule {
  final List<BudgetRiskNotificationToSchedule> notifications;
  final Set<String> updatedSignatures;
  const NewBudgetRisksToSchedule(
      {required this.notifications, required this.updatedSignatures});
}

String _budgetRiskSignature(String category) => 'budget_risk:$category';

/// Pure decision logic for the budget-risk tier (Tier A, ~3 min delay):
/// mirrors [computeNewSpikesToSchedule] — keyed by category rather than by
/// day, since a budget risk is a per-category-per-month concept.
NewBudgetRisksToSchedule computeNewBudgetRisksToSchedule({
  required List<BudgetRisk> risks,
  required Set<String> alreadyScheduled,
  required DateTime now,
}) {
  final seen = {...alreadyScheduled};
  final toSchedule = <BudgetRiskNotificationToSchedule>[];

  for (final r in risks) {
    final sig = _budgetRiskSignature(r.category);
    if (!seen.add(sig)) continue;
    final dateSuffix = r.exceedDate != null
        ? ', around ${_dowLabel(r.exceedDate!)} ${r.exceedDate!.day} ${_monthNames[r.exceedDate!.month - 1]}'
        : '';
    toSchedule.add(BudgetRiskNotificationToSchedule(
      id: sig.hashCode & 0x7fffffff,
      title: 'Budget risk',
      body:
          '${r.category} may exceed its budget by ${_rm(r.overageAmount)} this month$dateSuffix.',
      scheduledDate: now.add(kUnusualSpendingDelay),
      signature: sig,
    ));
  }

  return NewBudgetRisksToSchedule(
      notifications: toSchedule, updatedSignatures: seen);
}

Future<void> _scheduleNewBudgetRisks(
  NotificationService notifications,
  SharedPreferences prefs,
  String monthKey,
  SpendingSnapshot snapshot,
) async {
  final key = 'notified_budget_risk_$monthKey';
  final seen = (prefs.getStringList(key) ?? <String>[]).toSet();

  final currentSignatures = snapshot.budgetRisks
      .map((r) => _budgetRiskSignature(r.category))
      .toSet();
  final stale = staleSignaturesToCancel(
      alreadyScheduled: seen, currentSignatures: currentSignatures);
  for (final sig in stale) {
    await notifications.cancelInsightNotification(sig.hashCode & 0x7fffffff);
  }
  seen.removeAll(stale);

  final result = computeNewBudgetRisksToSchedule(
      risks: snapshot.budgetRisks, alreadyScheduled: seen, now: DateTime.now());
  for (final n in result.notifications) {
    await notifications.scheduleInsightNotification(
      id: n.id,
      title: n.title,
      body: n.body,
      scheduledDate: n.scheduledDate,
    );
  }

  if (result.notifications.isNotEmpty || stale.isNotEmpty) {
    await prefs.setStringList(key, result.updatedSignatures.toList());
  }
}

/// A single category-overspending notification to schedule (not show
/// immediately).
class CategoryOverspendNotificationToSchedule {
  final int id;
  final String title;
  final String body;
  final DateTime scheduledDate;
  final String signature;
  const CategoryOverspendNotificationToSchedule({
    required this.id,
    required this.title,
    required this.body,
    required this.scheduledDate,
    required this.signature,
  });
}

class NewCategoryOverspendToSchedule {
  final List<CategoryOverspendNotificationToSchedule> notifications;
  final Set<String> updatedSignatures;
  const NewCategoryOverspendToSchedule(
      {required this.notifications, required this.updatedSignatures});
}

String _overspendSignature(String category) => 'overspend:$category';

/// Pure decision logic for the significant-category-overspending tier
/// (Tier A, ~3 min delay): mirrors [computeNewSpikesToSchedule], keyed by
/// category.
NewCategoryOverspendToSchedule computeNewCategoryOverspendToSchedule({
  required List<CategoryOverspend> overspends,
  required Set<String> alreadyScheduled,
  required DateTime now,
}) {
  final seen = {...alreadyScheduled};
  final toSchedule = <CategoryOverspendNotificationToSchedule>[];

  for (final o in overspends) {
    final sig = _overspendSignature(o.category);
    if (!seen.add(sig)) continue;
    toSchedule.add(CategoryOverspendNotificationToSchedule(
      id: sig.hashCode & 0x7fffffff,
      title: 'Category spending up',
      body:
          '${o.category} spending is ${o.pctIncrease.round()}% higher than this time last month.',
      scheduledDate: now.add(kUnusualSpendingDelay),
      signature: sig,
    ));
  }

  return NewCategoryOverspendToSchedule(
      notifications: toSchedule, updatedSignatures: seen);
}

Future<void> _scheduleNewCategoryOverspend(
  NotificationService notifications,
  SharedPreferences prefs,
  String monthKey,
  SpendingSnapshot snapshot,
) async {
  final key = 'notified_overspend_$monthKey';
  final seen = (prefs.getStringList(key) ?? <String>[]).toSet();

  final currentSignatures = snapshot.categoryOverspends
      .map((o) => _overspendSignature(o.category))
      .toSet();
  final stale = staleSignaturesToCancel(
      alreadyScheduled: seen, currentSignatures: currentSignatures);
  for (final sig in stale) {
    await notifications.cancelInsightNotification(sig.hashCode & 0x7fffffff);
  }
  seen.removeAll(stale);

  final result = computeNewCategoryOverspendToSchedule(
      overspends: snapshot.categoryOverspends,
      alreadyScheduled: seen,
      now: DateTime.now());
  for (final n in result.notifications) {
    await notifications.scheduleInsightNotification(
      id: n.id,
      title: n.title,
      body: n.body,
      scheduledDate: n.scheduledDate,
    );
  }

  if (result.notifications.isNotEmpty || stale.isNotEmpty) {
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

/// Builds one line per available result (projected month-end spending,
/// spending pace, leading-category change — in that order, only the ones
/// that are non-null). Empty when nothing is eligible to report yet — or,
/// after a recalculation, no longer eligible (e.g. the transaction behind
/// it was edited or deleted).
List<String> buildNextDaySummaryLines(SpendingSnapshot snapshot) {
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
  return lines;
}

/// Pure decision logic for requirement 3 (combined next-day summary):
/// targets delivery for 11:00 local time on the day after [now], and
/// compares against [storedTargetSignature]/[storedContentSignature]
/// (whatever was persisted for the last scheduled summary) to decide
/// whether anything needs to change. Returns `null` when there's nothing
/// available to say yet ([buildNextDaySummaryLines] is empty), or when the
/// would-be notification is identical (same target day and content) to the
/// one already pending — this is what prevents re-scheduling (and
/// duplicate-notifying) on every minor recheck.
NextDaySummaryUpdate? computeNextDaySummaryUpdate({
  required SpendingSnapshot snapshot,
  required DateTime now,
  String? storedTargetSignature,
  String? storedContentSignature,
}) {
  final lines = buildNextDaySummaryLines(snapshot);
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

/// What [_scheduleNextDaySummary] should do about the pending next-day
/// summary notification, for a given recalculation.
enum NextDaySummaryAction {
  /// Nothing eligible, and nothing was pending either — no-op.
  none,

  /// Recalculation no longer has anything eligible to report, but something
  /// was previously scheduled — cancel it and clear its stored signatures.
  clear,

  /// New or changed content — (re)schedule, replacing whatever was pending.
  replace,
}

/// Result of [decideNextDaySummaryAction]: pure decision logic paired with
/// the [NextDaySummaryUpdate] to apply when [action] is
/// [NextDaySummaryAction.replace] (`null` otherwise).
class NextDaySummaryDecision {
  final NextDaySummaryAction action;
  final NextDaySummaryUpdate? update;
  const NextDaySummaryDecision._(this.action, this.update);
  const NextDaySummaryDecision.none() : this._(NextDaySummaryAction.none, null);
  const NextDaySummaryDecision.clear()
      : this._(NextDaySummaryAction.clear, null);
  NextDaySummaryDecision.replace(NextDaySummaryUpdate update)
      : this._(NextDaySummaryAction.replace, update);
}

/// Pure decision logic for requirement 3 (combined next-day summary),
/// covering all three outcomes a recalculation can produce:
///  - nothing eligible now, and nothing was pending -> [NextDaySummaryAction.none]
///  - nothing eligible now, but something *was* pending -> [NextDaySummaryAction.clear]
///    (the previously scheduled summary must be cancelled and its stored
///    signatures cleared, rather than left to fire with stale content)
///  - eligible content that differs from what's pending (by target day or
///    text) -> [NextDaySummaryAction.replace]
///  - eligible content identical to what's already pending -> [NextDaySummaryAction.none]
///    (do not reschedule)
NextDaySummaryDecision decideNextDaySummaryAction({
  required SpendingSnapshot snapshot,
  required DateTime now,
  String? storedTargetSignature,
  String? storedContentSignature,
}) {
  if (buildNextDaySummaryLines(snapshot).isEmpty) {
    final hadPending =
        storedTargetSignature != null || storedContentSignature != null;
    return hadPending
        ? const NextDaySummaryDecision.clear()
        : const NextDaySummaryDecision.none();
  }

  final update = computeNextDaySummaryUpdate(
    snapshot: snapshot,
    now: now,
    storedTargetSignature: storedTargetSignature,
    storedContentSignature: storedContentSignature,
  );
  return update == null
      ? const NextDaySummaryDecision.none()
      : NextDaySummaryDecision.replace(update);
}

// Combines whichever of {forecast, pace, leading-category change} are
// currently available into a single expandable notification, scheduled for
// 11:00 AM the next day rather than sent immediately. If the content that
// would be shown changes before that delivery time, the pending notification
// is replaced in place (same fixed id) rather than stacking a second one. If
// recalculation no longer has anything eligible to report, whatever was
// pending is cancelled instead of being left to fire with stale content.
Future<void> _scheduleNextDaySummary(
  NotificationService notifications,
  SharedPreferences prefs,
  SpendingSnapshot snapshot,
) async {
  final decision = decideNextDaySummaryAction(
    snapshot: snapshot,
    now: DateTime.now(),
    storedTargetSignature: prefs.getString(_kNextDaySummaryTargetKey),
    storedContentSignature: prefs.getString(_kNextDaySummarySigKey),
  );

  switch (decision.action) {
    case NextDaySummaryAction.none:
      return;
    case NextDaySummaryAction.clear:
      await notifications
          .cancelInsightNotification(kNextDaySummaryNotificationId);
      await prefs.remove(_kNextDaySummaryTargetKey);
      await prefs.remove(_kNextDaySummarySigKey);
      return;
    case NextDaySummaryAction.replace:
      final update = decision.update!;
      await notifications
          .cancelInsightNotification(kNextDaySummaryNotificationId);
      await notifications.scheduleInsightNotification(
        id: kNextDaySummaryNotificationId,
        title: 'Your financial summary',
        body: update.lines.join('\n'),
        scheduledDate: update.scheduledDate,
        expandable: true,
      );
      await prefs.setString(_kNextDaySummaryTargetKey, update.targetSignature);
      await prefs.setString(_kNextDaySummarySigKey, update.contentSignature);
      return;
  }
}

/// The 6:00 PM merchant-pattern / saving-opportunity digest to (re)schedule,
/// or `null` when nothing needs to change.
class SixPmDigestUpdate {
  final DateTime scheduledDate; // the next 6:00 PM occurrence after `now`.
  final List<String> lines;
  final String targetSignature;
  final String contentSignature;
  const SixPmDigestUpdate({
    required this.scheduledDate,
    required this.lines,
    required this.targetSignature,
    required this.contentSignature,
  });
}

/// Builds one line per merchant pattern (repeated-this-month or recurring)
/// plus one for a saving opportunity, in that order. Empty when nothing is
/// eligible yet — or no longer eligible after a recalculation.
List<String> buildSixPmDigestLines(SpendingSnapshot snapshot) {
  final lines = <String>[];
  for (final p in snapshot.merchantPatterns) {
    if (p.type == MerchantPatternType.repeated) {
      lines.add(
          'You spent ${_rm(p.amount)} at ${p.merchant} across ${p.count} transactions this month.');
    } else {
      lines.add(
          '${_rm(p.amount)} to ${p.merchant} appears to be a monthly recurring payment.');
    }
  }
  if (snapshot.savingOpportunity != null) {
    lines.add(
        'At your current pace, you could spend about ${_rm(snapshot.savingOpportunity!.estimatedSavings)} less by month end.');
  }
  return lines;
}

/// The next 6:00 PM occurrence strictly after [now] — today's if [now] is
/// still before 6 PM, otherwise tomorrow's.
DateTime nextSixPm(DateTime now) {
  final today6pm = DateTime(now.year, now.month, now.day, 18, 0);
  return now.isBefore(today6pm)
      ? today6pm
      : DateTime(now.year, now.month, now.day + 1, 18, 0);
}

/// Pure decision logic for Tier B (6:00 PM digest): targets the next 6:00 PM
/// occurrence and compares against [storedTargetSignature]/
/// [storedContentSignature] to decide whether anything needs to change —
/// mirrors [computeNextDaySummaryUpdate].
SixPmDigestUpdate? compute6pmDigestUpdate({
  required SpendingSnapshot snapshot,
  required DateTime now,
  String? storedTargetSignature,
  String? storedContentSignature,
}) {
  final lines = buildSixPmDigestLines(snapshot);
  if (lines.isEmpty) return null;

  final target = nextSixPm(now);
  final targetSignature = target.toIso8601String().substring(0, 16);
  final contentSignature = lines.join('');
  if (storedTargetSignature == targetSignature &&
      storedContentSignature == contentSignature) {
    return null;
  }

  return SixPmDigestUpdate(
    scheduledDate: target,
    lines: lines,
    targetSignature: targetSignature,
    contentSignature: contentSignature,
  );
}

/// What [_scheduleSixPmDigest] should do about the pending digest
/// notification, for a given recalculation — mirrors
/// [NextDaySummaryAction]/[decideNextDaySummaryAction].
enum SixPmDigestAction { none, clear, replace }

class SixPmDigestDecision {
  final SixPmDigestAction action;
  final SixPmDigestUpdate? update;
  const SixPmDigestDecision._(this.action, this.update);
  const SixPmDigestDecision.none() : this._(SixPmDigestAction.none, null);
  const SixPmDigestDecision.clear() : this._(SixPmDigestAction.clear, null);
  SixPmDigestDecision.replace(SixPmDigestUpdate update)
      : this._(SixPmDigestAction.replace, update);
}

SixPmDigestDecision decideSixPmDigestAction({
  required SpendingSnapshot snapshot,
  required DateTime now,
  String? storedTargetSignature,
  String? storedContentSignature,
}) {
  if (buildSixPmDigestLines(snapshot).isEmpty) {
    final hadPending =
        storedTargetSignature != null || storedContentSignature != null;
    return hadPending
        ? const SixPmDigestDecision.clear()
        : const SixPmDigestDecision.none();
  }

  final update = compute6pmDigestUpdate(
    snapshot: snapshot,
    now: now,
    storedTargetSignature: storedTargetSignature,
    storedContentSignature: storedContentSignature,
  );
  return update == null
      ? const SixPmDigestDecision.none()
      : SixPmDigestDecision.replace(update);
}

// Combines whichever of {merchant patterns, saving opportunity} are
// currently available into a single expandable notification, scheduled for
// the next 6:00 PM. Same replace-in-place / cancel-when-no-longer-eligible
// behavior as the next-day summary.
Future<void> _scheduleSixPmDigest(
  NotificationService notifications,
  SharedPreferences prefs,
  SpendingSnapshot snapshot,
) async {
  final decision = decideSixPmDigestAction(
    snapshot: snapshot,
    now: DateTime.now(),
    storedTargetSignature: prefs.getString(_kSixPmDigestTargetKey),
    storedContentSignature: prefs.getString(_kSixPmDigestSigKey),
  );

  switch (decision.action) {
    case SixPmDigestAction.none:
      return;
    case SixPmDigestAction.clear:
      await notifications.cancelInsightNotification(kSixPmDigestNotificationId);
      await prefs.remove(_kSixPmDigestTargetKey);
      await prefs.remove(_kSixPmDigestSigKey);
      return;
    case SixPmDigestAction.replace:
      final update = decision.update!;
      await notifications.cancelInsightNotification(kSixPmDigestNotificationId);
      await notifications.scheduleInsightNotification(
        id: kSixPmDigestNotificationId,
        title: 'Spending patterns',
        body: update.lines.join('\n'),
        scheduledDate: update.scheduledDate,
        expandable: true,
      );
      await prefs.setString(_kSixPmDigestTargetKey, update.targetSignature);
      await prefs.setString(_kSixPmDigestSigKey, update.contentSignature);
      return;
  }
}
