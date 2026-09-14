import 'package:flutter_test/flutter_test.dart';
import 'package:money_app_flutter/core/utils/weekly_trend.dart';

void main() {
  group('bucketIntoWeeks', () {
    test('buckets a 31-day month into 5 non-overlapping windows', () {
      final dailyFull = List<double>.filled(31, 10);
      final weeks = bucketIntoWeeks(dailyFull, 31);

      expect(weeks, hasLength(5));
      expect(weeks[0].startDay, 1);
      expect(weeks[0].endDay, 7);
      expect(weeks[0].total, 70);
      // Last window is shorter than 7 days (31 = 4*7 + 3).
      expect(weeks[4].startDay, 29);
      expect(weeks[4].endDay, 31);
      expect(weeks[4].total, 30);
    });

    test('marks a week in progress as partial (still bucketed, not dropped)',
        () {
      // 10 days elapsed: week 1 (days 1-7) is complete, week 2 (days 8-14)
      // is in progress, week 3+ hasn't started. Days after daysElapsed have
      // no recorded spending yet, matching real computeDailyTotals output.
      final dailyFull = [
        for (var i = 0; i < 30; i++) i < 10 ? 5.0 : 0.0,
      ];
      final weeks = bucketIntoWeeks(dailyFull, 10);

      expect(weeks[0].future, isFalse);
      expect(weeks[0].partial, isFalse);
      expect(weeks[1].future, isFalse);
      expect(weeks[1].partial, isTrue);
      // The in-progress week is still present with its (partial) total.
      expect(weeks[1].total, 15); // days 8, 9, 10 only
      expect(weeks[2].future, isTrue);
      expect(weeks[2].partial, isFalse);
    });

    test('no partial week when daysElapsed lands exactly on a week boundary',
        () {
      final dailyFull = List<double>.filled(30, 5);
      final weeks = bucketIntoWeeks(dailyFull, 7);

      expect(weeks[0].future, isFalse);
      expect(weeks[0].partial, isFalse);
      expect(weeks[1].future, isTrue);
      expect(weeks[1].partial, isFalse);
    });
  });

  group('computeCompletedWeeksAverage', () {
    test('averages only completed weeks, excluding the partial current week',
        () {
      // Week 1 complete at 70, week 2 in progress (partial) at 15 — the
      // partial week must not drag the average down.
      final dailyFull = [
        for (var i = 0; i < 30; i++) i < 7 ? 10.0 : 5.0,
      ];
      final weeks = bucketIntoWeeks(dailyFull, 10);

      final avg = computeCompletedWeeksAverage(weeks);

      expect(avg, 70); // only week 1 counts
    });

    test('averages multiple completed weeks correctly', () {
      // 21-day-elapsed window: weeks 1-3 all complete (days 1-21), nothing
      // partial or future among them.
      final dailyFull = [
        for (var i = 0; i < 30; i++) i < 21 ? 10.0 : 0.0,
      ];
      final weeks = bucketIntoWeeks(dailyFull, 21);

      final avg = computeCompletedWeeksAverage(weeks);

      expect(avg, 70); // each of the 3 completed weeks totals 70
    });

    test('returns null when no week has completed yet', () {
      final dailyFull = List<double>.filled(30, 5);
      final weeks = bucketIntoWeeks(dailyFull, 3); // still inside week 1

      expect(computeCompletedWeeksAverage(weeks), isNull);
    });

    test('returns null (not a misleading 0) for the very first day of the month',
        () {
      final dailyFull = List<double>.filled(30, 5);
      final weeks = bucketIntoWeeks(dailyFull, 1);

      expect(computeCompletedWeeksAverage(weeks), isNull);
    });
  });
}
