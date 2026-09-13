/// A single OCR-detected line of text with its bounding-box position.
/// Deliberately independent of google_mlkit_text_recognition's own
/// `TextLine`/`Rect` types so the row-grouping logic below can be unit
/// tested with plain Dart fixtures, without ML Kit or platform channels.
class PositionedLine {
  final String text;
  final double top;
  final double bottom;
  final double left;

  const PositionedLine({
    required this.text,
    required this.top,
    required this.bottom,
    required this.left,
  });
}

/// Groups OCR-detected lines into visual rows using their bounding boxes,
/// then orders each row left-to-right.
///
/// ML Kit's own block/line grouping is not guaranteed to match visual
/// reading order: a label and its amount that sit on the same printed row
/// (e.g. "TOTAL" on the left, "15.90" on the right) can be detected as
/// separate lines — even separate blocks — and end up far apart once ML
/// Kit's blocks are simply concatenated. Re-deriving rows directly from
/// every line's bounding box (regardless of which block it came from) keeps
/// same-row label/amount pairs together, which the parser relies on to
/// associate a total's label with its value.
///
/// Rows are built by scanning lines top-to-bottom and grouping a line into
/// the current row when its vertical center falls within half a line-height
/// of the row's running average center — wide enough to tolerate small
/// per-line jitter within one printed row, narrow enough not to merge
/// consecutive rows on tightly-spaced thermal receipts.
List<String> groupIntoRows(List<PositionedLine> lines) {
  if (lines.isEmpty) return [];

  final sorted = [...lines]..sort((a, b) => a.top.compareTo(b.top));

  final rows = <List<PositionedLine>>[];
  for (final line in sorted) {
    final center = (line.top + line.bottom) / 2;

    if (rows.isNotEmpty) {
      final row = rows.last;
      final rowCenter =
          row.map((l) => (l.top + l.bottom) / 2).reduce((a, b) => a + b) / row.length;
      final rowHeight = row.map((l) => l.bottom - l.top).reduce((a, b) => a + b) / row.length;
      final tolerance = rowHeight * 0.5;

      if ((center - rowCenter).abs() <= tolerance) {
        row.add(line);
        continue;
      }
    }

    rows.add([line]);
  }

  return rows.map((row) {
    final ordered = [...row]..sort((a, b) => a.left.compareTo(b.left));
    return ordered.map((l) => l.text).join('  ');
  }).toList();
}
