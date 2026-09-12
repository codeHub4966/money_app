import 'package:flutter_test/flutter_test.dart';
import 'package:money_app_flutter/core/services/insight_notification_detector.dart';
import 'package:money_app_flutter/core/utils/category_change.dart';
import 'package:money_app_flutter/presentation/providers/insight_notification_provider.dart';

SpendingSnapshot _snapshot({
  double avgDay = 50,
  int daysElapsed = 10,
  List<SpendingSpike> spikes = const [],
  double? pacePct,
  double? forecastProjected,
  CategoryChange? categoryChange,
}) {
  return SpendingSnapshot(
    avgDay: avgDay,
    daysElapsed: daysElapsed,
    spikes: spikes,
    pacePct: pacePct,
    forecastProjected: forecastProjected,
    categoryChange: categoryChange,
  );
}

void main() {
  group('computeNewSpikesToSchedule (requirement 2: delayed anomaly alert)',
      () {
    final now = DateTime(2026, 3, 10, 9, 0);
    final spike = SpendingSpike(
      date: DateTime(2026, 3, 6),
      amount: 200,
      topCategory: 'Electronics',
    );

    test('schedules a new spike exactly kUnusualSpendingDelay after now', () {
      final result = computeNewSpikesToSchedule(
        snapshot: _snapshot(spikes: [spike]),
        alreadyScheduled: const {},
        now: now,
      );

      expect(result.notifications, hasLength(1));
      expect(result.notifications.single.scheduledDate,
          now.add(kUnusualSpendingDelay));
      expect(result.notifications.single.scheduledDate,
          now.add(const Duration(minutes: 3)));
      expect(result.notifications.single.title, 'Unusual spending detected');
      expect(result.updatedSignatures, {'2026-03-06'});
    });

    test('does not mention any delay in the notification text', () {
      final result = computeNewSpikesToSchedule(
        snapshot: _snapshot(spikes: [spike]),
        alreadyScheduled: const {},
        now: now,
      );

      final body = result.notifications.single.body.toLowerCase();
      expect(body.contains('minute'), isFalse);
      expect(body.contains('later'), isFalse);
      expect(body.contains('delay'), isFalse);
    });

    test(
        'the multiplier in the body text is computed from the RM0-excluded avgDay',
        () {
      // avgDay here is assumed already computed as spent/non-zero-days (as
      // computeCurrentMonthSnapshot does) — this only checks that the
      // multiplier passes that value through untouched rather than
      // re-deriving it from elapsed calendar days.
      final result = computeNewSpikesToSchedule(
        snapshot: _snapshot(avgDay: 80, spikes: [spike]),
        alreadyScheduled: const {},
        now: now,
      );

      expect(result.notifications.single.body, contains('2.5x your average'));
    });

    test(
        'duplicate prevention: an already-scheduled spike is not scheduled again',
        () {
      final result = computeNewSpikesToSchedule(
        snapshot: _snapshot(spikes: [spike]),
        alreadyScheduled: {'2026-03-06'},
        now: now,
      );

      expect(result.notifications, isEmpty);
      expect(result.updatedSignatures, {'2026-03-06'});
    });
  });

  group(
      'computeNextDaySummaryUpdate (requirement 3: combined next-day summary)',
      () {
    final now = DateTime(2026, 3, 10, 21, 30);

    test('schedules for 11:00 local time on the following day', () {
      final update = computeNextDaySummaryUpdate(
        snapshot: _snapshot(forecastProjected: 1200),
        now: now,
      );

      expect(update, isNotNull);
      expect(update!.scheduledDate, DateTime(2026, 3, 11, 11, 0));
    });

    test('includes one line per available result, in order', () {
      final update = computeNextDaySummaryUpdate(
        snapshot: _snapshot(
          forecastProjected: 1200,
          pacePct: 15,
          categoryChange:
              const CategoryChange(previous: 'Food', current: 'Transport'),
        ),
        now: now,
      );

      expect(update, isNotNull);
      expect(update!.lines, hasLength(3));
      expect(update.lines[0], contains('Projected month-end spending'));
      expect(update.lines[1], contains('Spending pace'));
      expect(update.lines[2],
          'Your leading spending category changed from Food to Transport.');
    });

    test('includes only the results that are available', () {
      final update = computeNextDaySummaryUpdate(
        snapshot: _snapshot(pacePct: -10),
        now: now,
      );

      expect(update, isNotNull);
      expect(update!.lines, hasLength(1));
      expect(update.lines.single, contains('Spending pace'));
    });

    test('returns null when nothing is available yet', () {
      final update =
          computeNextDaySummaryUpdate(snapshot: _snapshot(), now: now);
      expect(update, isNull);
    });

    test(
        'duplicate prevention: unchanged content for the same target day is not rescheduled',
        () {
      final snapshot = _snapshot(forecastProjected: 1200);
      final first = computeNextDaySummaryUpdate(snapshot: snapshot, now: now);
      expect(first, isNotNull);

      final second = computeNextDaySummaryUpdate(
        snapshot: snapshot,
        now: now,
        storedTargetSignature: first!.targetSignature,
        storedContentSignature: first.contentSignature,
      );

      expect(second, isNull);
    });

    test('replaces the pending summary once its content changes', () {
      final first = computeNextDaySummaryUpdate(
        snapshot: _snapshot(forecastProjected: 1200),
        now: now,
      );
      expect(first, isNotNull);

      // Same target day, but the forecast has since moved.
      final second = computeNextDaySummaryUpdate(
        snapshot: _snapshot(forecastProjected: 1500),
        now: now,
        storedTargetSignature: first!.targetSignature,
        storedContentSignature: first.contentSignature,
      );

      expect(second, isNotNull);
      expect(second!.contentSignature, isNot(first.contentSignature));
      expect(second.scheduledDate, first.scheduledDate);
    });
  });
}
