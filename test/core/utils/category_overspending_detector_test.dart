import 'package:flutter_test/flutter_test.dart';
import 'package:money_app_flutter/core/utils/category_overspending_detector.dart';
import 'package:money_app_flutter/domain/models/transaction.dart' as tx;

tx.Transaction _tx(
    {required double amount, required DateTime date, String category = 'Shopping'}) {
  return tx.Transaction(
    id: 'id-${date.toIso8601String()}-$amount-$category',
    type: tx.TransactionType.expense,
    amount: amount,
    category: category,
    accountId: 'acc',
    date: date,
  );
}

void main() {
  group('detectCategoryOverspending', () {
    test('flags a category with a meaningful increase, correct pct', () {
      final current = [_tx(amount: 145, date: DateTime(2026, 3, 5))];
      final previous = [_tx(amount: 100, date: DateTime(2026, 2, 5))];

      final result = detectCategoryOverspending(
        currentMonthTx: current,
        previousMonthTx: previous,
        daysElapsed: 10,
      );

      expect(result, hasLength(1));
      expect(result.single.category, 'Shopping');
      expect(result.single.currentAmount, 145);
      expect(result.single.previousAmount, 100);
      expect(result.single.pctIncrease, 45);
    });

    test('empty when the increase is below the meaningful percent threshold',
        () {
      final current = [_tx(amount: 110, date: DateTime(2026, 3, 5))];
      final previous = [_tx(amount: 100, date: DateTime(2026, 2, 5))];

      final result = detectCategoryOverspending(
        currentMonthTx: current,
        previousMonthTx: previous,
        daysElapsed: 10,
      );
      expect(result, isEmpty);
    });

    test('empty when the previous-period baseline is too small to trust', () {
      // RM1 -> RM50 is a huge percent jump but the baseline is too thin.
      final current = [_tx(amount: 50, date: DateTime(2026, 3, 5))];
      final previous = [_tx(amount: 1, date: DateTime(2026, 2, 5))];

      final result = detectCategoryOverspending(
        currentMonthTx: current,
        previousMonthTx: previous,
        daysElapsed: 10,
      );
      expect(result, isEmpty);
    });

    test('empty when spending decreased', () {
      final current = [_tx(amount: 50, date: DateTime(2026, 3, 5))];
      final previous = [_tx(amount: 100, date: DateTime(2026, 2, 5))];

      final result = detectCategoryOverspending(
        currentMonthTx: current,
        previousMonthTx: previous,
        daysElapsed: 10,
      );
      expect(result, isEmpty);
    });

    test('only counts transactions up to daysElapsed in both periods', () {
      final current = [
        _tx(amount: 145, date: DateTime(2026, 3, 5)),
        _tx(amount: 900, date: DateTime(2026, 3, 20)), // after daysElapsed
      ];
      final previous = [_tx(amount: 100, date: DateTime(2026, 2, 5))];

      final result = detectCategoryOverspending(
        currentMonthTx: current,
        previousMonthTx: previous,
        daysElapsed: 10,
      );

      expect(result, hasLength(1));
      expect(result.single.currentAmount, 145);
    });

    test('sorted by percent increase, highest first', () {
      final current = [
        _tx(amount: 200, date: DateTime(2026, 3, 5), category: 'A'), // +100%
        _tx(amount: 260, date: DateTime(2026, 3, 5), category: 'B'), // +30%
      ];
      final previous = [
        _tx(amount: 100, date: DateTime(2026, 2, 5), category: 'A'),
        _tx(amount: 200, date: DateTime(2026, 2, 5), category: 'B'),
      ];

      final result = detectCategoryOverspending(
        currentMonthTx: current,
        previousMonthTx: previous,
        daysElapsed: 10,
      );

      expect(result, hasLength(2));
      expect(result[0].category, 'A');
      expect(result[1].category, 'B');
    });

    test(
        'returns every qualifying category (more than 3), sorted — the '
        'detector itself never truncates; only the UI limits to the top 3',
        () {
      final current = [
        _tx(amount: 400, date: DateTime(2026, 3, 5), category: 'A'), // +300%
        _tx(amount: 200, date: DateTime(2026, 3, 5), category: 'B'), // +100%
        _tx(amount: 260, date: DateTime(2026, 3, 5), category: 'C'), // +30%
        _tx(amount: 130, date: DateTime(2026, 3, 5), category: 'D'), // +30%
      ];
      final previous = [
        _tx(amount: 100, date: DateTime(2026, 2, 5), category: 'A'),
        _tx(amount: 100, date: DateTime(2026, 2, 5), category: 'B'),
        _tx(amount: 200, date: DateTime(2026, 2, 5), category: 'C'),
        _tx(amount: 100, date: DateTime(2026, 2, 5), category: 'D'),
      ];

      final result = detectCategoryOverspending(
        currentMonthTx: current,
        previousMonthTx: previous,
        daysElapsed: 10,
      );

      expect(result, hasLength(4));
      expect(result[0].category, 'A');
      expect(result[1].category, 'B');
      // C and D tie at +30%; both must still be present.
      expect(result.skip(2).map((r) => r.category).toSet(), {'C', 'D'});
    });
  });
}
