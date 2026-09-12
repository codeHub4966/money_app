import '../../domain/models/transaction.dart' as tx;

/// The leading (highest-spend) category among [monthTx] for days up to and
/// including [upToDay], or `null` when there's no spending in that window.
///
/// [monthTx] must already be filtered to the anomaly-eligible expense
/// transactions for a single month (see `isAnomalyEligibleExpense` in
/// spending_anomaly.dart).
String? leadingCategory(List<tx.Transaction> monthTx, int upToDay) {
  final totals = <String, double>{};
  for (final t in monthTx) {
    if (t.date.day > upToDay) continue;
    totals[t.category] = (totals[t.category] ?? 0) + t.amount;
  }
  if (totals.isEmpty) return null;
  final sorted = totals.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return sorted.first.key;
}

/// A change in leading spending category between two comparable periods.
class CategoryChange {
  final String previous;
  final String current;
  const CategoryChange({required this.previous, required this.current});
}

/// Compares the leading category so far this period against the same-length
/// period last month.
///
/// Returns `null` unless both periods have spending data (via
/// [leadingCategory]) and the leading category actually changed between
/// them — this is the single shared calculation used by both the Insights
/// page and the notification detector so they can't drift apart.
CategoryChange? detectCategoryChange({
  required List<tx.Transaction> currentMonthTx,
  required List<tx.Transaction> previousMonthTx,
  required int daysElapsed,
}) {
  final current = leadingCategory(currentMonthTx, daysElapsed);
  final previous = leadingCategory(previousMonthTx, daysElapsed);
  if (current == null || previous == null) return null;
  if (current == previous) return null;
  return CategoryChange(previous: previous, current: current);
}
