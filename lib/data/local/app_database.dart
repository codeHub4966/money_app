import 'dart:io';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'tables/transactions_table.dart';
import 'tables/wallets_table.dart';
import 'tables/budgets_table.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [Transactions, Wallets, Budgets])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// For tests only — lets callers pass an in-memory [QueryExecutor]
  /// instead of opening the real on-disk database file.
  @visibleForTesting
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async {
      if (from == 1) {
        await m.addColumn(transactions, transactions.receiptImagePath);
      }
    },
    beforeOpen: (details) async {
      // One-time (idempotent) data rename: the "Goods" category was renamed
      // to "Groceries", but existing rows stored the old label as plain
      // text. Keep old data working against the new category list.
      await (update(transactions)..where((t) => t.category.equals('Goods')))
          .write(const TransactionsCompanion(category: Value('Groceries')));
      await (update(budgets)..where((b) => b.categoryName.equals('Goods')))
          .write(const BudgetsCompanion(categoryName: Value('Groceries')));
    },
  );

  Future<void> deleteAllData() async {
    await transaction(() async {
      await delete(transactions).go();
      await delete(wallets).go();
      await delete(budgets).go();
    });
  }

  /// Atomically replaces all wallets/budgets/transactions with the given
  /// rows — used by a Full Restore, which must behave as a true replace
  /// rather than a merge. Everything happens inside one Drift transaction
  /// so a failure partway through (e.g. a malformed row) leaves the
  /// existing data untouched instead of half-cleared.
  Future<void> replaceAllData({
    required List<WalletsCompanion> wallets,
    required List<BudgetsCompanion> budgets,
    required List<TransactionsCompanion> transactions,
  }) async {
    await transaction(() async {
      await delete(this.transactions).go();
      await delete(this.wallets).go();
      await delete(this.budgets).go();
      for (final w in wallets) {
        await into(this.wallets).insert(w);
      }
      for (final b in budgets) {
        await into(this.budgets).insert(b);
      }
      for (final t in transactions) {
        await into(this.transactions).insert(t);
      }
    });
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'money_app.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
