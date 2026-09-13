import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
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

  /// Lowercases and strips punctuation/apostrophes so wallet names like
  /// "Touch 'n Go" normalize the same way as the canonical detected keyword
  /// `'touch n go'` — without this, the apostrophe alone would silently
  /// defeat what should be an exact brand match.
  static String _normalize(String s) {
    return s.toLowerCase().replaceAll(RegExp(r"[^a-z0-9]+"), ' ').trim();
  }

  static Wallet? match(String? keyword, List<Wallet> wallets) {
    if (keyword == null || wallets.isEmpty) return null;
    final normalizedKeyword = _normalize(keyword);

    Wallet? result;
    if (keyword == 'cash') {
      // There is no dedicated "cash" wallet type, so a cash wallet can only
      // be recognized by name (e.g. a wallet named "Cash").
      result = _uniqueOrNull(
        wallets.where((w) => _normalize(w.name).contains('cash')),
      );
    } else if (specificPaymentBrands.contains(keyword)) {
      final exact = _uniqueOrNull(wallets.where((w) => _normalize(w.name) == normalizedKeyword));
      result = exact ??
          _uniqueOrNull(
            wallets.where((w) {
              final normalizedName = _normalize(w.name);
              return normalizedName.contains(normalizedKeyword) ||
                  normalizedKeyword.contains(normalizedName);
            }),
          );
    } else if (genericCardKeywords.contains(keyword)) {
      // "Visa"/"Mastercard"/"Debit"/"Credit" identify a card network, not
      // which of the user's bank/credit wallets was actually used. Guessing
      // among several would silently pick the wrong bank, so this only
      // auto-fills when there is exactly one candidate wallet to guess.
      result = _uniqueOrNull(
        wallets.where((w) =>
            w.type == WalletType.bank ||
            w.type == WalletType.creditCard ||
            w.type == WalletType.debitCard),
      );
    }

    if (kDebugMode) {
      debugPrint('[ReceiptWalletMatcher] keyword "$keyword" against '
          '${wallets.map((w) => w.name).toList()} -> ${result?.name}');
    }
    return result;
  }

  /// Returns the single match, or null if there are zero or more than one —
  /// an ambiguous match is treated the same as no match, since a wrong
  /// confident guess is worse than leaving the field for the user.
  static Wallet? _uniqueOrNull(Iterable<Wallet> matches) {
    final list = matches.toList();
    return list.length == 1 ? list.first : null;
  }
}
