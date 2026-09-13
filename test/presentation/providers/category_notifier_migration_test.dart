import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:money_app_flutter/presentation/providers/app_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CategoryNotifier "Goods" -> "Groceries" migration', () {
    test('renames a persisted "Goods" category label in place, keeping its id', () async {
      SharedPreferences.setMockInitialValues({
        'app_categories_v1': jsonEncode({
          'expense': [
            {'id': 'goods', 'label': 'Goods', 'emoji': '🧻'},
            {'id': 'food', 'label': 'Food', 'emoji': '🍲'},
          ],
          'income': [
            {'id': 'salary', 'label': 'Salary', 'emoji': '💰'},
          ],
        }),
      });

      final notifier = CategoryNotifier();
      await notifier.reloadFromPrefs();

      final expense = notifier.state['expense']!;
      final goods = expense.firstWhere((c) => c.id == 'goods');
      expect(goods.label, 'Groceries');
      // The id (used for lookups/emoji-matching) stays stable.
      expect(goods.id, 'goods');
      // Untouched categories are unaffected.
      expect(expense.firstWhere((c) => c.id == 'food').label, 'Food');

      // Persisted copy is also updated so future loads see the fix.
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('app_categories_v1')!;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final persistedGoods = (data['expense'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((e) => e['id'] == 'goods');
      expect(persistedGoods['label'], 'Groceries');
    });

    test('leaves an already-migrated label untouched', () async {
      SharedPreferences.setMockInitialValues({
        'app_categories_v1': jsonEncode({
          'expense': [
            {'id': 'goods', 'label': 'Groceries', 'emoji': '🧻'},
          ],
          'income': [],
        }),
      });

      final notifier = CategoryNotifier();
      await notifier.reloadFromPrefs();

      expect(notifier.state['expense']!.single.label, 'Groceries');
    });

    test('a fresh install with no persisted prefs defaults to "Groceries"', () async {
      SharedPreferences.setMockInitialValues({});

      final notifier = CategoryNotifier();
      await notifier.reloadFromPrefs();

      final goods = notifier.state['expense']!.firstWhere((c) => c.id == 'goods');
      expect(goods.label, 'Groceries');
    });
  });
}
