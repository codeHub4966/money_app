import 'package:flutter_test/flutter_test.dart';
import 'package:money_app_flutter/core/utils/spending_anomaly.dart';
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
  group('computeDailySpendingThreshold', () {
    test('excludes RM0 days from Q1/Q3/IQR/threshold', () {
      const nonZero = [10.0, 20.0, 30.0, 40.0, 50.0];
      final withZeros = [0.0, 10.0, 0.0, 20.0, 30.0, 0.0, 40.0, 50.0, 0.0];

      final a = computeDailySpendingThreshold(nonZero);
      final b = computeDailySpendingThreshold(withZeros);

      expect(a, isNotNull);
      expect(b, isNotNull);
      expect(b!.q1, a!.q1);
      expect(b.q3, a.q3);
      expect(b.iqr, a.iqr);
      expect(b.upperThreshold, a.upperThreshold);
    });

    test('returns null with fewer than 5 non-zero spending days', () {
      final result =
          computeDailySpendingThreshold([10.0, 20.0, 0.0, 30.0, 0.0]);
      expect(result, isNull);
    });

    test('computes a threshold once exactly 5 non-zero spending days exist',
        () {
      final result =
          computeDailySpendingThreshold([10.0, 20.0, 30.0, 40.0, 50.0]);
      expect(result, isNotNull);
      // Exclusive-median (Tukey's hinges): lower=[10,20] -> q1=15, upper=[40,50] -> q3=45.
      expect(result!.q1, 15.0);
      expect(result.q3, 45.0);
      expect(result.iqr, 30.0);
      expect(result.upperThreshold, 45.0 + 1.5 * 30.0);
    });
  });

  group('detectUnusualSpendingDays', () {
    final month = DateTime(2026, 3, 1);

    test('returns no result when fewer than 5 spending days are available', () {
      final dailyTotals = [10.0, 20.0, 0.0, 30.0, 0.0];
      final spikes = detectUnusualSpendingDays(
          dailyTotals: dailyTotals, monthTx: const [], month: month);
      expect(spikes, isEmpty);
    });

    // These use a 6th (largest) value on top of a 5-value base so the split
    // lands on an odd-sized (3-element) upper half: with n=5 the top value
    // enters directly into Q3's average and inflates it, but with n=6 the
    // upper-half median depends only on the *middle* of {40, 50, spike} — 50
    // regardless of the spike's exact size — so the threshold used by
    // detectUnusualSpendingDays is known ahead of time.
    test('a value exactly at the threshold is not unusual', () {
      final probe = computeDailySpendingThreshold(
          [10.0, 20.0, 30.0, 40.0, 50.0, 1000.0])!;
      final dailyTotals = [10.0, 20.0, 30.0, 40.0, 50.0, probe.upperThreshold];

      final spikes = detectUnusualSpendingDays(
          dailyTotals: dailyTotals, monthTx: const [], month: month);

      expect(spikes, isEmpty);
    });

    test('a value greater than the threshold is unusual', () {
      final probe = computeDailySpendingThreshold(
          [10.0, 20.0, 30.0, 40.0, 50.0, 1000.0])!;
      final aboveThreshold = probe.upperThreshold + 0.01;
      final dailyTotals = [10.0, 20.0, 30.0, 40.0, 50.0, aboveThreshold];

      final spikes = detectUnusualSpendingDays(
          dailyTotals: dailyTotals, monthTx: const [], month: month);

      expect(spikes, hasLength(1));
      expect(spikes.single.amount, aboveThreshold);
      expect(spikes.single.date, DateTime(2026, 3, 6));
    });

    test('picks the largest category on the unusual day as topCategory', () {
      final dailyTotals = [10.0, 20.0, 30.0, 40.0, 50.0, 300.0];
      final day6 = DateTime(2026, 3, 6);
      final monthTx = [
        _tx(amount: 250.0, date: day6, category: 'Electronics'),
        _tx(amount: 50.0, date: day6, category: 'Food'),
      ];

      final spikes = detectUnusualSpendingDays(
          dailyTotals: dailyTotals, monthTx: monthTx, month: month);

      expect(spikes, hasLength(1));
      expect(spikes.single.topCategory, 'Electronics');
    });
  });

  group('isAnomalyEligibleExpense', () {
    final month = DateTime(2026, 3, 1);

    test('excludes Transfer and Balance Adjustment categories', () {
      final transfer =
          _tx(amount: 100, date: DateTime(2026, 3, 5), category: 'Transfer');
      final balanceAdjustment = _tx(
          amount: 100,
          date: DateTime(2026, 3, 5),
          category: 'Balance Adjustment');
      final normal =
          _tx(amount: 100, date: DateTime(2026, 3, 5), category: 'Food');

      expect(
          isAnomalyEligibleExpense(transfer, month.year, month.month), isFalse);
      expect(
          isAnomalyEligibleExpense(balanceAdjustment, month.year, month.month),
          isFalse);
      expect(isAnomalyEligibleExpense(normal, month.year, month.month), isTrue);
    });

    test('excludes non-expense transactions and other months', () {
      final income = _tx(
          amount: 100,
          date: DateTime(2026, 3, 5),
          type: TransactionType.income);
      final otherMonth = _tx(amount: 100, date: DateTime(2026, 2, 5));

      expect(
          isAnomalyEligibleExpense(income, month.year, month.month), isFalse);
      expect(isAnomalyEligibleExpense(otherMonth, month.year, month.month),
          isFalse);
    });
  });

  group('eligibleExpensesUpToMonth (historical-month future-data cutoff)', () {
    test('excludes transactions dated after the given month', () {
      final all = [
        _tx(amount: 55, date: DateTime(2026, 6, 5)), // June
        _tx(amount: 55, date: DateTime(2026, 7, 4)), // July
        _tx(amount: 55, date: DateTime(2026, 8, 5)), // August
      ];

      final upToJune = eligibleExpensesUpToMonth(all, DateTime(2026, 6, 1));

      expect(upToJune, hasLength(1));
      expect(upToJune.single.date, DateTime(2026, 6, 5));
    });

    test('includes transactions dated in or before the given month', () {
      final all = [
        _tx(amount: 55, date: DateTime(2026, 6, 5)),
        _tx(amount: 55, date: DateTime(2026, 7, 4)),
      ];

      final upToJuly = eligibleExpensesUpToMonth(all, DateTime(2026, 7, 1));

      expect(upToJuly, hasLength(2));
    });

    test('still excludes Transfer/Balance Adjustment/income regardless of date',
        () {
      final all = [
        _tx(amount: 55, date: DateTime(2026, 6, 5), category: 'Transfer'),
        _tx(
            amount: 55,
            date: DateTime(2026, 6, 6),
            category: 'Balance Adjustment'),
        _tx(
            amount: 55,
            date: DateTime(2026, 6, 7),
            type: TransactionType.income),
      ];

      expect(eligibleExpensesUpToMonth(all, DateTime(2026, 6, 1)), isEmpty);
    });
  });
}
