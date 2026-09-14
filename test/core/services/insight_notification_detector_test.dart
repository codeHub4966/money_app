import 'package:flutter_test/flutter_test.dart';
import 'package:money_app_flutter/core/services/insight_notification_detector.dart';
import 'package:money_app_flutter/core/utils/merchant_pattern_detector.dart';
import 'package:money_app_flutter/core/utils/spending_anomaly.dart';
import 'package:money_app_flutter/core/utils/spending_forecast_calculator.dart';
import 'package:money_app_flutter/domain/models/budget.dart';
import 'package:money_app_flutter/domain/models/transaction.dart';

Transaction _tx({
  required double amount,
  required DateTime date,
  TransactionType type = TransactionType.expense,
  String category = 'Food',
  String? note,
}) {
  return Transaction(
    id: 'id-${date.toIso8601String()}-$amount-$category-${note ?? ''}',
    type: type,
    amount: amount,
    category: category,
    accountId: 'acc',
    date: date,
    note: note,
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

  group('avgDay (calendar-day average)', () {
    test('RM0 calendar days dilute avgDay — divisor is days elapsed', () {
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
      // 10 elapsed calendar days (1-10), including the RM0 ones — spending
      // pace is total spent ÷ days elapsed, not ÷ non-zero spending days.
      expect(snapshot!.avgDay, 400 / 10);
      expect(snapshot.avgDay, 40);
    });

    test('matches the same spent/days-elapsed formula insights_tab.dart uses',
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
      // spent / calendar days elapsed, using the same isAnomalyEligibleExpense
      // filter and day-bucketing.
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
      final expectedAvgDay = spent / daysElapsed;

      expect(snapshot, isNotNull);
      expect(snapshot!.avgDay, expectedAvgDay);
    });
  });

  group('avgNonZeroDay (used for the unusual-spending multiplier)', () {
    test('averages only days with recorded spending, unlike avgDay', () {
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
      // 400 spent across 5 non-zero days -> 80, not 400/10 (= avgDay's 40).
      expect(snapshot!.avgNonZeroDay, 80);
      expect(snapshot.avgNonZeroDay, isNot(snapshot.avgDay));
    });

    test(
        'computeAvgPerNonZeroDay returns 0 for an all-RM0 window (avoids division by zero)',
        () {
      expect(computeAvgPerNonZeroDay([0, 0, 0]), 0.0);
      expect(computeAvgPerNonZeroDay(const []), 0.0);
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

  group('budgetRisks (shared with budget_risk_detector.dart)', () {
    test('flags a category projected to exceed its budget', () {
      final transactions = [
        for (var d = 1; d <= 10; d++)
          _tx(amount: 20, date: DateTime(2026, 3, d), category: 'Food'),
      ];
      final budgets = [
        const Budget(id: 'food', categoryName: 'Food', monthlyLimit: 300, spent: 0),
      ];

      final snapshot = computeCurrentMonthSnapshot(transactions,
          DateTime(2026, 3, 10),
          budgets: budgets);

      expect(snapshot, isNotNull);
      expect(snapshot!.budgetRisks, hasLength(1));
      expect(snapshot.budgetRisks.single.category, 'Food');
    });

    test('empty when there are no budgets', () {
      final transactions = [
        _tx(amount: 300, date: DateTime(2026, 3, 2), category: 'Food'),
      ];
      final snapshot =
          computeCurrentMonthSnapshot(transactions, DateTime(2026, 3, 10));

      expect(snapshot, isNotNull);
      expect(snapshot!.budgetRisks, isEmpty);
    });
  });

  group('categoryOverspends (shared with category_overspending_detector.dart)',
      () {
    test('flags a category with a meaningful increase vs last month', () {
      final transactions = [
        _tx(amount: 145, date: DateTime(2026, 3, 5), category: 'Shopping'),
        _tx(amount: 100, date: DateTime(2026, 2, 5), category: 'Shopping'),
      ];

      final snapshot =
          computeCurrentMonthSnapshot(transactions, DateTime(2026, 3, 10));

      expect(snapshot, isNotNull);
      expect(snapshot!.categoryOverspends, hasLength(1));
      expect(snapshot.categoryOverspends.single.category, 'Shopping');
    });
  });

  group('merchantPatterns (shared with merchant_pattern_detector.dart)', () {
    test('flags a merchant repeated 3+ times this month', () {
      final transactions = [
        _tx(
            amount: 20,
            date: DateTime(2026, 3, 2),
            note: 'Starbucks — Latte'),
        _tx(
            amount: 30,
            date: DateTime(2026, 3, 10),
            note: 'Starbucks — Mocha'),
        _tx(
            amount: 40,
            date: DateTime(2026, 3, 15),
            note: 'Starbucks — Cake'),
      ];

      final snapshot =
          computeCurrentMonthSnapshot(transactions, DateTime(2026, 3, 20));

      expect(snapshot, isNotNull);
      expect(
          snapshot!.merchantPatterns
              .where((p) => p.type == MerchantPatternType.repeated),
          hasLength(1));
    });
  });

  group('savingOpportunity (shared with saving_opportunity_detector.dart)',
      () {
    test('flags a clearly-lower recent pace', () {
      final transactions = [
        for (var d = 1; d <= 3; d++)
          _tx(amount: 30, date: DateTime(2026, 3, d)),
        for (var d = 4; d <= 10; d++)
          _tx(amount: 10, date: DateTime(2026, 3, d)),
      ];

      final snapshot =
          computeCurrentMonthSnapshot(transactions, DateTime(2026, 3, 10));

      expect(snapshot, isNotNull);
      expect(snapshot!.savingOpportunity, isNotNull);
      expect(snapshot.savingOpportunity!.estimatedSavings, greaterThan(0));
    });

    test('is null when there is not enough data yet', () {
      final transactions = [
        _tx(amount: 10, date: DateTime(2026, 3, 1)),
      ];

      final snapshot =
          computeCurrentMonthSnapshot(transactions, DateTime(2026, 3, 3));

      expect(snapshot, isNotNull);
      expect(snapshot!.savingOpportunity, isNull);
    });
  });
}
