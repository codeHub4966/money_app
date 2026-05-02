import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/repositories/transaction_repository.dart';
import '../../data/repositories/wallet_repository.dart';
import '../../data/repositories/budget_repository.dart';
import '../../domain/models/transaction.dart';
import '../../domain/models/wallet.dart';
import '../../domain/models/budget.dart';
import '../../domain/models/app_category.dart';

class BackupService {
  static const _version = 1;

  // ── EXPORT ────────────────────────────────────────────────────────────────

  static Future<void> exportBackup({
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
      final imgFile = File(imagePath);
      if (imgFile.existsSync()) {
        imageBase64 = base64Encode(imgFile.readAsBytesSync());
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
      'wallets': wallets.map((w) => {
        'id': w.id,
        'name': w.name,
        'type': w.type.name,
        'balance': w.balance,
        'includeInTotal': w.includeInTotal,
      }).toList(),
      'budgets': budgets.map((b) => {
        'id': b.id,
        'categoryName': b.categoryName,
        'monthlyLimit': b.monthlyLimit,
      }).toList(),
      'transactions': transactions.map((t) => {
        'id': t.id,
        'type': t.type.name,
        'amount': t.amount,
        'category': t.category,
        'accountId': t.accountId,
        'note': t.note,
        'date': t.date.toIso8601String(),
      }).toList(),
    };

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

  // ── IMPORT ────────────────────────────────────────────────────────────────

  /// Returns a summary string on success, throws on failure.
  static Future<String> importBackup({
    required ITransactionRepository txRepo,
    required IWalletRepository walletRepo,
    required IBudgetRepository budgetRepo,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result == null) throw Exception('No file selected.');

    final content = File(result.files.single.path!).readAsStringSync();
    final data = jsonDecode(content) as Map<String, dynamic>;

    final version = data['version'] as int? ?? 0;
    if (version < 1) throw Exception('Unsupported backup format.');

    final prefs = await SharedPreferences.getInstance();

    // ── 1. Profile ──────────────────────────────────────────────────────────
    final profileName = data['profileName'] as String?;
    if (profileName != null) {
      await prefs.setString('profile_name', profileName);
    }

    // Restore profile image from base64
    final imageBase64 = data['profileImageBase64'] as String?;
    if (imageBase64 != null) {
      final dir = await getApplicationDocumentsDirectory();
      final imgFile = File('${dir.path}/profile_image_restored.jpg')
        ..writeAsBytesSync(base64Decode(imageBase64));
      await prefs.setString('profile_image_path', imgFile.path);
    }

    // ── 2. Wallet order ─────────────────────────────────────────────────────
    final walletOrder = (data['walletOrder'] as List?)?.cast<String>();
    if (walletOrder != null) {
      await prefs.setStringList('wallet_order_v1', walletOrder);
    }

    // ── 3. Categories ───────────────────────────────────────────────────────
    final catsRaw = data['categories'] as Map<String, dynamic>?;
    if (catsRaw != null) {
      await prefs.setString('app_categories_v1', jsonEncode(catsRaw));
    }

    // ── 4. Wallets ──────────────────────────────────────────────────────────
    int walletCount = 0;
    final walletsRaw = data['wallets'] as List?;
    if (walletsRaw != null) {
      for (final w in walletsRaw) {
        await walletRepo.add(Wallet(
          id: w['id'] as String,
          name: w['name'] as String,
          type: WalletType.values.byName(w['type'] as String),
          balance: (w['balance'] as num).toDouble(),
          includeInTotal: w['includeInTotal'] as bool,
        ));
        walletCount++;
      }
    }

    // ── 5. Budgets ──────────────────────────────────────────────────────────
    int budgetCount = 0;
    final budgetsRaw = data['budgets'] as List?;
    if (budgetsRaw != null) {
      for (final b in budgetsRaw) {
        await budgetRepo.add(Budget(
          id: b['id'] as String,
          categoryName: b['categoryName'] as String,
          monthlyLimit: (b['monthlyLimit'] as num).toDouble(),
          spent: 0,
        ));
        budgetCount++;
      }
    }

    // ── 6. Transactions ─────────────────────────────────────────────────────
    int txCount = 0;
    final txRaw = data['transactions'] as List?;
    if (txRaw != null) {
      for (final t in txRaw) {
        await txRepo.add(Transaction(
          id: t['id'] as String,
          type: TransactionType.values.byName(t['type'] as String),
          amount: (t['amount'] as num).toDouble(),
          category: t['category'] as String,
          accountId: t['accountId'] as String,
          note: t['note'] as String?,
          date: DateTime.parse(t['date'] as String),
        ));
        txCount++;
      }
    }

    return 'Restored: $walletCount wallets, $budgetCount budgets, $txCount transactions.';
  }
}
