import 'package:drift/drift.dart';
import '../../domain/models/budget.dart' as model;
import '../local/app_database.dart';

/// Thrown by [LocalBudgetRepository.add] when the budget's category already
/// has a different budget row. Safe to show `toString()` to the user.
class DuplicateBudgetCategoryException implements Exception {
  static const message = 'A budget already exists for this category.';
  @override
  String toString() => message;
}

abstract class IBudgetRepository {
  Stream<List<model.Budget>> watchAll();
  Future<void> add(model.Budget b);
  Future<void> delete(String id);
}

class LocalBudgetRepository implements IBudgetRepository {
  final AppDatabase _db;
  LocalBudgetRepository(this._db);

  @override
  Stream<List<model.Budget>> watchAll() {
    return _db.select(_db.budgets).watch().map(
      (rows) => rows.map(_toModel).toList(),
    );
  }

  @override
  Future<void> add(model.Budget b) async {
    // Enforced here (not just in the UI) so no code path — including any
    // future one — can accidentally create two budgets for the same
    // category. A budget being edited (same id) never counts as its own
    // duplicate, so editing without changing category is unaffected.
    final rows = await _db.select(_db.budgets).get();
    final isDuplicate = rows.any((row) =>
        row.id != b.id &&
        row.categoryName.toLowerCase() == b.categoryName.toLowerCase());
    if (isDuplicate) {
      throw DuplicateBudgetCategoryException();
    }

    await _db.into(_db.budgets).insertOnConflictUpdate(
      BudgetsCompanion(
        id: Value(b.id),
        categoryName: Value(b.categoryName),
        monthlyLimit: Value(b.monthlyLimit),
      ),
    );
  }

  @override
  Future<void> delete(String id) {
    return (_db.delete(_db.budgets)..where((b) => b.id.equals(id))).go();
  }

  model.Budget _toModel(Budget row) => model.Budget(
        id: row.id,
        categoryName: row.categoryName,
        monthlyLimit: row.monthlyLimit,
        spent: 0,
      );
}
