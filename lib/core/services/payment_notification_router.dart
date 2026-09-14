import '../../domain/models/detected_payment.dart';
import 'gmail_bank_notification_parser.dart';
import 'tng_notification_parser.dart';

/// The official Touch 'n Go eWallet Android package name.
const String tngPackageName = 'my.com.tngdigital.ewallet';

/// The Gmail Android package name.
const String gmailPackageName = 'com.google.android.gm';

/// A notification captured by the native `NotificationListenerService`,
/// before any parsing. Mirrors the fields the Android platform channel sends
/// over (see `PaymentNotificationListenerService.kt`).
class RawPaymentNotification {
  final String packageName;
  final String? key;
  final DateTime postTime;
  final String? title;
  final String? text;
  final String? bigText;
  final String? subText;

  const RawPaymentNotification({
    required this.packageName,
    this.key,
    required this.postTime,
    this.title,
    this.text,
    this.bigText,
    this.subText,
  });

  factory RawPaymentNotification.fromMap(Map<Object?, Object?> map) {
    return RawPaymentNotification(
      packageName: map['packageName'] as String,
      key: map['key'] as String?,
      postTime: DateTime.fromMillisecondsSinceEpoch(
        (map['postTime'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      ),
      title: map['title'] as String?,
      text: map['text'] as String?,
      bigText: map['bigText'] as String?,
      subText: map['subText'] as String?,
    );
  }
}

/// Routes a [RawPaymentNotification] to the parser matching its source app,
/// per the module's package allowlist. Notifications from any other app are
/// never processed — see the "Only process notifications from the official
/// Touch 'n Go eWallet app package" / Gmail-only spec requirements.
class PaymentNotificationRouter {
  PaymentNotificationRouter._();

  static DetectedPayment? route(
    RawPaymentNotification raw, {
    List<String> existingCategoryLabels = const [],
  }) {
    switch (raw.packageName) {
      case tngPackageName:
        return TngNotificationParser.parse(raw, existingCategoryLabels: existingCategoryLabels);
      case gmailPackageName:
        return GmailBankNotificationParser.parse(raw, existingCategoryLabels: existingCategoryLabels);
      default:
        return null;
    }
  }
}
