import 'package:flutter_test/flutter_test.dart';
import 'package:money_app_flutter/core/services/receipt_scanner_service.dart';

void main() {
  group('parseReceiptText — typical Malaysian receipt layout', () {
    final rawText = '''
NASI KANDAR PELITA SDN BHD
NO 12 JALAN SS15/4D
47500 SUBANG JAYA SELANGOR
TEL: 03-5621 1234
GST NO: 001234567890
TAX INVOICE
DATE: 05/09/2026  TIME: 13:45
1 x Nasi Lemak Ayam       8.50
1 x Teh Tarik             2.50
SUBTOTAL                 11.00
SST @6%                   0.66
TOTAL (INCL. SST)         11.66
CASH                      20.00
CHANGE                     8.34
CASHIER: 01  COUNTER: 1
THANK YOU
''';

    late ReceiptData data;
    setUp(() {
      data = ReceiptScannerService.parseReceiptText(rawText, now: DateTime(2026, 9, 13));
    });

    test('picks the real business name as merchant, with high confidence', () {
      expect(data.merchantName, 'NASI KANDAR PELITA SDN BHD');
      expect(data.merchantConfidence, FieldConfidence.high);
    });

    test('distinguishes the grand total from subtotal, tax, cash and change', () {
      expect(data.amount, 11.66);
      expect(data.amountConfidence, FieldConfidence.high);
    });

    test('reads the labelled transaction date with high confidence', () {
      expect(data.date, DateTime(2026, 9, 5));
      expect(data.dateConfidence, FieldConfidence.high);
    });

    test('detects the cash payment keyword (not the unrelated "cashier" line)', () {
      expect(data.detectedPaymentKeyword, 'cash');
    });

    test('extracts item descriptions for note-building', () {
      expect(data.itemDescriptions, containsAll(['Nasi Lemak Ayam', 'Teh Tarik']));
    });
  });

  group('parseReceiptText — multiple totals on one receipt', () {
    test('picks TOTAL over SUBTOTAL and DISCOUNT', () {
      final data = ReceiptScannerService.parseReceiptText('''
STORE ABC
SUBTOTAL   20.00
DISCOUNT   2.00
TOTAL      18.00
''');
      expect(data.amount, 18.00);
      expect(data.amountConfidence, FieldConfidence.high);
    });

    test('picks TOTAL over CASH tendered and CHANGE, even though CASH is larger', () {
      final data = ReceiptScannerService.parseReceiptText('''
STORE ABC
TOTAL      15.90
CASH       50.00
CHANGE     34.10
''');
      // Regression: the old "largest amount on the receipt" fallback would
      // have picked CASH (50.00) here since it's the biggest number.
      expect(data.amount, 15.90);
      expect(data.amountConfidence, FieldConfidence.high);
    });

    test('marks the amount low-confidence when two total-like lines disagree', () {
      final data = ReceiptScannerService.parseReceiptText('''
STORE ABC
TOTAL SALES (EXCL GST)   15.00
TOTAL (INCL GST)         15.90
''');
      expect(data.amount, isNotNull);
      expect(data.amountConfidence, FieldConfidence.low);
    });
  });

  group('parseReceiptText — split label/amount rows', () {
    test('still finds the amount when the label and value are on separate lines, '
        'but only at low confidence since the association is indirect', () {
      final data = ReceiptScannerService.parseReceiptText('''
STORE ABC
TOTAL
15.90
''');
      expect(data.amount, 15.90);
      expect(data.amountConfidence, FieldConfidence.low);
    });

    test('does not borrow a value from a differently-labelled next line', () {
      final data = ReceiptScannerService.parseReceiptText('''
STORE ABC
TOTAL
CASH
20.00
''');
      // "TOTAL" has no inline price and the very next line is itself a
      // different label ("CASH"), so nothing should be borrowed from it.
      expect(data.amount, 20.00);
      expect(data.amountConfidence, FieldConfidence.low);
    });
  });

  group('parseReceiptText — ambiguous / implausible dates', () {
    test('ignores an expiry/best-before date even though it contains "date"', () {
      final data = ReceiptScannerService.parseReceiptText(
        '''
STORE ABC
DATE: 05/09/2026
BEST BEFORE: 01/01/2027
TOTAL 10.00
''',
        now: DateTime(2026, 9, 13),
      );
      expect(data.date, DateTime(2026, 9, 5));
      expect(data.dateConfidence, FieldConfidence.high);
    });

    test('marks the date low-confidence when two differently-labelled dates disagree', () {
      final data = ReceiptScannerService.parseReceiptText(
        '''
STORE ABC
INVOICE DATE: 05/09/2026
ORDER DATE: 06/09/2026
TOTAL 10.00
''',
        now: DateTime(2026, 9, 13),
      );
      expect(data.date, isNotNull);
      expect(data.dateConfidence, FieldConfidence.low);
    });

    test('rejects an implausible OCR-misread date rather than trusting it', () {
      final data = ReceiptScannerService.parseReceiptText(
        '''
STORE ABC
DATE: 05/09/2099
TOTAL 10.00
''',
        now: DateTime(2026, 9, 13),
      );
      expect(data.date, isNull);
      expect(data.dateConfidence, FieldConfidence.missing);
    });
  });

  group('parseReceiptText — noisy headers (watermark/copy stamps)', () {
    test('skips watermark/copy stamps and still finds the real merchant and category', () {
      final data = ReceiptScannerService.parseReceiptText('''
SECURE COPY
WATERMARK PRINT
99 SPEEDMART SDN BHD
NO 5 JALAN 51A/223
TEL: 03-7960 1111
1 x Milk 1L                6.90
1 x Bread                  3.20
SUBTOTAL                  10.10
TOTAL                     10.10
CASH                      20.00
CHANGE                     9.90
''');
      expect(data.merchantName, '99 SPEEDMART SDN BHD');
      expect(data.merchantConfidence, FieldConfidence.high);
      expect(data.amount, 10.10);

      final (category, confidence) = ReceiptScannerService.suggestCategory(
        merchantName: data.merchantName,
        itemDescriptions: data.itemDescriptions,
        rawText: data.rawText,
        existingCategoryLabels: ['Groceries', 'Food'],
      );
      expect(category, 'Groceries');
      expect(confidence, FieldConfidence.high);
    });
  });

  group('parseReceiptText — a different Malaysian receipt layout (petrol station)', () {
    test('extracts merchant, grand total and the specific e-wallet payment keyword', () {
      final data = ReceiptScannerService.parseReceiptText(
        '''
PETRONAS STATION KLCC
JALAN AMPANG
TEL: 03-1234 5678
DATE : 10/09/2026
RON95              50.00
GRAND TOTAL        50.00
TOUCH N GO         50.00
THANK YOU
''',
        now: DateTime(2026, 9, 13),
      );

      expect(data.merchantName, 'PETRONAS STATION KLCC');
      expect(data.amount, 50.00);
      expect(data.amountConfidence, FieldConfidence.high);
      expect(data.date, DateTime(2026, 9, 10));
      expect(data.detectedPaymentKeyword, 'touch n go');
    });
  });

  group('suggestCategory — ambiguity between equally-strong categories', () {
    test('does not claim high confidence on a genuine tie between two categories', () {
      final (category, confidence) = ReceiptScannerService.suggestCategory(
        itemDescriptions: ['nasi', 'chicken', 'milk', 'eggs'],
        existingCategoryLabels: ['Food', 'Groceries'],
      );
      // Both categories score equally (8 each) from the item list — a real
      // tie should not be reported as a confident classification.
      expect(category, isNotNull);
      expect(confidence, FieldConfidence.low);
    });

    test('is high-confidence when one category clearly dominates', () {
      final (category, confidence) = ReceiptScannerService.suggestCategory(
        merchantName: 'Restoran ABC',
        itemDescriptions: ['nasi lemak', 'teh tarik'],
        existingCategoryLabels: ['Food', 'Transport'],
      );
      expect(category, 'Food');
      expect(confidence, FieldConfidence.high);
    });
  });
}
