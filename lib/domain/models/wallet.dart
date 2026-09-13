enum WalletType { eWallet, debitCard, creditCard, bank, savings, others }

extension WalletTypeStorage on WalletType {
  /// Parses a persisted [WalletType] name, translating the pre-migration
  /// type set (bank/credit/cash/crypto/savings/other) so existing wallets
  /// keep working after the account-type options changed. 'other' mapped to
  /// e-wallet since the old UI already labelled that bucket "E-Wallet(s)".
  static WalletType fromStorageName(String name) {
    switch (name) {
      case 'credit':
        return WalletType.creditCard;
      case 'other':
        return WalletType.eWallet;
      case 'cash':
      case 'crypto':
        return WalletType.others;
      default:
        return WalletType.values.byName(name);
    }
  }
}

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
