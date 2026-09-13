import 'package:flutter_test/flutter_test.dart';
import 'package:money_app_flutter/core/utils/group_by_day.dart';

void main() {
  group('groupByDay', () {
    test('groups items that fall on the same calendar day', () {
      final items = [
        DateTime(2026, 3, 5, 9, 0),
        DateTime(2026, 3, 5, 18, 30),
        DateTime(2026, 3, 4, 12, 0),
      ];

      final grouped = groupByDay(items, (d) => d);

      expect(grouped.length, 2);
      expect(grouped[DateTime(2026, 3, 5)]!.length, 2);
      expect(grouped[DateTime(2026, 3, 4)]!.length, 1);
    });

    test('preserves the input order of items within a group', () {
      final items = [
        DateTime(2026, 3, 5, 9, 0),
        DateTime(2026, 3, 5, 8, 0),
        DateTime(2026, 3, 5, 22, 0),
      ];

      final grouped = groupByDay(items, (d) => d);

      expect(grouped[DateTime(2026, 3, 5)], items);
    });

    test('preserves group order matching first-seen order (newest-first input stays newest-first)', () {
      final items = [
        DateTime(2026, 3, 5),
        DateTime(2026, 3, 3),
        DateTime(2026, 3, 4),
      ];

      final grouped = groupByDay(items, (d) => d);

      expect(grouped.keys.toList(), [
        DateTime(2026, 3, 5),
        DateTime(2026, 3, 3),
        DateTime(2026, 3, 4),
      ]);
    });

    test('returns an empty map for an empty input', () {
      expect(groupByDay<DateTime>(const [], (d) => d), isEmpty);
    });
  });

  group('formatDateHeader', () {
    final now = DateTime(2026, 3, 5, 14, 30);

    test('labels the current day as Today', () {
      expect(formatDateHeader(DateTime(2026, 3, 5), now: now), 'Today');
    });

    test('labels the previous day as Yesterday', () {
      expect(formatDateHeader(DateTime(2026, 3, 4), now: now), 'Yesterday');
    });

    test('formats other days as "D Mon YYYY"', () {
      expect(formatDateHeader(DateTime(2026, 3, 1), now: now), '1 Mar 2026');
      expect(formatDateHeader(DateTime(2025, 12, 25), now: now), '25 Dec 2025');
    });
  });
}
