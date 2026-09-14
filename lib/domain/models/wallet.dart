enum WalletType { eWallet, card, bank, cash, savings, others }

extension WalletTypeStorage on WalletType {
  /// Parses a persisted [WalletType] name, translating retired type sets so
  /// existing wallets keep working after the account-type options changed.
  /// Two earlier generations are handled: the original set (bank/credit/
  /// cash/crypto/savings/other), where 'credit' predates today's naming and
  /// 'crypto' has no direct equivalent; and the intermediate set (eWallet/
  /// debitCard/creditCard/bank/savings/others), where 'debitCard'/
  /// 'creditCard' were merged back into a single 'card' type. 'other'
  /// mapped to e-wallet since the old UI already labelled that bucket
  /// "E-Wallet(s)". 'cash' is a real type again, so it now falls through to
  /// the default case instead of being folded into 'others'.
  static WalletType fromStorageName(String name) {
    switch (name) {
      case 'debitCard':
      case 'creditCard':
      case 'credit':
        return WalletType.card;
      case 'other':
        return WalletType.eWallet;
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
