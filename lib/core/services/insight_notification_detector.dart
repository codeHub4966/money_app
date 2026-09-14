import '../../domain/models/budget.dart' as bg;
import '../../domain/models/transaction.dart' as tx;
import '../utils/budget_risk_detector.dart';
import '../utils/category_change.dart';
import '../utils/category_overspending_detector.dart';
import '../utils/merchant_pattern_detector.dart';
import '../utils/saving_opportunity_detector.dart';
import '../utils/spending_anomaly.dart';
import '../utils/spending_forecast_calculator.dart';

// Lightweight, standalone re-derivation of "is this day unusual" / "what are
// today's smart insights" for the CURRENT month, used only to decide when to
// fire a local notification (insight_notification_provider.dart). Kept
// separate from insights_tab.dart's private UI model so the Insights screen
// itself never has to change shape for this to work. Unusual-day detection,
// avg/day, 7-day pace, month-end forecast, budget risk, category
// overspending, merchant patterns, and saving opportunity are all shared via
// the detector/calculator files under core/utils/ so both surfaces stay
// consistent.

class SpendingSpike {
  final DateTime date;
  final double amount;
  final String topCategory;
  const SpendingSpike(
      {required this.date, required this.amount, required this.topCategory});
}

class SpendingSnapshot {
  final double avgDay;
  final double avgNonZeroDay;
  final int daysElapsed;
  final List<SpendingSpike> spikes;
  final double? pacePct;
  final String? topCategory;
  final double? topCategoryPct;
  final double? forecastProjected;
  final CategoryChange? categoryChange;
  final List<BudgetRisk> budgetRisks;
  final List<CategoryOverspend> categoryOverspends;
  final List<MerchantPattern> merchantPatterns;
  final SavingOpportunity? savingOpportunity;
  const SpendingSnapshot({
    required this.avgDay,
    required this.avgNonZeroDay,
    required this.daysElapsed,
    required this.spikes,
    this.pacePct,
    this.topCategory,
    this.topCategoryPct,
    this.forecastProjected,
    this.categoryChange,
    this.budgetRisks = const [],
    this.categoryOverspends = const [],
    this.merchantPatterns = const [],
    this.savingOpportunity,
  });
}

bool _isSpendableExpense(tx.Transaction t, DateTime month) =>
    isAnomalyEligibleExpense(t, month.year, month.month);

/// Returns null when there's no recorded spending yet this month.
SpendingSnapshot? computeCurrentMonthSnapshot(
    List<tx.Transaction> all, DateTime now,
    {List<bg.Budget> budgets = const []}) {
  final month = DateTime(now.year, now.month, 1);
  final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
  final daysElapsed = now.day.clamp(1, daysInMonth);

  final monthTx = all.where((t) => _isSpendableExpense(t, month)).toList();

  final dailyFull = computeDailyTotals(monthTx, daysInMonth);
  final recorded = dailyFull.sublist(0, daysElapsed);
  final spent = recorded.fold(0.0, (s, v) => s + v);
  if (spent <= 0) return null;

  // Calendar-day average: total spent so far ÷ days elapsed this month.
  final avgDay = computeAvgPerDay(spent, daysElapsed);
  // Average of only the days with recorded spending — used for the unusual
  // spending multiplier so RM0 days don't understate a spike's size.
  final avgNonZeroDay = computeAvgPerNonZeroDay(recorded);

  // Unusual spending days: IQR rule shared with the Insights tab.
  final spikes = detectUnusualSpendingDays(
          dailyTotals: recorded, monthTx: monthTx, month: month)
      .map((d) => SpendingSpike(
          date: d.date, amount: d.amount, topCategory: d.topCategory))
      .toList();

  // 7-day pace vs earlier-in-month pace.
  final pace = computeSevenDayPace(recorded, daysElapsed);
  final pacePct = pace.pacePct;

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
  final forecast = computeMonthForecast(
    recorded: recorded,
    daysElapsed: daysElapsed,
    daysInMonth: daysInMonth,
    spent: spent,
  );
  final forecastProjected = forecast?.projected;

  // Leading category vs the same period last month.
  final prevMonth = DateTime(month.year, month.month - 1, 1);
  final prevMonthTx =
      all.where((t) => _isSpendableExpense(t, prevMonth)).toList();
  final categoryChange = detectCategoryChange(
    currentMonthTx: monthTx,
    previousMonthTx: prevMonthTx,
    daysElapsed: daysElapsed,
  );

  // Budget risk: which category budgets are on pace to be exceeded.
  final budgetRisks = detectBudgetRisks(
    budgets: budgets,
    monthTx: monthTx,
    month: month,
    daysElapsed: daysElapsed,
    daysInMonth: daysInMonth,
  );

  // Category overspending vs the same period last month.
  final categoryOverspends = detectCategoryOverspending(
    currentMonthTx: monthTx,
    previousMonthTx: prevMonthTx,
    daysElapsed: daysElapsed,
  );

  // Merchant repeated/recurring spending patterns. Cut off at the end of
  // the current month (the only month this snapshot ever covers) — shared
  // with insights_tab.dart's historical-month cutoff so both call sites
  // agree on what "up to this point" means.
  final allEligibleTx = eligibleExpensesUpToMonth(all, month);
  final merchantPatterns = detectMerchantPatterns(
    currentMonthTx: monthTx,
    allEligibleTx: allEligibleTx,
  );

  // Saving opportunity from a clearly-lower recent pace.
  final savingOpportunity = detectSavingOpportunity(
    recorded: recorded,
    daysElapsed: daysElapsed,
    daysInMonth: daysInMonth,
    spent: spent,
  );

  return SpendingSnapshot(
    avgDay: avgDay,
    avgNonZeroDay: avgNonZeroDay,
    daysElapsed: daysElapsed,
    spikes: spikes,
    pacePct: pacePct,
    topCategory: topCategory,
    topCategoryPct: topCategoryPct,
    forecastProjected: forecastProjected,
    categoryChange: categoryChange,
    budgetRisks: budgetRisks,
    categoryOverspends: categoryOverspends,
    merchantPatterns: merchantPatterns,
    savingOpportunity: savingOpportunity,
  );
}
