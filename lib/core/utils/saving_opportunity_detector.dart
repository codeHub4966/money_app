import 'spending_forecast_calculator.dart';

/// Shared saving-opportunity math used by both the Insights tab and the
/// notification detector. Built entirely from the already-shared
/// `computeSevenDayPace`/`computeMonthForecast` so a "pace is down" reading
/// can never disagree between the two surfaces.

/// How far below the earlier-in-month pace the last 7 days must be before
/// it's considered a real saving opportunity (not noise).
const double kMinPaceDropPctForSavingOpportunity = -20.0;

/// Minimum estimated month-end savings before it's worth surfacing.
const double kMinSavingOpportunityAmount = 10.0;

/// A detected drop in spending pace and the month-end savings it implies if
/// it continues.
class SavingOpportunity {
  final double estimatedSavings;
  final double pacePct;
  const SavingOpportunity(
      {required this.estimatedSavings, required this.pacePct});
}

/// Detects whether the user's recent (last-7-day) spending pace is clearly
/// lower than their earlier pace this month, and estimates how much less
/// they may spend by month end if it continues.
///
/// [recorded] must be the per-day totals for days `1..daysElapsed` only.
/// Returns `null` when there isn't enough elapsed history for
/// [computeSevenDayPace] to compare (fewer than 8 days — this is also what
/// "enough data available" means here), when the pace isn't clearly down, or
/// when the estimated savings don't clear [kMinSavingOpportunityAmount].
SavingOpportunity? detectSavingOpportunity({
  required List<double> recorded,
  required int daysElapsed,
  required int daysInMonth,
  required double spent,
}) {
  final pace = computeSevenDayPace(recorded, daysElapsed);
  final pacePct = pace.pacePct;
  final paceBefore = pace.paceBefore;
  if (pacePct == null || paceBefore == null) return null;
  if (pacePct > kMinPaceDropPctForSavingOpportunity) return null;

  final forecast = computeMonthForecast(
    recorded: recorded,
    daysElapsed: daysElapsed,
    daysInMonth: daysInMonth,
    spent: spent,
  );
  if (forecast == null) return null;

  final projectedAtOldPace = spent + paceBefore * (daysInMonth - daysElapsed);
  final estimatedSavings =
      (projectedAtOldPace - forecast.projected).clamp(0.0, double.infinity);
  if (estimatedSavings < kMinSavingOpportunityAmount) return null;

  return SavingOpportunity(estimatedSavings: estimatedSavings, pacePct: pacePct);
}
