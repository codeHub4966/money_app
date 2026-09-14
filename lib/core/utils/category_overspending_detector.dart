import '../../domain/models/transaction.dart' as tx;

/// Shared category-overspending math used by both the Insights tab and the
/// notification detector.
///
/// Minimum previous-period spend in a category before its percent increase
/// is trusted — avoids inflated percentages from a tiny baseline (e.g.
/// RM1 -> RM50 reading as a 4900% increase).
const double kMinCategoryOverspendBaseline = 20.0;

/// Minimum percent increase considered "meaningful".
const double kMinCategoryOverspendPct = 30.0;

/// Minimum absolute increase considered "meaningful".
const double kMinCategoryOverspendAmount = 10.0;

/// A category whose current-period spending is meaningfully higher than the
/// same-length period last month.
class CategoryOverspend {
  final String category;
  final double currentAmount;
  final double previousAmount;
  final double pctIncrease;
  const CategoryOverspend({
    required this.category,
    required this.currentAmount,
    required this.previousAmount,
    required this.pctIncrease,
  });
}

Map<String, double> _totalsUpToDay(List<tx.Transaction> monthTx, int upToDay) {
  final totals = <String, double>{};
  for (final t in monthTx) {
    if (t.date.day > upToDay) continue;
    totals[t.category] = (totals[t.category] ?? 0) + t.amount;
  }
  return totals;
}

/// Compares each category's spending so far this period against the same
/// day-window last month — the identical eligible-expense/date-comparison
/// rule `category_change.dart`'s `detectCategoryChange` uses, applied per
/// category instead of only to the single leading category.
///
/// [currentMonthTx]/[previousMonthTx] must already be filtered to the
/// anomaly-eligible expense transactions for their respective months (see
/// `isAnomalyEligibleExpense` in spending_anomaly.dart). Returns categories
/// whose increase clears all three "meaningful" bars
/// ([kMinCategoryOverspendBaseline], [kMinCategoryOverspendPct],
/// [kMinCategoryOverspendAmount]), sorted by percent increase, highest first.
List<CategoryOverspend> detectCategoryOverspending({
  required List<tx.Transaction> currentMonthTx,
  required List<tx.Transaction> previousMonthTx,
  required int daysElapsed,
}) {
  final current = _totalsUpToDay(currentMonthTx, daysElapsed);
  final previous = _totalsUpToDay(previousMonthTx, daysElapsed);

  final result = <CategoryOverspend>[];
  for (final entry in current.entries) {
    final currentAmount = entry.value;
    final previousAmount = previous[entry.key] ?? 0;
    if (previousAmount < kMinCategoryOverspendBaseline) continue;

    final increase = currentAmount - previousAmount;
    if (increase < kMinCategoryOverspendAmount) continue;

    final pctIncrease = increase / previousAmount * 100;
    if (pctIncrease < kMinCategoryOverspendPct) continue;

    result.add(CategoryOverspend(
      category: entry.key,
      currentAmount: currentAmount,
      previousAmount: previousAmount,
      pctIncrease: pctIncrease,
    ));
  }

  result.sort((a, b) => b.pctIncrease.compareTo(a.pctIncrease));
  return result;
}
