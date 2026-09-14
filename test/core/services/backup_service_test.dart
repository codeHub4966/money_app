import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:money_app_flutter/core/services/backup_service.dart';
import 'package:money_app_flutter/core/services/import_service.dart'
    show ImportValidationException;
import 'package:money_app_flutter/data/local/app_database.dart'
    hide Transaction, Wallet, Budget;
import 'package:money_app_flutter/data/repositories/budget_repository.dart';
import 'package:money_app_flutter/data/repositories/transaction_repository.dart';
import 'package:money_app_flutter/data/repositories/wallet_repository.dart';
import 'package:money_app_flutter/domain/models/budget.dart';
import 'package:money_app_flutter/domain/models/transaction.dart';
import 'package:money_app_flutter/domain/models/wallet.dart';

class _FakePathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String docsPath;
  _FakePathProviderPlatform(this.docsPath);

  @override
  Future<String?> getApplicationDocumentsPath() async => docsPath;

  @override
  Future<String?> getTemporaryPath() async => docsPath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late AppDatabase db;
  late LocalWalletRepository walletRepo;
  late LocalBudgetRepository budgetRepo;
  late LocalTransactionRepository txRepo;

  const notificationsChannel =
      MethodChannel('dexterous.com/flutter/local_notifications');

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('backup_service_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    walletRepo = LocalWalletRepository(db);
    budgetRepo = LocalBudgetRepository(db);
    txRepo = LocalTransactionRepository(db);

    // A successful restore clears stale Smart Insight notifications, which
    // goes through the real flutter_local_notifications plugin channel —
    // stub it out so these tests don't need a real platform.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notificationsChannel, (call) async => null);
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notificationsChannel, null);
    await db.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('buildBackupPayload (requirement 8A: receipts in the backup)', () {
    test('encodes a transaction\'s receipt image as base64, keyed by id',
        () async {
      final receiptFile = File('${tempDir.path}/receipt_src.jpg');
      await receiptFile.writeAsBytes([1, 2, 3, 4, 5]);

      await walletRepo.add(const Wallet(
          id: 'w1', name: 'Cash', type: WalletType.cash, balance: 100, includeInTotal: true));
      await txRepo.add(Transaction(
        id: 't1',
        type: TransactionType.expense,
        amount: 20,
        category: 'Food',
        accountId: 'w1',
        date: DateTime(2026, 1, 1),
        receiptImagePath: receiptFile.path,
      ));

      final payload = await BackupService.buildBackupPayload(
        txRepo: txRepo,
        walletRepo: walletRepo,
        budgetRepo: budgetRepo,
        categories: const {'expense': [], 'income': []},
        walletOrder: const ['w1'],
      );

      final receipts = payload['receipts'] as Map<String, dynamic>;
      expect(receipts['t1'], base64Encode([1, 2, 3, 4, 5]));

      final txs = payload['transactions'] as List;
      final t1 = txs.single as Map;
      expect(t1['hasReceipt'], isTrue);
      // The original local absolute path must never be stored.
      expect(t1.containsKey('receiptImagePath'), isFalse);
    });

    test('a transaction with no receipt backs up normally', () async {
      await walletRepo.add(const Wallet(
          id: 'w1', name: 'Cash', type: WalletType.cash, balance: 100, includeInTotal: true));
      await txRepo.add(Transaction(
        id: 't1',
        type: TransactionType.expense,
        amount: 20,
        category: 'Food',
        accountId: 'w1',
        date: DateTime(2026, 1, 1),
      ));

      final payload = await BackupService.buildBackupPayload(
        txRepo: txRepo,
        walletRepo: walletRepo,
        budgetRepo: budgetRepo,
        categories: const {'expense': [], 'income': []},
        walletOrder: const [],
      );

      final txs = payload['transactions'] as List;
      expect((txs.single as Map)['hasReceipt'], isFalse);
      expect((payload['receipts'] as Map), isEmpty);
    });

    test('a missing receipt file on disk is skipped, not a backup failure',
        () async {
      await walletRepo.add(const Wallet(
          id: 'w1', name: 'Cash', type: WalletType.cash, balance: 100, includeInTotal: true));
      await txRepo.add(Transaction(
        id: 't1',
        type: TransactionType.expense,
        amount: 20,
        category: 'Food',
        accountId: 'w1',
        date: DateTime(2026, 1, 1),
        receiptImagePath: '${tempDir.path}/does_not_exist.jpg',
      ));

      final payload = await BackupService.buildBackupPayload(
        txRepo: txRepo,
        walletRepo: walletRepo,
        budgetRepo: budgetRepo,
        categories: const {'expense': [], 'income': []},
        walletOrder: const [],
      );

      expect((payload['receipts'] as Map), isEmpty);
      expect((payload['transactions'] as List).single, isA<Map>());
    });
  });

  group('importBackupContent (requirement 8B/8C: full replace restore)', () {
    String backupJson({
      required List<Map<String, dynamic>> wallets,
      required List<Map<String, dynamic>> budgets,
      required List<Map<String, dynamic>> transactions,
      Map<String, String> receipts = const {},
      int version = 2,
    }) =>
        jsonEncode({
          'version': version,
          'profileName': 'Restored User',
          'profileImageBase64': null,
          'walletOrder': wallets.map((w) => w['id']).toList(),
          'categories': {'expense': [], 'income': []},
          'wallets': wallets,
          'budgets': budgets,
          'transactions': transactions,
          'receipts': receipts,
        });

    test('recreates receipt files and points receiptImagePath at the new local file',
        () async {
      final receiptBytes = [9, 8, 7, 6, 5];
      final content = backupJson(
        wallets: [
          {'id': 'w1', 'name': 'Cash', 'type': 'cash', 'balance': 50.0, 'includeInTotal': true},
        ],
        budgets: const [],
        transactions: [
          {
            'id': 't1',
            'type': 'expense',
            'amount': 12.5,
            'category': 'Food',
            'accountId': 'w1',
            'note': null,
            'date': '2026-01-01T10:00:00.000',
          },
        ],
        receipts: {'t1': base64Encode(receiptBytes)},
      );

      await BackupService.importBackupContent(content, db: db);

      final restoredTx = await txRepo.watchAll().first;
      expect(restoredTx, hasLength(1));
      final path = restoredTx.single.receiptImagePath;
      expect(path, isNotNull);
      expect(path, isNot(contains('receipts_restore_staging')));
      final restoredFile = File(path!);
      expect(await restoredFile.exists(), isTrue);
      expect(await restoredFile.readAsBytes(), receiptBytes);
    });

    test('replaces rather than merges existing data', () async {
      // Pre-existing data that must be gone after restore.
      await walletRepo.add(const Wallet(
          id: 'old-wallet', name: 'Old', type: WalletType.cash, balance: 999, includeInTotal: true));
      await txRepo.add(Transaction(
        id: 'old-tx',
        type: TransactionType.expense,
        amount: 5,
        category: 'Old',
        accountId: 'old-wallet',
        date: DateTime(2020, 1, 1),
      ));
      await budgetRepo.add(const Budget(id: 'old-budget', categoryName: 'Old', monthlyLimit: 10, spent: 0));

      final content = backupJson(
        wallets: [
          {'id': 'new-wallet', 'name': 'New', 'type': 'bank', 'balance': 200.0, 'includeInTotal': true},
        ],
        budgets: [
          {'id': 'new-budget', 'categoryName': 'Food', 'monthlyLimit': 300.0},
        ],
        transactions: [
          {
            'id': 'new-tx',
            'type': 'income',
            'amount': 100.0,
            'category': 'Salary',
            'accountId': 'new-wallet',
            'note': null,
            'date': '2026-02-01T00:00:00.000',
          },
        ],
      );

      await BackupService.importBackupContent(content, db: db);

      final wallets = await walletRepo.watchAll().first;
      final budgets = await budgetRepo.watchAll().first;
      final txs = await txRepo.watchAll().first;

      expect(wallets.map((w) => w.id), ['new-wallet']);
      expect(budgets.map((b) => b.id), ['new-budget']);
      expect(txs.map((t) => t.id), ['new-tx']);
    });

    test('an invalid backup throws and does not erase current data', () async {
      await walletRepo.add(const Wallet(
          id: 'keep-me', name: 'Cash', type: WalletType.cash, balance: 42, includeInTotal: true));

      final badContent = jsonEncode({'version': 2, 'wallets': 'not-a-list'});

      await expectLater(
        () => BackupService.importBackupContent(badContent, db: db),
        throwsA(isA<ImportValidationException>()),
      );

      final wallets = await walletRepo.watchAll().first;
      expect(wallets.map((w) => w.id), ['keep-me']);
    });

    test('unparsable JSON throws and does not erase current data', () async {
      await walletRepo.add(const Wallet(
          id: 'keep-me', name: 'Cash', type: WalletType.cash, balance: 42, includeInTotal: true));

      await expectLater(
        () => BackupService.importBackupContent('{not valid json', db: db),
        throwsA(isA<ImportValidationException>()),
      );

      final wallets = await walletRepo.watchAll().first;
      expect(wallets, hasLength(1));
    });

    test('a future/corrupt version is rejected with a clear error', () async {
      final content = backupJson(wallets: const [], budgets: const [], transactions: const [])
          .replaceFirst('"version":2', '"version":99');

      await expectLater(
        () => BackupService.importBackupContent(content, db: db),
        throwsA(isA<ImportValidationException>()),
      );
    });

    test('a failed restore (DB error partway through) cleans up newly-staged receipt files and leaves existing data untouched',
        () async {
      final oldReceipt = File('${tempDir.path}/receipts/old-tx.jpg');
      await oldReceipt.create(recursive: true);
      await oldReceipt.writeAsBytes([1, 1, 1]);
      await walletRepo.add(const Wallet(
          id: 'old-wallet', name: 'Old', type: WalletType.cash, balance: 10, includeInTotal: true));
      await txRepo.add(Transaction(
        id: 'old-tx',
        type: TransactionType.expense,
        amount: 5,
        category: 'Old',
        accountId: 'old-wallet',
        date: DateTime(2020, 1, 1),
        receiptImagePath: oldReceipt.path,
      ));

      // Force the DB clear+insert transaction to fail partway through.
      await db.customStatement('DROP TABLE budgets');

      final content = backupJson(
        wallets: [
          {'id': 'new-wallet', 'name': 'New', 'type': 'bank', 'balance': 1.0, 'includeInTotal': true},
        ],
        budgets: const [],
        transactions: [
          {
            'id': 'new-tx',
            'type': 'expense',
            'amount': 1.0,
            'category': 'Food',
            'accountId': 'new-wallet',
            'note': null,
            'date': '2026-01-01T00:00:00.000',
          },
        ],
        receipts: {'new-tx': base64Encode([2, 2, 2])},
      );

      await expectLater(
        () => BackupService.importBackupContent(content, db: db),
        throwsA(anything),
      );

      // Original data (DB rolled back automatically) survives.
      final wallets = await walletRepo.watchAll().first;
      expect(wallets.map((w) => w.id), ['old-wallet']);
      expect(await oldReceipt.exists(), isTrue,
          reason: 'the pre-existing receipt must never be touched before the DB swap succeeds');

      // No leftover staging directory from the failed attempt.
      final leftovers = tempDir
          .listSync()
          .whereType<Directory>()
          .where((d) => d.path.contains('receipts_restore_staging'));
      expect(leftovers, isEmpty);
    });

    test('an old v1 backup (no receipts field) restores its data with no receipts',
        () async {
      final content = jsonEncode({
        'version': 1,
        'profileName': 'Legacy User',
        'profileImageBase64': null,
        'walletOrder': ['w1'],
        'categories': {'expense': [], 'income': []},
        'wallets': [
          {'id': 'w1', 'name': 'Cash', 'type': 'cash', 'balance': 75.0, 'includeInTotal': true},
        ],
        'budgets': [],
        'transactions': [
          {
            'id': 't1',
            'type': 'expense',
            'amount': 30.0,
            'category': 'Food',
            'accountId': 'w1',
            'note': null,
            'date': '2025-01-01T00:00:00.000',
          },
        ],
        // No 'receipts' key at all — matches a real pre-v2 export.
      });

      final summary = await BackupService.importBackupContent(content, db: db);

      final txs = await txRepo.watchAll().first;
      expect(txs, hasLength(1));
      expect(txs.single.receiptImagePath, isNull);
      expect(summary, contains('1 wallets'));
    });
  });
}
