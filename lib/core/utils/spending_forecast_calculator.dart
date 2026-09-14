import '../../domain/models/transaction.dart' as tx;

/// Shared spending-forecast math used by both the Insights tab
/// (`insights_tab.dart`) and the notification detector
/// (`insight_notification_detector.dart`), so the two surfaces can never
/// drift apart on average/day, 7-day pace, or the month-end forecast.

/// Buckets [monthTx] (already filtered to the eligible expenses for a single
/// month) into a fixed-length list of per-day totals, index `i` = day `i+1`.
List<double> computeDailyTotals(List<tx.Transaction> monthTx, int daysInMonth) {
  final dailyTotals = List<double>.filled(daysInMonth, 0);
  for (final t in monthTx) {
    if (t.date.day >= 1 && t.date.day <= daysInMonth) {
      dailyTotals[t.date.day - 1] += t.amount;
    }
  }
  return dailyTotals;
}

/// Calendar-day spending average: total spent so far this month divided by
/// the number of calendar days elapsed (RM0 days included in the divisor).
double computeAvgPerDay(double spent, int daysElapsed) =>
    daysElapsed > 0 ? spent / daysElapsed : 0.0;

/// Average spend across only the days that had any recorded spending ("your
/// normal spending day"), used for the unusual-spending multiplier so a
/// month with many RM0 days doesn't understate how much bigger a spike is
/// than a typical spending day. [recorded] must be the per-day totals for
/// days `1..daysElapsed` only. Returns 0 when there are no non-zero days.
double computeAvgPerNonZeroDay(List<double> recorded) {
  final nonZero = recorded.where((v) => v > 0).toList();
  if (nonZero.isEmpty) return 0.0;
  return nonZero.fold(0.0, (s, v) => s + v) / nonZero.length;
}

/// Result of [computeSevenDayPace]: the trailing-7-day daily average vs the
/// daily average for the rest of the elapsed month, and the percent change
/// between them. All fields are null when there isn't enough elapsed history
/// (fewer than 8 days) or the "earlier" pace is zero (nothing to compare
/// against).
class SpendingPace {
  final double? pacePct;
  final double? paceNow;
  final double? paceBefore;
  const SpendingPace({this.pacePct, this.paceNow, this.paceBefore});
}

/// Compares the last 7 elapsed days' average daily spend against the average
/// for the days before that, within the current month. [recorded] must be
/// the per-day totals for days `1..daysElapsed` only.
SpendingPace computeSevenDayPace(List<double> recorded, int daysElapsed) {
  if (daysElapsed < 8) return const SpendingPace();
  final recent7 = recorded.sublist(daysElapsed - 7);
  final earlier = recorded.sublist(0, daysElapsed - 7);
  final paceNow = recent7.fold(0.0, (s, v) => s + v) / 7;
  final paceBefore = earlier.isEmpty
      ? 0.0
      : earlier.fold(0.0, (s, v) => s + v) / earlier.length;
  if (paceBefore <= 0) return const SpendingPace();
  return SpendingPace(
    paceNow: paceNow,
    paceBefore: paceBefore,
    pacePct: (paceNow - paceBefore) / paceBefore * 100,
  );
}

/// Result of [computeMonthForecast]: the projected month-end total and the
/// running cumulative spend for each elapsed day (index 0 = RM0 before day
/// 1), used to draw the forecast trend line.
class SpendingForecast {
  final double projected;
  final List<double> cumulative;
  const SpendingForecast({required this.projected, required this.cumulative});
}

/// Projects month-end spending from a trailing pace (the last 7 elapsed days,
/// or all elapsed days if fewer than 7) applied to the remaining days in the
/// month. [recorded] must be the per-day totals for days `1..daysElapsed`
/// only. Returns `null` once the month is over (`daysElapsed >= daysInMonth`)
/// since there are no remaining days to project.
SpendingForecast? computeMonthForecast({
  required List<double> recorded,
  required int daysElapsed,
  required int daysInMonth,
  required double spent,
}) {
  if (daysElapsed >= daysInMonth) return null;
  final paceWindow =
      daysElapsed >= 7 ? recorded.sublist(daysElapsed - 7) : recorded;
  final pace = paceWindow.fold(0.0, (s, v) => s + v) / paceWindow.length;
  final projected = spent + pace * (daysInMonth - daysElapsed);

  final cumulative = <double>[0];
  var run = 0.0;
  for (var i = 0; i < daysElapsed; i++) {
    run += recorded[i];
    cumulative.add(run);
  }
  return SpendingForecast(projected: projected, cumulative: cumulative);
}
