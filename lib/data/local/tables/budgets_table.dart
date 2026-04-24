import 'package:drift/drift.dart';

class Budgets extends Table {
  TextColumn get id => text()();
  TextColumn get categoryName => text()();
  RealColumn get monthlyLimit => real()();

  @override
  Set<Column> get primaryKey => {id};
}
