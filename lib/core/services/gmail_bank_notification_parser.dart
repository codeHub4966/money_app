import '../../domain/models/detected_payment.dart';
import 'payment_notification_guards.dart';
import 'payment_notification_router.dart';
import 'receipt_scanner_service.dart';

// Parses Gmail notifications (package [gmailPackageName]) that appear to be
// a successful bank/payment/transfer message into a [DetectedPayment]. Not
// limited to any one bank — [parse] tries the bank-specific entry points
// first (currently sharing one extractor, since no bank has been found to
// need different wording rules yet — they exist as seams for future
// bank-specific quirks) and always falls back to [parseGenericBank] for any
// bank/financial institution not explicitly named. Kept fully independent of
// the receipt-OCR parsers — this reads push-notification text, not a scanned
// receipt image.
class GmailBankNotificationParser {
  GmailBankNotificationParser._();

  // Case-insensitive brand markers used only to pick which bank-specific
  // entry point handles the notification (and to label [DetectedPayment
  // .sourceName]) — these do not gate whether parsing happens at all, since
  // an unrecognised bank still falls through to [parseGenericBank].
  static final RegExp _gxBankPattern = RegExp(r'\bgx\s*bank\b', caseSensitive: false);
  static final RegExp _maybankPattern = RegExp(r'\bmaybank\b', caseSensitive: false);
  static final RegExp _publicBankPattern = RegExp(r'\bpublic\s*bank\b|\bpbb\b', caseSensitive: false);

  // Wording confirming a successful transaction, per the spec's list:
  // "payment successful", "payment is successful", "transaction successful",
  // "transaction is successful", "transfer successful", "transfer is
  // successful", "your transfer is successful", "successfully transferred",
  // "successful payment of RM...", "transaction of RM... to ... is
  // successful", "RM... to ... is successful".
  static final RegExp _successWordingPattern = RegExp(
    r'(?:payment|transaction|transfer)\s+(?:is\s+)?successful|'
    r'successfully\s+transferred|'
    r'successful\s+payment\s+of|'
    r'(?:rm|myr)\s*[\d,]+\.\d{2}\s+to\s+.+?\s+is\s+successful',
    caseSensitive: false,
  );

  // "RM0.01 to AU XIAO YEW on 14 Sep 2026 is successful" /
  // "RM37.10 to MAXIS-AUTO 5651171034 is successful" /
  // "RM27.00 to Grab is successful"
  static final RegExp _toNameIsSuccessfulPattern = RegExp(
    r'(?:rm|myr)\s*[\d,]+\.\d{2}\s+to\s+(.+?)(?:\s+on\s+.+?)?\s+is\s+successful',
    caseSensitive: false,
  );

  // "successfully transferred to CHANG NYET CHING" (Gmail phrasing of the
  // same TNG-style wording, in case a bank uses it too).
  static final RegExp _successfullyTransferredToPattern = RegExp(
    r'successfully\s+transferred\s+to\s+(.+?)[.\n]',
    caseSensitive: false,
  );

  static bool looksLikeGmailBankNotification(String combinedText) {
    return !containsExcludedKeyword(combinedText) &&
        _successWordingPattern.hasMatch(combinedText) &&
        extractPaymentAmount(combinedText) != null;
  }

  static String? _extractCounterparty(String combinedText) {
    final toIsSuccessful = _toNameIsSuccessfulPattern.firstMatch(combinedText);
    if (toIsSuccessful != null) {
      final name = toIsSuccessful.group(1)!.trim();
      if (name.isNotEmpty) return name;
    }
    final transferredTo = _successfullyTransferredToPattern.firstMatch(combinedText);
    if (transferredTo != null) {
      final name = transferredTo.group(1)!.trim();
      if (name.isNotEmpty) return name;
    }
    return null;
  }

  static DetectedPayment? _extract(
    String combinedText, {
    required String sourceName,
    required DateTime dateTime,
    required String sourcePackage,
    required String? rawKey,
    required List<String> existingCategoryLabels,
  }) {
    if (!looksLikeGmailBankNotification(combinedText)) return null;

    final amount = extractPaymentAmount(combinedText);
    final counterparty = _extractCounterparty(combinedText);
    if (amount == null || counterparty == null) return null;

    final isTransfer = looksLikeTransfer(combinedText);
    final note = isTransfer ? 'Transfer to $counterparty' : counterparty;

    String? category;
    if (!isTransfer) {
      final (suggested, _) = ReceiptScannerService.suggestCategory(
        merchantName: counterparty,
        existingCategoryLabels: existingCategoryLabels,
      );
      category = suggested;
    }

    return DetectedPayment(
      amount: amount,
      merchantOrReceiver: counterparty,
      note: note,
      suggestedCategory: category,
      suggestedWalletId: null,
      sourceApp: 'gmail',
      sourceName: sourceName,
      dateTime: dateTime,
      notificationKey: buildNotificationDedupKey(
        sourcePackage: sourcePackage,
        rawNotificationKey: rawKey,
        amount: amount,
        merchantOrReceiver: counterparty,
        dateTime: dateTime,
      ),
      isTransfer: isTransfer,
    );
  }

  static DetectedPayment? parseGxBank(
    String combinedText, {
    required DateTime dateTime,
    required String sourcePackage,
    String? rawKey,
    List<String> existingCategoryLabels = const [],
  }) =>
      _extract(
        combinedText,
        sourceName: 'GXBank',
        dateTime: dateTime,
        sourcePackage: sourcePackage,
        rawKey: rawKey,
        existingCategoryLabels: existingCategoryLabels,
      );

  static DetectedPayment? parseMaybank(
    String combinedText, {
    required DateTime dateTime,
    required String sourcePackage,
    String? rawKey,
    List<String> existingCategoryLabels = const [],
  }) =>
      _extract(
        combinedText,
        sourceName: 'Maybank',
        dateTime: dateTime,
        sourcePackage: sourcePackage,
        rawKey: rawKey,
        existingCategoryLabels: existingCategoryLabels,
      );

  static DetectedPayment? parsePublicBank(
    String combinedText, {
    required DateTime dateTime,
    required String sourcePackage,
    String? rawKey,
    List<String> existingCategoryLabels = const [],
  }) =>
      _extract(
        combinedText,
        sourceName: 'Public Bank',
        dateTime: dateTime,
        sourcePackage: sourcePackage,
        rawKey: rawKey,
        existingCategoryLabels: existingCategoryLabels,
      );

  /// Handles any bank/financial institution not specifically named above —
  /// deliberately not limited to a hardcoded bank list, per the spec.
  static DetectedPayment? parseGenericBank(
    String combinedText, {
    required DateTime dateTime,
    required String sourcePackage,
    String? rawKey,
    List<String> existingCategoryLabels = const [],
  }) =>
      _extract(
        combinedText,
        sourceName: 'Bank',
        dateTime: dateTime,
        sourcePackage: sourcePackage,
        rawKey: rawKey,
        existingCategoryLabels: existingCategoryLabels,
      );

  static DetectedPayment? parse(
    RawPaymentNotification raw, {
    List<String> existingCategoryLabels = const [],
  }) {
    if (raw.packageName != gmailPackageName) return null;

    // Prefer bigText when it carries more complete content than text.
    final body = (raw.bigText != null && raw.bigText!.length >= (raw.text?.length ?? 0))
        ? raw.bigText!
        : (raw.text ?? '');
    final joined = [raw.title, body, raw.subText].where((s) => s != null && s.isNotEmpty).join('\n');
    // Collapse wrapped lines (e.g. a receiver name wrapping onto the next
    // line before "on <date> is successful") into single-space-separated
    // text so the multi-word regexes below can match across the wrap.
    final combined = joined.replaceAll(RegExp(r'\s+'), ' ').trim();

    if (_gxBankPattern.hasMatch(combined)) {
      return parseGxBank(
        combined,
        dateTime: raw.postTime,
        sourcePackage: raw.packageName,
        rawKey: raw.key,
        existingCategoryLabels: existingCategoryLabels,
      );
    }
    if (_maybankPattern.hasMatch(combined)) {
      return parseMaybank(
        combined,
        dateTime: raw.postTime,
        sourcePackage: raw.packageName,
        rawKey: raw.key,
        existingCategoryLabels: existingCategoryLabels,
      );
    }
    if (_publicBankPattern.hasMatch(combined)) {
      return parsePublicBank(
        combined,
        dateTime: raw.postTime,
        sourcePackage: raw.packageName,
        rawKey: raw.key,
        existingCategoryLabels: existingCategoryLabels,
      );
    }
    return parseGenericBank(
      combined,
      dateTime: raw.postTime,
      sourcePackage: raw.packageName,
      rawKey: raw.key,
      existingCategoryLabels: existingCategoryLabels,
    );
  }
}
