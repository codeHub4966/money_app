import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/services/insight_notification_detector.dart';
import '../../core/services/notification_service.dart';
import '../../domain/models/transaction.dart' as tx;
import 'app_providers.dart';

const _monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _dowNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
String _dowLabel(DateTime d) => _dowNames[d.weekday - 1];
String _rm(num v) => 'RM${v.toStringAsFixed(0)}';

/// Watches [transactionsProvider] for the lifetime of the app and fires a
/// local notification the first time it sees a new unusual-spending day or a
/// meaningfully-changed smart insight for the current month. Read once (e.g.
/// `ref.watch(insightNotificationWatcherProvider)`) near the app root so it
/// stays alive regardless of which screen is showing.
final insightNotificationWatcherProvider = Provider<void>((ref) {
  ref.listen<AsyncValue<List<tx.Transaction>>>(transactionsProvider, (previous, next) {
    final list = next.valueOrNull;
    if (list == null) return;
    _checkForNewInsights(list);
  }, fireImmediately: true);
});

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

  await _notifyNewSpikes(notifications, prefs, monthKey, snapshot);
  await _notifyUpdatedInsights(notifications, prefs, monthKey, snapshot);
}

Future<void> _notifyNewSpikes(
  NotificationService notifications,
  SharedPreferences prefs,
  String monthKey,
  SpendingSnapshot snapshot,
) async {
  final key = 'notified_spikes_$monthKey';
  final seen = (prefs.getStringList(key) ?? <String>[]).toSet();
  var changed = false;

  for (final s in snapshot.spikes) {
    final sig = s.date.toIso8601String().substring(0, 10);
    if (!seen.add(sig)) continue;
    changed = true;
    final multiplier = snapshot.avgDay > 0 ? s.amount / snapshot.avgDay : 0.0;
    await notifications.showInsightNotification(
      id: sig.hashCode & 0x7fffffff,
      title: 'Unusual spending detected',
      body: '${_dowLabel(s.date)}, ${s.date.day} ${_monthNames[s.date.month - 1]} — ${_rm(s.amount)}, '
          'about ${multiplier.toStringAsFixed(1)}x your average. Mostly ${s.topCategory.toLowerCase()}.',
    );
  }

  if (changed) await prefs.setStringList(key, seen.toList());
}

Future<void> _notifyUpdatedInsights(
  NotificationService notifications,
  SharedPreferences prefs,
  String monthKey,
  SpendingSnapshot snapshot,
) async {
  final key = 'notified_insight_sigs_$monthKey';
  final seen = (prefs.getStringList(key) ?? <String>[]).toSet();
  var changed = false;

  Future<void> notifyIfNew(String signature, String body) async {
    if (!seen.add(signature)) return;
    changed = true;
    await notifications.showInsightNotification(
      id: signature.hashCode & 0x7fffffff,
      title: 'New spending insight',
      body: body,
    );
  }

  // Bucketed to the nearest 5%/RM10 so tiny fluctuations from one more
  // transaction don't trigger a fresh notification every time.
  if (snapshot.pacePct != null) {
    final up = snapshot.pacePct! >= 0;
    await notifyIfNew(
      'pace:${(snapshot.pacePct! / 5).round()}',
      'Your spending over the last 7 days is ${snapshot.pacePct!.abs().toStringAsFixed(0)}% '
          '${up ? 'higher' : 'lower'} than earlier this month.',
    );
  }
  if (snapshot.topCategory != null) {
    await notifyIfNew(
      'cat:${snapshot.topCategory}:${(snapshot.topCategoryPct! / 5).round()}',
      '${snapshot.topCategory} is your highest spending category this month, '
          'at ${snapshot.topCategoryPct!.round()}% of total expenses.',
    );
  }
  if (snapshot.forecastProjected != null) {
    await notifyIfNew(
      'forecast:${(snapshot.forecastProjected! / 10).round()}',
      'At the current pace, this month ends near ${_rm(snapshot.forecastProjected!)}.',
    );
  }

  if (changed) await prefs.setStringList(key, seen.toList());
}
