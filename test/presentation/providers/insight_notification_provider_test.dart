import 'package:flutter_test/flutter_test.dart';
import 'package:money_app_flutter/core/services/insight_notification_detector.dart';
import 'package:money_app_flutter/core/utils/budget_risk_detector.dart';
import 'package:money_app_flutter/core/utils/category_change.dart';
import 'package:money_app_flutter/core/utils/category_overspending_detector.dart';
import 'package:money_app_flutter/core/utils/merchant_pattern_detector.dart';
import 'package:money_app_flutter/core/utils/saving_opportunity_detector.dart';
import 'package:money_app_flutter/presentation/providers/insight_notification_provider.dart';

Future<void> _pumpEventLoop() => Future<void>.delayed(Duration.zero);

SpendingSnapshot _snapshot({
  double avgDay = 50,
  double? avgNonZeroDay,
  int daysElapsed = 10,
  List<SpendingSpike> spikes = const [],
  double? pacePct,
  double? forecastProjected,
  CategoryChange? categoryChange,
  List<BudgetRisk> budgetRisks = const [],
  List<CategoryOverspend> categoryOverspends = const [],
  List<MerchantPattern> merchantPatterns = const [],
  SavingOpportunity? savingOpportunity,
}) {
  return SpendingSnapshot(
    avgDay: avgDay,
    avgNonZeroDay: avgNonZeroDay ?? avgDay,
    daysElapsed: daysElapsed,
    spikes: spikes,
    pacePct: pacePct,
    forecastProjected: forecastProjected,
    categoryChange: categoryChange,
    budgetRisks: budgetRisks,
    categoryOverspends: categoryOverspends,
    merchantPatterns: merchantPatterns,
    savingOpportunity: savingOpportunity,
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
      expect(result.updatedEntries.keys, {'2026-03-06'});
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
        'the multiplier in the body text is computed from the snapshot avgNonZeroDay, '
        'not the calendar-day avgDay', () {
      // avgNonZeroDay here is assumed already computed as the average of
      // non-zero spending days (as computeCurrentMonthSnapshot does) — this
      // checks the multiplier passes that value through untouched rather
      // than re-deriving it, and that it ignores avgDay entirely.
      final result = computeNewSpikesToSchedule(
        snapshot: _snapshot(avgDay: 20, avgNonZeroDay: 80, spikes: [spike]),
        alreadyScheduled: const {},
        now: now,
      );

      expect(result.notifications.single.body, contains('2.5x your average'));
    });

    test(
        'duplicate prevention: an already-scheduled spike with unchanged content is not scheduled again',
        () {
      final first = computeNewSpikesToSchedule(
        snapshot: _snapshot(spikes: [spike]),
        alreadyScheduled: const {},
        now: now,
      );

      final second = computeNewSpikesToSchedule(
        snapshot: _snapshot(spikes: [spike]),
        alreadyScheduled: first.updatedEntries,
        now: now,
      );

      expect(second.notifications, isEmpty);
      expect(second.updatedEntries.keys, {'2026-03-06'});
    });

    test(
        'stale content: a still-current spike whose amount changed is rescheduled under the same id',
        () {
      final first = computeNewSpikesToSchedule(
        snapshot: _snapshot(spikes: [spike]),
        alreadyScheduled: const {},
        now: now,
      );
      expect(first.notifications, hasLength(1));
      final originalId = first.notifications.single.id;

      // Same day, but the transaction behind the spike was edited so its
      // amount (and thus the notification body) changed.
      final editedSpike = SpendingSpike(
        date: DateTime(2026, 3, 6),
        amount: 500,
        topCategory: 'Electronics',
      );
      final second = computeNewSpikesToSchedule(
        snapshot: _snapshot(spikes: [editedSpike]),
        alreadyScheduled: first.updatedEntries,
        now: now.add(const Duration(minutes: 1)),
      );

      expect(second.notifications, hasLength(1));
      expect(second.notifications.single.id, originalId);
      expect(second.notifications.single.body,
          isNot(first.notifications.single.body));
      // Fresh ~3-minute delay from the latest recalculation.
      expect(second.notifications.single.scheduledDate,
          now.add(const Duration(minutes: 1)).add(kUnusualSpendingDelay));
    });
  });

  group('staleSignaturesToCancel (cancel stale pending notifications)', () {
    test('returns signatures no longer present after a recalculation', () {
      final stale = staleSignaturesToCancel(
        alreadyScheduled: {'2026-03-06', '2026-03-08'},
        currentSignatures: {'2026-03-08'},
      );
      expect(stale, {'2026-03-06'});
    });

    test('empty when every previously-scheduled signature is still current',
        () {
      final stale = staleSignaturesToCancel(
        alreadyScheduled: {'2026-03-06'},
        currentSignatures: {'2026-03-06', '2026-03-08'},
      );
      expect(stale, isEmpty);
    });

    test(
        'full scenario: a spike that disappears after recalculation is flagged stale and dropped',
        () {
      final now = DateTime(2026, 3, 10, 9, 0);
      final spike = SpendingSpike(
        date: DateTime(2026, 3, 6),
        amount: 200,
        topCategory: 'Electronics',
      );

      // First recalculation schedules the spike and persists its signature.
      final first = computeNewSpikesToSchedule(
        snapshot: _snapshot(spikes: [spike]),
        alreadyScheduled: const {},
        now: now,
      );
      expect(first.notifications, hasLength(1));

      // The underlying transaction was edited/deleted so it's no longer an
      // unusual-spending day — the next recalculation has no spikes.
      final stale = staleSignaturesToCancel(
        alreadyScheduled: first.updatedEntries.keys.toSet(),
        currentSignatures: const {},
      );
      expect(stale, {'2026-03-06'});

      // Nothing new to schedule for an empty spike list.
      final second = computeNewSpikesToSchedule(
        snapshot: _snapshot(spikes: const []),
        alreadyScheduled: first.updatedEntries,
        now: now,
      );
      expect(second.notifications, isEmpty);
    });
  });

  group('computeNewBudgetRisksToSchedule (Tier A: ~3 min delay)', () {
    final now = DateTime(2026, 3, 10, 9, 0);
    const risk = BudgetRisk(
      category: 'Food',
      monthlyLimit: 300,
      spent: 200,
      projected: 620,
      overageAmount: 320,
    );

    test('schedules a new budget risk exactly kUnusualSpendingDelay after now',
        () {
      final result = computeNewBudgetRisksToSchedule(
        risks: [risk],
        alreadyScheduled: const {},
        now: now,
      );

      expect(result.notifications, hasLength(1));
      expect(result.notifications.single.scheduledDate,
          now.add(kUnusualSpendingDelay));
      expect(result.notifications.single.body, contains('Food'));
      expect(result.notifications.single.body, contains('RM320'));
      expect(result.updatedEntries.keys, {'budget_risk:Food'});
    });

    test(
        'duplicate prevention: an already-scheduled category risk with unchanged content is not scheduled again',
        () {
      final first = computeNewBudgetRisksToSchedule(
        risks: [risk],
        alreadyScheduled: const {},
        now: now,
      );
      final second = computeNewBudgetRisksToSchedule(
        risks: [risk],
        alreadyScheduled: first.updatedEntries,
        now: now,
      );
      expect(second.notifications, isEmpty);
    });

    test(
        'stale content: a still-current risk whose overage amount changed is rescheduled under the same id',
        () {
      final first = computeNewBudgetRisksToSchedule(
        risks: [risk],
        alreadyScheduled: const {},
        now: now,
      );
      final originalId = first.notifications.single.id;

      const changedRisk = BudgetRisk(
        category: 'Food',
        monthlyLimit: 300,
        spent: 250,
        projected: 700,
        overageAmount: 400,
      );
      final second = computeNewBudgetRisksToSchedule(
        risks: [changedRisk],
        alreadyScheduled: first.updatedEntries,
        now: now.add(const Duration(minutes: 1)),
      );

      expect(second.notifications, hasLength(1));
      expect(second.notifications.single.id, originalId);
      expect(second.notifications.single.body, contains('RM400'));
      expect(second.notifications.single.scheduledDate,
          now.add(const Duration(minutes: 1)).add(kUnusualSpendingDelay));
    });
  });

  group('computeNewCategoryOverspendToSchedule (Tier A: ~3 min delay)', () {
    final now = DateTime(2026, 3, 10, 9, 0);
    const overspend = CategoryOverspend(
      category: 'Shopping',
      currentAmount: 145,
      previousAmount: 100,
      pctIncrease: 45,
    );

    test(
        'schedules a new category overspend exactly kUnusualSpendingDelay after now',
        () {
      final result = computeNewCategoryOverspendToSchedule(
        overspends: [overspend],
        alreadyScheduled: const {},
        now: now,
      );

      expect(result.notifications, hasLength(1));
      expect(result.notifications.single.scheduledDate,
          now.add(kUnusualSpendingDelay));
      expect(result.notifications.single.body, contains('Shopping'));
      expect(result.notifications.single.body, contains('45%'));
      expect(result.updatedEntries.keys, {'overspend:Shopping'});
    });

    test(
        'duplicate prevention: an already-scheduled category overspend with unchanged content is not scheduled again',
        () {
      final first = computeNewCategoryOverspendToSchedule(
        overspends: [overspend],
        alreadyScheduled: const {},
        now: now,
      );
      final second = computeNewCategoryOverspendToSchedule(
        overspends: [overspend],
        alreadyScheduled: first.updatedEntries,
        now: now,
      );
      expect(second.notifications, isEmpty);
    });

    test(
        'stale content: a still-current overspend whose percentage changed is rescheduled under the same id',
        () {
      final first = computeNewCategoryOverspendToSchedule(
        overspends: [overspend],
        alreadyScheduled: const {},
        now: now,
      );
      final originalId = first.notifications.single.id;

      const changedOverspend = CategoryOverspend(
        category: 'Shopping',
        currentAmount: 200,
        previousAmount: 100,
        pctIncrease: 100,
      );
      final second = computeNewCategoryOverspendToSchedule(
        overspends: [changedOverspend],
        alreadyScheduled: first.updatedEntries,
        now: now.add(const Duration(minutes: 1)),
      );

      expect(second.notifications, hasLength(1));
      expect(second.notifications.single.id, originalId);
      expect(second.notifications.single.body, contains('100%'));
      expect(second.notifications.single.scheduledDate,
          now.add(const Duration(minutes: 1)).add(kUnusualSpendingDelay));
    });
  });

  group('compute6pmDigestUpdate / decideSixPmDigestAction (Tier B: 6:00 PM)',
      () {
    test('targets today 6:00 PM when now is before 6 PM', () {
      final now = DateTime(2026, 3, 10, 14, 0);
      final update = compute6pmDigestUpdate(
        snapshot: _snapshot(savingOpportunity:
            const SavingOpportunity(estimatedSavings: 180, pacePct: -30)),
        now: now,
      );

      expect(update, isNotNull);
      expect(update!.scheduledDate, DateTime(2026, 3, 10, 18, 0));
    });

    test('targets tomorrow 6:00 PM when now is after 6 PM', () {
      final now = DateTime(2026, 3, 10, 20, 0);
      final update = compute6pmDigestUpdate(
        snapshot: _snapshot(savingOpportunity:
            const SavingOpportunity(estimatedSavings: 180, pacePct: -30)),
        now: now,
      );

      expect(update, isNotNull);
      expect(update!.scheduledDate, DateTime(2026, 3, 11, 18, 0));
    });

    test('includes merchant pattern and saving opportunity lines', () {
      final now = DateTime(2026, 3, 10, 14, 0);
      final update = compute6pmDigestUpdate(
        snapshot: _snapshot(
          merchantPatterns: [
            MerchantPattern(
              type: MerchantPatternType.repeated,
              merchant: 'Starbucks',
              amount: 90,
              count: 4,
              lastDate: DateTime(2026, 3, 9),
            ),
          ],
          savingOpportunity:
              const SavingOpportunity(estimatedSavings: 180, pacePct: -30),
        ),
        now: now,
      );

      expect(update, isNotNull);
      expect(update!.lines, hasLength(2));
      expect(update.lines[0], contains('Starbucks'));
      expect(update.lines[1], contains('RM180'));
    });

    test('returns null when nothing is available yet', () {
      final update =
          compute6pmDigestUpdate(snapshot: _snapshot(), now: DateTime(2026, 3, 10, 14, 0));
      expect(update, isNull);
    });

    test('duplicate prevention: unchanged content is not rescheduled', () {
      final now = DateTime(2026, 3, 10, 14, 0);
      final snapshot = _snapshot(
          savingOpportunity:
              const SavingOpportunity(estimatedSavings: 180, pacePct: -30));
      final first = compute6pmDigestUpdate(snapshot: snapshot, now: now);
      expect(first, isNotNull);

      final second = compute6pmDigestUpdate(
        snapshot: snapshot,
        now: now,
        storedTargetSignature: first!.targetSignature,
        storedContentSignature: first.contentSignature,
      );
      expect(second, isNull);
    });

    test('decideSixPmDigestAction: clear when no longer eligible but was pending',
        () {
      final now = DateTime(2026, 3, 10, 14, 0);
      final decision = decideSixPmDigestAction(
        snapshot: _snapshot(),
        now: now,
        storedTargetSignature: '2026-03-10T18:00',
        storedContentSignature: 'At your current pace...',
      );
      expect(decision.action, SixPmDigestAction.clear);
    });

    test('decideSixPmDigestAction: replace with new eligible content', () {
      final now = DateTime(2026, 3, 10, 14, 0);
      final decision = decideSixPmDigestAction(
        snapshot: _snapshot(
            savingOpportunity:
                const SavingOpportunity(estimatedSavings: 180, pacePct: -30)),
        now: now,
      );
      expect(decision.action, SixPmDigestAction.replace);
    });

    test('decideSixPmDigestAction: none when nothing eligible and nothing pending',
        () {
      final decision = decideSixPmDigestAction(
        snapshot: _snapshot(),
        now: DateTime(2026, 3, 10, 14, 0),
      );
      expect(decision.action, SixPmDigestAction.none);
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
