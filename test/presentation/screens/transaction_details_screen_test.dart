import 'package:flutter_test/flutter_test.dart';
import 'package:money_app_flutter/domain/models/transaction.dart';
import 'package:money_app_flutter/domain/models/wallet.dart';
import 'package:money_app_flutter/presentation/screens/home/transaction_details_screen.dart';

Wallet _wallet(String id, double balance) => Wallet(
      id: id,
      name: id,
      type: WalletType.bank,
      balance: balance,
      includeInTotal: true,
    );

void main() {
  group('computeDeleteTransactionPlan (requirement 1: delete uses latest edit)',
      () {
    test(
        'reverses the transaction\'s current (edited) amount and wallet, not any original value',
        () {
      // Original was RM50 from Wallet A; the transaction was since edited to
      // RM80 from Wallet B. Only the current (post-edit) transaction object
      // is ever passed in here — there is no "original" to accidentally use.
      final walletA = _wallet('walletA', 200); // untouched by the edited tx
      final walletB = _wallet('walletB', 300); // holds the RM80 expense

      final edited = Transaction(
        id: 't1',
        type: TransactionType.expense,
        amount: 80,
        category: 'Food',
        accountId: 'walletB',
        date: DateTime(2026, 1, 1),
      );

      final plan = computeDeleteTransactionPlan(
        transaction: edited,
        wallets: [walletA, walletB],
        allTransactions: [edited],
      );

      expect(plan.walletUpdates, hasLength(1));
      expect(plan.walletUpdates.single.walletId, 'walletB');
      // 300 + 80 (reverse the expense) = 380 — walletA is untouched.
      expect(plan.walletUpdates.single.balance, 380);
    });

    test('reverses an income transaction by subtracting it back out', () {
      final wallet = _wallet('w1', 150);
      final tx = Transaction(
        id: 't1',
        type: TransactionType.income,
        amount: 50,
        category: 'Salary',
        accountId: 'w1',
        date: DateTime(2026, 1, 1),
      );

      final plan = computeDeleteTransactionPlan(
        transaction: tx,
        wallets: [wallet],
        allTransactions: [tx],
      );

      expect(plan.walletUpdates.single.balance, 100);
      expect(plan.pairedTransactionId, isNull);
    });

    test('Balance Adjustment entries are reversed the same way as regular transactions',
        () {
      final wallet = _wallet('w1', 120);
      final tx = Transaction(
        id: 't1',
        type: TransactionType.income,
        amount: 20,
        category: 'Balance Adjustment',
        accountId: 'w1',
        date: DateTime(2026, 1, 1),
      );

      final plan = computeDeleteTransactionPlan(
        transaction: tx,
        wallets: [wallet],
        allTransactions: [tx],
      );

      expect(plan.walletUpdates.single.walletId, 'w1');
      expect(plan.walletUpdates.single.balance, 100);
    });

    test('a missing wallet (already deleted) yields no wallet update but still identifies the transaction',
        () {
      final tx = Transaction(
        id: 't1',
        type: TransactionType.expense,
        amount: 10,
        category: 'Food',
        accountId: 'gone',
        date: DateTime(2026, 1, 1),
      );

      final plan = computeDeleteTransactionPlan(
        transaction: tx,
        wallets: const [],
        allTransactions: [tx],
      );

      expect(plan.walletUpdates, isEmpty);
      expect(plan.pairedTransactionId, isNull);
    });

    group('transfers', () {
      test('reverses both sides of the pair and identifies the paired id', () {
        final from = _wallet('from', 70); // 100 - 30
        final to = _wallet('to', 50); // 20 + 30
        final out = Transaction(
          id: 'x_out',
          type: TransactionType.expense,
          amount: 30,
          category: 'Transfer',
          accountId: 'from',
          date: DateTime(2026, 1, 1),
        );
        final inTx = Transaction(
          id: 'x_in',
          type: TransactionType.income,
          amount: 30,
          category: 'Transfer',
          accountId: 'to',
          date: DateTime(2026, 1, 1),
        );

        final plan = computeDeleteTransactionPlan(
          transaction: out,
          wallets: [from, to],
          allTransactions: [out, inTx],
        );

        expect(plan.pairedTransactionId, 'x_in');
        final fromUpdate =
            plan.walletUpdates.firstWhere((u) => u.walletId == 'from');
        final toUpdate =
            plan.walletUpdates.firstWhere((u) => u.walletId == 'to');
        expect(fromUpdate.balance, 100); // reversed the expense
        expect(toUpdate.balance, 20); // reversed the paired income
      });

      test('reversal uses the paired transaction\'s latest amount, not the deleted side\'s',
          () {
        // Edited transfers can, in principle, have their pair edited
        // independently — the plan must reverse each side using that
        // side's own (current) amount.
        final from = _wallet('from', 50);
        final to = _wallet('to', 90);
        final out = Transaction(
          id: 'x_out',
          type: TransactionType.expense,
          amount: 60,
          category: 'Transfer',
          accountId: 'from',
          date: DateTime(2026, 1, 1),
        );
        final inTx = Transaction(
          id: 'x_in',
          type: TransactionType.income,
          amount: 60,
          category: 'Transfer',
          accountId: 'to',
          date: DateTime(2026, 1, 1),
        );

        final plan = computeDeleteTransactionPlan(
          transaction: inTx,
          wallets: [from, to],
          allTransactions: [out, inTx],
        );

        expect(plan.pairedTransactionId, 'x_out');
        final fromUpdate =
            plan.walletUpdates.firstWhere((u) => u.walletId == 'from');
        final toUpdate =
            plan.walletUpdates.firstWhere((u) => u.walletId == 'to');
        expect(fromUpdate.balance, 110); // 50 + 60
        expect(toUpdate.balance, 30); // 90 - 60
      });

      test('missing paired transaction: reverses only the found side', () {
        final from = _wallet('from', 70);
        final out = Transaction(
          id: 'x_out',
          type: TransactionType.expense,
          amount: 30,
          category: 'Transfer',
          accountId: 'from',
          date: DateTime(2026, 1, 1),
        );

        final plan = computeDeleteTransactionPlan(
          transaction: out,
          wallets: [from],
          allTransactions: [out],
        );

        expect(plan.pairedTransactionId, isNull);
        expect(plan.walletUpdates, hasLength(1));
        expect(plan.walletUpdates.single.walletId, 'from');
        expect(plan.walletUpdates.single.balance, 100);
      });

      test('carries the paired transaction\'s receipt path for cleanup, if any',
          () {
        final from = _wallet('from', 70);
        final to = _wallet('to', 50);
        final out = Transaction(
          id: 'x_out',
          type: TransactionType.expense,
          amount: 30,
          category: 'Transfer',
          accountId: 'from',
          date: DateTime(2026, 1, 1),
        );
        final inTx = Transaction(
          id: 'x_in',
          type: TransactionType.income,
          amount: 30,
          category: 'Transfer',
          accountId: 'to',
          date: DateTime(2026, 1, 1),
          receiptImagePath: '/receipts/x_in.jpg',
        );

        final plan = computeDeleteTransactionPlan(
          transaction: out,
          wallets: [from, to],
          allTransactions: [out, inTx],
        );

        expect(plan.pairedReceiptPath, '/receipts/x_in.jpg');
      });
    });
  });
}
