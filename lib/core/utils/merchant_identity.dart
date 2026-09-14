/// Shared merchant-identity heuristics used by both
/// `merchant_category_history.dart` (merchant -> category learning) and
/// `merchant_pattern_detector.dart` (repeated/recurring merchant spending
/// insights), so the two never drift apart on what counts as "the merchant".
///
/// Merchant isn't stored on `Transaction` directly — it's recovered from the
/// leading "Merchant — items..." note format written by the receipt
/// scanner's `_buildNote` (see `receipt_scanner_service.dart`).
library;

const Set<String> _genericMerchantNames = {
  'other',
  'misc',
  'miscellaneous',
  'n/a',
  'na',
  'unknown',
  'general',
  'payment',
  'purchase',
  'transaction',
};

/// Extracts the merchant name from a transaction [note], or `null` when
/// there's no usable merchant text (empty note, or no leading
/// "Merchant — ..." segment).
String? extractMerchant(String? note) {
  if (note == null || note.isEmpty) return null;
  final merchant = note.split(' — ').first.trim();
  return merchant.isEmpty ? null : merchant;
}

/// Lowercases, trims, and collapses repeated whitespace so trivially
/// different renderings of the same merchant name ("Tealive", " tealive ",
/// "Tealive  SS15") group together. Punctuation is left largely intact —
/// only whitespace is normalized — to avoid merging genuinely different
/// merchant names that happen to share words.
String normalizeMerchant(String merchant) {
  return merchant.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
}

/// Whether [merchant] is too generic/unreliable to identify a real merchant
/// pattern from (e.g. "Other", "Payment", "N/A", or a purely numeric note).
bool isGenericMerchant(String merchant) {
  final normalized = normalizeMerchant(merchant);
  if (normalized.length < 2) return true;
  if (_genericMerchantNames.contains(normalized)) return true;
  if (RegExp(r'^[0-9\s.,-]+$').hasMatch(normalized)) return true;
  return false;
}
