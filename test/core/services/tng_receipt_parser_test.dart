import 'package:flutter_test/flutter_test.dart';
import 'package:money_app_flutter/core/services/receipt_scanner_service.dart';
import 'package:money_app_flutter/core/services/tng_receipt_parser.dart';
import 'package:money_app_flutter/domain/models/transaction.dart';

void main() {
  group('parsePaidText — Payment Details present (spec example)', () {
    final rawText = '''
Payment Successful
RM 12.50
AU XIAO YEW
15 Sep 2026, 2:32 PM
Payment Details
fruit
Payment Method
Touch 'n Go eWallet
''';

    late TngReceiptData data;
    setUp(() {
      data = TngReceiptParser.parsePaidText(rawText);
    });

    test('is always an Expense', () {
      expect(data.transactionType, TransactionType.expense);
      expect(data.kind, TngTransactionKind.paid);
    });

    test('parses amount, merchant, date/time, payment details and payment method', () {
      expect(data.amount, 12.50);
      expect(data.counterpartyName, 'AU XIAO YEW');
      expect(data.date, DateTime(2026, 9, 15, 14, 32));
      expect(data.paymentDetails, 'fruit');
      expect(data.paymentMethod, "Touch 'n Go eWallet");
    });

    test('note is "<Payment Details> - Paid to <Merchant>"', () {
      expect(data.note, 'fruit - Paid to AU XIAO YEW');
    });
  });

  group('parsePaidText — Payment Details missing', () {
    test('note is "Paid to <Merchant>" and no category is auto-selected', () {
      final data = TngReceiptParser.parsePaidText('''
Payment Successful
RM 12.50
AU XIAO YEW
15 Sep 2026, 2:32 PM
Payment Method
Touch 'n Go eWallet
''');

      expect(data.paymentDetails, isNull);
      expect(data.note, 'Paid to AU XIAO YEW');
      expect(data.category, isNull);
      expect(data.categoryConfidence, FieldConfidence.missing);
    });

    test('note is "Paid to <Merchant>" when Payment Details is present but blank', () {
      final data = TngReceiptParser.parsePaidText('''
Payment Successful
RM 12.50
AU XIAO YEW
15 Sep 2026, 2:32 PM
Payment Details

Payment Method
Touch 'n Go eWallet
''');

      expect(data.note, 'Paid to AU XIAO YEW');
      expect(data.category, isNull);
    });
  });

  group('parsePaidText — category suggestion', () {
    test('uses only Payment Details text, never the merchant name', () {
      // "Grab" is a strong Transportation keyword as a merchant name; "milk"
      // is a Groceries keyword as the Payment Details text. If the merchant
      // name were (wrongly) fed into suggestCategory, Transportation would
      // win instead.
      final data = TngReceiptParser.parsePaidText(
        '''
Payment Successful
RM 5.00
Grab
1 Jan 2026, 9:00 AM
Payment Details
milk
Payment Method
Touch 'n Go eWallet
''',
        existingCategoryLabels: ['Groceries', 'Transportation'],
      );

      expect(data.counterpartyName, 'Grab');
      expect(data.category, 'Groceries');
    });
  });

  group('parseTransferredText — Remark is Fund Transfer (spec example)', () {
    late TngReceiptData data;
    setUp(() {
      data = TngReceiptParser.parseTransferredText('''
Transfer Successful
RM 50.00
CHANG NYET CHING
15 Sep 2026, 2:35 PM
Remark
Fund Transfer
''');
    });

    test('is always an Expense', () {
      expect(data.transactionType, TransactionType.expense);
      expect(data.kind, TngTransactionKind.transferred);
    });

    test('parses amount, receiver, remark and date & time', () {
      expect(data.amount, 50.00);
      expect(data.counterpartyName, 'CHANG NYET CHING');
      expect(data.remark, 'Fund Transfer');
      expect(data.date, DateTime(2026, 9, 15, 14, 35));
    });

    test('note is "Transfer to <Receiver>" and no category is auto-selected', () {
      expect(data.note, 'Transfer to CHANG NYET CHING');
      expect(data.category, isNull);
      expect(data.categoryConfidence, FieldConfidence.missing);
    });
  });

  group('parseTransferredText — Remark is a custom note (spec example)', () {
    test('note is "<Remark> - Transfer to <Receiver>"', () {
      final data = TngReceiptParser.parseTransferredText('''
Transfer Successful
RM 30.00
CHANG NYET CHING
15 Sep 2026, 2:35 PM
Remark
snacks
''');

      expect(data.remark, 'snacks');
      expect(data.note, 'snacks - Transfer to CHANG NYET CHING');
    });
  });

  group('parseTransferredText — category suggestion', () {
    test('uses only Remark text, never the receiver name', () {
      // "Grab" as the receiver name is a strong Transportation keyword;
      // "milk" as the remark is a Groceries keyword. If the receiver name
      // were (wrongly) fed into suggestCategory, Transportation would win.
      final data = TngReceiptParser.parseTransferredText(
        '''
Transfer Successful
RM 5.00
Grab
1 Jan 2026, 9:00 AM
Remark
milk
''',
        existingCategoryLabels: ['Groceries', 'Transportation'],
      );

      expect(data.counterpartyName, 'Grab');
      expect(data.category, 'Groceries');
    });

    test('missing Remark is treated as Fund Transfer (no note references a null remark)', () {
      final data = TngReceiptParser.parseTransferredText('''
Transfer Successful
RM 5.00
CHANG NYET CHING
1 Jan 2026, 9:00 AM
''');

      expect(data.remark, isNull);
      expect(data.note, 'Transfer to CHANG NYET CHING');
      expect(data.category, isNull);
    });
  });

  group('field extraction — labelled fields and layouts', () {
    test('reads an explicitly labelled receiver ("To") over the fallback heuristic', () {
      final data = TngReceiptParser.parseTransferredText('''
Transfer Successful
RM 20.00
To
CHANG NYET CHING
15 Sep 2026, 2:35 PM
Remark
Fund Transfer
''');

      expect(data.counterpartyName, 'CHANG NYET CHING');
    });

    test('reads inline "Label: value" layout as well as stacked layout', () {
      final data = TngReceiptParser.parsePaidText('''
Payment Successful
RM 12.50
AU XIAO YEW
15/09/2026, 14:32
Payment Details: fruit
Payment Method: Touch 'n Go eWallet
''');

      expect(data.paymentDetails, 'fruit');
      expect(data.paymentMethod, "Touch 'n Go eWallet");
      expect(data.date, DateTime(2026, 9, 15, 14, 32));
    });
  });

  group('Format B — Payment with Payment Details', () {
    test('parses fields and sets note to exactly the Payment Details value', () {
      final data = TngReceiptParser.parseTngFormatB('''
Activity
Details
-RM19.50
Successful
Transaction Type
Payment
Merchant
Sushi Mentai Kampar
Payment Details
Payment - Sushi Mentai Kampar
Payment Method
Touch 'n Go eWallet
Date/Time
05/09/2026 17:29:48
Transaction No.
2609051729481234567
''');

      expect(data.format, TngFormat.b);
      expect(data.kind, TngTransactionKind.paid);
      expect(data.transactionType, TransactionType.expense);
      expect(data.amount, 19.50);
      expect(data.counterpartyName, 'Sushi Mentai Kampar');
      expect(data.paymentDetails, 'Payment - Sushi Mentai Kampar');
      expect(data.paymentMethod, "Touch 'n Go eWallet");
      expect(data.date, DateTime(2026, 9, 5, 17, 29, 48));
      expect(data.note, 'Payment - Sushi Mentai Kampar');
    });
  });

  group('Format B — DuitNow QR payment', () {
    test('parses fields and sets note to exactly the Payment Details value', () {
      final data = TngReceiptParser.parseTngFormatB('''
Activity
Details
-RM5.40
Successful
Transaction Type
DuitNow QR
Merchant
65 ONDO-GUNUNG RAPAT
Payment Details
DuitNow QR - 65 ONDO-GUNUNG RAPAT
Payment Method
Touch 'n Go eWallet
Date/Time
06/09/2026 09:15:00
Wallet Ref
WR20260906091500987
''');

      expect(data.amount, 5.40);
      expect(data.counterpartyName, '65 ONDO-GUNUNG RAPAT');
      expect(data.paymentDetails, 'DuitNow QR - 65 ONDO-GUNUNG RAPAT');
      expect(data.note, 'DuitNow QR - 65 ONDO-GUNUNG RAPAT');
    });
  });

  group('Format B — DuitNow QR TNGD payment', () {
    test('parses fields, including a tiny RM0.01 amount', () {
      final data = TngReceiptParser.parseTngFormatB('''
Activity
Details
-RM0.01
Successful
Transaction Type
DuitNow QR TNGD
Merchant
MR DIY (KK) SDN BHD
Payment Details
Payment - MR DIY (KK) SDN BHD
Payment Method
Touch 'n Go eWallet
Date/Time
07/09/2026 10:00:00
''');

      expect(data.amount, 0.01);
      expect(data.counterpartyName, 'MR DIY (KK) SDN BHD');
      expect(data.paymentDetails, 'Payment - MR DIY (KK) SDN BHD');
      expect(data.note, 'Payment - MR DIY (KK) SDN BHD');
    });
  });

  group('Format B — Transfer to Wallet with Payment Details', () {
    test('note is "<Payment Details> - Transfer to <Transfer To>"', () {
      final data = TngReceiptParser.parseTngFormatB('''
Activity
Details
-RM30.00
Successful
Transaction Type
Transfer to Wallet
Transfer To
CHANG NYET CHING
Payment Details
snacks
Payment Method
Touch 'n Go eWallet
Date/Time
08/09/2026 11:20:00
''');

      expect(data.kind, TngTransactionKind.transferred);
      expect(data.amount, 30.00);
      expect(data.counterpartyName, 'CHANG NYET CHING');
      expect(data.paymentDetails, 'snacks');
      expect(data.note, 'snacks - Transfer to CHANG NYET CHING');
    });
  });

  group('Format B — Transfer to Wallet without Payment Details', () {
    test('note is "Transfer to <Transfer To>" and no category is auto-selected', () {
      final data = TngReceiptParser.parseTngFormatB('''
Activity
Details
-RM30.00
Successful
Transaction Type
Transfer to Wallet
Transfer To
CHANG NYET CHING
Payment Method
Touch 'n Go eWallet
Date/Time
08/09/2026 11:20:00
''');

      expect(data.paymentDetails, isNull);
      expect(data.counterpartyName, 'CHANG NYET CHING');
      expect(data.note, 'Transfer to CHANG NYET CHING');
      expect(data.category, isNull);
    });
  });

  group('Format B — negative RM amount parsing', () {
    double? amountOf(String amountLine) {
      final data = TngReceiptParser.parseTngFormatB('''
Transaction Type
Payment
$amountLine
Merchant
Test Merchant
Date/Time
01/01/2026 00:00:00
''');
      return data.amount;
    }

    test('"-RM19.50" parses to 19.50', () => expect(amountOf('-RM19.50'), 19.50));
    test('"-RM5.40" parses to 5.40', () => expect(amountOf('-RM5.40'), 5.40));
    test('"-RM0.01" parses to 0.01', () => expect(amountOf('-RM0.01'), 0.01));
    test('"RM 19.50" (no sign) parses to 19.50', () => expect(amountOf('RM 19.50'), 19.50));
  });

  group('Format B — wrapped OCR values', () {
    test('a Payment Details value wrapped over two OCR lines is reassembled', () {
      final data = TngReceiptParser.parseTngFormatB('''
Activity
Details
-RM0.01
Successful
Transaction Type
DuitNow QR TNGD
Merchant
MR DIY (KK) SDN BHD
Payment Details
Payment - MR DIY (KK)
SDN BHD
Payment Method
Touch 'n Go eWallet
Date/Time
07/09/2026 10:00:00
''');

      expect(data.paymentDetails, 'Payment - MR DIY (KK) SDN BHD');
      expect(data.note, 'Payment - MR DIY (KK) SDN BHD');
    });
  });

  group('Format B — category suggestion', () {
    test('Payment: uses only Payment Details text, never the merchant name', () {
      final data = TngReceiptParser.parseTngFormatB(
        '''
Transaction Type
Payment
Merchant
Grab
Payment Details
milk
Date/Time
01/01/2026 09:00:00
''',
        existingCategoryLabels: ['Groceries', 'Transportation'],
      );

      expect(data.counterpartyName, 'Grab');
      expect(data.category, 'Groceries');
    });

    test('Transfer to Wallet: uses only Payment Details text, never Transfer To', () {
      final data = TngReceiptParser.parseTngFormatB(
        '''
Transaction Type
Transfer to Wallet
Transfer To
Grab
Payment Details
milk
Date/Time
01/01/2026 09:00:00
''',
        existingCategoryLabels: ['Groceries', 'Transportation'],
      );

      expect(data.counterpartyName, 'Grab');
      expect(data.category, 'Groceries');
    });
  });

  group('Format A vs Format B separation', () {
    const formatAPaidText = '''
Payment Successful
RM 12.50
AU XIAO YEW
15 Sep 2026, 2:32 PM
Payment Details
fruit
Payment Method
Touch 'n Go eWallet
''';

    const formatBText = '''
Activity
Details
-RM19.50
Successful
Transaction Type
Payment
Merchant
Sushi Mentai Kampar
Payment Details
Payment - Sushi Mentai Kampar
Payment Method
Touch 'n Go eWallet
Date/Time
05/09/2026 17:29:48
''';

    test('detection correctly classifies each format', () {
      expect(TngReceiptParser.isTngFormatA(formatAPaidText), isTrue);
      expect(TngReceiptParser.isTngFormatB(formatAPaidText), isFalse);
      expect(TngReceiptParser.isTngFormatA(formatBText), isFalse);
      expect(TngReceiptParser.isTngFormatB(formatBText), isTrue);
    });

    test('parse() routes to the correct parser and preserves Format A behavior', () {
      final routedA = TngReceiptParser.parse(formatAPaidText);
      final direct = TngReceiptParser.parsePaidText(formatAPaidText);
      expect(routedA.format, TngFormat.a);
      expect(routedA.note, direct.note);
      expect(routedA.counterpartyName, direct.counterpartyName);

      final routedB = TngReceiptParser.parse(formatBText);
      expect(routedB.format, TngFormat.b);
      expect(routedB.note, 'Payment - Sushi Mentai Kampar');
    });
  });

  group('isTngReceipt — screenshot detection', () {
    test('Format A Transferred screenshot is detected as TNG', () {
      final rawText = '''
RM 0.02
Transferred
Receiver CHANG NYET CHING
Remark snacks
Date & Time 14/09/2026 17:20:36
''';
      expect(TngReceiptParser.isTngReceipt(rawText), isTrue);
    });

    test('Format A Transferred screenshot ("Transfer Successful" wording) is detected as TNG', () {
      final rawText = '''
Transfer Successful
RM 30.00
Receiver
CHANG NYET CHING
15 Sep 2026, 2:35 PM
Remark
Fund Transfer
''';
      expect(TngReceiptParser.isTngReceipt(rawText), isTrue);
    });

    test('Format A Paid screenshot is detected as TNG', () {
      final rawText = '''
Payment Successful
RM 12.50
AU XIAO YEW
15 Sep 2026, 2:32 PM
Payment Details
fruit
Payment Method
Touch 'n Go eWallet
''';
      expect(TngReceiptParser.isTngReceipt(rawText), isTrue);
    });

    test('Format B Activity/Details screenshot is detected as TNG', () {
      final rawText = '''
Activity
Details
-RM19.50
Successful
Transaction Type
Payment
Merchant
Sushi Mentai Kampar
Payment Details
Payment - Sushi Mentai Kampar
Payment Method
Touch 'n Go eWallet
Date/Time
05/09/2026 17:29:48
Wallet Ref
WR20260906091500987
Transaction No.
2609051729481234567
''';
      expect(TngReceiptParser.isTngReceipt(rawText), isTrue);
    });

    test('a normal paper receipt is not falsely detected as TNG', () {
      final rawText = '''
99 Speed Mart
Jalan Test 123, Petaling Jaya
Milk 5.00
Bread 3.20
Eggs 2.50
SUBTOTAL 10.70
SST 0.50
TOTAL 11.20
Payment
DuitNow QR
Merchant Copy
CASH 20.00
CHANGE 8.80
Thank You
''';
      expect(TngReceiptParser.isTngReceipt(rawText), isFalse);
    });

    test('single generic keywords do not trigger TNG detection', () {
      for (final rawText in [
        'Payment',
        'Merchant',
        'Successful',
        'QR',
        'DuitNow',
        'A DuitNow QR payment was made successfully at the merchant.',
      ]) {
        expect(TngReceiptParser.isTngReceipt(rawText), isFalse, reason: rawText);
      }
    });

    test('isTngFormatA alone is not treated as proof of a TNG screenshot', () {
      // isTngFormatA() only means "not Format B" — a completely unrelated
      // block of text (no TNG structure at all) still satisfies it, but
      // must never be classified as TNG by isTngReceipt.
      const rawText = 'Just some random unrelated text with no TNG structure.';
      expect(TngReceiptParser.isTngFormatA(rawText), isTrue);
      expect(TngReceiptParser.isTngReceipt(rawText), isFalse);
    });
  });

  group('whitespace-separated ("side-by-side OCR") layout', () {
    test('Receiver / Remark / Date & Time parse correctly with no punctuation separator', () {
      final rawText = '''
RM 0.02
Transferred
Receiver CHANG NYET CHING
Remark snacks
Date & Time 14/09/2026 17:20:36
''';
      final data = TngReceiptParser.parse(rawText, existingCategoryLabels: ['Snacks']);

      expect(data.format, TngFormat.a);
      expect(data.kind, TngTransactionKind.transferred);
      expect(data.amount, 0.02);
      expect(data.counterpartyName, 'CHANG NYET CHING');
      expect(data.remark, 'snacks');
      expect(data.date, DateTime(2026, 9, 14, 17, 20, 36));
      expect(data.note, 'snacks - Transfer to CHANG NYET CHING');
      expect(data.category, 'Snacks');
    });
  });
}
