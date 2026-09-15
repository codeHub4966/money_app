import 'package:flutter_test/flutter_test.dart';
import 'package:money_app_flutter/core/services/public_bank_receipt_parser.dart';
import 'package:money_app_flutter/core/services/receipt_scanner_service.dart';
import 'package:money_app_flutter/domain/models/transaction.dart';

void main() {
  group('looksLikePublicBankReceipt', () {
    test('confidently detects a Money Sent screen', () {
      expect(
        PublicBankReceiptParser.looksLikePublicBankReceipt('''
Money Sent
RM50.00
Reference No.
2026091512345678
Date & Time
15 Sep 2026, 2:32 PM
From Account
Savings Account-1234567890
Recipient Reference
rice
Recipient Account
CHANG NYET CHING O/B AU
4450438109
'''),
        isTrue,
      );
    });

    test('confidently detects a Money Paid screen', () {
      expect(
        PublicBankReceiptParser.looksLikePublicBankReceipt('''
Money Paid
RM12.50
Recipient Name
AU XIAO YEW
Recipient's Bank
CIMB Bank
Transfer Method
DuitNow QR
'''),
        isTrue,
      );
    });

    test('does not fire on an ordinary paper receipt', () {
      expect(
        PublicBankReceiptParser.looksLikePublicBankReceipt('''
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

  group('parseMoneySentText — Recipient Reference = rice (spec example)', () {
    final rawText = '''
Money Sent
RM50.00
Reference No.
2026091512345678
Date & Time
15 Sep 2026, 2:32 PM
From Account
Savings Account-1234567890
Recipient Reference
rice
Recipient Account
CHANG NYET CHING O/B AU
4450438109
Recipient Bank
AmBank
Transfer Method
DuitNow Transfer
DuitNow Ref No.
2026091512345
678901234567
''';

    late PublicBankReceiptData data;
    setUp(() {
      data = PublicBankReceiptParser.parseMoneySentText(rawText);
    });

    test('is always an Expense', () {
      expect(data.transactionType, TransactionType.expense);
      expect(data.kind, PublicBankTransactionKind.moneySent);
    });

    test('parses amount, date/time, recipient reference/account/bank, transfer method and from account', () {
      expect(data.amount, 50.00);
      expect(data.date, DateTime(2026, 9, 15, 14, 32));
      expect(data.recipientReference, 'rice');
      expect(data.recipientAccount, 'CHANG NYET CHING O/B AU 4450438109');
      expect(data.recipientBank, 'AmBank');
      expect(data.transferMethod, 'DuitNow Transfer');
      expect(data.fromAccount, 'Savings Account-1234567890');
    });

    test('note is "<Recipient Reference> - Sent to <Recipient Account>" (spec example)', () {
      expect(data.note, 'rice - Sent to CHANG NYET CHING O/B AU 4450438109');
    });

    test('category is suggested from Recipient Reference alone', () {
      expect(data.category, anyOf('Food & Dining', 'Groceries'));
    });
  });

  group('parseMoneySentText — Recipient Reference = skirt', () {
    test('category resolves to Clothing', () {
      final data = PublicBankReceiptParser.parseMoneySentText('''
Money Sent
RM89.00
Date & Time
20 Sep 2026, 9:15 AM
Recipient Reference
skirt
Recipient Account
CHANG NYET CHING O/B AU
4450438109
Recipient Bank
Public Bank
Transfer Method
DuitNow Transfer
''');

      expect(data.recipientReference, 'skirt');
      expect(data.note, 'skirt - Sent to CHANG NYET CHING O/B AU 4450438109');
      expect(data.category, 'Clothing');
    });
  });

  group('parseMoneySentText — unmatched Recipient Reference', () {
    test('category is left unselected for "hhh"', () {
      final data = PublicBankReceiptParser.parseMoneySentText('''
Money Sent
RM20.00
Date & Time
1 Jan 2026, 9:00 AM
Recipient Reference
hhh
Recipient Account
CHANG NYET CHING O/B AU
4450438109
''');

      expect(data.recipientReference, 'hhh');
      expect(data.note, 'hhh - Sent to CHANG NYET CHING O/B AU 4450438109');
      expect(data.category, isNull);
      expect(data.categoryConfidence, FieldConfidence.missing);
    });
  });

  group('parseMoneySentText — Recipient Reference missing', () {
    test('note is "Sent to <Recipient Account>" and no category is auto-selected', () {
      final data = PublicBankReceiptParser.parseMoneySentText('''
Money Sent
RM50.00
Reference No.
2026091512345678
Date & Time
15 Sep 2026, 2:32 PM
From Account
Savings Account-1234567890
Recipient Account
CHANG NYET CHING O/B AU
4450438109
Recipient Bank
AmBank
Transfer Method
DuitNow Transfer
''');

      expect(data.recipientReference, isNull);
      expect(data.recipientAccount, 'CHANG NYET CHING O/B AU 4450438109');
      expect(data.note, 'Sent to CHANG NYET CHING O/B AU 4450438109');
      expect(data.category, isNull);
      expect(data.categoryConfidence, FieldConfidence.missing);
    });
  });

  group('parseMoneyPaidText — Recipient Name matches a category (spec example layout)', () {
    test('note is "Paid to <Recipient Name>" and category is suggested', () {
      final data = PublicBankReceiptParser.parseMoneyPaidText('''
Money Paid
RM12.50
Reference No.
2026091512345678
Date & Time
15 Sep 2026, 2:32 PM
From Account
Savings Account-1234567890
Recipient Name
Zus Coffee
Recipient's Bank
CIMB Bank
Payment Method
DuitNow QR
''');

      expect(data.transactionType, TransactionType.expense);
      expect(data.kind, PublicBankTransactionKind.moneyPaid);
      expect(data.amount, 12.50);
      expect(data.date, DateTime(2026, 9, 15, 14, 32));
      expect(data.recipientName, 'Zus Coffee');
      expect(data.recipientBank, 'CIMB Bank');
      expect(data.paymentMethod, 'DuitNow QR');
      expect(data.fromAccount, 'Savings Account-1234567890');
      expect(data.note, 'Paid to Zus Coffee');
      expect(data.category, 'Food & Dining');
    });
  });

  group('parseMoneyPaidText — category remains empty when no keyword match exists', () {
    test('note is still built, but category stays unselected (spec example)', () {
      final data = PublicBankReceiptParser.parseMoneyPaidText('''
Money Paid
RM12.50
Date & Time
15 Sep 2026, 2:32 PM
Recipient Name
AU XIAO YEW
Recipient's Bank
CIMB Bank
Payment Method
DuitNow QR
''');

      expect(data.recipientName, 'AU XIAO YEW');
      expect(data.note, 'Paid to AU XIAO YEW');
      expect(data.category, isNull);
      expect(data.categoryConfidence, FieldConfidence.missing);
    });
  });

  group('field extraction — multi-line and wrapped layouts', () {
    test('Recipient Account split across two OCR lines (name line + account-number line)', () {
      final data = PublicBankReceiptParser.parseMoneySentText('''
Money Sent
RM50.00
Date & Time
15 Sep 2026, 2:32 PM
Recipient Reference
rice
Recipient Account
CHANG NYET CHING O/B AU
4450438109
Recipient Bank
AmBank
''');

      expect(data.recipientAccount, 'CHANG NYET CHING O/B AU 4450438109');
    });

    test('a DuitNow Ref No. wrapped across multiple lines does not disrupt surrounding fields', () {
      final data = PublicBankReceiptParser.parseMoneySentText('''
Money Sent
RM75.00
Reference No.
2026091512345678
Date & Time
15 Sep 2026, 2:32 PM
From Account
Savings Account-1234567890
Recipient Reference
skirt
Recipient Account
CHANG NYET CHING O/B AU
4450438109
Recipient Bank
AmBank
DuitNow Ref No.
2026091512345
678901234567890
Transfer Method
DuitNow Transfer
''');

      expect(data.amount, 75.00);
      expect(data.date, DateTime(2026, 9, 15, 14, 32));
      expect(data.recipientReference, 'skirt');
      expect(data.recipientAccount, 'CHANG NYET CHING O/B AU 4450438109');
      expect(data.recipientBank, 'AmBank');
      expect(data.transferMethod, 'DuitNow Transfer');
      expect(data.fromAccount, 'Savings Account-1234567890');
      expect(data.note, 'skirt - Sent to CHANG NYET CHING O/B AU 4450438109');
      expect(data.category, 'Clothing');
    });

    test('reads inline "Label: value" layout as well as stacked layout', () {
      final data = PublicBankReceiptParser.parseMoneyPaidText('''
Money Paid
RM12.50
Date & Time: 15/09/2026, 14:32
Recipient Name: AU XIAO YEW
Payment Method: DuitNow QR
''');

      expect(data.date, DateTime(2026, 9, 15, 14, 32));
      expect(data.recipientName, 'AU XIAO YEW');
      expect(data.paymentMethod, 'DuitNow QR');
    });

    test(
        'reads whitespace-separated "Label value" layout (real device OCR merging a '
        'side-by-side label/value row onto one line) — Money Sent spec example', () {
      final data = PublicBankReceiptParser.parseMoneySentText('''
Money Sent
RM 0.01
Reference No. 059592
Date & Time 14/09/2026 05:49:59 PM
Transfer Method Other Public Bank Account
Recipient Reference rice
Recipient Bank Public Bank Berhad
Recipient Account CHANG NYET CHING O/B AU
4450438109
From Account ******6316
''');

      expect(data.amount, 0.01);
      expect(data.date, DateTime(2026, 9, 14, 17, 49, 59));
      expect(data.recipientReference, 'rice');
      expect(data.recipientBank, 'Public Bank Berhad');
      expect(data.recipientAccount, 'CHANG NYET CHING O/B AU 4450438109');
      expect(data.transferMethod, 'Other Public Bank Account');
      expect(data.fromAccount, '******6316');
      expect(data.note, 'rice - Sent to CHANG NYET CHING O/B AU 4450438109');
      expect(data.category, anyOf('Food & Dining', 'Groceries'));
    });

    test('reads whitespace-separated "Label value" layout — Money Paid spec example', () {
      final data = PublicBankReceiptParser.parseMoneyPaidText('''
Money Paid
RM 0.01
Payment Method DuitNow QR
Recipient Name AU XIAO YEW
Recipient's Bank TNG DIGITAL SDN BHD
From Account ******6316
''');

      expect(data.amount, 0.01);
      expect(data.paymentMethod, 'DuitNow QR');
      expect(data.recipientName, 'AU XIAO YEW');
      expect(data.recipientBank, 'TNG DIGITAL SDN BHD');
      expect(data.fromAccount, '******6316');
      expect(data.note, 'Paid to AU XIAO YEW');
    });
  });

  group('detectTransactionKind', () {
    test('detects Money Sent from the header', () {
      expect(
        PublicBankReceiptParser.detectTransactionKind('Money Sent\nRM10.00'),
        PublicBankTransactionKind.moneySent,
      );
    });

    test('detects Money Paid from the header', () {
      expect(
        PublicBankReceiptParser.detectTransactionKind('Money Paid\nRM10.00'),
        PublicBankTransactionKind.moneyPaid,
      );
    });

    test('falls back to Recipient Account / Transfer Method fields when there is no header, '
        'including whitespace-separated layout', () {
      expect(
        PublicBankReceiptParser.detectTransactionKind('''
RM10.00
Recipient Reference rice
Recipient Account CHANG NYET CHING O/B AU
Transfer Method Other Public Bank Account
'''),
        PublicBankTransactionKind.moneySent,
      );
    });

    test('falls back to Recipient Name / Payment Method fields when there is no header', () {
      expect(
        PublicBankReceiptParser.detectTransactionKind('''
RM10.00
Recipient Name AU XIAO YEW
Payment Method DuitNow QR
'''),
        PublicBankTransactionKind.moneyPaid,
      );
    });

    test('returns null when neither a header nor distinguishing fields are present', () {
      expect(PublicBankReceiptParser.detectTransactionKind('RM10.00\n15 Sep 2026'), isNull);
    });
  });

  group('parse — dispatches to the right kind-specific parser', () {
    test('routes a Money Sent screen to parseMoneySentText', () {
      final data = PublicBankReceiptParser.parse('''
Money Sent
RM50.00
Recipient Reference rice
Recipient Account CHANG NYET CHING O/B AU
''');

      expect(data, isNotNull);
      expect(data!.kind, PublicBankTransactionKind.moneySent);
      expect(data.note, 'rice - Sent to CHANG NYET CHING O/B AU');
    });

    test('routes a Money Paid screen to parseMoneyPaidText', () {
      final data = PublicBankReceiptParser.parse('''
Money Paid
RM12.50
Recipient Name AU XIAO YEW
''');

      expect(data, isNotNull);
      expect(data!.kind, PublicBankTransactionKind.moneyPaid);
      expect(data.note, 'Paid to AU XIAO YEW');
    });

    test('returns null for text that is not recognisable as either kind', () {
      expect(PublicBankReceiptParser.parse('RM8.50\n12 Sep 2026'), isNull);
    });
  });
}
