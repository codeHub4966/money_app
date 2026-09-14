import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app_flutter/data/local/app_database.dart'
    hide Transaction, Wallet;
import 'package:money_app_flutter/data/repositories/transaction_repository.dart';
import 'package:money_app_flutter/data/repositories/transaction_wallet_service.dart';
import 'package:money_app_flutter/data/repositories/wallet_repository.dart';
import 'package:money_app_flutter/domain/models/transaction.dart';
import 'package:money_app_flutter/domain/models/wallet.dart';

Wallet _wallet(String id, double balance) => Wallet(
      id: id,
      name: id,
      type: WalletType.bank,
      balance: balance,
      includeInTotal: true,
    );

void main() {
  late AppDatabase db;
  late LocalWalletRepository walletRepo;
  late LocalTransactionRepository txRepo;
  late TransactionWalletService service;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    walletRepo = LocalWalletRepository(db);
    txRepo = LocalTransactionRepository(db);
    service = TransactionWalletService(db);
  });

  tearDown(() => db.close());

  group('TransactionWalletService.saveTransaction', () {
    test('writes the wallet balance and the transaction row together', () async {
      await walletRepo.add(_wallet('w1', 100));

      await service.saveTransaction(
        transaction: Transaction(
          id: 't1',
          type: TransactionType.expense,
          amount: 30,
          category: 'Food',
          accountId: 'w1',
          date: DateTime(2026, 1, 1),
        ),
        walletUpdates: const [WalletBalanceWrite('w1', 70)],
      );

      final wallets = await walletRepo.watchAll().first;
      final txs = await txRepo.watchAll().first;
      expect(wallets.single.balance, 70);
      expect(txs.single.id, 't1');
      expect(txs.single.amount, 30);
    });
  });

  group('TransactionWalletService.deleteTransaction', () {
    test('reverses the wallet balance and removes the transaction row', () async {
      await walletRepo.add(_wallet('w1', 70));
      await txRepo.add(Transaction(
        id: 't1',
        type: TransactionType.expense,
        amount: 30,
        category: 'Food',
        accountId: 'w1',
        date: DateTime(2026, 1, 1),
      ));

      await service.deleteTransaction(
        transactionId: 't1',
        walletUpdates: const [WalletBalanceWrite('w1', 100)],
      );

      final wallets = await walletRepo.watchAll().first;
      final txs = await txRepo.watchAll().first;
      expect(wallets.single.balance, 100);
      expect(txs, isEmpty);
    });
  });

  group('TransactionWalletService.saveTransfer (transfer atomicity)', () {
    test('writes both sides of the transfer and both wallet balances together',
        () async {
      await walletRepo.add(_wallet('from', 100));
      await walletRepo.add(_wallet('to', 20));

      await service.saveTransfer(
        outTransaction: Transaction(
          id: 't_out',
          type: TransactionType.expense,
          amount: 30,
          category: 'Transfer',
          accountId: 'from',
          date: DateTime(2026, 1, 1),
        ),
        inTransaction: Transaction(
          id: 't_in',
          type: TransactionType.income,
          amount: 30,
          category: 'Transfer',
          accountId: 'to',
          date: DateTime(2026, 1, 1),
        ),
        walletUpdates: const [
          WalletBalanceWrite('from', 70),
          WalletBalanceWrite('to', 50),
        ],
      );

      final wallets = await walletRepo.watchAll().first;
      final txs = await txRepo.watchAll().first;
      expect(wallets.firstWhere((w) => w.id == 'from').balance, 70);
      expect(wallets.firstWhere((w) => w.id == 'to').balance, 50);
      expect(txs.map((t) => t.id).toSet(), {'t_out', 't_in'});
    });
  });

  group('TransactionWalletService.deleteTransferPair (transfer atomicity)', () {
    test('removes both sides of the transfer and reverses both wallet balances',
        () async {
      await walletRepo.add(_wallet('from', 70));
      await walletRepo.add(_wallet('to', 50));
      await txRepo.add(Transaction(
        id: 't_out',
        type: TransactionType.expense,
        amount: 30,
        category: 'Transfer',
        accountId: 'from',
        date: DateTime(2026, 1, 1),
      ));
      await txRepo.add(Transaction(
        id: 't_in',
        type: TransactionType.income,
        amount: 30,
        category: 'Transfer',
        accountId: 'to',
        date: DateTime(2026, 1, 1),
      ));

      await service.deleteTransferPair(
        outId: 't_out',
        inId: 't_in',
        walletUpdates: const [
          WalletBalanceWrite('from', 100),
          WalletBalanceWrite('to', 20),
        ],
      );

      final wallets = await walletRepo.watchAll().first;
      final txs = await txRepo.watchAll().first;
      expect(wallets.firstWhere((w) => w.id == 'from').balance, 100);
      expect(wallets.firstWhere((w) => w.id == 'to').balance, 20);
      expect(txs, isEmpty);
    });
  });

  group('atomic rollback on failure', () {
    test(
        'a failure partway through saveTransfer rolls back the wallet balance writes that already ran',
        () async {
      await walletRepo.add(_wallet('from', 100));
      await walletRepo.add(_wallet('to', 20));

      // Force the transaction insert step to fail with a real database
      // error, after the wallet balance writes (which run first inside the
      // same atomic block) have already been applied in-transaction.
      await db.customStatement('DROP TABLE transactions');

      await expectLater(
        () => service.saveTransfer(
          outTransaction: Transaction(
            id: 't_out',
            type: TransactionType.expense,
            amount: 30,
            category: 'Transfer',
            accountId: 'from',
            date: DateTime(2026, 1, 1),
          ),
          inTransaction: Transaction(
            id: 't_in',
            type: TransactionType.income,
            amount: 30,
            category: 'Transfer',
            accountId: 'to',
            date: DateTime(2026, 1, 1),
          ),
          walletUpdates: const [
            WalletBalanceWrite('from', 70),
            WalletBalanceWrite('to', 50),
          ],
        ),
        throwsA(anything),
      );

      // Wallet balances must be exactly what they were before the call —
      // not left at the intermediate (uncommitted) values.
      final wallets = await walletRepo.watchAll().first;
      expect(wallets.firstWhere((w) => w.id == 'from').balance, 100);
      expect(wallets.firstWhere((w) => w.id == 'to').balance, 20);
    });

    test(
        'a failure partway through saveTransaction rolls back the wallet balance write',
        () async {
      await walletRepo.add(_wallet('w1', 100));
      await db.customStatement('DROP TABLE transactions');

      await expectLater(
        () => service.saveTransaction(
          transaction: Transaction(
            id: 't1',
            type: TransactionType.expense,
            amount: 30,
            category: 'Food',
            accountId: 'w1',
            date: DateTime(2026, 1, 1),
          ),
          walletUpdates: const [WalletBalanceWrite('w1', 70)],
        ),
        throwsA(anything),
      );

      final wallets = await walletRepo.watchAll().first;
      expect(wallets.single.balance, 100);
    });
  });

  group('IWalletRepository.isReferencedByTransactions (wallet deletion guard)',
      () {
    test('true when a transaction still uses the wallet\'s accountId', () async {
      await walletRepo.add(_wallet('w1', 100));
      await txRepo.add(Transaction(
        id: 't1',
        type: TransactionType.expense,
        amount: 30,
        category: 'Food',
        accountId: 'w1',
        date: DateTime(2026, 1, 1),
      ));

      expect(await walletRepo.isReferencedByTransactions('w1'), isTrue);
    });

    test('false when no transaction references the wallet', () async {
      await walletRepo.add(_wallet('w1', 100));

      expect(await walletRepo.isReferencedByTransactions('w1'), isFalse);
    });

    test('false once the referencing transaction has been removed', () async {
      await walletRepo.add(_wallet('w1', 100));
      await txRepo.add(Transaction(
        id: 't1',
        type: TransactionType.expense,
        amount: 30,
        category: 'Food',
        accountId: 'w1',
        date: DateTime(2026, 1, 1),
      ));
      await txRepo.delete('t1');

      expect(await walletRepo.isReferencedByTransactions('w1'), isFalse);
    });
  });
}
