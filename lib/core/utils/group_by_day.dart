/// Groups [items] by calendar day (year/month/day of [dateOf]'s result),
/// preserving the relative order [items] were given in within each group.
Map<DateTime, List<T>> groupByDay<T>(
    List<T> items, DateTime Function(T) dateOf) {
  final grouped = <DateTime, List<T>>{};
  for (final item in items) {
    final d = dateOf(item);
    final day = DateTime(d.year, d.month, d.day);
    grouped.putIfAbsent(day, () => []).add(item);
  }
  return grouped;
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Formats a day (as returned by [groupByDay]'s keys) as "Today",
/// "Yesterday", or "D Mon YYYY" relative to [now].
String formatDateHeader(DateTime day, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  if (day == today) return 'Today';
  if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
  return '${day.day} ${_months[day.month - 1]} ${day.year}';
}
