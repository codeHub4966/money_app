import '../../domain/models/wallet.dart';

/// Resolves a [DetectedPayment]'s source (TNG eWallet, or a named bank from
/// a Gmail notification) to one of the user's existing wallets — but only
/// when the match is unambiguous, per the spec ("If there are multiple
/// possible matching accounts: leave account unselected"). Deliberately
/// independent from `ReceiptWalletMatcher` (which resolves *receipt* text
/// clues like "VISA DEBIT" or "E-WALLET") — notification monitoring must
/// stay fully separate from receipt-OCR code.
class PaymentNotificationWalletMatcher {
  PaymentNotificationWalletMatcher._();

  static const List<String> _tngKeywords = ['touch n go', 'tng', 'touchngo', 'touch & go'];

  /// Bank name -> the keywords that identify a wallet as that bank. Not
  /// exhaustive of every bank the Gmail parser recognises — only entries
  /// wallets are plausibly named after need to be listed here.
  static const Map<String, List<String>> _bankKeywords = {
    'gxbank': ['gxbank', 'gx bank'],
    'maybank': ['maybank', 'may bank', 'mbb'],
    'public bank': ['public bank', 'pbb'],
    'cimb': ['cimb'],
    'hong leong': ['hong leong', 'hlb'],
    'rhb': ['rhb'],
    'ambank': ['ambank', 'am bank'],
    'bank islam': ['bank islam'],
    'bank rakyat': ['bank rakyat'],
    'uob': ['uob'],
    'ocbc': ['ocbc'],
    'hsbc': ['hsbc'],
    'standard chartered': ['standard chartered'],
  };

  static String _normalize(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

  static bool _matchesAny(String normalizedName, List<String> keywords) {
    final padded = ' $normalizedName ';
    return keywords.any((k) => padded.contains(' ${_normalize(k)} '));
  }

  /// Returns the single matching wallet, or null when there are zero or more
  /// than one — an ambiguous match is treated the same as no match.
  static Wallet? _uniqueOrNull(Iterable<Wallet> matches) {
    final list = matches.toList();
    return list.length == 1 ? list.first : null;
  }

  /// [sourceApp] is `'tng'` or `'gmail'`; [sourceName] is the bank name
  /// detected by the Gmail parser (e.g. `'Maybank'`, `'GXBank'`), ignored
  /// for TNG.
  static Wallet? match({
    required String sourceApp,
    required String sourceName,
    required List<Wallet> wallets,
  }) {
    if (wallets.isEmpty) return null;

    if (sourceApp == 'tng') {
      return _uniqueOrNull(wallets.where(
        (w) => w.type == WalletType.eWallet && _matchesAny(_normalize(w.name), _tngKeywords),
      ));
    }

    if (sourceApp == 'gmail') {
      final normalizedSource = _normalize(sourceName);
      final keywords = _bankKeywords[normalizedSource] ?? [sourceName];
      return _uniqueOrNull(wallets.where((w) => _matchesAny(_normalize(w.name), keywords)));
    }

    return null;
  }
}
