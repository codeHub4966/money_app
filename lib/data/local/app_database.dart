import 'dart:io';
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

  @override
  int get schemaVersion => 1;

  Future<void> deleteAllData() async {
    await transaction(() async {
      await delete(transactions).go();
      await delete(wallets).go();
      await delete(budgets).go();
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
