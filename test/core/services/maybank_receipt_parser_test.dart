import 'package:flutter_test/flutter_test.dart';
import 'package:money_app_flutter/core/services/maybank_receipt_parser.dart';
import 'package:money_app_flutter/core/services/receipt_scanner_service.dart';
import 'package:money_app_flutter/domain/models/transaction.dart';

void main() {
  group('looksLikeMaybankReceipt', () {
    test('confidently detects a DuitNow Transfer screen', () {
      expect(
        MaybankReceiptParser.looksLikeMaybankReceipt('''
Maybank
DuitNow Transfer
RM50.00
15 Sep 2026, 2:32 PM
Beneficiary Name
AU XIAO XUAN
Beneficiary Account Number
1234567890123
Receiving Bank
CIMB Bank
Recipient Reference
hhhh
Reference ID
MB20260915123456
Successful
Share Receipt
'''),
        isTrue,
      );
    });

    test('confidently detects a Scan and Pay screen', () {
      expect(
        MaybankReceiptParser.looksLikeMaybankReceipt('''
Maybank
Scan and Pay
RM8.50
12 Sep 2026, 1:05 PM
Merchant Name
AUXIAOYEW
Reference ID
MB20260912111222
Successful
Share Receipt
'''),
        isTrue,
      );
    });

    test('does not fire on an ordinary paper receipt', () {
      expect(
        MaybankReceiptParser.looksLikeMaybankReceipt('''
Zus Coffee
Kopitiam Corner
1x Latte 12.00
Total 12.00
Thank You
'''),
        isFalse,
      );
    });
  });

  group('detectReceiptType', () {
    test('detects DuitNow Transfer from the header', () {
      expect(
        MaybankReceiptParser.detectReceiptType('DuitNow Transfer\nRM10.00'),
        MaybankReceiptType.duitNowTransfer,
      );
    });

    test('detects Scan and Pay from the header', () {
      expect(
        MaybankReceiptParser.detectReceiptType('Scan and Pay\nRM10.00'),
        MaybankReceiptType.scanAndPay,
      );
    });

    test('falls back to Beneficiary Name / Receiving Bank fields when there is no header', () {
      expect(
        MaybankReceiptParser.detectReceiptType('''
RM10.00
Beneficiary Name
AU XIAO XUAN
Receiving Bank
CIMB Bank
'''),
        MaybankReceiptType.duitNowTransfer,
      );
    });

    test('falls back to a Merchant Name field when there is no header', () {
      expect(
        MaybankReceiptParser.detectReceiptType('''
RM10.00
Merchant Name
AUXIAOYEW
'''),
        MaybankReceiptType.scanAndPay,
      );
    });

    test('returns null when neither a header nor distinguishing fields are present', () {
      expect(MaybankReceiptParser.detectReceiptType('RM10.00\n15 Sep 2026'), isNull);
    });
  });

  group('1. DuitNow Transfer with Recipient Reference + Beneficiary Name (spec example)', () {
    final rawText = '''
Maybank
DuitNow Transfer
RM50.00
15 Sep 2026, 2:32 PM
Beneficiary Name
AU XIAO XUAN
Beneficiary Account Number
1234567890123
Receiving Bank
CIMB Bank
Recipient Reference
hhhh
Reference ID
MB20260915123456
Successful
Share Receipt
''';

    late MaybankReceiptData data;
    setUp(() {
      data = MaybankReceiptParser.parseDuitNowTransferText(rawText);
    });

    test('is always an Expense', () {
      expect(data.transactionType, TransactionType.expense);
      expect(data.type, MaybankReceiptType.duitNowTransfer);
    });

    test('parses amount, date/time, beneficiary/reference fields', () {
      expect(data.amount, 50.00);
      expect(data.date, DateTime(2026, 9, 15, 14, 32));
      expect(data.beneficiaryName, 'AU XIAO XUAN');
      expect(data.beneficiaryAccountNumber, '1234567890123');
      expect(data.receivingBank, 'CIMB Bank');
      expect(data.recipientReference, 'hhhh');
      expect(data.referenceId, 'MB20260915123456');
    });

    test('note is "<Recipient Reference> - <Beneficiary Name>" (spec example)', () {
      expect(data.note, 'hhhh - AU XIAO XUAN');
    });

    test('does not leak "Successful" or "Share Receipt" into any parsed field', () {
      expect(data.beneficiaryName, isNot(contains('Successful')));
      expect(data.note, isNot(contains('Share Receipt')));
    });
  });

  group('2. DuitNow Transfer without Recipient Reference', () {
    test('note is just the Beneficiary Name', () {
      final data = MaybankReceiptParser.parseDuitNowTransferText('''
Maybank
DuitNow Transfer
RM120.00
20 Sep 2026, 9:15 AM
Beneficiary Name
AU XIAO XUAN
Beneficiary Account Number
9876543210123
Receiving Bank
Public Bank
Reference ID
MB20260920987654
''');

      expect(data.recipientReference, isNull);
      expect(data.beneficiaryName, 'AU XIAO XUAN');
      expect(data.note, 'AU XIAO XUAN');
      expect(data.note, isNot(startsWith('-')));
      expect(data.note, isNot(endsWith('-')));
    });
  });

  group('3. Scan and Pay with Merchant Name only (spec example)', () {
    test('note is just the Merchant Name', () {
      final data = MaybankReceiptParser.parseScanAndPayText('''
Maybank
Scan and Pay
RM8.50
12 Sep 2026, 1:05 PM
Merchant Name
AUXIAOYEW
Reference ID
MB20260912111222
Successful
Share Receipt
''');

      expect(data.transactionType, TransactionType.expense);
      expect(data.type, MaybankReceiptType.scanAndPay);
      expect(data.amount, 8.50);
      expect(data.date, DateTime(2026, 9, 12, 13, 5));
      expect(data.merchantName, 'AUXIAOYEW');
      expect(data.referenceId, 'MB20260912111222');
      expect(data.recipientReference, isNull);
      expect(data.note, 'AUXIAOYEW');
    });
  });

  group('4. Missing Merchant/Beneficiary values should not create empty note text', () {
    test('DuitNow Transfer with only Recipient Reference builds a note with no dangling separator', () {
      final data = MaybankReceiptParser.parseDuitNowTransferText('''
Maybank
DuitNow Transfer
RM30.00
5 Sep 2026, 10:00 AM
Recipient Reference
grocery
Reference ID
MB20260905333444
''');

      expect(data.beneficiaryName, isNull);
      expect(data.note, 'grocery');
      expect(data.note, isNot(contains('null')));
      expect(data.note, isNot(contains(' - ')));
    });

    test('Scan and Pay with neither Recipient Reference nor Merchant Name produces no note at all', () {
      final data = MaybankReceiptParser.parseScanAndPayText('''
Maybank
Scan and Pay
RM15.00
6 Sep 2026, 11:00 AM
Reference ID
MB20260906222333
''');

      expect(data.merchantName, isNull);
      expect(data.recipientReference, isNull);
      expect(data.note, isNull);
    });
  });

  group('5. Category matched from Recipient Reference', () {
    test('DuitNow Transfer with Recipient Reference "rice" resolves a food/groceries category', () {
      final data = MaybankReceiptParser.parseDuitNowTransferText('''
Maybank
DuitNow Transfer
RM50.00
15 Sep 2026, 2:32 PM
Beneficiary Name
AU XIAO XUAN
Receiving Bank
CIMB Bank
Recipient Reference
rice
''');

      expect(data.recipientReference, 'rice');
      expect(data.note, 'rice - AU XIAO XUAN');
      expect(data.category, anyOf('Food & Dining', 'Groceries'));
    });
  });

  group('6. Category matched from Merchant Name', () {
    test('Scan and Pay with Merchant Name "Zus Coffee" resolves Food & Dining', () {
      final data = MaybankReceiptParser.parseScanAndPayText('''
Maybank
Scan and Pay
RM12.50
15 Sep 2026, 2:32 PM
Merchant Name
Zus Coffee
''');

      expect(data.merchantName, 'Zus Coffee');
      expect(data.note, 'Zus Coffee');
      expect(data.category, 'Food & Dining');
    });
  });

  group('7. Category matched from Beneficiary Name', () {
    test('DuitNow Transfer with Beneficiary Name "Zus Coffee" resolves Food & Dining', () {
      final data = MaybankReceiptParser.parseDuitNowTransferText('''
Maybank
DuitNow Transfer
RM12.50
15 Sep 2026, 2:32 PM
Beneficiary Name
Zus Coffee
Receiving Bank
CIMB Bank
''');

      expect(data.beneficiaryName, 'Zus Coffee');
      expect(data.recipientReference, isNull);
      expect(data.note, 'Zus Coffee');
      expect(data.category, 'Food & Dining');
    });
  });

  group('8. No category match leaves category unselected', () {
    test('DuitNow Transfer with unmatched Recipient Reference and Beneficiary Name', () {
      final data = MaybankReceiptParser.parseDuitNowTransferText('''
Maybank
DuitNow Transfer
RM20.00
1 Jan 2026, 9:00 AM
Beneficiary Name
AU XIAO XUAN
Receiving Bank
CIMB Bank
Recipient Reference
hhh
''');

      expect(data.recipientReference, 'hhh');
      expect(data.note, 'hhh - AU XIAO XUAN');
      expect(data.category, isNull);
      expect(data.categoryConfidence, FieldConfidence.missing);
    });

    test('Scan and Pay with an unmatched Merchant Name', () {
      final data = MaybankReceiptParser.parseScanAndPayText('''
Maybank
Scan and Pay
RM20.00
1 Jan 2026, 9:00 AM
Merchant Name
AUXIAOYEW
''');

      expect(data.merchantName, 'AUXIAOYEW');
      expect(data.note, 'AUXIAOYEW');
      expect(data.category, isNull);
      expect(data.categoryConfidence, FieldConfidence.missing);
    });
  });

  group('field extraction — inline layout and noise robustness', () {
    test('reads inline "Label: value" layout as well as stacked layout', () {
      final data = MaybankReceiptParser.parseDuitNowTransferText('''
Maybank
DuitNow Transfer
RM50.00
Date & Time: 15/09/2026, 14:32
Beneficiary Name: AU XIAO XUAN
Receiving Bank: CIMB Bank
Recipient Reference: hhhh
''');

      expect(data.date, DateTime(2026, 9, 15, 14, 32));
      expect(data.beneficiaryName, 'AU XIAO XUAN');
      expect(data.receivingBank, 'CIMB Bank');
      expect(data.recipientReference, 'hhhh');
    });

    test('a "Successful" status line right after a wrapped value does not get merged into it', () {
      final data = MaybankReceiptParser.parseDuitNowTransferText('''
Maybank
DuitNow Transfer
RM45.00
10 Sep 2026, 3:20 PM
Beneficiary Name
AU XIAO XUAN
Successful
Beneficiary Account Number
1122334455667
Receiving Bank
Hong Leong Bank
Recipient Reference
dinner
Reference ID
MB20260910555666
Malayan Banking Berhad (196001000142)
This receipt is computer generated and no signature is required
Share Receipt
''');

      expect(data.beneficiaryName, 'AU XIAO XUAN');
      expect(data.beneficiaryAccountNumber, '1122334455667');
      expect(data.receivingBank, 'Hong Leong Bank');
      expect(data.note, 'dinner - AU XIAO XUAN');
    });
  });

  group('whitespace-separated ("side-by-side OCR") layout', () {
    test('Scan and Pay spec example: "Merchant Name AUXIAOYEW" / "Amount RM 0.01"', () {
      final data = MaybankReceiptParser.parseScanAndPayText('''
Maybank
Scan and Pay
Merchant Name AUXIAOYEW
Amount RM 0.01
''');

      expect(data.amount, 0.01);
      expect(data.merchantName, 'AUXIAOYEW');
      expect(data.note, 'AUXIAOYEW');
    });

    test('transfer spec example: Beneficiary Name / Beneficiary Account Number / '
        'Recipient Reference / Amount all whitespace-separated', () {
      final data = MaybankReceiptParser.parseDuitNowTransferText('''
Maybank
Third Party Transfer
Beneficiary Name AU XIAO XUAN
Beneficiary Account Number 158284304009
Recipient Reference hhhh
Amount RM 5.20
''');

      expect(data.amount, 5.20);
      expect(data.beneficiaryName, 'AU XIAO XUAN');
      expect(data.beneficiaryAccountNumber, '158284304009');
      expect(data.recipientReference, 'hhhh');
      expect(data.note, 'hhhh - AU XIAO XUAN');
    });

    test('Reference ID reads a whitespace-separated value', () {
      final data = MaybankReceiptParser.parseScanAndPayText('''
Maybank
Scan and Pay
Reference ID QR83721748
Merchant Name AUXIAOYEW
Amount RM 0.01
''');

      expect(data.referenceId, 'QR83721748');
      expect(data.merchantName, 'AUXIAOYEW');
    });

    test('"Third Party Transfer" (no literal "DuitNow Transfer" header) still routes via '
        'Beneficiary Name field detection', () {
      final data = MaybankReceiptParser.parse('''
Maybank
Third Party Transfer
Beneficiary Name AU XIAO XUAN
Beneficiary Account Number 158284304009
Recipient Reference hhhh
Amount RM 5.20
''');

      expect(data, isNotNull);
      expect(data!.type, MaybankReceiptType.duitNowTransfer);
      expect(data.amount, 5.20);
      expect(data.note, 'hhhh - AU XIAO XUAN');
    });
  });

  group('parse — dispatches to the right receipt-type parser', () {
    test('routes a DuitNow Transfer screen to parseDuitNowTransferText', () {
      final data = MaybankReceiptParser.parse('''
Maybank
DuitNow Transfer
RM50.00
15 Sep 2026, 2:32 PM
Beneficiary Name
AU XIAO XUAN
Recipient Reference
hhhh
''');

      expect(data, isNotNull);
      expect(data!.type, MaybankReceiptType.duitNowTransfer);
      expect(data.note, 'hhhh - AU XIAO XUAN');
    });

    test('routes a Scan and Pay screen to parseScanAndPayText', () {
      final data = MaybankReceiptParser.parse('''
Maybank
Scan and Pay
RM8.50
12 Sep 2026, 1:05 PM
Merchant Name
AUXIAOYEW
''');

      expect(data, isNotNull);
      expect(data!.type, MaybankReceiptType.scanAndPay);
      expect(data.note, 'AUXIAOYEW');
    });

    test('returns null for text that is not recognisable as either receipt type', () {
      expect(MaybankReceiptParser.parse('RM8.50\n12 Sep 2026'), isNull);
    });
  });
}
