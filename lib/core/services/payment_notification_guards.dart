// Shared, source-agnostic helpers for the payment-notification-monitoring
// module (TngNotificationParser / GmailBankNotificationParser). Kept in its
// own file — and deliberately NOT shared with the receipt-OCR parsers — so
// notification monitoring stays fully independent of receipt scanning, even
// though both happen to need "is this text an amount" / "is this text noise"
// checks.

/// Amount pattern shared by both notification parsers: `RM5.20`, `RM 5.20`,
/// `MYR5.20`, `MYR 5.20`, with an optional thousands separator.
final RegExp paymentAmountPattern = RegExp(
  r'(?:rm|myr)\s*(\d{1,3}(?:,\d{3})*\.\d{2})',
  caseSensitive: false,
);

/// Extracts the first amount found in [text], or null if none.
double? extractPaymentAmount(String text) {
  final match = paymentAmountPattern.firstMatch(text);
  if (match == null) return null;
  return double.tryParse(match.group(1)!.replaceAll(',', ''));
}

/// Notifications whose text mentions any of these should never produce a
/// [DetectedPayment] — OTP/verification codes, failed/declined transactions,
/// refunds, promotions, and account/statement/security noise. Checked as
/// whole-word/phrase matches so e.g. "cash" doesn't collide with "cashback"
/// (the more specific phrase is listed explicitly).
final List<RegExp> excludedNotificationPatterns = [
  RegExp(r'\bOTP\b', caseSensitive: false),
  RegExp(r'\bTAC\b', caseSensitive: false),
  RegExp(r'verification\s*code', caseSensitive: false),
  RegExp(r'\bfailed\b', caseSensitive: false),
  RegExp(r'\bdeclined\b', caseSensitive: false),
  RegExp(r'\brejected\b', caseSensitive: false),
  RegExp(r'\brefund(?:ed)?\b', caseSensitive: false),
  RegExp(r'\breversal\b', caseSensitive: false),
  RegExp(r'\bcashback\b', caseSensitive: false),
  RegExp(r'\bpromotion\b', caseSensitive: false),
  RegExp(r'\bcampaign\b', caseSensitive: false),
  RegExp(r'statement\s*(?:is\s*)?available', caseSensitive: false),
  RegExp(r'monthly\s*statement', caseSensitive: false),
  RegExp(r'login\s*alert', caseSensitive: false),
  RegExp(r'security\s*alert', caseSensitive: false),
  RegExp(r'account\s*balance', caseSensitive: false),
];

/// True when [text] contains any of the exclusion signals above.
bool containsExcludedKeyword(String text) {
  return excludedNotificationPatterns.any((p) => p.hasMatch(text));
}

/// Transfer-related wording that classifies a notification as a transfer
/// rather than a merchant payment, per the spec.
final RegExp transferWordingPattern = RegExp(
  r'\btransfer(?:red)?\b|\bbeneficiary\b|\brecipient\b',
  caseSensitive: false,
);

bool looksLikeTransfer(String text) => transferWordingPattern.hasMatch(text);
