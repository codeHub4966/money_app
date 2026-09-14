import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:money_app_flutter/domain/models/app_category.dart';
import 'package:money_app_flutter/domain/models/budget.dart';
import 'package:money_app_flutter/domain/models/transaction.dart';
import 'package:money_app_flutter/presentation/providers/app_providers.dart';

/// Pumps a minimal widget tree under [overrides] and hands back a real
/// [WidgetRef] (via [Consumer]) — CategoryNotifier.remove takes a WidgetRef,
/// so this is the officially-supported way to exercise it without a hand
/// rolled fake.
Future<WidgetRef> _pumpRef(
    WidgetTester tester, List<Override> overrides) async {
  late WidgetRef captured;
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        home: Consumer(builder: (context, ref, _) {
          // Watching (not just reading) starts the underlying streams
          // immediately so their first value has already landed by the
          // time a test calls into CategoryNotifier.remove, which reads
          // them synchronously.
          ref.watch(transactionsProvider);
          ref.watch(budgetsProvider);
          captured = ref;
          return const SizedBox();
        }),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return captured;
}

Transaction _tx({required String category}) => Transaction(
      id: 't1',
      type: TransactionType.expense,
      amount: 10,
      category: category,
      accountId: 'w1',
      date: DateTime(2026, 1, 1),
    );

void main() {
  group('CategoryNotifier.remove (requirement 4: compare by label, not id)',
      () {
    testWidgets(
        'blocks deletion when a transaction stores the category LABEL, even '
        'though it differs from the id', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final ref = await _pumpRef(tester, [
        transactionsProvider
            .overrideWith((ref) => Stream.value([_tx(category: 'Groceries')])),
        budgetsProvider.overrideWith((ref) => Stream.value(const <Budget>[])),
      ]);

      // "goods" is the id; "Groceries" is the label actually stored on the
      // transaction — the exact id/label mismatch from the bug report.
      const cat = AppCategory(id: 'goods', label: 'Groceries', emoji: '🧻');

      await expectLater(
        () => ref.read(categoriesProvider.notifier).remove('expense', cat, ref),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('currently in use'),
        )),
      );
    });

    testWidgets('blocks deletion when a BUDGET stores the category label',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final ref = await _pumpRef(tester, [
        transactionsProvider.overrideWith((ref) => Stream.value(const [])),
        budgetsProvider.overrideWith((ref) => Stream.value([
              const Budget(
                  id: 'b1',
                  categoryName: 'Groceries',
                  monthlyLimit: 200,
                  spent: 0),
            ])),
      ]);

      const cat = AppCategory(id: 'goods', label: 'Groceries', emoji: '🧻');

      await expectLater(
        () => ref.read(categoriesProvider.notifier).remove('expense', cat, ref),
        throwsA(isA<Exception>()),
      );
    });

    testWidgets('comparison is case-insensitive', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final ref = await _pumpRef(tester, [
        transactionsProvider
            .overrideWith((ref) => Stream.value([_tx(category: 'FOOD')])),
        budgetsProvider.overrideWith((ref) => Stream.value(const <Budget>[])),
      ]);

      const cat = AppCategory(id: 'food', label: 'Food', emoji: '🍲');

      await expectLater(
        () => ref.read(categoriesProvider.notifier).remove('expense', cat, ref),
        throwsA(isA<Exception>()),
      );
    });

    testWidgets(
        'allows deletion when the label is genuinely unused (and no longer matches by stale id comparison either)',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final ref = await _pumpRef(tester, [
        transactionsProvider
            .overrideWith((ref) => Stream.value([_tx(category: 'Food')])),
        budgetsProvider.overrideWith((ref) => Stream.value(const <Budget>[])),
      ]);

      const cat = AppCategory(id: 'unused_123', label: 'Unused', emoji: '❓');
      final notifier = ref.read(categoriesProvider.notifier);
      notifier.add('expense', cat);
      await tester.pump();

      await notifier.remove('expense', cat, ref);

      expect(notifier.state['expense']!.any((c) => c.id == 'unused_123'),
          isFalse);
    });

    testWidgets(
        'regression: the id no longer matching the label must NOT let an in-use category through',
        (tester) async {
      // Directly demonstrates the original bug: comparing against cat.id
      // ("goods") never matches the stored label ("Groceries"), so the old
      // code would have wrongly allowed this delete.
      SharedPreferences.setMockInitialValues({});
      final ref = await _pumpRef(tester, [
        transactionsProvider
            .overrideWith((ref) => Stream.value([_tx(category: 'Groceries')])),
        budgetsProvider.overrideWith((ref) => Stream.value(const <Budget>[])),
      ]);

      const cat = AppCategory(id: 'goods', label: 'Groceries', emoji: '🧻');
      expect(cat.id.toLowerCase() == 'groceries', isFalse);

      final notifier = ref.read(categoriesProvider.notifier);
      var threw = false;
      try {
        await notifier.remove('expense', cat, ref);
      } catch (_) {
        threw = true;
      }
      expect(threw, isTrue);
    });
  });
}
