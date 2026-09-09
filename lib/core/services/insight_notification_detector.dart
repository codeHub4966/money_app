import '../../domain/models/transaction.dart' as tx;

// Lightweight, standalone re-derivation of "is this day unusual" / "what are
// today's smart insights" for the CURRENT month, used only to decide when to
// fire a local notification (insight_notification_provider.dart). Kept
// separate from insights_tab.dart's private UI model so the Insights screen
// itself never has to change shape for this to work.

class SpendingSpike {
  final DateTime date;
  final double amount;
  final String topCategory;
  const SpendingSpike({required this.date, required this.amount, required this.topCategory});
}

class SpendingSnapshot {
  final double avgDay;
  final int daysElapsed;
  final List<SpendingSpike> spikes;
  final double? pacePct;
  final String? topCategory;
  final double? topCategoryPct;
  final double? forecastProjected;
  const SpendingSnapshot({
    required this.avgDay, required this.daysElapsed, required this.spikes,
    this.pacePct, this.topCategory, this.topCategoryPct, this.forecastProjected,
  });
}

bool _isSpendableExpense(tx.Transaction t, DateTime month) =>
    t.type == tx.TransactionType.expense &&
    t.date.year == month.year && t.date.month == month.month &&
    t.category != 'Transfer' && t.category != 'Balance Adjustment';

/// Returns null when there's no recorded spending yet this month.
SpendingSnapshot? computeCurrentMonthSnapshot(List<tx.Transaction> all, DateTime now) {
  final month = DateTime(now.year, now.month, 1);
  final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
  final daysElapsed = now.day.clamp(1, daysInMonth);

  final monthTx = all.where((t) => _isSpendableExpense(t, month)).toList();

  final dailyFull = List<double>.filled(daysInMonth, 0);
  for (final t in monthTx) {
    if (t.date.day >= 1 && t.date.day <= daysInMonth) dailyFull[t.date.day - 1] += t.amount;
  }
  final recorded = dailyFull.sublist(0, daysElapsed);
  final spent = recorded.fold(0.0, (s, v) => s + v);
  if (spent <= 0) return null;

  final avgDay = spent / daysElapsed;

  // Unusual spending days: same >= 2x-average rule as the Insights tab.
  final threshold = avgDay * 2;
  final spikes = <SpendingSpike>[];
  for (var i = 0; i < daysElapsed; i++) {
    if (recorded[i] < threshold) continue;
    final day = i + 1;
    final byCategory = <String, double>{};
    for (final t in monthTx.where((t) => t.date.day == day)) {
      byCategory[t.category] = (byCategory[t.category] ?? 0) + t.amount;
    }
    final topDayCat = byCategory.entries.isEmpty
        ? 'spending'
        : (byCategory.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;
    spikes.add(SpendingSpike(date: DateTime(month.year, month.month, day), amount: recorded[i], topCategory: topDayCat));
  }
  spikes.sort((a, b) => b.date.compareTo(a.date));

  // 7-day pace vs earlier-in-month pace.
  double? pacePct;
  if (daysElapsed >= 8) {
    final recent7 = recorded.sublist(daysElapsed - 7);
    final earlier = recorded.sublist(0, daysElapsed - 7);
    final pn = recent7.fold(0.0, (s, v) => s + v) / 7;
    final pb = earlier.isEmpty ? 0.0 : earlier.fold(0.0, (s, v) => s + v) / earlier.length;
    if (pb > 0) pacePct = (pn - pb) / pb * 100;
  }

  // Top category so far this month.
  final catTotals = <String, double>{};
  for (final t in monthTx) {
    if (t.date.day > daysElapsed) continue;
    catTotals[t.category] = (catTotals[t.category] ?? 0) + t.amount;
  }
  final sortedCats = catTotals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  String? topCategory;
  double? topCategoryPct;
  if (sortedCats.isNotEmpty) {
    topCategory = sortedCats.first.key;
    topCategoryPct = sortedCats.first.value / spent * 100;
  }

  // Month-end forecast, only while the month is still in progress.
  double? forecastProjected;
  if (daysElapsed < daysInMonth) {
    final paceWindow = daysElapsed >= 7 ? recorded.sublist(daysElapsed - 7) : recorded;
    final pace = paceWindow.fold(0.0, (s, v) => s + v) / paceWindow.length;
    forecastProjected = spent + pace * (daysInMonth - daysElapsed);
  }

  return SpendingSnapshot(
    avgDay: avgDay, daysElapsed: daysElapsed, spikes: spikes,
    pacePct: pacePct, topCategory: topCategory, topCategoryPct: topCategoryPct,
    forecastProjected: forecastProjected,
  );
}
