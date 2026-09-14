import 'package:drift/drift.dart';
import '../../domain/models/transaction.dart' as model;
import '../local/app_database.dart';

/// A single wallet balance write to apply as part of an atomic operation.
class WalletBalanceWrite {
  final String walletId;
  final double balance;
  const WalletBalanceWrite(this.walletId, this.balance);
}

/// Composes writes across the `transactions` and `wallets` tables inside a
/// single Drift database transaction, so an add/edit/delete transaction (or
/// transfer) and the wallet balance change(s) it requires either both
/// succeed or both roll back — never a wallet updated with no matching
/// transaction saved, or only one side of a transfer persisted/removed.
class TransactionWalletService {
  final AppDatabase _db;
  TransactionWalletService(this._db);

  Future<void> _applyBalanceWrites(Iterable<WalletBalanceWrite> writes) async {
    for (final w in writes) {
      await (_db.update(_db.wallets)..where((t) => t.id.equals(w.walletId)))
          .write(WalletsCompanion(balance: Value(w.balance)));
    }
  }

  Future<void> _upsertTransaction(model.Transaction t) {
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

  Future<void> _deleteTransactionRow(String id) {
    return (_db.delete(_db.transactions)..where((t) => t.id.equals(id))).go();
  }

  /// Add or edit a single transaction together with the wallet balance
  /// write(s) it requires.
  Future<void> saveTransaction({
    required model.Transaction transaction,
    required List<WalletBalanceWrite> walletUpdates,
  }) {
    return _db.transaction(() async {
      await _applyBalanceWrites(walletUpdates);
      await _upsertTransaction(transaction);
    });
  }

  /// Delete a single transaction (regular income/expense or a Balance
  /// Adjustment entry) together with the wallet balance reversal it
  /// requires.
  Future<void> deleteTransaction({
    required String transactionId,
    required List<WalletBalanceWrite> walletUpdates,
  }) {
    return _db.transaction(() async {
      await _applyBalanceWrites(walletUpdates);
      await _deleteTransactionRow(transactionId);
    });
  }

  /// Create or edit both sides of a transfer together with the wallet
  /// balance write(s) it requires.
  Future<void> saveTransfer({
    required model.Transaction outTransaction,
    required model.Transaction inTransaction,
    required List<WalletBalanceWrite> walletUpdates,
  }) {
    return _db.transaction(() async {
      await _applyBalanceWrites(walletUpdates);
      await _upsertTransaction(outTransaction);
      await _upsertTransaction(inTransaction);
    });
  }

  /// Delete both sides of a transfer together with the wallet balance
  /// reversal(s) it requires.
  Future<void> deleteTransferPair({
    required String outId,
    required String inId,
    required List<WalletBalanceWrite> walletUpdates,
  }) {
    return _db.transaction(() async {
      await _applyBalanceWrites(walletUpdates);
      await _deleteTransactionRow(outId);
      await _deleteTransactionRow(inId);
    });
  }
}
