import 'package:drift/drift.dart';

class Wallets extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get type => text()(); // bank, credit, cash, crypto, savings, other
  RealColumn get balance => real()();
  BoolColumn get includeInTotal => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}
