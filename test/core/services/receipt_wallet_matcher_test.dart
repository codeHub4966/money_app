import 'package:flutter_test/flutter_test.dart';
import 'package:money_app_flutter/core/services/receipt_wallet_matcher.dart';
import 'package:money_app_flutter/domain/models/wallet.dart';

Wallet _wallet(String id, String name, WalletType type) =>
    Wallet(id: id, name: name, type: type, balance: 0, includeInTotal: true);

void main() {
  group('ReceiptWalletMatcher', () {
    test('maps cash keyword to the single cash wallet', () {
      final wallets = [
        _wallet('1', 'Cash', WalletType.others),
        _wallet('2', 'Maybank', WalletType.bank),
      ];
      expect(ReceiptWalletMatcher.match('cash', wallets)?.id, '1');
    });

    test('maps a specific bank keyword to the matching named wallet', () {
      final wallets = [
        _wallet('1', 'Maybank Savings', WalletType.bank),
        _wallet('2', 'CIMB Current', WalletType.bank),
      ];
      expect(ReceiptWalletMatcher.match('maybank', wallets)?.id, '1');
      expect(ReceiptWalletMatcher.match('cimb', wallets)?.id, '2');
    });

    test('does not guess a specific bank when no wallet name matches it', () {
      final wallets = [_wallet('1', 'Touch n Go', WalletType.eWallet)];
      expect(ReceiptWalletMatcher.match('maybank', wallets), isNull);
    });

    // Requirement: a generic card network (Visa/Mastercard/Debit/Credit)
    // must not be confused with a specific bank/payment brand — it should
    // only ever resolve to a bank/credit wallet, and only when there is
    // exactly one, since it doesn't identify *which* one was actually used.
    test('resolves a generic card keyword only when exactly one bank/credit wallet exists', () {
      final wallets = [
        _wallet('1', 'Maybank', WalletType.bank),
        _wallet('2', 'Cash', WalletType.others),
      ];
      expect(ReceiptWalletMatcher.match('visa', wallets)?.id, '1');
      expect(ReceiptWalletMatcher.match('mastercard', wallets)?.id, '1');
    });

    test('refuses to guess a generic card keyword when multiple bank/credit wallets exist', () {
      final wallets = [
        _wallet('1', 'Maybank', WalletType.bank),
        _wallet('2', 'CIMB', WalletType.bank),
      ];
      // Previously this silently picked whichever wallet was first in the
      // list — a confident but arbitrary (and often wrong) guess.
      expect(ReceiptWalletMatcher.match('visa', wallets), isNull);
      expect(ReceiptWalletMatcher.match('debit', wallets), isNull);
    });

    test('returns null for an unknown keyword or empty wallet list', () {
      expect(ReceiptWalletMatcher.match(null, [_wallet('1', 'Cash', WalletType.others)]), isNull);
      expect(ReceiptWalletMatcher.match('visa', []), isNull);
      expect(ReceiptWalletMatcher.match('boost', [_wallet('1', 'Cash', WalletType.others)]), isNull);
    });

    // Requirement: 'MAYBANK' -> Maybank, 'CASH'/'TUNAI' -> Cash, 'TNG' ->
    // Touch 'n Go, and every generic-card-alone keyword -> null.
    test('resolves each documented evidence tier correctly', () {
      final wallets = [
        _wallet('1', 'Maybank', WalletType.bank),
        _wallet('2', 'CIMB', WalletType.bank),
        _wallet('3', 'Cash', WalletType.others),
        _wallet('4', "Touch 'n Go", WalletType.eWallet),
      ];

      expect(ReceiptWalletMatcher.match('maybank', wallets)?.name, 'Maybank');
      expect(ReceiptWalletMatcher.match('cash', wallets)?.name, 'Cash');
      // 'tng'/'tunai' are normalized to a canonical keyword upstream by
      // ReceiptScannerService._detectPaymentKeyword ('touch n go' / 'cash')
      // before ever reaching the matcher — exercised here directly.
      expect(ReceiptWalletMatcher.match('touch n go', wallets)?.name, "Touch 'n Go");
      expect(ReceiptWalletMatcher.match('visa', wallets), isNull); // ambiguous: 2 bank/credit wallets
      expect(ReceiptWalletMatcher.match('mastercard', wallets), isNull);
      expect(ReceiptWalletMatcher.match('debit', wallets), isNull);
      expect(ReceiptWalletMatcher.match('credit', wallets), isNull);
    });

    test('tolerates punctuation differences between the wallet name and the canonical keyword', () {
      // "Touch 'n Go" (apostrophe) must still match the canonical detected
      // keyword 'touch n go' (no apostrophe) — punctuation alone should
      // never defeat what is otherwise an exact brand match.
      final wallets = [_wallet('1', "Touch 'n Go", WalletType.eWallet)];
      expect(ReceiptWalletMatcher.match('touch n go', wallets)?.id, '1');
    });

    test('MAYBANK VISA resolves to Maybank via the specific brand, not the generic card word', () {
      final wallets = [
        _wallet('1', 'Maybank', WalletType.bank),
        _wallet('2', 'CIMB', WalletType.bank),
      ];
      // The scanner's _detectPaymentKeyword returns the FIRST matching
      // canonical keyword found in the receipt text; a receipt containing
      // both "MAYBANK" and "VISA" is detected as 'maybank' (the specific
      // brand), so the matcher only ever sees the specific keyword here.
      expect(ReceiptWalletMatcher.match('maybank', wallets)?.name, 'Maybank');
    });
  });
}
