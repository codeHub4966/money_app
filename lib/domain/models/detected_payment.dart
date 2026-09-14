/// A payment or transfer detected from an Android notification (TNG eWallet
/// or a Gmail bank notification) — see [PaymentNotificationRouter] and its
/// parsers in `core/services/`. Never saved directly: the user must confirm
/// it (tapping "Yes" on the local confirmation notification) and then
/// manually press "Confirm Transaction" on the prefilled Add Transaction
/// screen before anything is written to the database.
class DetectedPayment {
  final double amount;
  final String merchantOrReceiver;
  final String note;
  final String? suggestedCategory;
  final String? suggestedWalletId;
  final String sourceApp; // e.g. 'tng' | 'gmail'
  final String sourceName; // e.g. 'Touch \'n Go eWallet', 'GXBank', 'Maybank'
  final DateTime dateTime;

  /// A stable de-duplication key — see [buildNotificationDedupKey]. Persisted
  /// by `DetectedPaymentDedupStore` so the same underlying notification never
  /// produces two confirmation prompts, including across app restarts.
  final String notificationKey;

  final bool isTransfer;

  const DetectedPayment({
    required this.amount,
    required this.merchantOrReceiver,
    required this.note,
    this.suggestedCategory,
    this.suggestedWalletId,
    required this.sourceApp,
    required this.sourceName,
    required this.dateTime,
    required this.notificationKey,
    required this.isTransfer,
  });

  Map<String, dynamic> toJson() => {
        'amount': amount,
        'merchantOrReceiver': merchantOrReceiver,
        'note': note,
        'suggestedCategory': suggestedCategory,
        'suggestedWalletId': suggestedWalletId,
        'sourceApp': sourceApp,
        'sourceName': sourceName,
        'dateTime': dateTime.toIso8601String(),
        'notificationKey': notificationKey,
        'isTransfer': isTransfer,
      };

  factory DetectedPayment.fromJson(Map<String, dynamic> json) {
    return DetectedPayment(
      amount: (json['amount'] as num).toDouble(),
      merchantOrReceiver: json['merchantOrReceiver'] as String,
      note: json['note'] as String,
      suggestedCategory: json['suggestedCategory'] as String?,
      suggestedWalletId: json['suggestedWalletId'] as String?,
      sourceApp: json['sourceApp'] as String,
      sourceName: json['sourceName'] as String,
      dateTime: DateTime.parse(json['dateTime'] as String),
      notificationKey: json['notificationKey'] as String,
      isTransfer: json['isTransfer'] as bool,
    );
  }

  /// The payload handed to `GoRouter.push('/add-transaction', extra: ...)` —
  /// matches the `Map<String, dynamic>` prefill convention already used by
  /// `/add-wallet`, `/add-budget`, `/wallet-account`.
  Map<String, dynamic> toPrefillMap() => {
        'amount': amount,
        'note': note,
        'category': suggestedCategory,
        'accountId': suggestedWalletId,
        'date': dateTime,
      };

  /// The confirmation-notification title/body text, per the spec:
  /// "Did you spend RM5.40 at 65 ONDO-GUNUNG RAPAT?" /
  /// "Did you transfer RM0.02 to CHANG NYET CHING?"
  String get confirmationBody {
    final amountText = amount.toStringAsFixed(2);
    return isTransfer
        ? 'Did you transfer RM$amountText to $merchantOrReceiver?'
        : 'Did you spend RM$amountText at $merchantOrReceiver?';
  }
}

/// Builds the stable de-duplication key for a detected payment, combining
/// the source package, the raw Android notification key/id (when available),
/// and the parsed amount/counterparty/timestamp — so a redelivered or
/// re-posted notification (same underlying payment) never produces a second
/// confirmation prompt, per the "Duplicate protection" spec.
String buildNotificationDedupKey({
  required String sourcePackage,
  required String? rawNotificationKey,
  required double amount,
  required String merchantOrReceiver,
  required DateTime dateTime,
}) {
  return [
    sourcePackage,
    rawNotificationKey ?? '',
    amount.toStringAsFixed(2),
    merchantOrReceiver.trim().toLowerCase(),
    dateTime.toIso8601String(),
  ].join('|');
}
