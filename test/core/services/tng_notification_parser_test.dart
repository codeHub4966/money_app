import 'package:flutter_test/flutter_test.dart';
import 'package:money_app_flutter/core/services/payment_notification_router.dart';
import 'package:money_app_flutter/core/services/tng_notification_parser.dart';

const _defaultExpenseLabels = [
  'Food', 'Groceries', 'Snacks', 'Fruit', 'Vegetab.', 'Games', 'Clothing',
  'Shopping', 'Transport', 'Movies', 'Health', 'Fitness', 'Gifts', 'Study',
  'Travel', 'Pets',
];

RawPaymentNotification _tng({
  required String title,
  required String body,
  String? key = 'tng-key-1',
  DateTime? postTime,
  bool useBigText = true,
}) {
  return RawPaymentNotification(
    packageName: tngPackageName,
    key: key,
    postTime: postTime ?? DateTime(2026, 9, 14, 10, 0),
    title: title,
    text: useBigText ? null : body,
    bigText: useBigText ? body : null,
  );
}

void main() {
  group('TNG DuitNow Payment', () {
    test('parses amount, merchant, note; isTransfer is false', () {
      final data = TngNotificationParser.parse(
        _tng(title: 'DuitNow Payment', body: 'You have paid RM5.40 to 65 ONDO-GUNUNG RAPAT.'),
        existingCategoryLabels: _defaultExpenseLabels,
      );

      expect(data, isNotNull);
      expect(data!.amount, 5.40);
      expect(data.merchantOrReceiver, '65 ONDO-GUNUNG RAPAT');
      expect(data.note, '65 ONDO-GUNUNG RAPAT');
      expect(data.isTransfer, isFalse);
      expect(data.sourceApp, 'tng');
    });

    test('leaves category unselected when no keyword matches', () {
      final data = TngNotificationParser.parse(
        _tng(title: 'DuitNow Payment', body: 'You have paid RM5.40 to 65 ONDO-GUNUNG RAPAT.'),
        existingCategoryLabels: _defaultExpenseLabels,
      );
      expect(data!.suggestedCategory, isNull);
    });

    test('category matched: merchant text matches a keyword bucket', () {
      final data = TngNotificationParser.parse(
        _tng(title: 'DuitNow Payment', body: 'You have paid RM8.90 to Starbucks KLCC.'),
        existingCategoryLabels: _defaultExpenseLabels,
      );
      expect(data!.suggestedCategory, 'Food');
    });
  });

  group('TNG Transfer', () {
    test('"RM 0.02 has been successfully transferred to ..."', () {
      final data = TngNotificationParser.parse(
        _tng(
          title: 'Transfer Successful.',
          body: 'RM 0.02 has been successfully transferred to CHANG NYET CHING.',
        ),
        existingCategoryLabels: _defaultExpenseLabels,
      );

      expect(data, isNotNull);
      expect(data!.amount, 0.02);
      expect(data.merchantOrReceiver, 'CHANG NYET CHING');
      expect(data.note, 'Transfer to CHANG NYET CHING');
      expect(data.isTransfer, isTrue);
      expect(data.suggestedCategory, isNull,
          reason: 'category must never be inferred from the receiver name');
    });

    test('"RM0.01 has been successfully transferred to ..." (no space after RM)', () {
      final data = TngNotificationParser.parse(
        _tng(
          title: 'Transfer Successful.',
          body: 'RM0.01 has been successfully transferred to CHANG NYET CHING.',
        ),
      );

      expect(data, isNotNull);
      expect(data!.amount, 0.01);
      expect(data.merchantOrReceiver, 'CHANG NYET CHING');
      expect(data.isTransfer, isTrue);
    });
  });

  group('Duplicate protection', () {
    test('the same notification produces the same dedup key', () {
      final raw = _tng(title: 'DuitNow Payment', body: 'You have paid RM5.40 to 65 ONDO-GUNUNG RAPAT.');
      final first = TngNotificationParser.parse(raw)!;
      final second = TngNotificationParser.parse(raw)!;
      expect(first.notificationKey, second.notificationKey);
    });
  });

  group('Ignored notifications', () {
    test('OTP is ignored', () {
      final data = TngNotificationParser.parse(
        _tng(title: 'OTP Verification', body: 'Your OTP is 123456. Do not share this with anyone.'),
      );
      expect(data, isNull);
    });

    test('failed payment is ignored', () {
      final data = TngNotificationParser.parse(
        _tng(title: 'Payment Failed', body: 'Your payment of RM5.40 to Store has failed.'),
      );
      expect(data, isNull);
    });

    test('non-TNG package is ignored', () {
      final raw = RawPaymentNotification(
        packageName: 'com.some.other.app',
        postTime: DateTime.now(),
        title: 'DuitNow Payment',
        text: 'You have paid RM5.40 to 65 ONDO-GUNUNG RAPAT.',
      );
      expect(TngNotificationParser.parse(raw), isNull);
    });
  });
}
