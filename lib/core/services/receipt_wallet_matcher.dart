import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import '../../domain/models/transaction.dart';
import '../../domain/models/wallet.dart';
import 'wallet_usage_stats.dart';

/// Resolves a scanned receipt to one of the user's existing wallets, using
/// (in priority order):
///
///  1. an explicit bank/e-wallet/cash name match (handled here by name);
///     the caller checks a *learned payment alias* before this, since that's
///     evidence from the user's own confirmed choice and outranks everything
///     below.
///  2. a cash clue with no matching wallet name -> the most-used cash wallet;
///  3. a card clue, qualified or not ("DEBIT CARD", "VISA CREDIT", "VISA",
///     "MASTERCARD", "CARD") -> the most-used card wallet;
///  4. a generic e-wallet clue ("E-WALLET", "QR PAYMENT", "DUITNOW QR", ...)
///     -> the most-used e-wallet;
///  5. no reliable clue at all -> the most-used "others" wallet;
///  6. nothing to fall back on -> whichever wallet is already selected.
///
/// Pure/stateless (no widget/provider dependencies) so it can be unit tested
/// directly against fixture wallet/transaction lists.
class ReceiptWalletMatcher {
  ReceiptWalletMatcher._();

  /// Bank names specific enough to identify a particular wallet by name.
  static const Map<String, List<String>> bankBrands = {
    'maybank': ['maybank', 'may bank', 'mbb'],
    'cimb': ['cimb'],
    'public bank': ['public bank', 'pbb'],
    'hong leong': ['hong leong', 'hlb'],
    'rhb': ['rhb'],
    'ambank': ['ambank', 'am bank'],
  };

  /// E-wallet brands specific enough to identify a particular wallet by name.
  static const Map<String, List<String>> eWalletBrands = {
    'touch n go': ['touch n go', 'tng', 'touchngo', 'touch & go'],
    'mae': ['mae'],
    'grabpay': ['grabpay', 'grab pay'],
    'boost': ['boost'],
    'shopeepay': ['shopeepay', 'shopee pay'],
  };

  static const List<String> _cashKeywords = ['cash', 'tunai'];

  // "Debit"/"credit" are checked as independent qualifiers (not tied to a
  // single first-match scan) so "VISA DEBIT" is recognized as a debit-card
  // clue rather than merely a generic "visa" one.
  static const List<String> _debitQualifiers = ['debit'];
  static const List<String> _creditQualifiers = ['credit'];

  // Card-network words that appear on almost any card receipt regardless of
  // which bank issued the card, and carry no debit/credit qualifier.
  static const List<String> _genericCardWords = ['visa', 'mastercard', 'card'];

  // 'duitnow' on its own is a generic QR-rail clue, not a specific wallet
  // brand — several e-wallets and banks all support DuitNow QR, so it must
  // never be treated as specifically Touch 'n Go (or any other named
  // brand); it only ever resolves through this generic tier.
  static const List<String> _genericEwalletClues = [
    'e wallet', 'ewallet', 'duitnow qr', 'qr pay', 'qr payment', 'qr',
    'duitnow', 'duit now',
  ];

  /// OCR commonly misreads the letter "Q" in "QR" as the digit "0" — "0R",
  /// "Q0" — which would otherwise stop "DUITNOW 0R" / "Q0 PAYMENT" from
  /// matching the "qr"/"duitnow qr" clues above. Restricted to standalone
  /// tokens so this never rewrites an unrelated digit/letter sequence
  /// elsewhere on the receipt (a lot/room number, an item code).
  static String _fixOcrPaymentMisreads(String normalized) {
    return normalized.replaceAllMapped(RegExp(r'\b(?:0r|q0)\b'), (_) => 'qr');
  }

  /// Lowercases and strips punctuation/whitespace runs down to single
  /// spaces, so brand names/keywords match regardless of case, apostrophes,
  /// dashes, or spacing (e.g. "Touch 'n Go" / "TOUCH-N-GO" / "touchngo" all
  /// normalize compatibly for phrase containment checks).
  static String _normalize(String s) {
    final collapsed = s.toLowerCase().replaceAll(RegExp(r"[^a-z0-9]+"), ' ').trim();
    return _fixOcrPaymentMisreads(collapsed);
  }

  /// Whole-phrase containment: [phrase] must appear as a complete run of
  /// normalized tokens inside [normalizedText], not merely as a substring
  /// (so "mae" doesn't fire on "name", and "card" doesn't fire on
  /// "discard").
  static bool _containsPhrase(String normalizedText, String phrase) {
    return ' $normalizedText '.contains(' ${_normalize(phrase)} ');
  }

  static bool _containsAny(String normalizedText, List<String> phrases) {
    return phrases.any((p) => _containsPhrase(normalizedText, p));
  }

  /// The evidence detected on a receipt, before any wallet is chosen.
  /// Exposed as its own function so the detection step can be tested/logged
  /// independently of which wallets happen to exist.
  static ({
    String? specificBrand,
    bool isCash,
    String? cardTypeHint,
    bool hasGenericCard,
    bool hasGenericEwallet,
  }) detectPaymentClue(String rawText) {
    final normalized = _normalize(rawText);

    String? specificBrand;
    for (final entry in {...bankBrands, ...eWalletBrands}.entries) {
      if (_containsAny(normalized, entry.value)) {
        specificBrand = entry.key;
        break;
      }
    }

    final isCash = _containsAny(normalized, _cashKeywords);

    String? cardTypeHint;
    if (_containsAny(normalized, _debitQualifiers)) {
      cardTypeHint = 'debit';
    } else if (_containsAny(normalized, _creditQualifiers)) {
      cardTypeHint = 'credit';
    }

    final hasGenericCard = _containsAny(normalized, _genericCardWords);
    final hasGenericEwallet = _containsAny(normalized, _genericEwalletClues);

    final clue = (
      specificBrand: specificBrand,
      isCash: isCash,
      cardTypeHint: cardTypeHint,
      hasGenericCard: hasGenericCard,
      hasGenericEwallet: hasGenericEwallet,
    );
    if (kDebugMode) {
      debugPrint('[ReceiptWalletMatcher] detected payment clues: $clue');
    }
    return clue;
  }

  /// Returns the single match, or null if there are zero or more than one —
  /// an ambiguous match is treated the same as no match, since a wrong
  /// confident guess is worse than leaving it for a fallback tier.
  static Wallet? _uniqueOrNull(Iterable<Wallet> matches) {
    final list = matches.toList();
    return list.length == 1 ? list.first : null;
  }

  static Wallet? _matchByExplicitName(String normalizedKeyword, List<Wallet> wallets) {
    final exact = _uniqueOrNull(wallets.where((w) => _normalize(w.name) == normalizedKeyword));
    return exact ??
        _uniqueOrNull(wallets.where((w) {
          final normalizedName = _normalize(w.name);
          return normalizedName.contains(normalizedKeyword) || normalizedKeyword.contains(normalizedName);
        }));
  }

  /// Finds a unique existing wallet whose name identifies it as the user's
  /// Touch 'n Go eWallet (matching name variants such as "TnG", "TNG",
  /// "Touch n Go", "Touch 'n Go", "Touch & Go", "Touch n Go eWallet" — see
  /// [eWalletBrands]'s `'touch n go'` entry). Intended for a screenshot
  /// that has already been confidently identified as a TNG screenshot by
  /// its own screen layout (see `TngReceiptParser.isTngReceipt`) — the
  /// screenshot itself is then strong wallet evidence on its own, so this
  /// deliberately does NOT require the OCR text to literally contain
  /// "Touch 'n Go" anywhere, unlike [match] below. Returns null when there
  /// isn't exactly one such wallet, so callers fall back to [match] instead
  /// of forcing the wrong account.
  static Wallet? findUniqueTngWallet(List<Wallet> wallets) {
    return _uniqueOrNull(
      wallets.where((w) => _containsAny(_normalize(w.name), eWalletBrands['touch n go']!)),
    );
  }

  /// Finds a unique existing wallet whose name identifies it as the user's
  /// Public Bank account (matching name variants such as "Public Bank",
  /// "PBB", "Public Bank Account" — see [bankBrands]'s `'public bank'`
  /// entry). Intended for a screenshot already confidently identified as a
  /// Public Bank transaction-detail screen by its own screen layout (see
  /// `PublicBankReceiptParser.looksLikePublicBankReceipt`) — the screenshot
  /// itself is then strong wallet evidence on its own, so this deliberately
  /// does NOT require the OCR text to literally contain "Public Bank"
  /// anywhere, unlike [match] below. Returns null when there isn't exactly
  /// one such wallet, so callers fall back to [match] instead of forcing the
  /// wrong account.
  static Wallet? findUniquePublicBankWallet(List<Wallet> wallets) {
    return _uniqueOrNull(
      wallets.where((w) => _containsAny(_normalize(w.name), bankBrands['public bank']!)),
    );
  }

  /// Finds a unique existing wallet whose name identifies it as the user's
  /// Maybank account (matching name variants such as "Maybank", "MBB" — see
  /// [bankBrands]'s `'maybank'` entry). Intended for a screenshot already
  /// confidently identified as a Maybank transaction-detail screen (see
  /// `MaybankReceiptParser.looksLikeMaybankReceipt`) — the screenshot itself
  /// is then strong wallet evidence on its own, so this does NOT require the
  /// OCR text to literally contain "Maybank" anywhere, unlike [match] below.
  ///
  /// A wallet named "MAE" is Maybank's separate e-wallet sub-account, not the
  /// main bank account, so it is only ever preferred when [preferMae] is
  /// true — the caller should only pass true when the parsed receipt's own
  /// source/payment context clearly indicates MAE, never merely because the
  /// screenshot is confidently Maybank. Returns null when there isn't
  /// exactly one matching wallet, so callers fall back to [match] instead of
  /// forcing the wrong account.
  static Wallet? findUniqueMaybankWallet(List<Wallet> wallets, {bool preferMae = false}) {
    if (preferMae) {
      final maeWallet = _uniqueOrNull(wallets.where((w) => _containsAny(_normalize(w.name), eWalletBrands['mae']!)));
      if (maeWallet != null) return maeWallet;
    }
    return _uniqueOrNull(
      wallets.where((w) => _containsAny(_normalize(w.name), bankBrands['maybank']!)),
    );
  }

  /// Resolves a receipt to a wallet, plus the reason the choice was made
  /// (one of: `explicit_wallet`, `cash_fallback`, `card_fallback`,
  /// `ewallet_fallback`, `others_fallback`, `preserve_current`, or `none`).
  /// Does NOT know about learned payment aliases — the caller checks those
  /// first, since they outrank every tier here.
  static (Wallet?, String) match({
    required String rawText,
    required List<Wallet> wallets,
    List<Transaction> transactions = const [],
    Wallet? currentWallet,
  }) {
    if (wallets.isEmpty) return (null, 'none');

    final clue = detectPaymentClue(rawText);
    Wallet? result;
    var reason = 'none';

    if (clue.isCash) {
      result = _uniqueOrNull(wallets.where((w) => _normalize(w.name).contains('cash')));
      if (result != null) reason = 'explicit_wallet';
    }

    if (result == null && clue.specificBrand != null) {
      result = _matchByExplicitName(_normalize(clue.specificBrand!), wallets);
      if (result != null) reason = 'explicit_wallet';
    }

    if (result == null && clue.isCash) {
      result = WalletUsageStats.findMostUsedWallet(
        wallets: wallets, transactions: transactions, allowedTypes: {WalletType.cash});
      if (result != null) reason = 'cash_fallback';
    }

    if (result == null && (clue.cardTypeHint != null || clue.hasGenericCard)) {
      result = WalletUsageStats.findMostUsedWallet(
        wallets: wallets, transactions: transactions, allowedTypes: {WalletType.card});
      if (result != null) reason = 'card_fallback';
    }

    if (result == null && clue.specificBrand == null && clue.hasGenericEwallet) {
      result = WalletUsageStats.findMostUsedWallet(
        wallets: wallets, transactions: transactions, allowedTypes: {WalletType.eWallet});
      if (result != null) reason = 'ewallet_fallback';
    }

    final hasAnyClue =
        clue.isCash || clue.specificBrand != null || clue.cardTypeHint != null || clue.hasGenericCard || clue.hasGenericEwallet;
    if (result == null && !hasAnyClue) {
      result = WalletUsageStats.findMostUsedWallet(
        wallets: wallets, transactions: transactions, allowedTypes: {WalletType.others});
      if (result != null) reason = 'others_fallback';
    }

    if (result == null && currentWallet != null) {
      result = currentWallet;
      reason = 'preserve_current';
    }

    if (kDebugMode) {
      debugPrint('[ReceiptWalletMatcher] final selected wallet: ${result?.name} (reason: $reason)');
    }

    return (result, reason);
  }
}
