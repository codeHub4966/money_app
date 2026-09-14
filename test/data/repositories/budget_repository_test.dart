import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app_flutter/data/local/app_database.dart' hide Budget;
import 'package:money_app_flutter/data/repositories/budget_repository.dart';
import 'package:money_app_flutter/domain/models/budget.dart';

void main() {
  late AppDatabase db;
  late LocalBudgetRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = LocalBudgetRepository(db);
  });

  tearDown(() => db.close());

  group('duplicate budget prevention (requirement 7)', () {
    test('creating a second budget for a category that already has one throws',
        () async {
      await repo.add(const Budget(
          id: 'b1', categoryName: 'Food', monthlyLimit: 100, spent: 0));

      expect(
        () => repo.add(const Budget(
            id: 'b2', categoryName: 'Food', monthlyLimit: 200, spent: 0)),
        throwsA(isA<DuplicateBudgetCategoryException>()),
      );

      final all = await repo.watchAll().first;
      expect(all, hasLength(1), reason: 'the duplicate must not be created');
    });

    test('the category comparison is case-insensitive', () async {
      await repo.add(const Budget(
          id: 'b1', categoryName: 'Food', monthlyLimit: 100, spent: 0));

      expect(
        () => repo.add(const Budget(
            id: 'b2', categoryName: 'FOOD', monthlyLimit: 50, spent: 0)),
        throwsA(isA<DuplicateBudgetCategoryException>()),
      );
    });

    test('the exception message matches the required wording', () async {
      await repo.add(const Budget(
          id: 'b1', categoryName: 'Food', monthlyLimit: 100, spent: 0));

      try {
        await repo.add(const Budget(
            id: 'b2', categoryName: 'food', monthlyLimit: 50, spent: 0));
        fail('expected DuplicateBudgetCategoryException');
      } on DuplicateBudgetCategoryException catch (e) {
        expect(e.toString(), 'A budget already exists for this category.');
      }
    });

    test('editing an existing budget (same id) keeps its own category available',
        () async {
      await repo.add(const Budget(
          id: 'b1', categoryName: 'Food', monthlyLimit: 100, spent: 0));

      // Re-saving with the same id and same category (e.g. only the limit
      // changed) must succeed rather than being flagged as a duplicate of
      // itself.
      await repo.add(const Budget(
          id: 'b1', categoryName: 'Food', monthlyLimit: 150, spent: 0));

      final all = await repo.watchAll().first;
      expect(all, hasLength(1));
      expect(all.single.monthlyLimit, 150);
    });

    test('different categories can each have their own budget', () async {
      await repo.add(const Budget(
          id: 'b1', categoryName: 'Food', monthlyLimit: 100, spent: 0));
      await repo.add(const Budget(
          id: 'b2', categoryName: 'Transport', monthlyLimit: 50, spent: 0));

      final all = await repo.watchAll().first;
      expect(all, hasLength(2));
    });
  });
}
