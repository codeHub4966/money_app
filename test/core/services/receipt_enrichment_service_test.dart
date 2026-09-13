import 'package:flutter_test/flutter_test.dart';
import 'package:money_app_flutter/core/services/receipt_enrichment_service.dart';
import 'package:money_app_flutter/core/services/receipt_scanner_service.dart';
import 'package:money_app_flutter/domain/models/wallet.dart';

ReceiptData _receipt({
  FieldConfidence amountConfidence = FieldConfidence.high,
  FieldConfidence dateConfidence = FieldConfidence.high,
  FieldConfidence merchantConfidence = FieldConfidence.high,
  String? detectedPaymentKeyword,
}) {
  return ReceiptData(
    amount: 10.0,
    date: DateTime(2026, 9, 5),
    merchantName: 'Store',
    rawText: 'Store\nTOTAL 10.00',
    amountConfidence: amountConfidence,
    dateConfidence: dateConfidence,
    merchantConfidence: merchantConfidence,
    detectedPaymentKeyword: detectedPaymentKeyword,
  );
}

final _cashWallet = const Wallet(id: '1', name: 'Cash', type: WalletType.others, balance: 0, includeInTotal: true);

void main() {
  group('ReceiptEnrichmentService.lowConfidenceFieldsFor — AI-fallback trigger decisions', () {
    test('is empty when every local field is high-confidence and wallet resolved', () {
      final fields = ReceiptEnrichmentService.lowConfidenceFieldsFor(
        local: _receipt(),
        localCategoryConfidence: FieldConfidence.high,
        localWallet: _cashWallet,
      );
      expect(fields, isEmpty);
    });

    test('flags amount when the local parser found conflicting/ambiguous total candidates', () {
      final fields = ReceiptEnrichmentService.lowConfidenceFieldsFor(
        local: _receipt(amountConfidence: FieldConfidence.low),
        localCategoryConfidence: FieldConfidence.high,
        localWallet: _cashWallet,
      );
      expect(fields, contains('amount'));
    });

    test('flags date when two labelled dates disagreed', () {
      final fields = ReceiptEnrichmentService.lowConfidenceFieldsFor(
        local: _receipt(dateConfidence: FieldConfidence.low),
        localCategoryConfidence: FieldConfidence.high,
        localWallet: _cashWallet,
      );
      expect(fields, contains('date'));
    });

    test('flags wallet only when a payment clue exists but could not be matched', () {
      final unresolved = ReceiptEnrichmentService.lowConfidenceFieldsFor(
        local: _receipt(detectedPaymentKeyword: 'visa'),
        localCategoryConfidence: FieldConfidence.high,
        localWallet: null,
      );
      expect(unresolved, contains('wallet'));

      // No payment clue at all is not, by itself, a reason to ask Gemini.
      final noClue = ReceiptEnrichmentService.lowConfidenceFieldsFor(
        local: _receipt(),
        localCategoryConfidence: FieldConfidence.high,
        localWallet: null,
      );
      expect(noClue, isNot(contains('wallet')));
    });

    test('flags category when local category confidence is low, not when it is genuinely high', () {
      final low = ReceiptEnrichmentService.lowConfidenceFieldsFor(
        local: _receipt(),
        localCategoryConfidence: FieldConfidence.low,
        localWallet: _cashWallet,
      );
      expect(low, contains('category'));

      final high = ReceiptEnrichmentService.lowConfidenceFieldsFor(
        local: _receipt(),
        localCategoryConfidence: FieldConfidence.high,
        localWallet: _cashWallet,
      );
      expect(high, isNot(contains('category')));
    });

    test('does not flag reliable fields just because another field is unreliable', () {
      final fields = ReceiptEnrichmentService.lowConfidenceFieldsFor(
        local: _receipt(amountConfidence: FieldConfidence.low),
        localCategoryConfidence: FieldConfidence.high,
        localWallet: _cashWallet,
      );
      expect(fields, ['amount']);
    });
  });

  group('ReceiptEnrichmentService.enrich — fast path with no network call', () {
    test('returns the local result unchanged, with usedAi false, when nothing is low-confidence', () async {
      final local = _receipt();
      final result = await ReceiptEnrichmentService.enrich(
        local: local,
        localCategory: 'Food',
        localCategoryConfidence: FieldConfidence.high,
        localWallet: _cashWallet,
        existingCategories: const ['Food'],
        existingWallets: [_cashWallet],
      );

      expect(result.usedAi, isFalse);
      expect(result.amount, local.amount);
      expect(result.date, local.date);
      expect(result.merchant, local.merchantName);
      expect(result.category, 'Food');
      expect(result.wallet, _cashWallet);
      expect(result.amountNeedsVerification, isFalse);
    });
  });
}
