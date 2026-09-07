import 'package:drift/drift.dart';
import '../../domain/models/transaction.dart' as model;
import '../local/app_database.dart';

abstract class ITransactionRepository {
  Stream<List<model.Transaction>> watchAll();
  Future<void> add(model.Transaction t);
  Future<void> delete(String id);
}

class LocalTransactionRepository implements ITransactionRepository {
  final AppDatabase _db;
  LocalTransactionRepository(this._db);

  @override
  Stream<List<model.Transaction>> watchAll() {
    return (_db.select(_db.transactions)
          ..orderBy([(t) => OrderingTerm.desc(t.date)]))
        .watch()
        .map(
      (rows) => rows.map(_toModel).toList(),
    );
  }

  @override
  Future<void> add(model.Transaction t) {
    return _db.into(_db.transactions).insertOnConflictUpdate(
      TransactionsCompanion(
        id: Value(t.id),
        type: Value(t.type.name),
        amount: Value(t.amount),
        category: Value(t.category),
        accountId: Value(t.accountId),
        note: Value(t.note),
        date: Value(t.date),
        receiptImagePath: Value(t.receiptImagePath),
      ),
    );
  }

  @override
  Future<void> delete(String id) {
    return (_db.delete(_db.transactions)
          ..where((t) => t.id.equals(id)))
        .go();
  }

  model.Transaction _toModel(Transaction row) => model.Transaction(
        id: row.id,
        type: model.TransactionType.values.byName(row.type),
        amount: row.amount,
        category: row.category,
        accountId: row.accountId,
        note: row.note,
        date: row.date,
        receiptImagePath: row.receiptImagePath,
      );
}
