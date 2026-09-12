import '../../domain/models/transaction.dart' as tx;
import '../utils/category_change.dart';
import '../utils/spending_anomaly.dart';

// Lightweight, standalone re-derivation of "is this day unusual" / "what are
// today's smart insights" for the CURRENT month, used only to decide when to
// fire a local notification (insight_notification_provider.dart). Kept
// separate from insights_tab.dart's private UI model so the Insights screen
// itself never has to change shape for this to work. Unusual-day detection
// itself is shared via spending_anomaly.dart so both stay consistent.

class SpendingSpike {
  final DateTime date;
  final double amount;
  final String topCategory;
  const SpendingSpike(
      {required this.date, required this.amount, required this.topCategory});
}

class SpendingSnapshot {
  final double avgDay;
  final int daysElapsed;
  final List<SpendingSpike> spikes;
  final double? pacePct;
  final String? topCategory;
  final double? topCategoryPct;
  final double? forecastProjected;
  final CategoryChange? categoryChange;
  const SpendingSnapshot({
    required this.avgDay,
    required this.daysElapsed,
    required this.spikes,
    this.pacePct,
    this.topCategory,
    this.topCategoryPct,
    this.forecastProjected,
    this.categoryChange,
  });
}

bool _isSpendableExpense(tx.Transaction t, DateTime month) =>
    isAnomalyEligibleExpense(t, month.year, month.month);

/// Returns null when there's no recorded spending yet this month.
SpendingSnapshot? computeCurrentMonthSnapshot(
    List<tx.Transaction> all, DateTime now) {
  final month = DateTime(now.year, now.month, 1);
  final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
  final daysElapsed = now.day.clamp(1, daysInMonth);

  final monthTx = all.where((t) => _isSpendableExpense(t, month)).toList();

  final dailyFull = List<double>.filled(daysInMonth, 0);
  for (final t in monthTx) {
    if (t.date.day >= 1 && t.date.day <= daysInMonth)
      dailyFull[t.date.day - 1] += t.amount;
  }
  final recorded = dailyFull.sublist(0, daysElapsed);
  final spent = recorded.fold(0.0, (s, v) => s + v);
  if (spent <= 0) return null;

  // Average is spend ÷ non-zero spending days so RM0 calendar days never
  // drag it down (and, in turn, never inflate the "x your average" figure).
  final nonZeroDays = recorded.where((v) => v > 0).length;
  final avgDay = nonZeroDays > 0 ? spent / nonZeroDays : 0.0;

  // Unusual spending days: IQR rule shared with the Insights tab.
  final spikes = detectUnusualSpendingDays(
          dailyTotals: recorded, monthTx: monthTx, month: month)
      .map((d) => SpendingSpike(
          date: d.date, amount: d.amount, topCategory: d.topCategory))
      .toList();

  // 7-day pace vs earlier-in-month pace.
  double? pacePct;
  if (daysElapsed >= 8) {
    final recent7 = recorded.sublist(daysElapsed - 7);
    final earlier = recorded.sublist(0, daysElapsed - 7);
    final pn = recent7.fold(0.0, (s, v) => s + v) / 7;
    final pb = earlier.isEmpty
        ? 0.0
        : earlier.fold(0.0, (s, v) => s + v) / earlier.length;
    if (pb > 0) pacePct = (pn - pb) / pb * 100;
  }

  // Top category so far this month.
  final catTotals = <String, double>{};
  for (final t in monthTx) {
    if (t.date.day > daysElapsed) continue;
    catTotals[t.category] = (catTotals[t.category] ?? 0) + t.amount;
  }
  final sortedCats = catTotals.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  String? topCategory;
  double? topCategoryPct;
  if (sortedCats.isNotEmpty) {
    topCategory = sortedCats.first.key;
    topCategoryPct = sortedCats.first.value / spent * 100;
  }

  // Month-end forecast, only while the month is still in progress.
  double? forecastProjected;
  if (daysElapsed < daysInMonth) {
    final paceWindow =
        daysElapsed >= 7 ? recorded.sublist(daysElapsed - 7) : recorded;
    final pace = paceWindow.fold(0.0, (s, v) => s + v) / paceWindow.length;
    forecastProjected = spent + pace * (daysInMonth - daysElapsed);
  }

  // Leading category vs the same period last month.
  final prevMonth = DateTime(month.year, month.month - 1, 1);
  final prevMonthTx =
      all.where((t) => _isSpendableExpense(t, prevMonth)).toList();
  final categoryChange = detectCategoryChange(
    currentMonthTx: monthTx,
    previousMonthTx: prevMonthTx,
    daysElapsed: daysElapsed,
  );

  return SpendingSnapshot(
    avgDay: avgDay,
    daysElapsed: daysElapsed,
    spikes: spikes,
    pacePct: pacePct,
    topCategory: topCategory,
    topCategoryPct: topCategoryPct,
    forecastProjected: forecastProjected,
    categoryChange: categoryChange,
  );
}
