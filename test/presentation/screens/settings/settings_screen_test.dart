import 'package:flutter_test/flutter_test.dart';
import 'package:money_app_flutter/presentation/screens/settings/settings_screen.dart';

void main() {
  test('Daily Expense Reminder default time remains 8:00 PM', () {
    expect(kDefaultDailyReminderTime.hour, 20);
    expect(kDefaultDailyReminderTime.minute, 0);
  });
}
