enum WalletType { bank, credit, cash, crypto, savings, other }

class Wallet {
  final String id;
  final String name;
  final WalletType type;
  final double balance;
  final bool includeInTotal;

  const Wallet({
    required this.id,
    required this.name,
    required this.type,
    required this.balance,
    required this.includeInTotal,
  });
}
