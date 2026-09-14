import 'package:flutter_test/flutter_test.dart';
import 'package:money_app_flutter/core/services/export_service.dart';
import 'package:money_app_flutter/core/services/import_service.dart';
import 'package:money_app_flutter/data/repositories/transaction_repository.dart';
import 'package:money_app_flutter/data/repositories/wallet_repository.dart';
import 'package:money_app_flutter/domain/models/transaction.dart';
import 'package:money_app_flutter/domain/models/wallet.dart';

class FakeTransactionRepository implements ITransactionRepository {
  final List<Transaction> items = [];

  @override
  Future<void> add(Transaction t) async {
    items.removeWhere((e) => e.id == t.id);
    items.add(t);
  }

  @override
  Future<void> delete(String id) async => items.removeWhere((e) => e.id == id);

  @override
  Stream<List<Transaction>> watchAll() => Stream.value(List.of(items));
}

class FakeWalletRepository implements IWalletRepository {
  final List<Wallet> items;
  FakeWalletRepository(this.items);

  @override
  Future<void> add(Wallet w) async {
    items.removeWhere((e) => e.id == w.id);
    items.add(w);
  }

  @override
  Future<void> delete(String id) async => items.removeWhere((e) => e.id == id);

  @override
  Stream<List<Wallet>> watchAll() => Stream.value(List.of(items));

  @override
  Future<void> updateBalance(String id, double newBalance) async {
    final i = items.indexWhere((e) => e.id == id);
    items[i] = Wallet(
      id: items[i].id,
      name: items[i].name,
      type: items[i].type,
      balance: newBalance,
      includeInTotal: items[i].includeInTotal,
    );
  }

  @override
  Future<bool> isReferencedByTransactions(String walletId) async => false;
}

Future<String?> _noFallback(List<Wallet> wallets) async => null;

void main() {
  late FakeTransactionRepository txRepo;
  late FakeWalletRepository walletRepo;

  setUp(() {
    txRepo = FakeTransactionRepository();
    walletRepo = FakeWalletRepository([
      const Wallet(
          id: 'wallet-a',
          name: 'Cash',
          type: WalletType.others,
          balance: 100,
          includeInTotal: true),
      const Wallet(
          id: 'wallet-b',
          name: 'Bank',
          type: WalletType.bank,
          balance: 500,
          includeInTotal: true),
    ]);
  });

  List<Transaction> sampleTransactions() => [
        Transaction(
          id: 'tx-1',
          type: TransactionType.expense,
          amount: 12.5,
          category: 'Food',
          accountId: 'wallet-a',
          note:
              'Lunch with friends and a fairly long note to check line wrapping',
          date: DateTime.parse('2026-09-01T10:15:00.000'),
        ),
        Transaction(
          id: 'tx-2',
          type: TransactionType.income,
          amount: 999.99,
          category: 'Salary',
          accountId: 'wallet-b',
          date: DateTime.parse('2026-09-02T09:00:00.000'),
        ),
      ];

  group('CSV import', () {
    test('imports valid rows and updates wallet balances', () async {
      final csv = ExportService.buildCsvString(sampleTransactions());

      final summary = await ImportService.importCsvContent(
        csv,
        txRepo: txRepo,
        walletRepo: walletRepo,
        resolveFallbackWallet: _noFallback,
      );

      expect(summary.imported, 2);
      expect(summary.skippedDuplicates, 0);
      expect(summary.invalidRows, 0);
      expect(txRepo.items.map((t) => t.id), containsAll(['tx-1', 'tx-2']));
      expect(walletRepo.items.firstWhere((w) => w.id == 'wallet-a').balance,
          100 - 12.5);
      expect(walletRepo.items.firstWhere((w) => w.id == 'wallet-b').balance,
          500 + 999.99);
    });

    test('rejects a file with the wrong header', () async {
      const badCsv = 'Foo,Bar\n1,2';
      expect(
        () => ImportService.importCsvContent(
          badCsv,
          txRepo: txRepo,
          walletRepo: walletRepo,
          resolveFallbackWallet: _noFallback,
        ),
        throwsA(isA<ImportValidationException>()),
      );
    });

    test(
        'counts invalid rows without defaulting amount/date, and never uses accountId "imported"',
        () async {
      final csv = '''
ID,Type,Amount,Category,Account,Note,Date
bad-amount,expense,0,Food,wallet-a,,2026-09-01T10:00:00.000
bad-amount2,expense,-5,Food,wallet-a,,2026-09-01T10:00:00.000
bad-date,expense,10,Food,wallet-a,,not-a-date
bad-type,notatype,10,Food,wallet-a,,2026-09-01T10:00:00.000
bad-category,expense,10,,wallet-a,,2026-09-01T10:00:00.000
bad-wallet,expense,10,Food,,,2026-09-01T10:00:00.000
literal-imported,expense,10,Food,imported,,2026-09-01T10:00:00.000
'''
          .trim();

      final summary = await ImportService.importCsvContent(
        csv,
        txRepo: txRepo,
        walletRepo: walletRepo,
        resolveFallbackWallet: _noFallback,
      );

      expect(summary.imported, 0);
      expect(summary.invalidRows, 7);
      expect(txRepo.items, isEmpty);
      // Balances must be untouched since nothing valid was imported.
      expect(
          walletRepo.items.firstWhere((w) => w.id == 'wallet-a').balance, 100);
    });

    test('skips rows whose ID already exists', () async {
      await txRepo.add(Transaction(
        id: 'tx-1',
        type: TransactionType.expense,
        amount: 1,
        category: 'Food',
        accountId: 'wallet-a',
        date: DateTime.now(),
      ));

      final csv = ExportService.buildCsvString(sampleTransactions());
      final summary = await ImportService.importCsvContent(
        csv,
        txRepo: txRepo,
        walletRepo: walletRepo,
        resolveFallbackWallet: _noFallback,
      );

      expect(summary.imported, 1);
      expect(summary.skippedDuplicates, 1);
      // Only tx-2's income should have moved wallet-b's balance; wallet-a
      // (tx-1's wallet) must be untouched since tx-1 was a duplicate.
      expect(
          walletRepo.items.firstWhere((w) => w.id == 'wallet-a').balance, 100);
      expect(walletRepo.items.firstWhere((w) => w.id == 'wallet-b').balance,
          500 + 999.99);
    });

    test('re-importing the same file a second time is a no-op', () async {
      final csv = ExportService.buildCsvString(sampleTransactions());

      await ImportService.importCsvContent(csv,
          txRepo: txRepo,
          walletRepo: walletRepo,
          resolveFallbackWallet: _noFallback);
      final balanceA =
          walletRepo.items.firstWhere((w) => w.id == 'wallet-a').balance;
      final balanceB =
          walletRepo.items.firstWhere((w) => w.id == 'wallet-b').balance;
      final txCount = txRepo.items.length;

      final summary2 = await ImportService.importCsvContent(csv,
          txRepo: txRepo,
          walletRepo: walletRepo,
          resolveFallbackWallet: _noFallback);

      expect(summary2.imported, 0);
      expect(summary2.skippedDuplicates, 2);
      expect(txRepo.items.length, txCount);
      expect(walletRepo.items.firstWhere((w) => w.id == 'wallet-a').balance,
          balanceA);
      expect(walletRepo.items.firstWhere((w) => w.id == 'wallet-b').balance,
          balanceB);
    });

    test(
        'asks for a fallback wallet when the original wallet is missing, and applies it',
        () async {
      final csv = '''
ID,Type,Amount,Category,Account,Note,Date
tx-9,expense,20,Food,ghost-wallet,,2026-09-01T10:00:00.000
'''
          .trim();

      final summary = await ImportService.importCsvContent(
        csv,
        txRepo: txRepo,
        walletRepo: walletRepo,
        resolveFallbackWallet: (wallets) async {
          expect(
              wallets.map((w) => w.id), containsAll(['wallet-a', 'wallet-b']));
          return 'wallet-b';
        },
      );

      expect(summary.imported, 1);
      expect(txRepo.items.single.accountId, 'wallet-b');
      expect(walletRepo.items.firstWhere((w) => w.id == 'wallet-b').balance,
          500 - 20);
    });

    test(
        'marks rows as invalid when the user cancels the fallback wallet prompt',
        () async {
      final csv = '''
ID,Type,Amount,Category,Account,Note,Date
tx-9,expense,20,Food,ghost-wallet,,2026-09-01T10:00:00.000
'''
          .trim();

      final summary = await ImportService.importCsvContent(
        csv,
        txRepo: txRepo,
        walletRepo: walletRepo,
        resolveFallbackWallet: _noFallback,
      );

      expect(summary.imported, 0);
      expect(summary.invalidRows, 1);
      expect(txRepo.items, isEmpty);
    });
  });

  group('PDF import', () {
    test('imports valid rows and updates wallet balances', () async {
      final bytes = await ExportService.buildPdfBytes(sampleTransactions());

      final summary = await ImportService.importPdfBytes(
        bytes,
        txRepo: txRepo,
        walletRepo: walletRepo,
        resolveFallbackWallet: _noFallback,
      );

      expect(summary.imported, 2);
      expect(summary.invalidRows, 0);
      final imported = txRepo.items.firstWhere((t) => t.id == 'tx-1');
      expect(imported.amount, 12.5);
      expect(imported.category, 'Food');
      expect(imported.accountId, 'wallet-a');
      expect(imported.date, DateTime.parse('2026-09-01T10:15:00.000'));
      expect(imported.note,
          'Lunch with friends and a fairly long note to check line wrapping');
      expect(walletRepo.items.firstWhere((w) => w.id == 'wallet-a').balance,
          100 - 12.5);
      expect(walletRepo.items.firstWhere((w) => w.id == 'wallet-b').balance,
          500 + 999.99);
    });

    test('rejects a PDF this app did not export', () async {
      // A well-formed but unrelated PDF (no ROW| data lines at all): reuse
      // buildPdfBytes with no transactions, which still emits the header
      // table but zero ROW lines - so extraction should find nothing.
      final bytes = await ExportService.buildPdfBytes([]);
      expect(
        () => ImportService.importPdfBytes(bytes,
            txRepo: txRepo,
            walletRepo: walletRepo,
            resolveFallbackWallet: _noFallback),
        throwsA(isA<ImportValidationException>()),
      );
    });

    test('re-importing the same PDF a second time is a no-op', () async {
      final bytes = await ExportService.buildPdfBytes(sampleTransactions());

      await ImportService.importPdfBytes(bytes,
          txRepo: txRepo,
          walletRepo: walletRepo,
          resolveFallbackWallet: _noFallback);
      final balanceA =
          walletRepo.items.firstWhere((w) => w.id == 'wallet-a').balance;
      final txCount = txRepo.items.length;

      final summary2 = await ImportService.importPdfBytes(bytes,
          txRepo: txRepo,
          walletRepo: walletRepo,
          resolveFallbackWallet: _noFallback);

      expect(summary2.imported, 0);
      expect(summary2.skippedDuplicates, 2);
      expect(txRepo.items.length, txCount);
      expect(walletRepo.items.firstWhere((w) => w.id == 'wallet-a').balance,
          balanceA);
    });

    test('asks for a fallback wallet when the PDF references an unknown wallet',
        () async {
      final txs = [
        Transaction(
          id: 'tx-42',
          type: TransactionType.expense,
          amount: 7.25,
          category: 'Transport',
          accountId: 'ghost-wallet',
          date: DateTime.parse('2026-09-03T08:00:00.000'),
        ),
      ];
      final bytes = await ExportService.buildPdfBytes(txs);

      final summary = await ImportService.importPdfBytes(
        bytes,
        txRepo: txRepo,
        walletRepo: walletRepo,
        resolveFallbackWallet: (wallets) async => 'wallet-a',
      );

      expect(summary.imported, 1);
      expect(txRepo.items.single.accountId, 'wallet-a');
      expect(walletRepo.items.firstWhere((w) => w.id == 'wallet-a').balance,
          100 - 7.25);
    });
  });
}
