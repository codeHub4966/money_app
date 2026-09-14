import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/local/app_database.dart';
import '../../data/repositories/transaction_repository.dart';
import '../../data/repositories/wallet_repository.dart';
import '../../data/repositories/budget_repository.dart';
import '../../domain/models/transaction.dart' as txmodel;
import '../../domain/models/wallet.dart' as walletmodel;
import '../../domain/models/app_category.dart';
import '../../presentation/providers/insight_notification_provider.dart'
    show clearInsightNotificationState;
import 'import_service.dart' show ImportValidationException;
import 'payment_alias_store.dart';
import 'receipt_file_service.dart';

/// A single restored transaction's fields, parsed and validated out of a
/// backup file's JSON before anything destructive happens.
class _ParsedTransaction {
  final String id;
  final txmodel.TransactionType type;
  final double amount;
  final String category;
  final String accountId;
  final String? note;
  final DateTime date;
  const _ParsedTransaction({
    required this.id,
    required this.type,
    required this.amount,
    required this.category,
    required this.accountId,
    this.note,
    required this.date,
  });
}

class BackupService {
  // v1: wallets/budgets/categories/walletOrder/profile/transactions.
  // v2: adds base64-encoded receipt images (keyed by transaction id) and
  // switches restore to a full replace instead of a merge.
  static const _version = 2;

  // ── EXPORT ────────────────────────────────────────────────────────────────

  /// Builds the full backup JSON payload (pure data — no file writing or
  /// sharing), so the "what goes into a backup" logic is testable without
  /// needing to mock platform file-share plumbing.
  static Future<Map<String, dynamic>> buildBackupPayload({
    required ITransactionRepository txRepo,
    required IWalletRepository walletRepo,
    required IBudgetRepository budgetRepo,
    required Map<String, List<AppCategory>> categories,
    required List<String> walletOrder,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    // Read current data snapshots
    final transactions = await txRepo.watchAll().first;
    final wallets = await walletRepo.watchAll().first;
    final budgets = await budgetRepo.watchAll().first;

    // Profile image: encode as base64 so it's portable
    final imagePath = prefs.getString('profile_image_path');
    String? imageBase64;
    if (imagePath != null) {
      try {
        final imgFile = File(imagePath);
        if (await imgFile.exists()) {
          imageBase64 = base64Encode(await imgFile.readAsBytes());
        }
      } catch (_) {
        // Skip a missing/corrupt profile image; the rest of the backup
        // still proceeds normally.
      }
    }

    // Encode each transaction's receipt image directly into the backup
    // (never the original local absolute path, which wouldn't exist on a
    // restoring device). One missing/corrupt receipt is skipped on its own
    // rather than failing the whole backup.
    final receiptsBase64 = <String, String>{};
    for (final t in transactions) {
      final path = t.receiptImagePath;
      if (path == null) continue;
      try {
        final file = File(path);
        if (await file.exists()) {
          receiptsBase64[t.id] = base64Encode(await file.readAsBytes());
        }
      } catch (_) {
        // Skip this one receipt; the transaction itself still backs up.
      }
    }

    final payload = {
      'version': _version,
      'exportedAt': DateTime.now().toIso8601String(),
      'profileName': prefs.getString('profile_name'),
      'profileImageBase64': imageBase64,
      'walletOrder': walletOrder,
      'categories': {
        'expense': categories['expense']!.map((c) => c.toJson()).toList(),
        'income': categories['income']!.map((c) => c.toJson()).toList(),
      },
      'wallets': wallets
          .map((w) => {
                'id': w.id,
                'name': w.name,
                'type': w.type.name,
                'balance': w.balance,
                'includeInTotal': w.includeInTotal,
              })
          .toList(),
      'budgets': budgets
          .map((b) => {
                'id': b.id,
                'categoryName': b.categoryName,
                'monthlyLimit': b.monthlyLimit,
              })
          .toList(),
      'transactions': transactions
          .map((t) => {
                'id': t.id,
                'type': t.type.name,
                'amount': t.amount,
                'category': t.category,
                'accountId': t.accountId,
                'note': t.note,
                'date': t.date.toIso8601String(),
                'hasReceipt': receiptsBase64.containsKey(t.id),
              })
          .toList(),
      'receipts': receiptsBase64,
    };

    return payload;
  }

  static Future<void> exportBackup({
    required ITransactionRepository txRepo,
    required IWalletRepository walletRepo,
    required IBudgetRepository budgetRepo,
    required Map<String, List<AppCategory>> categories,
    required List<String> walletOrder,
  }) async {
    final payload = await buildBackupPayload(
      txRepo: txRepo,
      walletRepo: walletRepo,
      budgetRepo: budgetRepo,
      categories: categories,
      walletOrder: walletOrder,
    );

    final json = const JsonEncoder.withIndent('  ').convert(payload);
    final dir = await getTemporaryDirectory();
    final date = DateTime.now().toIso8601String().substring(0, 10);
    final file = File('${dir.path}/money_backup_$date.json')
      ..writeAsStringSync(json);

    await Share.shareXFiles(
      [XFile(file.path)],
      subject: 'Money App Backup – $date',
    );
  }

  // ── IMPORT (Full Restore: replaces current data) ────────────────────────

  /// Returns a summary string on success, throws on failure. Nothing is
  /// deleted until the backup has been fully parsed and validated.
  static Future<String> importBackup({required AppDatabase db}) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result == null) throw Exception('No file selected.');
    final path = result.files.single.path;
    if (path == null) throw Exception('No file selected.');

    final content = File(path).readAsStringSync();
    return importBackupContent(content, db: db);
  }

  /// The full validate-then-replace restore logic, given raw backup file
  /// content directly (so it's testable without mocking a file picker).
  static Future<String> importBackupContent(
    String content, {
    required AppDatabase db,
  }) async {
    late final Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('not a JSON object');
      }
      data = decoded;
    } catch (_) {
      throw ImportValidationException(
          'This file is not a valid backup (could not be parsed).');
    }

    final version = data['version'];
    if (version is! int || version < 1) {
      throw ImportValidationException('Unsupported backup format.');
    }
    if (version > _version) {
      throw ImportValidationException(
          'This backup was created by a newer version of the app and cannot be restored.');
    }

    // ── Full structural validation — nothing destructive yet ──────────────
    final walletsRaw = data['wallets'];
    final budgetsRaw = data['budgets'];
    final txRaw = data['transactions'];
    if (walletsRaw is! List || budgetsRaw is! List || txRaw is! List) {
      throw ImportValidationException(
          'This backup file is missing required data and cannot be restored.');
    }

    final walletCompanions = walletsRaw.map(_parseWallet).toList();
    final budgetCompanions = budgetsRaw.map(_parseBudget).toList();
    final parsedTx = txRaw.map(_parseTransaction).toList();

    final receiptsRaw = data['receipts'];
    final receiptsMap =
        receiptsRaw is Map ? receiptsRaw.cast<String, dynamic>() : <String, dynamic>{};

    // Decode each receipt's base64 payload; a corrupt entry is skipped on
    // its own rather than failing the whole restore.
    final decodedReceipts = <String, List<int>>{};
    final txIds = parsedTx.map((t) => t.id).toSet();
    for (final entry in receiptsMap.entries) {
      if (!txIds.contains(entry.key)) continue;
      final value = entry.value;
      if (value is! String) continue;
      try {
        decodedReceipts[entry.key] = base64Decode(value);
      } catch (_) {
        // Skip this one receipt image.
      }
    }

    final docsDir = await getApplicationDocumentsDirectory();
    final stagingDir = Directory(
        '${docsDir.path}/receipts_restore_staging_${DateTime.now().microsecondsSinceEpoch}');
    // tx id -> staged (temporary) file path. Nothing here touches the
    // user's existing data or files yet.
    final stagedPaths = <String, String>{};

    try {
      if (decodedReceipts.isNotEmpty) {
        await stagingDir.create(recursive: true);
        for (final entry in decodedReceipts.entries) {
          try {
            final staged = File('${stagingDir.path}/${entry.key}.jpg');
            await staged.writeAsBytes(entry.value);
            stagedPaths[entry.key] = staged.path;
          } catch (_) {
            // Skip; that one transaction restores without a receipt.
          }
        }
      }

      final finalReceiptsDirPath = '${docsDir.path}/receipts';
      final txCompanions = parsedTx.map((t) {
        final hasStaged = stagedPaths.containsKey(t.id);
        return TransactionsCompanion(
          id: Value(t.id),
          type: Value(t.type.name),
          amount: Value(t.amount),
          category: Value(t.category),
          accountId: Value(t.accountId),
          note: Value(t.note),
          date: Value(t.date),
          receiptImagePath: Value(
              hasStaged ? '$finalReceiptsDirPath/${t.id}.jpg' : null),
        );
      }).toList();

      // Snapshot old receipt paths before the DB is cleared, so they can be
      // cleaned up (only) once the replace has actually succeeded.
      final oldTransactions = await db.select(db.transactions).get();
      final oldReceiptPaths = oldTransactions
          .map((t) => t.receiptImagePath)
          .whereType<String>()
          .toSet();

      // The one all-or-nothing step: clearing + inserting inside a single
      // Drift transaction. If this throws, it rolls back automatically and
      // the user's existing data/files are untouched — only the staging
      // directory (cleaned up in `finally`) was ever written to.
      await db.replaceAllData(
        wallets: walletCompanions,
        budgets: budgetCompanions,
        transactions: txCompanions,
      );

      // DB swap succeeded — move staged receipts into their permanent
      // location, then remove old receipt files no longer referenced.
      final receiptsDir = Directory(finalReceiptsDirPath);
      if (stagedPaths.isNotEmpty && !await receiptsDir.exists()) {
        await receiptsDir.create(recursive: true);
      }
      for (final entry in stagedPaths.entries) {
        try {
          await File(entry.value)
              .copy('$finalReceiptsDirPath/${entry.key}.jpg');
        } catch (_) {}
      }
      final newReceiptPaths = stagedPaths.keys
          .map((id) => '$finalReceiptsDirPath/$id.jpg')
          .toSet();
      for (final oldPath in oldReceiptPaths) {
        if (newReceiptPaths.contains(oldPath)) continue;
        await deleteReceiptFileBestEffort(oldPath);
      }

      // ── Preferences: profile, wallet order, categories ───────────────
      final prefs = await SharedPreferences.getInstance();

      final profileName = data['profileName'];
      if (profileName is String && profileName.isNotEmpty) {
        await prefs.setString('profile_name', profileName);
      } else {
        await prefs.remove('profile_name');
      }

      final oldProfileImagePath = prefs.getString('profile_image_path');
      final imageBase64 = data['profileImageBase64'];
      if (imageBase64 is String) {
        try {
          final bytes = base64Decode(imageBase64);
          final imgFile = File(
              '${docsDir.path}/profile_image_restored_${DateTime.now().microsecondsSinceEpoch}.jpg');
          await imgFile.writeAsBytes(bytes);
          await prefs.setString('profile_image_path', imgFile.path);
          if (oldProfileImagePath != null &&
              oldProfileImagePath != imgFile.path) {
            await deleteReceiptFileBestEffort(oldProfileImagePath);
          }
        } catch (_) {
          await prefs.remove('profile_image_path');
        }
      } else {
        await prefs.remove('profile_image_path');
        if (oldProfileImagePath != null) {
          await deleteReceiptFileBestEffort(oldProfileImagePath);
        }
      }

      final walletOrderRaw = data['walletOrder'];
      final walletOrder = walletOrderRaw is List
          ? walletOrderRaw.whereType<String>().toList()
          : <String>[];
      await prefs.setStringList('wallet_order_v1', walletOrder);

      final catsRaw = data['categories'];
      if (catsRaw is Map) {
        await prefs.setString('app_categories_v1', jsonEncode(catsRaw));
      }

      // A restore can replace/renumber wallet ids and transaction data, so
      // any state keyed to the old dataset must not linger.
      await clearInsightNotificationState();
      await PaymentAliasStore.clearAll();

      return 'Restored: ${walletCompanions.length} wallets, '
          '${budgetCompanions.length} budgets, ${txCompanions.length} transactions.';
    } finally {
      try {
        if (await stagingDir.exists()) {
          await stagingDir.delete(recursive: true);
        }
      } catch (_) {}
    }
  }

  static WalletsCompanion _parseWallet(dynamic raw) {
    if (raw is! Map) {
      throw ImportValidationException(
          'This backup file contains an invalid wallet entry.');
    }
    final id = raw['id'];
    final name = raw['name'];
    final type = raw['type'];
    final balance = raw['balance'];
    final includeInTotal = raw['includeInTotal'];
    if (id is! String ||
        name is! String ||
        type is! String ||
        balance is! num ||
        includeInTotal is! bool) {
      throw ImportValidationException(
          'This backup file contains an invalid wallet entry.');
    }
    late final walletmodel.WalletType walletType;
    try {
      walletType = walletmodel.WalletTypeStorage.fromStorageName(type);
    } catch (_) {
      throw ImportValidationException(
          'This backup file contains an invalid wallet entry.');
    }
    return WalletsCompanion(
      id: Value(id),
      name: Value(name),
      type: Value(walletType.name),
      balance: Value(balance.toDouble()),
      includeInTotal: Value(includeInTotal),
    );
  }

  static BudgetsCompanion _parseBudget(dynamic raw) {
    if (raw is! Map) {
      throw ImportValidationException(
          'This backup file contains an invalid budget entry.');
    }
    final id = raw['id'];
    final categoryName = raw['categoryName'];
    final monthlyLimit = raw['monthlyLimit'];
    if (id is! String || categoryName is! String || monthlyLimit is! num) {
      throw ImportValidationException(
          'This backup file contains an invalid budget entry.');
    }
    return BudgetsCompanion(
      id: Value(id),
      categoryName: Value(categoryName),
      monthlyLimit: Value(monthlyLimit.toDouble()),
    );
  }

  static _ParsedTransaction _parseTransaction(dynamic raw) {
    if (raw is! Map) {
      throw ImportValidationException(
          'This backup file contains an invalid transaction entry.');
    }
    final id = raw['id'];
    final type = raw['type'];
    final amount = raw['amount'];
    final category = raw['category'];
    final accountId = raw['accountId'];
    final dateRaw = raw['date'];
    if (id is! String ||
        type is! String ||
        amount is! num ||
        category is! String ||
        accountId is! String ||
        dateRaw is! String) {
      throw ImportValidationException(
          'This backup file contains an invalid transaction entry.');
    }
    late final DateTime date;
    try {
      date = DateTime.parse(dateRaw);
    } catch (_) {
      throw ImportValidationException(
          'This backup file contains an invalid transaction entry.');
    }
    late final txmodel.TransactionType txType;
    try {
      txType = txmodel.TransactionType.values.byName(type);
    } catch (_) {
      throw ImportValidationException(
          'This backup file contains an invalid transaction entry.');
    }
    return _ParsedTransaction(
      id: id,
      type: txType,
      amount: amount.toDouble(),
      category: category,
      accountId: accountId,
      note: raw['note'] is String ? raw['note'] as String : null,
      date: date,
    );
  }
}
