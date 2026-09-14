import 'package:flutter_test/flutter_test.dart';
import 'package:money_app_flutter/core/services/payment_notification_wallet_matcher.dart';
import 'package:money_app_flutter/domain/models/wallet.dart';

Wallet _wallet(String id, String name, WalletType type) {
  return Wallet(id: id, name: name, type: type, balance: 0, includeInTotal: true);
}

void main() {
  group('TNG wallet matching', () {
    test('unambiguous match: a single e-wallet named Touch n Go', () {
      final wallets = [
        _wallet('w1', "Touch 'n Go eWallet", WalletType.eWallet),
        _wallet('w2', 'Maybank Savings', WalletType.bank),
      ];

      final result = PaymentNotificationWalletMatcher.match(
        sourceApp: 'tng',
        sourceName: "Touch 'n Go eWallet",
        wallets: wallets,
      );

      expect(result?.id, 'w1');
    });

    test('ambiguous wallet match: two e-wallets both named like TNG -> unselected', () {
      final wallets = [
        _wallet('w1', 'TNG eWallet', WalletType.eWallet),
        _wallet('w2', 'TNG Wallet 2', WalletType.eWallet),
      ];

      final result = PaymentNotificationWalletMatcher.match(
        sourceApp: 'tng',
        sourceName: 'Touch n Go',
        wallets: wallets,
      );

      expect(result, isNull);
    });

    test('no e-wallet present -> unselected', () {
      final wallets = [_wallet('w1', 'Maybank Savings', WalletType.bank)];
      final result = PaymentNotificationWalletMatcher.match(
        sourceApp: 'tng',
        sourceName: 'Touch n Go',
        wallets: wallets,
      );
      expect(result, isNull);
    });
  });

  group('Gmail bank wallet matching', () {
    test('unambiguous match: a single wallet named after the detected bank', () {
      final wallets = [
        _wallet('w1', 'Maybank Savings', WalletType.bank),
        _wallet('w2', "Touch 'n Go eWallet", WalletType.eWallet),
      ];

      final result = PaymentNotificationWalletMatcher.match(
        sourceApp: 'gmail',
        sourceName: 'Maybank',
        wallets: wallets,
      );

      expect(result?.id, 'w1');
    });

    test('ambiguous wallet match: two Maybank-named wallets -> unselected', () {
      final wallets = [
        _wallet('w1', 'Maybank Savings', WalletType.bank),
        _wallet('w2', 'Maybank Current', WalletType.bank),
      ];

      final result = PaymentNotificationWalletMatcher.match(
        sourceApp: 'gmail',
        sourceName: 'Maybank',
        wallets: wallets,
      );

      expect(result, isNull);
    });

    test('a generic "Bank" sourceName does not falsely match an unrelated wallet', () {
      final wallets = [_wallet('w1', 'Cash', WalletType.others)];
      final result = PaymentNotificationWalletMatcher.match(
        sourceApp: 'gmail',
        sourceName: 'Bank',
        wallets: wallets,
      );
      expect(result, isNull);
    });
  });
}
