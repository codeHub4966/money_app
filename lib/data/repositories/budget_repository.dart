import 'package:drift/drift.dart';
import '../../domain/models/budget.dart' as model;
import '../local/app_database.dart';

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
  Future<void> add(model.Budget b) {
    return _db.into(_db.budgets).insertOnConflictUpdate(
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
