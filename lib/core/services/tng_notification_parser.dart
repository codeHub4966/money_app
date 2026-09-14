import '../../domain/models/detected_payment.dart';
import 'payment_notification_guards.dart';
import 'payment_notification_router.dart';
import 'receipt_scanner_service.dart';

// Parses push notifications posted by the official Touch 'n Go eWallet app
// (package [tngPackageName]) into a [DetectedPayment]. This is a different
// source and shape from a TNG *screenshot* OCR'd by [TngReceiptParser] (a
// full-screen transaction-detail layout) — a push notification is a single
// short title/body pair — so this lives in its own file and does not import
// or extend the receipt parser. Category suggestion is NOT reimplemented
// here: [ReceiptScannerService.suggestCategory] is called directly.
class TngNotificationParser {
  TngNotificationParser._();

  // "You have paid RM5.40 to 65 ONDO-GUNUNG RAPAT."
  static final RegExp _paidPattern = RegExp(
    r'you\s+have\s+paid\s+(?:rm|myr)\s*[\d,]+\.\d{2}\s+to\s+(.+?)\.?\s*$',
    caseSensitive: false,
  );

  // "RM 0.02 has been successfully transferred to CHANG NYET CHING."
  // "RM0.01 has been successfully transferred to CHANG NYET CHING."
  static final RegExp _transferredPattern = RegExp(
    r'(?:rm|myr)\s*[\d,]+\.\d{2}\s+has\s+been\s+successfully\s+transferred\s+to\s+(.+?)\.?\s*$',
    caseSensitive: false,
  );

  static DetectedPayment? parse(
    RawPaymentNotification raw, {
    List<String> existingCategoryLabels = const [],
  }) {
    if (raw.packageName != tngPackageName) return null;

    // Prefer the fuller bigText body when present, else the plain text/title.
    final rawBody = (raw.bigText?.isNotEmpty ?? false) ? raw.bigText! : (raw.text ?? '');
    final body = rawBody.replaceAll(RegExp(r'\s+'), ' ').trim();
    final combined = '${raw.title ?? ''}\n$body';

    if (containsExcludedKeyword(combined)) return null;

    final amount = extractPaymentAmount(body) ?? extractPaymentAmount(combined);
    if (amount == null) return null;

    final transferMatch = _transferredPattern.firstMatch(body);
    if (transferMatch != null) {
      final receiver = transferMatch.group(1)!.trim();
      if (receiver.isEmpty) return null;
      return DetectedPayment(
        amount: amount,
        merchantOrReceiver: receiver,
        note: 'Transfer to $receiver',
        suggestedCategory: null,
        suggestedWalletId: null,
        sourceApp: 'tng',
        sourceName: "Touch 'n Go eWallet",
        dateTime: raw.postTime,
        notificationKey: buildNotificationDedupKey(
          sourcePackage: raw.packageName,
          rawNotificationKey: raw.key,
          amount: amount,
          merchantOrReceiver: receiver,
          dateTime: raw.postTime,
        ),
        isTransfer: true,
      );
    }

    final paidMatch = _paidPattern.firstMatch(body);
    if (paidMatch != null) {
      final merchant = paidMatch.group(1)!.trim();
      if (merchant.isEmpty) return null;
      final (category, _) = ReceiptScannerService.suggestCategory(
        merchantName: merchant,
        existingCategoryLabels: existingCategoryLabels,
      );
      return DetectedPayment(
        amount: amount,
        merchantOrReceiver: merchant,
        note: merchant,
        suggestedCategory: category,
        suggestedWalletId: null,
        sourceApp: 'tng',
        sourceName: "Touch 'n Go eWallet",
        dateTime: raw.postTime,
        notificationKey: buildNotificationDedupKey(
          sourcePackage: raw.packageName,
          rawNotificationKey: raw.key,
          amount: amount,
          merchantOrReceiver: merchant,
          dateTime: raw.postTime,
        ),
        isTransfer: false,
      );
    }

    return null;
  }
}
