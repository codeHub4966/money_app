import 'package:flutter_test/flutter_test.dart';
import 'package:money_app_flutter/core/utils/budget_risk_detector.dart';
import 'package:money_app_flutter/domain/models/budget.dart';
import 'package:money_app_flutter/domain/models/transaction.dart' as tx;

tx.Transaction _tx(
    {required double amount, required DateTime date, String category = 'Food'}) {
  return tx.Transaction(
    id: 'id-${date.toIso8601String()}-$amount-$category',
    type: tx.TransactionType.expense,
    amount: amount,
    category: category,
    accountId: 'acc',
    date: date,
  );
}

Budget _budget(String category, double limit) =>
    Budget(id: category, categoryName: category, monthlyLimit: limit, spent: 0);

void main() {
  final month = DateTime(2026, 3, 1);
  const daysInMonth = 31;

  group('detectBudgetRisks', () {
    test('empty when there is no budget for any spent category', () {
      final risks = detectBudgetRisks(
        budgets: const [],
        monthTx: [_tx(amount: 500, date: DateTime(2026, 3, 5))],
        month: month,
        daysElapsed: 10,
        daysInMonth: daysInMonth,
      );
      expect(risks, isEmpty);
    });

    test('empty when comfortably under budget', () {
      final risks = detectBudgetRisks(
        budgets: [_budget('Food', 1000)],
        monthTx: [
          for (var d = 1; d <= 10; d++) _tx(amount: 5, date: DateTime(2026, 3, d)),
        ],
        month: month,
        daysElapsed: 10,
        daysInMonth: daysInMonth,
      );
      expect(risks, isEmpty);
    });

    test('flags a category projected to meaningfully exceed its budget', () {
      // RM20/day * 31 days = RM620 projected, vs a RM300 budget -> well over
      // both the RM10 and 3% meaningful-overage floors.
      final risks = detectBudgetRisks(
        budgets: [_budget('Food', 300)],
        monthTx: [
          for (var d = 1; d <= 10; d++) _tx(amount: 20, date: DateTime(2026, 3, d)),
        ],
        month: month,
        daysElapsed: 10,
        daysInMonth: daysInMonth,
      );

      expect(risks, hasLength(1));
      expect(risks.single.category, 'Food');
      expect(risks.single.monthlyLimit, 300);
      expect(risks.single.spent, 200);
      expect(risks.single.projected, closeTo(620, 0.001));
      expect(risks.single.overageAmount, closeTo(320, 0.001));
    });

    test('empty when the projected overage is too weak to be meaningful', () {
      // Budget RM1000, projected only marginally over (RM1005) -> below both
      // the RM10 floor and the 3% (RM30) floor.
      final risks = detectBudgetRisks(
        budgets: [_budget('Food', 1000)],
        monthTx: [
          for (var d = 1; d <= 10; d++)
            _tx(amount: 1005 / 31, date: DateTime(2026, 3, d)),
        ],
        month: month,
        daysElapsed: 10,
        daysInMonth: daysInMonth,
      );
      expect(risks, isEmpty);
    });

    test('empty before kMinDaysElapsedForBudgetRisk days have elapsed', () {
      final risks = detectBudgetRisks(
        budgets: [_budget('Food', 50)],
        monthTx: [_tx(amount: 500, date: DateTime(2026, 3, 1))],
        month: month,
        daysElapsed: 1,
        daysInMonth: daysInMonth,
      );
      expect(risks, isEmpty);
    });

    test('exceedDate is included once >= 3 non-zero category spending days',
        () {
      final risks = detectBudgetRisks(
        budgets: [_budget('Food', 300)],
        monthTx: [
          for (var d = 1; d <= 10; d++) _tx(amount: 20, date: DateTime(2026, 3, d)),
        ],
        month: month,
        daysElapsed: 10,
        daysInMonth: daysInMonth,
      );

      expect(risks.single.exceedDate, isNotNull);
      expect(risks.single.exceedDate!.isBefore(DateTime(2026, 4, 1)), isTrue);
    });

    test('exceedDate is null with fewer than 3 non-zero category spending days',
        () {
      // Only 2 non-zero spending days, both within the trailing-7-day pace
      // window (days 4-10) so the projection is still driven by real spend.
      final risks = detectBudgetRisks(
        budgets: [_budget('Food', 300)],
        monthTx: [
          _tx(amount: 100, date: DateTime(2026, 3, 8)),
          _tx(amount: 100, date: DateTime(2026, 3, 9)),
        ],
        month: month,
        daysElapsed: 10,
        daysInMonth: daysInMonth,
      );

      expect(risks, hasLength(1));
      expect(risks.single.exceedDate, isNull);
    });

    test('category matching is case-insensitive, matching budgetsProvider', () {
      final risks = detectBudgetRisks(
        budgets: [_budget('food', 300)],
        monthTx: [
          for (var d = 1; d <= 10; d++)
            _tx(amount: 20, date: DateTime(2026, 3, d), category: 'Food'),
        ],
        month: month,
        daysElapsed: 10,
        daysInMonth: daysInMonth,
      );
      expect(risks, hasLength(1));
    });
  });
}
