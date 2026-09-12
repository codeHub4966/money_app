import 'package:flutter_test/flutter_test.dart';
import 'package:money_app_flutter/core/services/insight_notification_detector.dart';
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
  // `now` is fixed so tests don't depend on the real clock: 10 days into
  // March 2026, with spending on days 1-6 and a spike on day 6.
  final now = DateTime(2026, 3, 10);

  List<Transaction> buildTransactions() => [
        _tx(amount: 10, date: DateTime(2026, 3, 1)),
        _tx(amount: 20, date: DateTime(2026, 3, 2)),
        _tx(amount: 30, date: DateTime(2026, 3, 3)),
        _tx(amount: 40, date: DateTime(2026, 3, 4)),
        _tx(amount: 50, date: DateTime(2026, 3, 5)),
        _tx(amount: 200, date: DateTime(2026, 3, 6), category: 'Electronics'),
        // Excluded: Transfer and Balance Adjustment should not affect totals
        // or be able to trigger a spike on their own.
        _tx(amount: 1000, date: DateTime(2026, 3, 7), category: 'Transfer'),
        _tx(
            amount: 1000,
            date: DateTime(2026, 3, 8),
            category: 'Balance Adjustment'),
        // Excluded: income never counts towards expense spending.
        _tx(
            amount: 1000,
            date: DateTime(2026, 3, 9),
            type: TransactionType.income),
      ];

  test('flags the unusual day and ignores Transfer/Balance Adjustment/income',
      () {
    final snapshot = computeCurrentMonthSnapshot(buildTransactions(), now);

    expect(snapshot, isNotNull);
    expect(snapshot!.spikes, hasLength(1));
    expect(snapshot.spikes.single.date, DateTime(2026, 3, 6));
    expect(snapshot.spikes.single.amount, 200);
    expect(snapshot.spikes.single.topCategory, 'Electronics');
  });

  test(
      'produces the same anomaly result as directly calling the shared detector',
      () {
    final transactions = buildTransactions();
    final snapshot = computeCurrentMonthSnapshot(transactions, now);

    // Replicates the exact filter + day-bucketing pattern insights_tab.dart
    // uses before calling the shared detectUnusualSpendingDays function, to
    // prove both call sites resolve through the identical shared logic.
    final month = DateTime(now.year, now.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final daysElapsed = now.day.clamp(1, daysInMonth);
    final monthTx = transactions
        .where((t) => isAnomalyEligibleExpense(t, month.year, month.month))
        .toList();
    final dailyFull = List<double>.filled(daysInMonth, 0);
    for (final t in monthTx) {
      dailyFull[t.date.day - 1] += t.amount;
    }
    final recorded = dailyFull.sublist(0, daysElapsed);
    final expectedSpikes = detectUnusualSpendingDays(
        dailyTotals: recorded, monthTx: monthTx, month: month);

    expect(snapshot, isNotNull);
    expect(snapshot!.spikes.length, expectedSpikes.length);
    for (var i = 0; i < expectedSpikes.length; i++) {
      expect(snapshot.spikes[i].date, expectedSpikes[i].date);
      expect(snapshot.spikes[i].amount, expectedSpikes[i].amount);
      expect(snapshot.spikes[i].topCategory, expectedSpikes[i].topCategory);
    }
  });

  test('returns no spikes once fewer than 5 non-zero spending days remain', () {
    final fewDaysNow = DateTime(2026, 3, 3);
    final transactions = [
      _tx(amount: 10, date: DateTime(2026, 3, 1)),
      _tx(amount: 500, date: DateTime(2026, 3, 2)),
      _tx(amount: 20, date: DateTime(2026, 3, 3)),
    ];

    final snapshot = computeCurrentMonthSnapshot(transactions, fewDaysNow);

    expect(snapshot, isNotNull);
    expect(snapshot!.spikes, isEmpty);
  });

  group('avgDay (RM0 exclusion)', () {
    test('RM0 calendar days do not affect avgDay or the spike multiplier', () {
      // Spending only on days 1, 3, 5, 7, 9 — days 2, 4, 6, 8, 10 are RM0.
      final transactions = [
        _tx(amount: 10, date: DateTime(2026, 3, 1)),
        _tx(amount: 20, date: DateTime(2026, 3, 3)),
        _tx(amount: 30, date: DateTime(2026, 3, 5)),
        _tx(amount: 40, date: DateTime(2026, 3, 7)),
        _tx(amount: 300, date: DateTime(2026, 3, 9), category: 'Electronics'),
      ];

      final snapshot =
          computeCurrentMonthSnapshot(transactions, DateTime(2026, 3, 10));

      expect(snapshot, isNotNull);
      // 5 non-zero spending days (1,3,5,7,9), NOT the 10 elapsed calendar
      // days — a naive spent/daysElapsed would give 400/10 = 40.
      expect(snapshot!.avgDay, 400 / 5);
      expect(snapshot.avgDay, 80);
    });

    test('matches the same spent/non-zero-days formula insights_tab.dart uses',
        () {
      final transactions = [
        _tx(amount: 10, date: DateTime(2026, 3, 1)),
        _tx(amount: 500, date: DateTime(2026, 3, 4)),
        _tx(amount: 20, date: DateTime(2026, 3, 6)),
        _tx(amount: 30, date: DateTime(2026, 3, 8)),
        _tx(amount: 40, date: DateTime(2026, 3, 10)),
      ];
      final now = DateTime(2026, 3, 10);

      final snapshot = computeCurrentMonthSnapshot(transactions, now);

      // Replicates insights_tab.dart's _MonthData.compute avgDay formula:
      // spent / count of non-zero days within the elapsed window, using the
      // same isAnomalyEligibleExpense filter and day-bucketing.
      final month = DateTime(now.year, now.month, 1);
      final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
      final daysElapsed = now.day.clamp(1, daysInMonth);
      final monthTx = transactions
          .where((t) => isAnomalyEligibleExpense(t, month.year, month.month))
          .toList();
      final dailyFull = List<double>.filled(daysInMonth, 0);
      for (final t in monthTx) {
        dailyFull[t.date.day - 1] += t.amount;
      }
      final recorded = dailyFull.sublist(0, daysElapsed);
      final spent = recorded.fold(0.0, (s, v) => s + v);
      final nonZeroDays = recorded.where((v) => v > 0).length;
      final expectedAvgDay = spent / nonZeroDays;

      expect(snapshot, isNotNull);
      expect(snapshot!.avgDay, expectedAvgDay);
    });
  });

  group('categoryChange', () {
    test('flags a leading-category change vs the same period last month', () {
      final transactions = [
        // Current month (March): Electronics leads.
        _tx(amount: 300, date: DateTime(2026, 3, 2), category: 'Electronics'),
        _tx(amount: 50, date: DateTime(2026, 3, 3)),
        // Previous month (February), same day-count window: Food leads.
        _tx(amount: 200, date: DateTime(2026, 2, 2)),
        _tx(amount: 30, date: DateTime(2026, 2, 3), category: 'Electronics'),
      ];

      final snapshot =
          computeCurrentMonthSnapshot(transactions, DateTime(2026, 3, 10));

      expect(snapshot, isNotNull);
      expect(snapshot!.categoryChange, isNotNull);
      expect(snapshot.categoryChange!.previous, 'Food');
      expect(snapshot.categoryChange!.current, 'Electronics');
    });

    test('is null when the leading category is unchanged', () {
      final transactions = [
        _tx(amount: 300, date: DateTime(2026, 3, 2), category: 'Electronics'),
        _tx(amount: 200, date: DateTime(2026, 2, 2), category: 'Electronics'),
      ];

      final snapshot =
          computeCurrentMonthSnapshot(transactions, DateTime(2026, 3, 10));

      expect(snapshot, isNotNull);
      expect(snapshot!.categoryChange, isNull);
    });

    test('is null when the previous period has no spending data', () {
      final transactions = [
        _tx(amount: 300, date: DateTime(2026, 3, 2), category: 'Electronics'),
      ];

      final snapshot =
          computeCurrentMonthSnapshot(transactions, DateTime(2026, 3, 10));

      expect(snapshot, isNotNull);
      expect(snapshot!.categoryChange, isNull);
    });
  });
}
