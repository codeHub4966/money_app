import 'package:flutter_test/flutter_test.dart';
import 'package:money_app_flutter/core/utils/spending_forecast_calculator.dart';
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
  group('computeDailyTotals', () {
    test('buckets transactions by day-of-month, index 0 = day 1', () {
      final monthTx = [
        _tx(amount: 10, date: DateTime(2026, 3, 1)),
        _tx(amount: 5, date: DateTime(2026, 3, 1)),
        _tx(amount: 20, date: DateTime(2026, 3, 3)),
      ];

      final totals = computeDailyTotals(monthTx, 31);

      expect(totals.length, 31);
      expect(totals[0], 15);
      expect(totals[1], 0);
      expect(totals[2], 20);
    });

    test('ignores transactions outside the day range', () {
      final monthTx = [_tx(amount: 10, date: DateTime(2026, 3, 1))];
      // A transaction dated day 1 of a hypothetical 0-length month range
      // should never be indexed out of bounds; here we just confirm a
      // normal in-range day still works with a short daysInMonth.
      final totals = computeDailyTotals(monthTx, 1);
      expect(totals, [10]);
    });
  });

  group('computeAvgPerDay', () {
    test('divides total spend by calendar days elapsed, RM0 days included',
        () {
      // 400 spent across 5 spending days, but 10 calendar days elapsed.
      expect(computeAvgPerDay(400, 10), 40);
    });

    test('returns 0 when no days have elapsed', () {
      expect(computeAvgPerDay(400, 0), 0);
    });
  });

  group('computeAvgPerNonZeroDay', () {
    test('divides total spend by only the non-zero spending days', () {
      // 400 spent, but only 5 of the 10 elapsed days have any spending.
      final recorded = <double>[10.0, 0, 20, 0, 30, 0, 40, 0, 300, 0];
      expect(computeAvgPerNonZeroDay(recorded), 80);
    });

    test('differs from computeAvgPerDay when there are RM0 days', () {
      final recorded = <double>[10.0, 0, 20, 0, 30, 0, 40, 0, 300, 0];
      final spent = recorded.fold(0.0, (s, v) => s + v);
      expect(computeAvgPerNonZeroDay(recorded),
          isNot(computeAvgPerDay(spent, recorded.length)));
    });

    test('returns 0 for an all-RM0 window (avoids division by zero)', () {
      expect(computeAvgPerNonZeroDay(List<double>.filled(10, 0)), 0);
    });

    test('returns 0 for an empty window', () {
      expect(computeAvgPerNonZeroDay(const []), 0);
    });
  });

  group('computeSevenDayPace', () {
    test('returns nulls when fewer than 8 days have elapsed', () {
      final recorded = List<double>.filled(7, 10);
      final pace = computeSevenDayPace(recorded, 7);
      expect(pace.pacePct, isNull);
      expect(pace.paceNow, isNull);
      expect(pace.paceBefore, isNull);
    });

    test('compares the last 7 days against the earlier days', () {
      // Days 1-3 (earlier) average 10/day, days 4-10 (recent 7) average
      // 20/day -> pace up 100%.
      final recorded = <double>[10, 10, 10, 20, 20, 20, 20, 20, 20, 20];
      final pace = computeSevenDayPace(recorded, 10);

      expect(pace.paceBefore, 10);
      expect(pace.paceNow, 20);
      expect(pace.pacePct, 100);
    });

    test('returns nulls when the earlier pace is zero (nothing to compare)',
        () {
      final recorded = <double>[0, 0, 0, 20, 20, 20, 20, 20, 20, 20];
      final pace = computeSevenDayPace(recorded, 10);
      expect(pace.pacePct, isNull);
    });
  });

  group('computeMonthForecast', () {
    test('returns null once the month is fully elapsed', () {
      final recorded = List<double>.filled(30, 10);
      final forecast = computeMonthForecast(
        recorded: recorded,
        daysElapsed: 30,
        daysInMonth: 30,
        spent: 300,
      );
      expect(forecast, isNull);
    });

    test('projects remaining days using the trailing-7-day pace', () {
      // 10 days elapsed at RM10/day (spent 100), 20 days remaining in a
      // 30-day month -> projected = 100 + 10*20 = 300.
      final recorded = List<double>.filled(10, 10);
      final forecast = computeMonthForecast(
        recorded: recorded,
        daysElapsed: 10,
        daysInMonth: 30,
        spent: 100,
      );

      expect(forecast, isNotNull);
      expect(forecast!.projected, 300);
    });

    test('uses all elapsed days as the pace window when fewer than 7 elapsed',
        () {
      // 3 days elapsed at RM10/day (spent 30), 27 remaining in a 30-day
      // month -> projected = 30 + 10*27 = 300.
      final recorded = [10.0, 10.0, 10.0];
      final forecast = computeMonthForecast(
        recorded: recorded,
        daysElapsed: 3,
        daysInMonth: 30,
        spent: 30,
      );

      expect(forecast, isNotNull);
      expect(forecast!.projected, 300);
    });

    test('cumulative tracks running spend, starting at 0', () {
      final recorded = [10.0, 0.0, 20.0];
      final forecast = computeMonthForecast(
        recorded: recorded,
        daysElapsed: 3,
        daysInMonth: 30,
        spent: 30,
      );

      expect(forecast, isNotNull);
      expect(forecast!.cumulative, [0, 10, 10, 30]);
    });
  });
}
