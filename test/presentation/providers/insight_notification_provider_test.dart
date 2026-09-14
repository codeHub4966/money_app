import 'package:flutter_test/flutter_test.dart';
import 'package:money_app_flutter/core/services/insight_notification_detector.dart';
import 'package:money_app_flutter/core/utils/category_change.dart';
import 'package:money_app_flutter/presentation/providers/insight_notification_provider.dart';

Future<void> _pumpEventLoop() => Future<void>.delayed(Duration.zero);

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

  group('decideNextDaySummaryAction (cancel/clear on no-longer-eligible)', () {
    final now = DateTime(2026, 3, 10, 21, 30);

    test('none: nothing eligible and nothing was pending', () {
      final decision = decideNextDaySummaryAction(
        snapshot: _snapshot(),
        now: now,
      );

      expect(decision.action, NextDaySummaryAction.none);
      expect(decision.update, isNull);
    });

    test(
        'clear: recalculation no longer has anything eligible, but a summary was pending',
        () {
      final decision = decideNextDaySummaryAction(
        snapshot: _snapshot(), // e.g. the transaction behind it was deleted
        now: now,
        storedTargetSignature: '2026-03-11',
        storedContentSignature: 'Projected month-end spending: RM1200.',
      );

      expect(decision.action, NextDaySummaryAction.clear);
      expect(decision.update, isNull);
    });

    test('replace: new eligible content with nothing previously pending', () {
      final decision = decideNextDaySummaryAction(
        snapshot: _snapshot(forecastProjected: 1200),
        now: now,
      );

      expect(decision.action, NextDaySummaryAction.replace);
      expect(decision.update, isNotNull);
      expect(decision.update!.scheduledDate, DateTime(2026, 3, 11, 11, 0));
    });

    test('replace: content changed from what was pending', () {
      final decision = decideNextDaySummaryAction(
        snapshot: _snapshot(forecastProjected: 1500),
        now: now,
        storedTargetSignature: '2026-03-11',
        storedContentSignature: 'Projected month-end spending: RM1200.',
      );

      expect(decision.action, NextDaySummaryAction.replace);
      expect(decision.update!.contentSignature,
          'Projected month-end spending: RM1500.');
    });

    test('none: target day and content unchanged from what was pending', () {
      final update = computeNextDaySummaryUpdate(
        snapshot: _snapshot(forecastProjected: 1200),
        now: now,
      )!;

      final decision = decideNextDaySummaryAction(
        snapshot: _snapshot(forecastProjected: 1200),
        now: now,
        storedTargetSignature: update.targetSignature,
        storedContentSignature: update.contentSignature,
      );

      expect(decision.action, NextDaySummaryAction.none);
    });
  });

  group('LatestOnlySerialRunner', () {
    test('runs a single scheduled value', () async {
      final calls = <int>[];
      final runner = LatestOnlySerialRunner<int>((v) async {
        calls.add(v);
      });

      runner.schedule(1);
      await _pumpEventLoop();

      expect(calls, [1]);
    });

    test('never overlaps: a slow call blocks the next one from starting',
        () async {
      final running = <int>[];
      var maxConcurrent = 0;
      final runner = LatestOnlySerialRunner<int>((v) async {
        running.add(v);
        maxConcurrent =
            running.length > maxConcurrent ? running.length : maxConcurrent;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        running.remove(v);
      });

      runner.schedule(1);
      runner.schedule(2);
      runner.schedule(3);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(maxConcurrent, 1);
    });

    test(
        'drops values superseded while a run is in flight, keeping only the latest',
        () async {
      final calls = <int>[];
      final runner = LatestOnlySerialRunner<int>((v) async {
        // Simulate the first (slow) run still being in flight when 2 and 3
        // are scheduled, so only 1 (already started) and 3 (the latest by
        // the time the first run finishes) should ever be handled.
        await Future<void>.delayed(const Duration(milliseconds: 20));
        calls.add(v);
      });

      runner.schedule(1);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      runner.schedule(2);
      runner.schedule(3);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(calls, [1, 3]);
    });

    test(
        'a call that starts later can never finish before/overwrite an earlier still-running one out of order',
        () async {
      // Regression guard for "prevent rapid transaction updates from
      // allowing an older calculation to overwrite a newer one": since the
      // runner never runs two calls concurrently, results are always
      // applied in the order the handler was invoked, never interleaved.
      final order = <String>[];
      final runner = LatestOnlySerialRunner<int>((v) async {
        order.add('start:$v');
        await Future<void>.delayed(Duration(milliseconds: v == 1 ? 30 : 5));
        order.add('end:$v');
      });

      runner.schedule(1);
      await _pumpEventLoop();
      runner.schedule(2);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(order, ['start:1', 'end:1', 'start:2', 'end:2']);
    });
  });
}
