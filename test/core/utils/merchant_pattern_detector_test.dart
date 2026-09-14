import 'package:flutter_test/flutter_test.dart';
import 'package:money_app_flutter/core/utils/merchant_pattern_detector.dart';
import 'package:money_app_flutter/domain/models/transaction.dart' as tx;

tx.Transaction _tx({
  required double amount,
  required DateTime date,
  String? note,
  String category = 'Food',
}) {
  return tx.Transaction(
    id: 'id-${date.toIso8601String()}-$amount-${note ?? ''}',
    type: tx.TransactionType.expense,
    amount: amount,
    category: category,
    accountId: 'acc',
    date: date,
    note: note,
  );
}

void main() {
  group('detectMerchantPatterns — repeated this month', () {
    test('flags a merchant with >= 3 transactions this month', () {
      final currentMonthTx = [
        _tx(amount: 20, date: DateTime(2026, 3, 2), note: 'Starbucks — Latte'),
        _tx(amount: 30, date: DateTime(2026, 3, 10), note: 'Starbucks — Mocha'),
        _tx(amount: 40, date: DateTime(2026, 3, 20), note: 'Starbucks — Cake'),
      ];

      final patterns = detectMerchantPatterns(
          currentMonthTx: currentMonthTx, allEligibleTx: currentMonthTx);

      final repeated =
          patterns.where((p) => p.type == MerchantPatternType.repeated);
      expect(repeated, hasLength(1));
      expect(repeated.single.merchant, 'Starbucks');
      expect(repeated.single.amount, 90);
      expect(repeated.single.count, 3);
    });

    test('does not flag a merchant with fewer than 3 transactions', () {
      final currentMonthTx = [
        _tx(amount: 20, date: DateTime(2026, 3, 2), note: 'Starbucks — Latte'),
        _tx(amount: 30, date: DateTime(2026, 3, 10), note: 'Starbucks — Mocha'),
      ];

      final patterns = detectMerchantPatterns(
          currentMonthTx: currentMonthTx, allEligibleTx: currentMonthTx);
      expect(patterns.where((p) => p.type == MerchantPatternType.repeated),
          isEmpty);
    });

    test('ignores generic/empty notes', () {
      final currentMonthTx = [
        _tx(amount: 20, date: DateTime(2026, 3, 2), note: 'Other'),
        _tx(amount: 30, date: DateTime(2026, 3, 10), note: 'Other'),
        _tx(amount: 40, date: DateTime(2026, 3, 20)), // no note
      ];

      final patterns = detectMerchantPatterns(
          currentMonthTx: currentMonthTx, allEligibleTx: currentMonthTx);
      expect(patterns, isEmpty);
    });

    test('never groups purely by category', () {
      // Same category, but different (non-generic) merchants -- must not be
      // treated as one pattern.
      final currentMonthTx = [
        _tx(amount: 20, date: DateTime(2026, 3, 2), note: 'Starbucks — Latte'),
        _tx(amount: 30, date: DateTime(2026, 3, 10), note: 'Tealive — Milk Tea'),
        _tx(amount: 40, date: DateTime(2026, 3, 20), note: 'McDonalds — Meal'),
      ];

      final patterns = detectMerchantPatterns(
          currentMonthTx: currentMonthTx, allEligibleTx: currentMonthTx);
      expect(patterns.where((p) => p.type == MerchantPatternType.repeated),
          isEmpty);
    });
  });

  group('detectMerchantPatterns — recurring monthly', () {
    test('flags a merchant charged ~monthly for 3+ consecutive months', () {
      final allEligibleTx = [
        _tx(amount: 55, date: DateTime(2026, 1, 5), note: 'Netflix — Sub'),
        _tx(amount: 55, date: DateTime(2026, 2, 4), note: 'Netflix — Sub'),
        _tx(amount: 55, date: DateTime(2026, 3, 5), note: 'Netflix — Sub'),
      ];

      final patterns = detectMerchantPatterns(
          currentMonthTx: const [], allEligibleTx: allEligibleTx);

      final recurring =
          patterns.where((p) => p.type == MerchantPatternType.recurring);
      expect(recurring, hasLength(1));
      expect(recurring.single.merchant, 'Netflix');
      expect(recurring.single.amount, 55);
      expect(recurring.single.count, 3);
      expect(recurring.single.lastDate, DateTime(2026, 3, 5));
    });

    test('does not flag when gaps are not ~monthly', () {
      final allEligibleTx = [
        _tx(amount: 55, date: DateTime(2026, 1, 1), note: 'Netflix — Sub'),
        _tx(amount: 55, date: DateTime(2026, 1, 10), note: 'Netflix — Sub'),
        _tx(amount: 55, date: DateTime(2026, 1, 20), note: 'Netflix — Sub'),
      ];

      final patterns = detectMerchantPatterns(
          currentMonthTx: const [], allEligibleTx: allEligibleTx);
      expect(patterns.where((p) => p.type == MerchantPatternType.recurring),
          isEmpty);
    });

    test('does not flag when amounts vary too much between charges', () {
      final allEligibleTx = [
        _tx(amount: 20, date: DateTime(2026, 1, 5), note: 'Netflix — Sub'),
        _tx(amount: 55, date: DateTime(2026, 2, 4), note: 'Netflix — Sub'),
        _tx(amount: 90, date: DateTime(2026, 3, 5), note: 'Netflix — Sub'),
      ];

      final patterns = detectMerchantPatterns(
          currentMonthTx: const [], allEligibleTx: allEligibleTx);
      expect(patterns.where((p) => p.type == MerchantPatternType.recurring),
          isEmpty);
    });

    test('does not flag with fewer than 3 qualifying charges', () {
      final allEligibleTx = [
        _tx(amount: 55, date: DateTime(2026, 2, 4), note: 'Netflix — Sub'),
        _tx(amount: 55, date: DateTime(2026, 3, 5), note: 'Netflix — Sub'),
      ];

      final patterns = detectMerchantPatterns(
          currentMonthTx: const [], allEligibleTx: allEligibleTx);
      expect(patterns, isEmpty);
    });
  });
}
