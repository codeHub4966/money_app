import 'dart:math';

import '../../domain/models/budget.dart';
import '../../domain/models/transaction.dart' as tx;
import 'spending_forecast_calculator.dart';

/// Shared budget-risk math used by both the Insights tab and the
/// notification detector, so a category flagged at risk in one surface is
/// always flagged the same way in the other.

/// Minimum number of elapsed days before a budget projection is trusted —
/// avoids wild extrapolation from a single day of spending.
const int kMinDaysElapsedForBudgetRisk = 3;

/// Minimum non-zero spending days in the category before an estimated
/// exceed-date is considered reliable enough to show.
const int kMinCategoryDaysForBudgetExceedDate = 3;

/// A budget projected to be exceeded before month end.
class BudgetRisk {
  final String category;
  final double monthlyLimit;
  final double spent;
  final double projected;
  final double overageAmount;
  final DateTime? exceedDate;
  const BudgetRisk({
    required this.category,
    required this.monthlyLimit,
    required this.spent,
    required this.projected,
    required this.overageAmount,
    this.exceedDate,
  });
}

/// Detects which of [budgets] are on pace to be exceeded before month end.
///
/// [monthTx] must already be filtered to the anomaly-eligible expense
/// transactions for [month] (see `isAnomalyEligibleExpense` in
/// spending_anomaly.dart) — category matching is case-insensitive to match
/// `budgetsProvider`'s existing matching rule.
///
/// A category is only flagged when the projected overage is meaningful
/// (>= RM10 or >= 3% of the budget, whichever is larger) and at least
/// [kMinDaysElapsedForBudgetRisk] days have elapsed. Budgets with no matching
/// spending, or where the projection doesn't clear that bar, are omitted.
List<BudgetRisk> detectBudgetRisks({
  required List<Budget> budgets,
  required List<tx.Transaction> monthTx,
  required DateTime month,
  required int daysElapsed,
  required int daysInMonth,
}) {
  if (daysElapsed < kMinDaysElapsedForBudgetRisk) return const [];

  final risks = <BudgetRisk>[];
  for (final budget in budgets) {
    if (budget.monthlyLimit <= 0) continue;
    final categoryTx = monthTx
        .where((t) =>
            t.category.toLowerCase() == budget.categoryName.toLowerCase())
        .toList();
    if (categoryTx.isEmpty) continue;

    final dailyTotals = computeDailyTotals(categoryTx, daysInMonth);
    final recorded = dailyTotals.sublist(0, daysElapsed);
    final spent = recorded.fold(0.0, (s, v) => s + v);
    if (spent <= 0) continue;

    final forecast = computeMonthForecast(
      recorded: recorded,
      daysElapsed: daysElapsed,
      daysInMonth: daysInMonth,
      spent: spent,
    );
    final projected = forecast?.projected ?? spent;
    if (projected <= budget.monthlyLimit) continue;

    final overageAmount = projected - budget.monthlyLimit;
    final meaningfulFloor = max(10.0, budget.monthlyLimit * 0.03);
    if (overageAmount < meaningfulFloor) continue;

    final nonZeroCategoryDays = recorded.where((v) => v > 0).length;
    DateTime? exceedDate;
    if (nonZeroCategoryDays >= kMinCategoryDaysForBudgetExceedDate &&
        spent < budget.monthlyLimit) {
      final remainingDays = daysInMonth - daysElapsed;
      final futureDailyPace =
          remainingDays > 0 ? (projected - spent) / remainingDays : 0.0;
      if (futureDailyPace > 0) {
        final remainingToLimit = budget.monthlyLimit - spent;
        final daysUntilExceed = (remainingToLimit / futureDailyPace).ceil();
        final exceedDay = daysElapsed + daysUntilExceed;
        if (exceedDay <= daysInMonth) {
          exceedDate = DateTime(month.year, month.month, exceedDay);
        }
      }
    }

    risks.add(BudgetRisk(
      category: budget.categoryName,
      monthlyLimit: budget.monthlyLimit,
      spent: spent,
      projected: projected,
      overageAmount: overageAmount,
      exceedDate: exceedDate,
    ));
  }

  risks.sort((a, b) => b.overageAmount.compareTo(a.overageAmount));
  return risks;
}
