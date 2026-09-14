import '../../domain/models/transaction.dart' as tx;

/// Minimum number of non-zero spending days required before unusual-spending
/// detection runs at all.
const int kMinSpendingDaysForAnomalyDetection = 5;

const Set<String> _excludedCategories = {'Transfer', 'Balance Adjustment'};

/// Whether [t] should count towards spending totals/anomaly detection for
/// [year]/[month]: an expense, dated in that month, and not a Transfer or
/// Balance Adjustment entry.
bool isAnomalyEligibleExpense(tx.Transaction t, int year, int month) =>
    isEligibleExpense(t) && t.date.year == year && t.date.month == month;

/// Whether [t] should count towards spending totals at all: an expense, not
/// a Transfer or Balance Adjustment entry, regardless of month. Used by
/// detectors that scan across multiple months (see
/// `merchant_pattern_detector.dart`) rather than one specific month.
bool isEligibleExpense(tx.Transaction t) =>
    t.type == tx.TransactionType.expense &&
    !_excludedCategories.contains(t.category);

/// Q1/Q3/IQR and the resulting upper outlier threshold for a set of daily
/// spending totals.
class DailySpendingThreshold {
  final double q1;
  final double q3;
  final double iqr;
  final double upperThreshold;
  const DailySpendingThreshold({
    required this.q1,
    required this.q3,
    required this.iqr,
    required this.upperThreshold,
  });
}

/// A single day flagged as unusual spending.
class UnusualSpendingDay {
  final DateTime date;
  final double amount;
  final String topCategory;
  const UnusualSpendingDay({
    required this.date,
    required this.amount,
    required this.topCategory,
  });
}

double _median(List<double> sortedValues) {
  final n = sortedValues.length;
  final mid = n ~/ 2;
  if (n.isOdd) return sortedValues[mid];
  return (sortedValues[mid - 1] + sortedValues[mid]) / 2;
}

/// Computes the IQR-based unusual-spending threshold from [dailyTotals].
///
/// Days with zero spending are excluded before the quartiles are computed, so
/// no-spend calendar days never affect the average, quartiles, IQR, or
/// threshold. Q1/Q3 use the exclusive-median (Tukey's hinges) method: the
/// sorted non-zero values are split at their midpoint, excluding the middle
/// value itself when the count is odd; Q1 is the median of the lower half and
/// Q3 the median of the upper half.
///
/// Returns `null` when fewer than [kMinSpendingDaysForAnomalyDetection]
/// non-zero spending days are available — detection should not run yet.
DailySpendingThreshold? computeDailySpendingThreshold(
    List<double> dailyTotals) {
  final nonZero = dailyTotals.where((v) => v > 0).toList()..sort();
  if (nonZero.length < kMinSpendingDaysForAnomalyDetection) return null;

  final n = nonZero.length;
  final mid = n ~/ 2;
  final lower = nonZero.sublist(0, mid);
  final upper = n.isOdd ? nonZero.sublist(mid + 1) : nonZero.sublist(mid);
  final q1 = _median(lower);
  final q3 = _median(upper);
  final iqr = q3 - q1;
  return DailySpendingThreshold(
      q1: q1, q3: q3, iqr: iqr, upperThreshold: q3 + 1.5 * iqr);
}

/// Detects unusual spending days among [dailyTotals] (index `i` = day `i + 1`
/// of [month]) using the IQR rule from [computeDailySpendingThreshold].
///
/// A day is unusual only when its total is strictly greater than
/// `Q3 + 1.5 * IQR` — a day exactly at the threshold is not flagged. Returns
/// an empty list when detection can't run yet (fewer than
/// [kMinSpendingDaysForAnomalyDetection] non-zero spending days).
///
/// [monthTx] must already be filtered to the anomaly-eligible transactions
/// for [month] (see [isAnomalyEligibleExpense]) — it's used only to find each
/// unusual day's top spending category. Results are sorted newest-first.
List<UnusualSpendingDay> detectUnusualSpendingDays({
  required List<double> dailyTotals,
  required List<tx.Transaction> monthTx,
  required DateTime month,
}) {
  final threshold = computeDailySpendingThreshold(dailyTotals);
  if (threshold == null) return const [];

  final result = <UnusualSpendingDay>[];
  for (var i = 0; i < dailyTotals.length; i++) {
    final amount = dailyTotals[i];
    if (amount <= threshold.upperThreshold) continue;
    final day = i + 1;
    final byCategory = <String, double>{};
    for (final t in monthTx.where((t) => t.date.day == day)) {
      byCategory[t.category] = (byCategory[t.category] ?? 0) + t.amount;
    }
    final topDayCat = byCategory.entries.isEmpty
        ? 'spending'
        : (byCategory.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value)))
            .first
            .key;
    result.add(UnusualSpendingDay(
      date: DateTime(month.year, month.month, day),
      amount: amount,
      topCategory: topDayCat,
    ));
  }
  result.sort((a, b) => b.date.compareTo(a.date));
  return result;
}
