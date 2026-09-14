import 'package:flutter_test/flutter_test.dart';
import 'package:money_app_flutter/core/services/gmail_bank_notification_parser.dart';
import 'package:money_app_flutter/core/services/payment_notification_router.dart';

const _defaultExpenseLabels = [
  'Food', 'Groceries', 'Snacks', 'Fruit', 'Vegetab.', 'Games', 'Clothing',
  'Shopping', 'Transport', 'Movies', 'Health', 'Fitness', 'Gifts', 'Study',
  'Travel', 'Pets',
];

RawPaymentNotification _gmail({
  required String title,
  String? text,
  String? bigText,
  String? subText,
  String? key = 'gmail-key-1',
  DateTime? postTime,
}) {
  return RawPaymentNotification(
    packageName: gmailPackageName,
    key: key,
    postTime: postTime ?? DateTime(2026, 9, 14, 10, 0),
    title: title,
    text: text,
    bigText: bigText,
    subText: subText,
  );
}

void main() {
  group('GXBank transfer', () {
    test('parses amount/receiver, isTransfer=true, note prefixed, no category', () {
      final data = GmailBankNotificationParser.parse(
        _gmail(
          title: 'Your transfer is successful',
          bigText: 'Your transaction of RM0.01 to AU XIAO YEW\non 14 Sep 2026 is successful.',
          subText: 'GXBank',
        ),
        existingCategoryLabels: _defaultExpenseLabels,
      );

      expect(data, isNotNull);
      expect(data!.amount, 0.01);
      expect(data.merchantOrReceiver, 'AU XIAO YEW');
      expect(data.note, 'Transfer to AU XIAO YEW');
      expect(data.isTransfer, isTrue);
      expect(data.sourceName, 'GXBank');
      expect(data.suggestedCategory, isNull);
    });
  });

  group('GXBank payment', () {
    test('parses amount/merchant, isTransfer=false', () {
      final data = GmailBankNotificationParser.parse(
        _gmail(
          title: 'Payment is successful',
          bigText: 'RM37.10 to MAXIS-AUTO 5651171034 is successful.',
          subText: 'GXBank',
        ),
        existingCategoryLabels: _defaultExpenseLabels,
      );

      expect(data, isNotNull);
      expect(data!.amount, 37.10);
      expect(data.merchantOrReceiver, 'MAXIS-AUTO 5651171034');
      expect(data.note, 'MAXIS-AUTO 5651171034');
      expect(data.isTransfer, isFalse);
      expect(data.sourceName, 'GXBank');
    });

    test('no category match: merchant text has no matching keyword bucket', () {
      final data = GmailBankNotificationParser.parse(
        _gmail(
          title: 'Payment is successful',
          bigText: 'RM37.10 to MAXIS-AUTO 5651171034 is successful.',
          subText: 'GXBank',
        ),
        existingCategoryLabels: _defaultExpenseLabels,
      );
      expect(data!.suggestedCategory, isNull);
    });
  });

  group('GXBank Grab payment', () {
    test('parses amount/merchant and matches the Transport category', () {
      final data = GmailBankNotificationParser.parse(
        _gmail(
          title: 'Grab payment successful',
          bigText: 'Your transaction of RM27.00 to Grab is successful.',
          subText: 'GXBank',
        ),
        existingCategoryLabels: _defaultExpenseLabels,
      );

      expect(data, isNotNull);
      expect(data!.amount, 27.00);
      expect(data.merchantOrReceiver, 'Grab');
      expect(data.isTransfer, isFalse);
      expect(data.suggestedCategory, 'Transport');
    });
  });

  group('Generic Gmail bank notification (no recognised bank name)', () {
    test('generic Gmail bank payment', () {
      final data = GmailBankNotificationParser.parse(
        _gmail(
          title: 'Payment is successful',
          bigText: 'RM15.00 to Grab is successful.',
        ),
        existingCategoryLabels: _defaultExpenseLabels,
      );

      expect(data, isNotNull);
      expect(data!.amount, 15.00);
      expect(data.merchantOrReceiver, 'Grab');
      expect(data.isTransfer, isFalse);
      expect(data.sourceName, 'Bank');
      expect(data.sourceApp, 'gmail');
    });

    test('generic Gmail bank transfer', () {
      final data = GmailBankNotificationParser.parse(
        _gmail(
          title: 'Your transfer is successful',
          bigText: 'Your transaction of RM10.00 to John Tan is successful.',
        ),
        existingCategoryLabels: _defaultExpenseLabels,
      );

      expect(data, isNotNull);
      expect(data!.amount, 10.00);
      expect(data.merchantOrReceiver, 'John Tan');
      expect(data.note, 'Transfer to John Tan');
      expect(data.isTransfer, isTrue);
      expect(data.suggestedCategory, isNull);
    });
  });

  group('Ignored / unsupported notifications', () {
    test('unsupported Gmail message (no amount, no success wording)', () {
      final data = GmailBankNotificationParser.parse(
        _gmail(title: 'You have a new message', text: 'Hey, how are you doing?'),
      );
      expect(data, isNull);
    });

    test('OTP is ignored', () {
      final data = GmailBankNotificationParser.parse(
        _gmail(title: 'Your OTP code', text: 'Your OTP is 123456. Do not share this with anyone.'),
      );
      expect(data, isNull);
    });

    test('failed payment is ignored', () {
      final data = GmailBankNotificationParser.parse(
        _gmail(title: 'Payment failed', text: 'Your payment of RM10.00 to Store has failed.'),
      );
      expect(data, isNull);
    });

    test('non-Gmail package is ignored', () {
      final raw = RawPaymentNotification(
        packageName: 'com.some.other.app',
        postTime: DateTime.now(),
        title: 'Payment is successful',
        bigText: 'RM10.00 to Store is successful.',
      );
      expect(GmailBankNotificationParser.parse(raw), isNull);
    });
  });
}
