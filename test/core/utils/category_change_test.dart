import 'package:flutter_test/flutter_test.dart';
import 'package:money_app_flutter/core/utils/category_change.dart';
import 'package:money_app_flutter/domain/models/transaction.dart';

Transaction _tx({
  required double amount,
  required DateTime date,
  TransactionType type = TransactionType.expense,
  String category = 'Food',
}) {
  return Transaction(
    id: 'id-${date.toIso8601String()}-$amount-$category',
    type: type,
    amount: amount,
    category: category,
    accountId: 'acc',
    date: date,
  );
}

void main() {
  group('leadingCategory', () {
    test('picks the category with the highest total up to the given day', () {
      final monthTx = [
        _tx(amount: 50, date: DateTime(2026, 3, 1), category: 'Food'),
        _tx(amount: 30, date: DateTime(2026, 3, 2), category: 'Transport'),
        _tx(amount: 40, date: DateTime(2026, 3, 3), category: 'Transport'),
      ];

      expect(leadingCategory(monthTx, 3), 'Transport');
    });

    test('only counts days up to and including upToDay', () {
      final monthTx = [
        _tx(amount: 10, date: DateTime(2026, 3, 1), category: 'Food'),
        _tx(amount: 1000, date: DateTime(2026, 3, 5), category: 'Electronics'),
      ];

      expect(leadingCategory(monthTx, 2), 'Food');
    });

    test('returns null when there is no spending', () {
      expect(leadingCategory(const [], 10), isNull);
    });
  });

  group('detectCategoryChange', () {
    test('returns null when both periods have the same leading category', () {
      final current = [
        _tx(amount: 50, date: DateTime(2026, 3, 1), category: 'Food')
      ];
      final previous = [
        _tx(amount: 20, date: DateTime(2026, 2, 1), category: 'Food')
      ];

      final result = detectCategoryChange(
        currentMonthTx: current,
        previousMonthTx: previous,
        daysElapsed: 5,
      );

      expect(result, isNull);
    });

    test('returns null when either period has no spending data', () {
      final current = [
        _tx(amount: 50, date: DateTime(2026, 3, 1), category: 'Food')
      ];

      final result = detectCategoryChange(
        currentMonthTx: current,
        previousMonthTx: const [],
        daysElapsed: 5,
      );

      expect(result, isNull);
    });

    test('returns the change when the leading category differs', () {
      final current = [
        _tx(amount: 50, date: DateTime(2026, 3, 1), category: 'Transport')
      ];
      final previous = [
        _tx(amount: 20, date: DateTime(2026, 2, 1), category: 'Food')
      ];

      final result = detectCategoryChange(
        currentMonthTx: current,
        previousMonthTx: previous,
        daysElapsed: 5,
      );

      expect(result, isNotNull);
      expect(result!.previous, 'Food');
      expect(result.current, 'Transport');
    });
  });
}
