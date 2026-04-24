import 'package:drift/drift.dart';

class Transactions extends Table {
  TextColumn get id => text()();
  TextColumn get type => text()(); // expense, income, transfer
  RealColumn get amount => real()();
  TextColumn get category => text()();
  TextColumn get accountId => text()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get date => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
