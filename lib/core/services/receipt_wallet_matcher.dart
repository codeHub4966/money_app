import '../../domain/models/wallet.dart';

/// Resolves a payment keyword detected on a receipt (e.g. `'maybank'`,
/// `'visa'`, `'cash'`) to one of the user's existing wallets.
///
/// Extracted as a standalone, pure function (no widget/provider
/// dependencies) so it can be unit tested directly against fixture wallet
/// lists, and reused consistently wherever a receipt scan needs to guess a
/// wallet.
class ReceiptWalletMatcher {
  ReceiptWalletMatcher._();

  /// Payment brands specific enough to identify a particular wallet by name
  /// (a bank, or an e-wallet), as opposed to [genericCardKeywords].
  static const specificPaymentBrands = {
    'touch n go', 'grabpay', 'boost', 'shopeepay', 'maybank', 'cimb',
    'public bank', 'hong leong', 'rhb', 'ambank',
  };

  /// Card-network words that appear on almost any card receipt regardless of
  /// which bank issued the card — they never identify a specific wallet by
  /// themselves.
  static const genericCardKeywords = {'visa', 'mastercard', 'debit', 'credit'};

  static Wallet? match(String? keyword, List<Wallet> wallets) {
    if (keyword == null || wallets.isEmpty) return null;

    if (keyword == 'cash') {
      return _uniqueOrNull(
        wallets.where((w) => w.type == WalletType.cash || w.name.toLowerCase().contains('cash')),
      );
    }

    if (specificPaymentBrands.contains(keyword)) {
      final exact = _uniqueOrNull(wallets.where((w) => w.name.toLowerCase() == keyword));
      if (exact != null) return exact;
      return _uniqueOrNull(
        wallets.where(
          (w) => w.name.toLowerCase().contains(keyword) || keyword.contains(w.name.toLowerCase()),
        ),
      );
    }

    if (genericCardKeywords.contains(keyword)) {
      // "Visa"/"Mastercard"/"Debit"/"Credit" identify a card network, not
      // which of the user's bank/credit wallets was actually used. Guessing
      // among several would silently pick the wrong bank, so this only
      // auto-fills when there is exactly one candidate wallet to guess.
      return _uniqueOrNull(
        wallets.where((w) => w.type == WalletType.bank || w.type == WalletType.credit),
      );
    }

    return null;
  }

  /// Returns the single match, or null if there are zero or more than one —
  /// an ambiguous match is treated the same as no match, since a wrong
  /// confident guess is worse than leaving the field for the user.
  static Wallet? _uniqueOrNull(Iterable<Wallet> matches) {
    final list = matches.toList();
    return list.length == 1 ? list.first : null;
  }
}
