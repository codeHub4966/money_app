import 'package:flutter_test/flutter_test.dart';
import 'package:money_app_flutter/domain/models/transaction.dart';
import 'package:money_app_flutter/domain/models/wallet.dart';
import 'package:money_app_flutter/presentation/screens/add_transaction_screen/add_transaction_screen.dart';

Wallet _wallet(String id, double balance) => Wallet(
      id: id,
      name: id,
      type: WalletType.bank,
      balance: balance,
      includeInTotal: true,
    );

Transaction _tx(TransactionType type, double amount, String accountId) => Transaction(
      id: 'old-tx',
      type: type,
      amount: amount,
      category: 'Food',
      accountId: accountId,
      date: DateTime(2026, 1, 1),
    );

void main() {
  group('computeWalletBalanceUpdates', () {
    test('new transaction applies its effect to the selected wallet', () {
      final wallet = _wallet('maybank', 100);

      final updates = computeWalletBalanceUpdates(
        oldTransaction: null,
        oldWallet: null,
        newWallet: wallet,
        newType: TransactionType.income,
        newAmount: 50,
      );

      expect(updates.length, 1);
      expect(updates.single.walletId, 'maybank');
      expect(updates.single.balance, 150);
    });

    test('same wallet + changed amount reverses old amount then applies new amount', () {
      final wallet = _wallet('maybank', 150); // 100 base + 50 old income
      final old = _tx(TransactionType.income, 50, 'maybank');

      final updates = computeWalletBalanceUpdates(
        oldTransaction: old,
        oldWallet: null,
        newWallet: wallet,
        newType: TransactionType.income,
        newAmount: 80,
      );

      expect(updates.length, 1);
      expect(updates.single.walletId, 'maybank');
      // 150 - 50 (reverse old income) + 80 (new income) = 180
      expect(updates.single.balance, 180);
    });

    test('same wallet + income/expense type change', () {
      final wallet = _wallet('maybank', 150); // 100 base + 50 old income
      final old = _tx(TransactionType.income, 50, 'maybank');

      final updates = computeWalletBalanceUpdates(
        oldTransaction: old,
        oldWallet: null,
        newWallet: wallet,
        newType: TransactionType.expense,
        newAmount: 50,
      );

      // 150 - 50 (reverse old income) - 50 (new expense) = 50
      expect(updates.single.balance, 50);
    });

    test('different wallet moves the balance from old wallet to new wallet', () {
      final maybank = _wallet('maybank', 100); // has the RM100 income applied
      final cash = _wallet('cash', 0);
      final old = _tx(TransactionType.income, 100, 'maybank');

      final updates = computeWalletBalanceUpdates(
        oldTransaction: old,
        oldWallet: maybank,
        newWallet: cash,
        newType: TransactionType.income,
        newAmount: 100,
      );

      expect(updates.length, 2);
      final maybankUpdate = updates.firstWhere((u) => u.walletId == 'maybank');
      final cashUpdate = updates.firstWhere((u) => u.walletId == 'cash');
      expect(maybankUpdate.balance, 0);
      expect(cashUpdate.balance, 100);
    });

    test('different wallet + changed amount', () {
      final maybank = _wallet('maybank', 100); // has the RM100 income applied
      final cash = _wallet('cash', 20);
      final old = _tx(TransactionType.income, 100, 'maybank');

      final updates = computeWalletBalanceUpdates(
        oldTransaction: old,
        oldWallet: maybank,
        newWallet: cash,
        newType: TransactionType.income,
        newAmount: 30,
      );

      final maybankUpdate = updates.firstWhere((u) => u.walletId == 'maybank');
      final cashUpdate = updates.firstWhere((u) => u.walletId == 'cash');
      expect(maybankUpdate.balance, 0);
      expect(cashUpdate.balance, 50); // 20 + 30
    });

    test('different wallet + income/expense type change', () {
      final maybank = _wallet('maybank', 100); // has the RM100 income applied
      final cash = _wallet('cash', 20);
      final old = _tx(TransactionType.income, 100, 'maybank');

      final updates = computeWalletBalanceUpdates(
        oldTransaction: old,
        oldWallet: maybank,
        newWallet: cash,
        newType: TransactionType.expense,
        newAmount: 30,
      );

      final maybankUpdate = updates.firstWhere((u) => u.walletId == 'maybank');
      final cashUpdate = updates.firstWhere((u) => u.walletId == 'cash');
      // Old income fully reversed from maybank regardless of new type.
      expect(maybankUpdate.balance, 0);
      // New expense reduces the new wallet.
      expect(cashUpdate.balance, -10); // 20 - 30
    });

    test('expense -> income across wallets combined with amount change', () {
      final maybank = _wallet('maybank', 50); // 100 base - 50 old expense
      final cash = _wallet('cash', 0);
      final old = _tx(TransactionType.expense, 50, 'maybank');

      final updates = computeWalletBalanceUpdates(
        oldTransaction: old,
        oldWallet: maybank,
        newWallet: cash,
        newType: TransactionType.income,
        newAmount: 75,
      );

      final maybankUpdate = updates.firstWhere((u) => u.walletId == 'maybank');
      final cashUpdate = updates.firstWhere((u) => u.walletId == 'cash');
      // Reversing an old expense adds it back.
      expect(maybankUpdate.balance, 100);
      expect(cashUpdate.balance, 75);
    });

    test(
        'documented worked example: RM100 income moved from Maybank to Cash',
        () {
      final maybank = _wallet('maybank', 100);
      final cash = _wallet('cash', 0);
      final old = _tx(TransactionType.income, 100, 'maybank');

      final updates = computeWalletBalanceUpdates(
        oldTransaction: old,
        oldWallet: maybank,
        newWallet: cash,
        newType: TransactionType.income,
        newAmount: 100,
      );

      final maybankUpdate = updates.firstWhere((u) => u.walletId == 'maybank');
      final cashUpdate = updates.firstWhere((u) => u.walletId == 'cash');
      expect(maybankUpdate.balance, 0);
      expect(cashUpdate.balance, 100);
    });
  });

  group('balanceEffect', () {
    test('income is positive, expense is negative', () {
      expect(balanceEffect(TransactionType.income, 20), 20);
      expect(balanceEffect(TransactionType.expense, 20), -20);
    });
  });
}
