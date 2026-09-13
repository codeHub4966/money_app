import 'package:flutter_test/flutter_test.dart';
import 'package:money_app_flutter/core/services/receipt_text_layout.dart';

void main() {
  group('groupIntoRows', () {
    test('returns nothing for an empty input', () {
      expect(groupIntoRows([]), isEmpty);
    });

    test('keeps unrelated rows separate and in top-to-bottom order', () {
      final rows = groupIntoRows([
        const PositionedLine(text: 'MERCHANT NAME', top: 0, bottom: 20, left: 10),
        const PositionedLine(text: 'Item A  5.00', top: 100, bottom: 120, left: 10),
        const PositionedLine(text: 'Item B  8.00', top: 140, bottom: 160, left: 10),
      ]);

      expect(rows, ['MERCHANT NAME', 'Item A  5.00', 'Item B  8.00']);
    });

    test('merges a label and its amount detected as separate same-row lines', () {
      // Simulates ML Kit emitting "TOTAL" and "15.90" as two separate lines
      // (even from different blocks) despite them being printed on the same
      // visual row — label on the left, amount on the right.
      final rows = groupIntoRows([
        const PositionedLine(text: 'TOTAL', top: 200, bottom: 220, left: 10),
        const PositionedLine(text: '15.90', top: 202, bottom: 222, left: 300),
      ]);

      expect(rows, ['TOTAL  15.90']);
    });

    test('orders a merged row left-to-right regardless of detection order', () {
      // The amount is detected/listed before the label (e.g. differing
      // block iteration order) but is visually to the right of it.
      final rows = groupIntoRows([
        const PositionedLine(text: '15.90', top: 202, bottom: 222, left: 300),
        const PositionedLine(text: 'TOTAL', top: 200, bottom: 220, left: 10),
      ]);

      expect(rows, ['TOTAL  15.90']);
    });

    test('does not merge closely-spaced but distinct rows on a thermal receipt', () {
      // Tight line spacing (rowHeight ~18) with each row cleanly offset by
      // one row-height should stay separate.
      final rows = groupIntoRows([
        const PositionedLine(text: 'SUBTOTAL  15.00', top: 0, bottom: 18, left: 10),
        const PositionedLine(text: 'TAX  0.90', top: 20, bottom: 38, left: 10),
        const PositionedLine(text: 'TOTAL  15.90', top: 40, bottom: 58, left: 10),
      ]);

      expect(rows, ['SUBTOTAL  15.00', 'TAX  0.90', 'TOTAL  15.90']);
    });

    test('merges an item description with its price across a wide column gap', () {
      final rows = groupIntoRows([
        const PositionedLine(text: 'Nasi Lemak', top: 50, bottom: 70, left: 10),
        const PositionedLine(text: '6.50', top: 52, bottom: 72, left: 250),
      ]);

      expect(rows, ['Nasi Lemak  6.50']);
    });
  });
}
