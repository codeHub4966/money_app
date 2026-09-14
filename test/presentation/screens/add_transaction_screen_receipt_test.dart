import 'package:flutter_test/flutter_test.dart';
import 'package:money_app_flutter/presentation/screens/add_transaction_screen/add_transaction_screen.dart';

void main() {
  group('receiptPermanentPath', () {
    test('builds the deterministic per-transaction receipt path', () {
      expect(receiptPermanentPath('/docs', 't1'), '/docs/receipts/t1.jpg');
    });
  });

  group(
      'isAlreadyPermanentReceiptPath (requirement 6A: no self-copy on edit)',
      () {
    test('true when the candidate path is already the permanent file', () {
      expect(
        isAlreadyPermanentReceiptPath(
            '/docs/receipts/t1.jpg', '/docs', 't1'),
        isTrue,
      );
    });

    test('false for a fresh picker temp path (new photo)', () {
      expect(
        isAlreadyPermanentReceiptPath(
            '/tmp/cache/image_picker_123.jpg', '/docs', 't1'),
        isFalse,
      );
    });

    test('false when it is another transaction\'s permanent path', () {
      expect(
        isAlreadyPermanentReceiptPath(
            '/docs/receipts/other-tx.jpg', '/docs', 't1'),
        isFalse,
      );
    });
  });

  group('shouldDeleteOldReceipt (requirements 6B/6C: replace/remove cleanup)',
      () {
    test('false when there was no old receipt', () {
      expect(shouldDeleteOldReceipt(null, '/docs/receipts/t1.jpg'), isFalse);
    });

    test(
        'false when unchanged — editing without touching the receipt overwrites in place',
        () {
      expect(
        shouldDeleteOldReceipt(
            '/docs/receipts/t1.jpg', '/docs/receipts/t1.jpg'),
        isFalse,
      );
    });

    test('true when the receipt was removed (new path is null)', () {
      expect(shouldDeleteOldReceipt('/docs/receipts/t1.jpg', null), isTrue);
    });

    test('true when replaced by a genuinely different path', () {
      expect(
        shouldDeleteOldReceipt(
            '/docs/receipts/t1.jpg', '/docs/receipts/other.jpg'),
        isTrue,
      );
    });
  });
}
