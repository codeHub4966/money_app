import 'package:drift/drift.dart';
import '../../domain/models/wallet.dart' as model;
import '../local/app_database.dart';

abstract class IWalletRepository {
  Stream<List<model.Wallet>> watchAll();
  Future<void> add(model.Wallet w);
  Future<void> delete(String id);
  Future<void> updateBalance(String id, double newBalance);
}

class LocalWalletRepository implements IWalletRepository {
  final AppDatabase _db;
  LocalWalletRepository(this._db);

  @override
  Stream<List<model.Wallet>> watchAll() {
    return _db.select(_db.wallets).watch().map(
      (rows) => rows.map(_toModel).toList(),
    );
  }

  @override
  Future<void> add(model.Wallet w) {
    return _db.into(_db.wallets).insertOnConflictUpdate(
      WalletsCompanion(
        id: Value(w.id),
        name: Value(w.name),
        type: Value(w.type.name),
        balance: Value(w.balance),
        includeInTotal: Value(w.includeInTotal),
      ),
    );
  }

  @override
  Future<void> delete(String id) {
    return (_db.delete(_db.wallets)..where((w) => w.id.equals(id))).go();
  }

  @override
  Future<void> updateBalance(String id, double newBalance) {
    return (_db.update(_db.wallets)..where((w) => w.id.equals(id)))
        .write(WalletsCompanion(balance: Value(newBalance)));
  }

  model.Wallet _toModel(Wallet row) => model.Wallet(
        id: row.id,
        name: row.name,
        type: model.WalletType.values.byName(row.type),
        balance: row.balance,
        includeInTotal: row.includeInTotal,
      );
}
