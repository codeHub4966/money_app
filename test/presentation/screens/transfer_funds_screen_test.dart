import 'package:flutter_test/flutter_test.dart';
import 'package:money_app_flutter/domain/models/wallet.dart';
import 'package:money_app_flutter/presentation/screens/wallet/transfer_funds_screen.dart';

Wallet _wallet(String id, double balance) => Wallet(
      id: id,
      name: id,
      type: WalletType.bank,
      balance: balance,
      includeInTotal: true,
    );

void main() {
  group('computeTransferBalanceUpdates', () {
    test('new transfer subtracts from the source and adds to the destination', () {
      final from = _wallet('maybank', 100);
      final to = _wallet('cash', 20);

      final updates = computeTransferBalanceUpdates(
        oldAmount: null,
        oldFromWallet: null,
        oldToWallet: null,
        newFromWallet: from,
        newToWallet: to,
        newAmount: 30,
      );

      expect(updates.length, 2);
      final fromUpdate = updates.firstWhere((u) => u.walletId == 'maybank');
      final toUpdate = updates.firstWhere((u) => u.walletId == 'cash');
      expect(fromUpdate.balance, 70);
      expect(toUpdate.balance, 50);
    });

    test('editing with the same wallets reverses the old amount then applies the new amount', () {
      // maybank started at 100, has already had RM30 subtracted (now 70);
      // cash started at 20, has already had RM30 added (now 50).
      final from = _wallet('maybank', 70);
      final to = _wallet('cash', 50);

      final updates = computeTransferBalanceUpdates(
        oldAmount: 30,
        oldFromWallet: from,
        oldToWallet: to,
        newFromWallet: from,
        newToWallet: to,
        newAmount: 50,
      );

      final fromUpdate = updates.firstWhere((u) => u.walletId == 'maybank');
      final toUpdate = updates.firstWhere((u) => u.walletId == 'cash');
      // 70 + 30 (reverse old) - 50 (new) = 50
      expect(fromUpdate.balance, 50);
      // 50 - 30 (reverse old) + 50 (new) = 70
      expect(toUpdate.balance, 70);
    });

    test('editing to change the source wallet moves the effect between wallets', () {
      final oldFrom = _wallet('maybank', 70); // 100 - 30
      final newFrom = _wallet('cimb', 200);
      final to = _wallet('cash', 50); // 20 + 30

      final updates = computeTransferBalanceUpdates(
        oldAmount: 30,
        oldFromWallet: oldFrom,
        oldToWallet: to,
        newFromWallet: newFrom,
        newToWallet: to,
        newAmount: 30,
      );

      final maybankUpdate = updates.firstWhere((u) => u.walletId == 'maybank');
      final cimbUpdate = updates.firstWhere((u) => u.walletId == 'cimb');
      final cashUpdate = updates.firstWhere((u) => u.walletId == 'cash');
      expect(maybankUpdate.balance, 100); // fully reversed
      expect(cimbUpdate.balance, 170); // 200 - 30
      // to wallet: reverse old (-30) then reapply new (+30) = unchanged
      expect(cashUpdate.balance, 50);
    });

    test('editing with from/to swapped nets out correctly for the shared wallet', () {
      final a = _wallet('a', 70); // was "from": 100 - 30
      final b = _wallet('b', 50); // was "to": 20 + 30

      final updates = computeTransferBalanceUpdates(
        oldAmount: 30,
        oldFromWallet: a,
        oldToWallet: b,
        newFromWallet: b,
        newToWallet: a,
        newAmount: 30,
      );

      final aUpdate = updates.firstWhere((u) => u.walletId == 'a');
      final bUpdate = updates.firstWhere((u) => u.walletId == 'b');
      // a: reverse old "from" (+30), then apply new "to" (+30) = 70 + 30 + 30 = 130
      expect(aUpdate.balance, 130);
      // b: reverse old "to" (-30), then apply new "from" (-30) = 50 - 30 - 30 = -10
      expect(bUpdate.balance, -10);
    });

    test('editing to increase the amount can push the source balance negative', () {
      final from = _wallet('maybank', 70); // 100 - 30
      final to = _wallet('cash', 50);

      final updates = computeTransferBalanceUpdates(
        oldAmount: 30,
        oldFromWallet: from,
        oldToWallet: to,
        newFromWallet: from,
        newToWallet: to,
        newAmount: 150,
      );

      final fromUpdate = updates.firstWhere((u) => u.walletId == 'maybank');
      // 70 + 30 (reverse) - 150 (new) = -50
      expect(fromUpdate.balance, -50);
    });
  });
}
