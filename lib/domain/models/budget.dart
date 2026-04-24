class Budget {
  final String id;
  final String categoryName;
  final double monthlyLimit;
  final double spent;

  const Budget({
    required this.id,
    required this.categoryName,
    required this.monthlyLimit,
    required this.spent,
  });

  double get remaining => monthlyLimit - spent;
  double get percentUsed => monthlyLimit > 0 ? (spent / monthlyLimit) * 100 : 0;
  bool get isOverBudget => spent > monthlyLimit;
}
