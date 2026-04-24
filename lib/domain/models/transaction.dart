enum TransactionType { expense, income, transfer }

class Transaction {
  final String id;
  final TransactionType type;
  final double amount;
  final String category;
  final String accountId;
  final String? note;
  final DateTime date;

  const Transaction({
    required this.id,
    required this.type,
    required this.amount,
    required this.category,
    required this.accountId,
    this.note,
    required this.date,
  });
}
