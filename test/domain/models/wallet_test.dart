import 'package:flutter_test/flutter_test.dart';
import 'package:money_app_flutter/domain/models/wallet.dart';

void main() {
  group('WalletTypeStorage.fromStorageName — current type set', () {
    test('parses every current WalletType by its own name', () {
      for (final type in WalletType.values) {
        expect(WalletTypeStorage.fromStorageName(type.name), type);
      }
    });
  });

  group('WalletTypeStorage.fromStorageName — intermediate type set (eWallet/debitCard/creditCard/bank/savings/others)', () {
    test('debitCard and creditCard both migrate to card', () {
      expect(WalletTypeStorage.fromStorageName('debitCard'), WalletType.card);
      expect(WalletTypeStorage.fromStorageName('creditCard'), WalletType.card);
    });
  });

  group('WalletTypeStorage.fromStorageName — original type set (bank/credit/cash/crypto/savings/other)', () {
    test('credit migrates to card', () {
      expect(WalletTypeStorage.fromStorageName('credit'), WalletType.card);
    });

    test('other (singular) migrates to eWallet', () {
      expect(WalletTypeStorage.fromStorageName('other'), WalletType.eWallet);
    });

    test('cash resolves directly to the reinstated cash type', () {
      expect(WalletTypeStorage.fromStorageName('cash'), WalletType.cash);
    });

    test('crypto migrates to others', () {
      expect(WalletTypeStorage.fromStorageName('crypto'), WalletType.others);
    });
  });
}
