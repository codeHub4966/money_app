import 'dart:math';

/// Shared weekly-bucketing math for the Insights tab's Weekly Trend view, so
/// the bar values and the dashed average line can never drift apart on what
/// counts as a "completed" week.

/// A single week's aggregated spending within a month. Weeks are
/// non-overlapping 7-day windows starting at day 1; the final window may be
/// shorter than 7 days when the month doesn't divide evenly.
class WeeklyBucket {
  final int startDay; // 1-indexed, inclusive
  final int endDay; // 1-indexed, inclusive
  final double total;
  final bool future; // hasn't started yet
  final bool partial; // in progress: started but not yet finished
  const WeeklyBucket({
    required this.startDay,
    required this.endDay,
    required this.total,
    required this.future,
    required this.partial,
  });
}

/// Buckets [dailyFull] (index 0 = day 1 of the month) into non-overlapping
/// weekly windows. [daysElapsed] marks how many days of the month have
/// actually happened — a week starting at or after that is [WeeklyBucket.future];
/// a week that straddles it (started but not finished) is
/// [WeeklyBucket.partial].
List<WeeklyBucket> bucketIntoWeeks(List<double> dailyFull, int daysElapsed) {
  final weeks = <WeeklyBucket>[];
  var start = 0;
  final daysInMonth = dailyFull.length;
  while (start < daysInMonth) {
    final end = min(start + 7, daysInMonth);
    final total = dailyFull.sublist(start, end).fold(0.0, (s, x) => s + x);
    weeks.add(WeeklyBucket(
      startDay: start + 1,
      endDay: end,
      total: total,
      future: start >= daysElapsed,
      partial: start < daysElapsed && end > daysElapsed,
    ));
    start = end;
  }
  return weeks;
}

/// Average weekly spend across completed weeks only — excludes both future
/// weeks and the current in-progress/partial week, since an incomplete week
/// would understate (or otherwise mislead) the average. Returns `null` when
/// no week has completed yet, so callers can omit the average line entirely
/// instead of showing one derived from a partial week.
double? computeCompletedWeeksAverage(List<WeeklyBucket> weeks) {
  final completed = weeks.where((w) => !w.future && !w.partial).toList();
  if (completed.isEmpty) return null;
  return completed.map((w) => w.total).reduce((a, b) => a + b) /
      completed.length;
}
