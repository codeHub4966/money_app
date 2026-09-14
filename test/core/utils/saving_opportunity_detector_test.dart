import 'package:flutter_test/flutter_test.dart';
import 'package:money_app_flutter/core/utils/saving_opportunity_detector.dart';

void main() {
  group('detectSavingOpportunity', () {
    test('estimates savings when the recent pace is clearly lower', () {
      // Days 1-3 (earlier) at RM30/day, days 4-10 (recent 7) at RM10/day ->
      // pace down (10-30)/30 = -66.7%, well past the -20% bar.
      final recorded = <double>[30, 30, 30, 10, 10, 10, 10, 10, 10, 10];
      final spent = recorded.fold(0.0, (s, v) => s + v);

      final result = detectSavingOpportunity(
        recorded: recorded,
        daysElapsed: 10,
        daysInMonth: 30,
        spent: spent,
      );

      expect(result, isNotNull);
      expect(result!.pacePct, closeTo(-66.7, 0.1));
      // Old pace continuing: spent + 30*(30-10) = 160 + 600 = 760.
      // New pace continuing (forecast): spent + 10*(30-10) = 160 + 200 = 360.
      // Savings = 760 - 360 = 400.
      expect(result.estimatedSavings, closeTo(400, 0.01));
    });

    test('null when recent spending is increasing', () {
      final recorded = <double>[10, 10, 10, 30, 30, 30, 30, 30, 30, 30];
      final spent = recorded.fold(0.0, (s, v) => s + v);

      final result = detectSavingOpportunity(
        recorded: recorded,
        daysElapsed: 10,
        daysInMonth: 30,
        spent: spent,
      );
      expect(result, isNull);
    });

    test('null when the pace drop is too small to be meaningful', () {
      // Days 1-3 at 10/day, days 4-10 at 9/day -> only -10% drop.
      final recorded = <double>[10, 10, 10, 9, 9, 9, 9, 9, 9, 9];
      final spent = recorded.fold(0.0, (s, v) => s + v);

      final result = detectSavingOpportunity(
        recorded: recorded,
        daysElapsed: 10,
        daysInMonth: 30,
        spent: spent,
      );
      expect(result, isNull);
    });

    test('null when fewer than 8 days have elapsed (not enough data)', () {
      final recorded = List<double>.filled(7, 10.0);
      final result = detectSavingOpportunity(
        recorded: recorded,
        daysElapsed: 7,
        daysInMonth: 30,
        spent: 70,
      );
      expect(result, isNull);
    });

    test('null once the month is fully elapsed (no forecast to compare)', () {
      final recorded = [
        for (var i = 0; i < 30; i++) i < 10 ? 20.0 : 5.0,
      ];
      final spent = recorded.fold(0.0, (s, v) => s + v);

      final result = detectSavingOpportunity(
        recorded: recorded,
        daysElapsed: 30,
        daysInMonth: 30,
        spent: spent,
      );
      expect(result, isNull);
    });
  });
}
