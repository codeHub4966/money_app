import 'package:flutter_test/flutter_test.dart';
import 'package:money_app_flutter/core/utils/merchant_identity.dart';

void main() {
  group('extractMerchant', () {
    test('reads the leading segment of a "Merchant — items" note', () {
      expect(extractMerchant('Starbucks — Latte, Croissant'), 'Starbucks');
    });

    test('returns the whole note when there is no " — " separator', () {
      expect(extractMerchant('Netflix'), 'Netflix');
    });

    test('returns null for a null or empty note', () {
      expect(extractMerchant(null), isNull);
      expect(extractMerchant(''), isNull);
    });
  });

  group('normalizeMerchant', () {
    test('lowercases, trims, and collapses whitespace', () {
      expect(normalizeMerchant(' Tealive  SS15 '), 'tealive ss15');
    });

    test('trivially different rendering of the same merchant normalizes equal',
        () {
      expect(normalizeMerchant('Tealive'), normalizeMerchant(' tealive '));
    });
  });

  group('isGenericMerchant', () {
    test('flags common generic/unreliable names', () {
      expect(isGenericMerchant('Other'), isTrue);
      expect(isGenericMerchant('Payment'), isTrue);
      expect(isGenericMerchant('N/A'), isTrue);
      expect(isGenericMerchant('123456'), isTrue);
      expect(isGenericMerchant('a'), isTrue);
    });

    test('does not flag a real merchant name', () {
      expect(isGenericMerchant('Starbucks'), isFalse);
      expect(isGenericMerchant('Netflix'), isFalse);
    });
  });
}
