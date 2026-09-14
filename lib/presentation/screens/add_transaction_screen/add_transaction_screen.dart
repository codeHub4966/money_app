import 'dart:io';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/repositories/transaction_wallet_service.dart';
import '../../../domain/models/transaction.dart';
import '../../../domain/models/wallet.dart';
import '../../../domain/models/app_category.dart';
import '../../../core/services/receipt_file_service.dart';
import '../../../core/services/receipt_scanner_service.dart';
import '../../../core/services/receipt_enrichment_service.dart';
import '../../../core/services/receipt_wallet_matcher.dart';
import '../../../core/services/merchant_category_history.dart';
import '../../../core/services/payment_alias_store.dart';
import '../../providers/app_providers.dart';

// Fixed colour palette cycled per category index
const _kBgColors = [
  Color(0xFFFFF0E8), Color(0xFFF5F0FF), Color(0xFFEFF4FF), Color(0xFFFFF0F7),
  Color(0xFFEFFFF4), Color(0xFFFFFBEB), Color(0xFFF3F4F6), Color(0xFFECFEFF),
  Color(0xFFFEF9C3), Color(0xFFFFEDED), Color(0xFFE0F2FE), Color(0xFFF0FDF4),
];

/// The signed effect a transaction of [type]/[amount] has on a wallet balance.
double balanceEffect(TransactionType type, double amount) {
  return type == TransactionType.income ? amount : -amount;
}

/// The permanent on-disk path a receipt for [transactionId] is stored at,
/// given the app's documents directory [docsPath].
String receiptPermanentPath(String docsPath, String transactionId) =>
    '$docsPath/receipts/$transactionId.jpg';

/// Whether [candidatePath] already points at [transactionId]'s permanent
/// receipt file (given documents directory [docsPath]) — e.g. when editing a
/// transaction without picking a new photo. When true, there is nothing to
/// copy, and attempting to copy the file onto itself can fail on some
/// platforms, so callers should reuse [candidatePath] directly instead.
bool isAlreadyPermanentReceiptPath(
        String candidatePath, String docsPath, String transactionId) =>
    candidatePath == receiptPermanentPath(docsPath, transactionId);

/// Whether the old receipt file at [oldPath] is no longer referenced by
/// [newPath] and should be cleaned up after a successful save — i.e. the
/// receipt was removed, or replaced by a genuinely different file. `false`
/// when there was no old receipt, or the path is unchanged (including the
/// common edit case where the same permanent path was simply overwritten in
/// place).
bool shouldDeleteOldReceipt(String? oldPath, String? newPath) =>
    oldPath != null && oldPath != newPath;

/// A single wallet balance write to apply.
class WalletBalanceUpdate {
  final String walletId;
  final double balance;
  const WalletBalanceUpdate(this.walletId, this.balance);
}

/// Computes the wallet balance write(s) needed when saving a transaction,
/// reversing [oldTransaction]'s effect (from [oldWallet] if the wallet
/// changed) before applying the new type/amount to [newWallet].
List<WalletBalanceUpdate> computeWalletBalanceUpdates({
  required Transaction? oldTransaction,
  required Wallet? oldWallet,
  required Wallet newWallet,
  required TransactionType newType,
  required double newAmount,
}) {
  if (oldTransaction == null) {
    return [
      WalletBalanceUpdate(
          newWallet.id, newWallet.balance + balanceEffect(newType, newAmount)),
    ];
  }

  if (oldTransaction.accountId == newWallet.id) {
    final newBalance = newWallet.balance -
        balanceEffect(oldTransaction.type, oldTransaction.amount) +
        balanceEffect(newType, newAmount);
    return [WalletBalanceUpdate(newWallet.id, newBalance)];
  }

  final updates = <WalletBalanceUpdate>[];
  if (oldWallet != null) {
    updates.add(WalletBalanceUpdate(oldWallet.id,
        oldWallet.balance - balanceEffect(oldTransaction.type, oldTransaction.amount)));
  }
  updates.add(WalletBalanceUpdate(
      newWallet.id, newWallet.balance + balanceEffect(newType, newAmount)));
  return updates;
}

class AddTransactionScreen extends ConsumerStatefulWidget {
  final Transaction? transaction;

  // Prefill fields for the payment-notification-monitoring flow (see
  // `DetectedPayment.toPrefillMap()` / `/add-transaction`'s route in
  // app_router.dart). Ignored when [transaction] is set (editing an
  // existing transaction always wins). Never auto-saves — the user still
  // has to review and press "Confirm Transaction".
  final double? initialAmount;
  final String? initialNote;
  final String? initialCategory;
  final String? initialAccountId;
  final DateTime? initialDate;

  const AddTransactionScreen({
    super.key,
    this.transaction,
    this.initialAmount,
    this.initialNote,
    this.initialCategory,
    this.initialAccountId,
    this.initialDate,
  });

  @override
  ConsumerState<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends ConsumerState<AddTransactionScreen> {
  late TransactionType _type;
  late String _account;
  late String _category;
  late String _amount;
  late final TextEditingController _noteCtrl;
  late DateTime _date;
  bool _saving = false;
  bool _showNumberPad = false;
  String? _receiptImagePath;
  bool _scanningReceipt = false;
  bool _enhancingWithAi = false;
  bool _rescanningWithAi = false;
  // Non-sensitive payment fingerprint (e.g. card last-4) detected on the
  // currently-attached receipt, if any — used to learn a wallet alias only
  // once the user actually confirms/saves this transaction.
  String? _receiptPaymentFingerprint;
  // Local OCR result for the currently-attached receipt, kept around so the
  // "Rescan with AI" button can send the same OCR text/context to Gemini
  // without re-running the scan-and-auto-fill flow. Null until a fresh scan
  // happens this session (e.g. when editing a transaction whose receipt was
  // attached previously) — "Rescan with AI" lazily OCRs it first in that case.
  ReceiptData? _lastReceiptData;
  FieldConfidence? _lastCategoryConfidence;

  @override
  void initState() {
    super.initState();
    final t = widget.transaction;
    // Prefill mode: seeded from a detected payment notification rather than
    // an existing saved transaction. Distinguished from a plain blank "Add
    // Transaction" open so a missing suggested category is left unselected
    // instead of defaulting to the first category in the list.
    final isPrefill = t == null && widget.initialAmount != null;
    _type = t?.type ?? TransactionType.expense;

    // Default to the transaction's account, or pick the first real wallet
    if (t?.accountId != null) {
      _account = t!.accountId;
    } else if (isPrefill && widget.initialAccountId != null) {
      _account = widget.initialAccountId!;
    } else {
      final wallets = ref.read(walletsProvider).valueOrNull ?? [];
      final orderNotifier = ref.read(walletOrderProvider.notifier);
      final sorted = orderNotifier.sort(wallets, (w) => w.id);
      _account = sorted.isNotEmpty ? sorted.first.id : '';
    }

    _amount = t != null
        ? t.amount.toStringAsFixed(2)
        : (widget.initialAmount?.toStringAsFixed(2) ?? '');
    _noteCtrl = TextEditingController(text: t?.note ?? widget.initialNote ?? '');
    _date = t?.date ?? widget.initialDate ?? DateTime.now();
    _receiptImagePath = t?.receiptImagePath;

    // Set initial category: use transaction's category, else the detected
    // payment's suggested category (possibly unselected), else first in list
    if (t?.category != null) {
      _category = t!.category;
    } else if (isPrefill) {
      _category = widget.initialCategory ?? '';
    } else {
      final key = _type == TransactionType.income ? 'income' : 'expense';
      final cats = ref.read(categoriesProvider)[key] ?? [];
      _category = cats.isNotEmpty ? cats.first.label : '';
    }
  }

  void _onKey(String key) {
    setState(() {
      if (key == 'backspace') {
        if (_amount.isNotEmpty) _amount = _amount.substring(0, _amount.length - 1);
      } else if (key == 'empty') {
        _amount = '';
      } else if (key == '.') {
        if (_amount.isEmpty) {
          _amount = '0.';
        } else {
          final lastNum = _getLastNumber(_amount);
          if (!lastNum.contains('.')) {
            _amount = '$_amount.';
          }
        }
      } else if (key == '+' || key == '-') {
        if (_amount.isEmpty) return;
        final lastChar = _amount[_amount.length - 1];
        if ('+-'.contains(lastChar)) {
          _amount = _amount.substring(0, _amount.length - 1) + key;
        } else {
          _amount = '$_amount$key';
        }
      } else if (key == '=') {
        final result = _evaluateExpression(_amount);
        if (result != null) {
          _amount = result.toString();
        }
      } else {
        _amount = _amount == '0' ? key : '$_amount$key';
      }
    });
  }

  String _getLastNumber(String expr) {
    if (expr.isEmpty) return '';
    int i = expr.length - 1;
    while (i >= 0 && !'+-'.contains(expr[i])) {
      i--;
    }
    return expr.substring(i + 1);
  }

  double? _evaluateExpression(String expr) {
    if (expr.isEmpty) return null;
    try {
      while (expr.isNotEmpty && '+-'.contains(expr[expr.length - 1])) {
        expr = expr.substring(0, expr.length - 1);
      }
      if (expr.isEmpty) return null;

      final tokens = <String>[];
      String currentNum = '';

      for (int i = 0; i < expr.length; i++) {
        final char = expr[i];
        if ('+-'.contains(char)) {
          if (currentNum.isNotEmpty) {
            tokens.add(currentNum);
            currentNum = '';
          }
          tokens.add(char);
        } else {
          currentNum += char;
        }
      }
      if (currentNum.isNotEmpty) tokens.add(currentNum);

      if (tokens.isEmpty) return null;

      final values = <double>[];
      final operators = <String>[];

      for (final token in tokens) {
        if ('+-'.contains(token)) {
          operators.add(token);
        } else {
          final num = double.tryParse(token);
          if (num == null) return null;
          values.add(num);
        }
      }

      if (values.isEmpty) return null;

      int i = 0;
      while (i < operators.length) {
        if (operators[i] == '+') {
          values[i] = values[i] + values[i + 1];
          values.removeAt(i + 1);
          operators.removeAt(i);
        } else if (operators[i] == '-') {
          values[i] = values[i] - values[i + 1];
          values.removeAt(i + 1);
          operators.removeAt(i);
        } else {
          i++;
        }
      }

      final result = values[0];
      return result % 1 == 0 ? result.roundToDouble() : result;
    } catch (e) {
      return null;
    }
  }

  List<AppCategory> _cats(Map<String, List<AppCategory>> all) =>
      all[_type == TransactionType.income ? 'income' : 'expense'] ?? [];

  Future<void> _save() async {
    final amount = double.tryParse(_amount);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a valid amount.')));
      return;
    }

    // Block save if no wallet selected
    final wallets = ref.read(walletsProvider).valueOrNull ?? [];
    final wallet = wallets.where((w) => w.id == _account).firstOrNull;
    if (wallet == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a wallet first.')),
      );
      return;
    }

    setState(() => _saving = true);
    final txService = ref.read(transactionWalletServiceProvider);

    final old = widget.transaction;
    final oldWallet = (old != null && old.accountId != wallet.id)
        ? wallets.where((w) => w.id == old.accountId).firstOrNull
        : null;
    final updates = computeWalletBalanceUpdates(
      oldTransaction: old,
      oldWallet: oldWallet,
      newWallet: wallet,
      newType: _type,
      newAmount: amount,
    );

    final transactionId = widget.transaction?.id ?? DateTime.now().millisecondsSinceEpoch.toString();
    final oldReceiptPath = widget.transaction?.receiptImagePath;
    String? savedReceiptPath;

    // Save receipt image to permanent storage if exists
    if (_receiptImagePath != null) {
      savedReceiptPath = await _saveReceiptImage(_receiptImagePath!, transactionId);
    }

    // Wallet balance update(s) and the transaction row are written together
    // atomically, so a failure partway through never leaves a wallet
    // balance changed without its transaction saved.
    await txService.saveTransaction(
      transaction: Transaction(
        id: transactionId,
        type: _type,
        amount: amount,
        category: _category,
        accountId: _account,
        note: _noteCtrl.text.isEmpty ? null : _noteCtrl.text,
        date: _date,
        receiptImagePath: savedReceiptPath,
      ),
      walletUpdates: updates
          .map((u) => WalletBalanceWrite(u.walletId, u.balance))
          .toList(),
    );

    // Only clean up the old receipt file once the database write has
    // succeeded, and only if it's no longer referenced (e.g. the user
    // removed it) — best-effort, never allowed to affect the saved
    // transaction.
    if (shouldDeleteOldReceipt(oldReceiptPath, savedReceiptPath)) {
      await deleteReceiptFileBestEffort(oldReceiptPath);
    }

    // Learn the payment-fingerprint -> wallet mapping only from this final,
    // user-confirmed save — never from an automatic guess.
    if (_receiptPaymentFingerprint != null) {
      await PaymentAliasStore.learn(_receiptPaymentFingerprint!, wallet.id);
    }

    if (mounted) context.pop();
  }

  Future<String?> _saveReceiptImage(String tempPath, String transactionId) async {
    final dir = await getApplicationDocumentsDirectory();
    final permanentPath = receiptPermanentPath(dir.path, transactionId);

    // Already pointing at this transaction's permanent receipt file (e.g.
    // editing without picking a new photo) — there's nothing to copy, and
    // copying the file onto itself can fail on some platforms. Returning
    // the existing path directly means a failed self-copy can never null
    // out the saved receiptImagePath.
    if (isAlreadyPermanentReceiptPath(tempPath, dir.path, transactionId)) {
      return permanentPath;
    }

    try {
      final receiptsDir = Directory('${dir.path}/receipts');
      if (!await receiptsDir.exists()) {
        await receiptsDir.create(recursive: true);
      }
      await File(tempPath).copy(permanentPath);
      return permanentPath;
    } catch (e) {
      return null;
    }
  }

  /// Asks the user before the receipt image is ever uploaded to the AI
  /// backend. Only shown when the local scan looks suspicious; returns
  /// `true` for "Yes", `false`/`null` for "No" or a dismissed dialog.
  Future<bool?> _confirmUseAiScan() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Use AI to scan?'),
        content: const Text(
          'The receipt scan may be inaccurate. Use AI to check the receipt image and improve the result?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );
  }

  Future<void> _scanReceipt() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Add Receipt',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.onSurface)),
            const SizedBox(height: 20),
            _SourceOption(
              icon: Icons.camera_alt,
              label: 'Take Photo',
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            const SizedBox(height: 12),
            _SourceOption(
              icon: Icons.photo_library,
              label: 'Choose from Gallery',
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (source == null) return;

    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: source, imageQuality: 100);

    if (pickedFile == null) return;

    // Show loading
    setState(() => _scanningReceipt = true);

    try {
      final receiptData = await ReceiptScannerService.scanReceipt(pickedFile.path);

      final key = _type == TransactionType.income ? 'income' : 'expense';
      final categories = ref.read(categoriesProvider)[key] ?? [];
      final existingLabels = categories.map((c) => c.label).toList();

      // Majority-based merchant history: only trusted as HIGH confidence
      // when backed by enough consistent past transactions (see
      // MerchantCategoryHistory) — a single accidental past category never
      // permanently biases future scans for that merchant.
      final transactions = ref.read(transactionsProvider).valueOrNull ?? [];
      final merchantHistory = MerchantCategoryHistory.build(transactions);
      final reliableMerchantCategory = receiptData.merchantName != null
          ? MerchantCategoryHistory.dominantCategory(merchantHistory, receiptData.merchantName!)
          : null;

      final (suggestedCategory, categoryConfidence) = ReceiptScannerService.suggestCategory(
        merchantName: receiptData.merchantName,
        itemDescriptions: receiptData.itemDescriptions,
        rawText: receiptData.rawText,
        existingCategoryLabels: existingLabels,
        reliableMerchantCategory: reliableMerchantCategory,
      );

      final wallets = ref.read(walletsProvider).valueOrNull ?? [];
      final currentWallet = wallets.where((w) => w.id == _account).firstOrNull;

      // Learned card/payment alias (e.g. "VISA ****1234" -> a specific
      // previously-confirmed wallet) takes priority over every rule-based
      // match below, since it's evidence from the user's own confirmed
      // choice rather than a guess.
      final fingerprint = PaymentAliasStore.extractFingerprint(receiptData.rawText);
      Wallet? matchedWallet;
      String? learnedAliasMatch;
      String walletMatchReason = 'none';
      if (fingerprint != null) {
        final learnedWalletId = await PaymentAliasStore.lookup(fingerprint);
        if (learnedWalletId != null) {
          matchedWallet = wallets.where((w) => w.id == learnedWalletId).firstOrNull;
          if (matchedWallet != null) {
            learnedAliasMatch = matchedWallet.name;
            walletMatchReason = 'learned_alias';
          }
        }
      }
      if (matchedWallet == null) {
        final (ruleWallet, reason) = ReceiptWalletMatcher.match(
          rawText: receiptData.rawText,
          wallets: wallets,
          transactions: transactions,
          currentWallet: currentWallet,
        );
        matchedWallet = ruleWallet;
        walletMatchReason = reason;
      }

      if (kDebugMode) {
        debugPrint('========== RECEIPT OCR (local) ==========');
        debugPrint('Raw OCR:\n${receiptData.rawText}');
        debugPrint('Merchant:\n${receiptData.merchantName} (${receiptData.merchantConfidence})');
        debugPrint('Items:\n${receiptData.itemDescriptions.join('\n')}');
        debugPrint('Amount:\n${receiptData.amount} (${receiptData.amountConfidence})');
        debugPrint('Date:\n${receiptData.date} (${receiptData.dateConfidence})');
        debugPrint('Detected payment keyword:\n${receiptData.detectedPaymentKeyword}');
        debugPrint('Payment fingerprint:\n$fingerprint');
        debugPrint('Learned alias match:\n$learnedAliasMatch');
        debugPrint('Current categories:\n${existingLabels.join(', ')}');
        debugPrint('Suggested category:\n$suggestedCategory ($categoryConfidence)');
        debugPrint('Matched wallet:\n${matchedWallet?.name} (reason: $walletMatchReason)');
        debugPrint('==========================================');
      }

      // Auto-fill immediately from the local parser — this never waits on
      // the network, exactly like before Gemini fallback was added. Any
      // Gemini correction is patched in afterward as a second pass.
      setState(() {
        _receiptImagePath = pickedFile.path;
        _receiptPaymentFingerprint = fingerprint;
        _scanningReceipt = false;
        _lastReceiptData = receiptData;
        _lastCategoryConfidence = categoryConfidence;

        if (receiptData.amount != null) {
          _amount = receiptData.amount!.toStringAsFixed(2);
        }
        if (receiptData.date != null) {
          _date = receiptData.date!;
        }
        if (receiptData.suggestedNote != null && receiptData.suggestedNote!.isNotEmpty) {
          _noteCtrl.text = receiptData.suggestedNote!;
        }
        if (suggestedCategory != null) {
          _category = suggestedCategory;
        }
        if (matchedWallet != null) {
          _account = matchedWallet.id;
        }
      });

      if (mounted) {
        final details = <String>[];
        if (receiptData.amount != null) details.add('RM ${receiptData.amount!.toStringAsFixed(2)}');
        if (receiptData.merchantName != null) details.add(receiptData.merchantName!);
        if (suggestedCategory != null) details.add(suggestedCategory);
        if (matchedWallet != null) details.add(matchedWallet.name);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              receiptData.hasData
                  ? 'Receipt scanned: ${details.join(' • ')}'
                  : 'Receipt attached (no data detected)',
            ),
            backgroundColor: receiptData.hasData ? Colors.green : AppTheme.onSurfaceVariant,
          ),
        );
      }

      // Suspicious check: reuses the same confidence/conflict system that
      // already gates every local field (amount ambiguity, low-confidence
      // date/merchant/category, an unresolved payment clue, ...). The image
      // is never sent to Gemini unless the user explicitly agrees below.
      final lowConfidenceFields = ReceiptEnrichmentService.lowConfidenceFieldsFor(
        local: receiptData,
        localCategoryConfidence: categoryConfidence,
        localWallet: matchedWallet,
      );

      if (kDebugMode) {
        debugPrint('[AddTransactionScreen] suspicious fields: $lowConfidenceFields');
      }

      if (lowConfidenceFields.isEmpty || !mounted) return;

      final useAi = await _confirmUseAiScan();
      if (!mounted || useAi != true) return;

      // Guard against a duplicate AI request while one is already in flight.
      if (_enhancingWithAi) return;

      setState(() => _enhancingWithAi = true);
      final enriched = await ReceiptEnrichmentService.enrich(
        local: receiptData,
        localCategory: suggestedCategory,
        localCategoryConfidence: categoryConfidence,
        localWallet: matchedWallet,
        existingCategories: existingLabels,
        existingWallets: wallets,
        imagePath: pickedFile.path,
      );
      if (mounted) setState(() => _enhancingWithAi = false);

      if (kDebugMode) {
        debugPrint('[AddTransactionScreen] final category: ${enriched.category ?? suggestedCategory}');
        debugPrint('[AddTransactionScreen] final wallet: ${(enriched.wallet ?? matchedWallet)?.name} (reason: $walletMatchReason)');
      }

      if (!mounted) return;

      if (!enriched.usedAi) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't reach AI — keeping the scanned details")),
        );
        return;
      }

      if (kDebugMode) {
        debugPrint('========== RECEIPT OCR (Gemini-enhanced) ==========');
        debugPrint('Amount:\n${enriched.amount} (needsVerification: ${enriched.amountNeedsVerification})');
        debugPrint('Date:\n${enriched.date}');
        debugPrint('Merchant:\n${enriched.merchant}');
        debugPrint('Category:\n${enriched.category}');
        debugPrint('Wallet:\n${enriched.wallet?.name}');
        debugPrint('====================================================');
      }

      // AI is a full verification pass here (the user explicitly opted in),
      // so its values are applied even when the local field was previously
      // high-confidence — see ReceiptEnrichmentService._merge.
      setState(() {
        if (enriched.amount != null) _amount = enriched.amount!.toStringAsFixed(2);
        if (enriched.date != null) _date = enriched.date!;
        if (enriched.merchant != null) {
          _noteCtrl.text = receiptData.itemDescriptions.isNotEmpty
              ? '${enriched.merchant} — ${receiptData.itemDescriptions.join(', ')}'
              : enriched.merchant!;
        }
        if (enriched.category != null) _category = enriched.category!;
        if (enriched.wallet != null) _account = enriched.wallet!.id;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enriched.amountNeedsVerification
                ? 'AI-enhanced with Gemini — please verify the total'
                : 'Receipt details enhanced with AI',
          ),
          backgroundColor: enriched.amountNeedsVerification ? Colors.orange : Colors.green,
        ),
      );
    } catch (e) {
      setState(() {
        _scanningReceipt = false;
        _enhancingWithAi = false;
        _receiptImagePath = pickedFile.path; // Still attach the image
        _lastReceiptData = null;
        _lastCategoryConfidence = null;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not scan receipt, but image was attached')),
        );
      }
    }
  }

  /// Explicit, user-initiated full AI verification pass over the already
  /// attached receipt image — separate from the automatic popup-gated flow
  /// in [_scanReceipt] above (left untouched). May be tapped any time after
  /// local OCR has auto-filled the form, and always calls Gemini regardless
  /// of field confidence, since tapping the button is itself the opt-in.
  Future<void> _rescanWithAi() async {
    if (_receiptImagePath == null) return;
    if (_enhancingWithAi || _rescanningWithAi) return;

    setState(() => _rescanningWithAi = true);

    try {
      // When editing a transaction whose receipt wasn't scanned this
      // session, there's no ReceiptData yet — run local OCR once just to
      // get text/context for the AI prompt. This does not re-auto-fill any
      // fields; only the AI result below does.
      var receiptData = _lastReceiptData;
      receiptData ??= await ReceiptScannerService.scanReceipt(_receiptImagePath!);

      final wallets = ref.read(walletsProvider).valueOrNull ?? [];
      final currentWallet = wallets.where((w) => w.id == _account).firstOrNull;
      final key = _type == TransactionType.income ? 'income' : 'expense';
      final categories = ref.read(categoriesProvider)[key] ?? [];
      final existingLabels = categories.map((c) => c.label).toList();

      final enriched = await ReceiptEnrichmentService.enrichForced(
        local: receiptData,
        localCategory: _category,
        localCategoryConfidence: _lastCategoryConfidence ?? FieldConfidence.high,
        localWallet: currentWallet,
        existingCategories: existingLabels,
        existingWallets: wallets,
        imagePath: _receiptImagePath!,
      );

      if (!mounted) return;

      if (!enriched.usedAi) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't reach AI — keeping current details")),
        );
        return;
      }

      final scannedItems = receiptData.itemDescriptions;
      setState(() {
        if (enriched.amount != null) _amount = enriched.amount!.toStringAsFixed(2);
        if (enriched.date != null) _date = enriched.date!;
        if (enriched.merchant != null) {
          _noteCtrl.text = scannedItems.isNotEmpty
              ? '${enriched.merchant} — ${scannedItems.join(', ')}'
              : enriched.merchant!;
        }
        if (enriched.category != null) _category = enriched.category!;
        if (enriched.wallet != null) _account = enriched.wallet!.id;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enriched.amountNeedsVerification
                ? 'AI-enhanced with Gemini — please verify the total'
                : 'Receipt details enhanced with AI',
          ),
          backgroundColor: enriched.amountNeedsVerification ? Colors.orange : Colors.green,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't reach AI — keeping current details")),
        );
      }
    } finally {
      if (mounted) setState(() => _rescanningWithAi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final allCats = ref.watch(categoriesProvider);
    final cats = _cats(allCats);

    // Ensure _category is valid for the current type
    if (cats.isNotEmpty && !cats.any((c) => c.label == _category)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _category = cats.first.label);
      });
    }

    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: SafeArea(
        child: Column(children: [
          _buildHeader(),
          Expanded(child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 120),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _buildTypeToggle(allCats),
              const SizedBox(height: 24),
              _buildAmountInput(),
              const SizedBox(height: 24),
              _buildSectionLabel('ACCOUNT'),
              const SizedBox(height: 12),
              _buildAccountSelector(),
              const SizedBox(height: 24),
              _buildSectionLabel('CATEGORY'),
              const SizedBox(height: 12),
              _buildCategoryGrid(cats),
              const SizedBox(height: 24),
              _buildSectionLabel('DATE'),
              const SizedBox(height: 12),
              _buildDateRow(),
              const SizedBox(height: 24),
              _buildSectionLabel('NOTE'),
              const SizedBox(height: 12),
              _buildNoteField(),
              const SizedBox(height: 16),
              _buildAttachmentRow(),
            ]),
          )),
          if (_showNumberPad)
            GestureDetector(
              onVerticalDragEnd: (d) {
                if (d.primaryVelocity != null && d.primaryVelocity! > 300) {
                  setState(() => _showNumberPad = false);
                }
              },
              child: _NumberPad(amount: _amount, onKey: _onKey, onDone: () {
                setState(() => _showNumberPad = false);
              }),
            )
          else
            _buildConfirmButton(),
        ]),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(children: [
        IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.secondary),
          onPressed: () => context.pop(),
        ),
        const SizedBox(width: 8),
        Text(widget.transaction != null ? 'Edit Transaction' : 'Add Transaction',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppTheme.onSurface)),
        const Spacer(),
        GestureDetector(
          onTap: _save,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(color: AppTheme.primary, borderRadius: BorderRadius.circular(20)),
            child: const Text('Save',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
          ),
        ),
      ]),
    );
  }

  Widget _buildTypeToggle(Map<String, List<AppCategory>> allCats) {
    const types = [TransactionType.expense, TransactionType.income];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
          color: AppTheme.surfaceContainerLow, borderRadius: BorderRadius.circular(50)),
      child: Row(children: types.map((t) {
        final active = _type == t;
        return Expanded(child: GestureDetector(
          onTap: () {
            final key = t == TransactionType.income ? 'income' : 'expense';
            final cats = allCats[key] ?? [];
            setState(() {
              _type = t;
              _category = cats.isNotEmpty ? cats.first.label : '';
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: active ? AppTheme.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(50),
            ),
            child: Text(t.name[0].toUpperCase() + t.name.substring(1),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                  color: active ? Colors.white : AppTheme.onSurfaceVariant)),
          ),
        ));
      }).toList()),
    );
  }

  Widget _buildAmountInput() {
    return GestureDetector(
      onTap: () => setState(() => _showNumberPad = true),
      child: Column(children: [
        Text('ENTER AMOUNT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
            letterSpacing: 2, color: AppTheme.onSurfaceVariant.withValues(alpha: 0.7))),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Text('RM', style: TextStyle(fontSize: 36, fontWeight: FontWeight.w700, color: AppTheme.secondary)),
          const SizedBox(width: 8),
          Text(
            _amount.isEmpty ? '0.00' : _amount,
            style: TextStyle(
              fontSize: 56,
              fontWeight: FontWeight.w800,
              color: _amount.isEmpty ? const Color(0xFFCDD0E0) : AppTheme.primary,
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
        letterSpacing: 1, color: AppTheme.onSurfaceVariant));
  }

  Widget _buildAccountSelector() {
    final rawWallets = ref.watch(walletsProvider).valueOrNull ?? <Wallet>[];
    final orderNotifier = ref.watch(walletOrderProvider.notifier);
    final wallets = orderNotifier.sort(rawWallets, (w) => w.id);

    // Resolve the display name/emoji for the selected account
    final selected = wallets.where((w) => w.id == _account).firstOrNull;
    final label = selected?.name ?? 'Select Account';
    final emoji = _walletEmoji(selected?.type);

    return GestureDetector(
      onTap: () => _showAccountSheet(wallets),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected != null
                ? AppTheme.secondary.withValues(alpha: 0.4)
                : AppTheme.surfaceContainerLow,
            width: selected != null ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8)
          ],
        ),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: selected != null
                  ? AppTheme.secondary.withValues(alpha: 0.1)
                  : AppTheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(emoji, style: const TextStyle(fontSize: 18)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: selected != null ? AppTheme.onSurface : AppTheme.onSurfaceVariant,
              ),
            ),
          ),
          const Icon(Icons.keyboard_arrow_down_rounded,
              color: AppTheme.onSurfaceVariant, size: 22),
        ]),
      ),
    );
  }

  String _walletEmoji(WalletType? type) {
    switch (type) {
      case WalletType.eWallet: return '📱';
      case WalletType.card:    return '💳';
      case WalletType.bank:    return '🏦';
      case WalletType.cash:    return '💵';
      case WalletType.savings: return '🐷';
      case WalletType.others:  return '📂';
      default:              return '👛';
    }
  }

  void _showAccountSheet(List<Wallet> wallets) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _AccountSheet(
        initialSelectedId: _account,
        walletEmoji: _walletEmoji,
        onSelect: (id) => setState(() => _account = id),
      ),
    );
  }

  Widget _buildCategoryGrid(List<AppCategory> cats) {
    const maxVisible = 8; // 2 rows × 4 cols
    final needMore = cats.length > maxVisible;
    // If we need a "More" button, show 7 real cats + 1 More = 8 cells
    final visible = needMore ? cats.take(maxVisible - 1).toList() : cats;
    final itemCount = visible.length + (needMore ? 1 : 0);

    return GridView.builder(
      itemCount: itemCount,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.85,
      ),
      itemBuilder: (_, i) {
        // "More" card
        if (needMore && i == visible.length) {
          return GestureDetector(
            onTap: () => _showMoreSheet(cats, cats.skip(maxVisible - 1).toList()),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03), blurRadius: 8)],
              ),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                      color: AppTheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.more_horiz_rounded,
                      size: 22, color: AppTheme.onSurfaceVariant)),
                const SizedBox(height: 6),
                const Text('More',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                        color: AppTheme.onSurface)),
              ]),
            ),
          );
        }

        final cat = visible[i];
        final selected = _category == cat.label;
        final bg = _kBgColors[i % _kBgColors.length];
        return GestureDetector(
          onTap: () => setState(() => _category = cat.label),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: selected
                  ? Border.all(
                      color: AppTheme.secondary.withValues(alpha: 0.4),
                      width: 1.5)
                  : null,
              boxShadow: [BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03), blurRadius: 8)],
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                      color: bg, borderRadius: BorderRadius.circular(12)),
                  child: Center(
                      child: Text(cat.emoji,
                          style: const TextStyle(fontSize: 20)))),
              const SizedBox(height: 6),
              Text(cat.label,
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: selected ? AppTheme.primary : AppTheme.onSurface),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ]),
          ),
        );
      },
    );
  }

  void _showMoreSheet(List<AppCategory> allCats, List<AppCategory> moreCats) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Center(child: Container(width: 48, height: 5,
                decoration: BoxDecoration(
                    color: AppTheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(3)))),
            const SizedBox(height: 16),
            const Text('More Categories',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700,
                    color: AppTheme.onSurface)),
            const SizedBox(height: 16),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: moreCats.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.85,
              ),
              itemBuilder: (_, i) {
                final cat = moreCats[i];
                final catIndex = allCats.indexOf(cat);
                final selected = _category == cat.label;
                final bg = _kBgColors[catIndex % _kBgColors.length];
                return GestureDetector(
                  onTap: () {
                    setState(() => _category = cat.label);
                    Navigator.pop(ctx);
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: selected
                          ? Border.all(
                              color: AppTheme.secondary.withValues(alpha: 0.4),
                              width: 1.5)
                          : null,
                      boxShadow: [BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 8)],
                    ),
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                              width: 40, height: 40,
                              decoration: BoxDecoration(
                                  color: bg,
                                  borderRadius: BorderRadius.circular(12)),
                              child: Center(
                                  child: Text(cat.emoji,
                                      style:
                                          const TextStyle(fontSize: 20)))),
                          const SizedBox(height: 6),
                          Text(cat.label,
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: selected
                                      ? AppTheme.primary
                                      : AppTheme.onSurface),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ]),
                  ),
                );
              },
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildDateRow() {
    return GestureDetector(
      onTap: () async {
        final picked = await showDatePicker(context: context,
            initialDate: _date, firstDate: DateTime(2020), lastDate: DateTime(2030));
        if (picked != null) setState(() => _date = picked);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
            color: AppTheme.surfaceContainerLow, borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          const Icon(Icons.calendar_today_rounded, size: 20, color: AppTheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Text('Today, ${_date.day} ${_monthName(_date.month)} ${_date.year}',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.onSurface)),
        ]),
      ),
    );
  }

  Widget _buildNoteField() {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8)]),
      child: TextField(
        controller: _noteCtrl,
        maxLines: 3,
        decoration: const InputDecoration(
          hintText: 'Add a description or receipt details...',
          hintStyle: TextStyle(color: Color(0xFFB0B5C8), fontSize: 14),
          border: InputBorder.none,
          contentPadding: EdgeInsets.all(16),
        ),
      ),
    );
  }

  /// Shows the already-attached receipt photo at full size in a dismissible
  /// overlay — tapping the "Receipt Attached" pill opens this instead of
  /// re-triggering the picker; removing/replacing the receipt is still done
  /// via the pill's own close ("x") icon.
  void _viewFullReceiptImage() {
    if (_receiptImagePath == null) return;
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            InteractiveViewer(
              child: Image.file(File(_receiptImagePath!)),
            ),
            IconButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              icon: const Icon(Icons.close, color: Colors.white),
              style: IconButton.styleFrom(backgroundColor: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachmentRow() {
    final hasReceipt = _receiptImagePath != null;
    final isBusy = _scanningReceipt || _enhancingWithAi || _rescanningWithAi;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
        GestureDetector(
          onTap: isBusy ? null : (hasReceipt ? _viewFullReceiptImage : _scanReceipt),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: hasReceipt
                  ? AppTheme.primary.withValues(alpha: 0.1)
                  : AppTheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(20),
              border: hasReceipt
                  ? Border.all(color: AppTheme.primary, width: 1.5)
                  : null,
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (_scanningReceipt)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (hasReceipt)
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.file(
                    File(_receiptImagePath!),
                    width: 22,
                    height: 22,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.receipt_long,
                      size: 20,
                      color: AppTheme.primary,
                    ),
                  ),
                )
              else
                const Icon(
                  Icons.camera_alt_outlined,
                  size: 20,
                  color: AppTheme.onSurfaceVariant,
                ),
              const SizedBox(width: 6),
              Text(
                _scanningReceipt
                    ? 'Scanning...'
                    : (_enhancingWithAi ? 'Verifying...' : (hasReceipt ? 'Receipt Attached' : 'Add Receipt')),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: hasReceipt ? AppTheme.primary : AppTheme.onSurfaceVariant,
                ),
              ),
              if (hasReceipt && !isBusy) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _receiptImagePath = null;
                      _receiptPaymentFingerprint = null;
                      _lastReceiptData = null;
                      _lastCategoryConfidence = null;
                    });
                  },
                  child: Icon(Icons.close, size: 18, color: AppTheme.primary),
                ),
              ],
            ]),
          ),
        ),
        if (hasReceipt) ...[
          const SizedBox(width: 12),
          GestureDetector(
            onTap: isBusy ? null : _rescanWithAi,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.secondary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.secondary, width: 1.5),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (_rescanningWithAi)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.secondary),
                  )
                else
                  const Icon(Icons.auto_awesome, size: 18, color: AppTheme.secondary),
                const SizedBox(width: 6),
                Text(
                  _rescanningWithAi ? 'Scanning...' : 'Rescan with AI',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.secondary,
                  ),
                ),
              ]),
            ),
          ),
        ],
      ],
      ),
    );
  }

  Widget _buildConfirmButton() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
            colors: [AppTheme.surface.withValues(alpha: 0), AppTheme.surface],
            begin: Alignment.topCenter, end: Alignment.bottomCenter),
      ),
      child: GestureDetector(
        onTap: _saving ? null : _save,
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            color: AppTheme.primary,
            borderRadius: BorderRadius.circular(50),
            boxShadow: [BoxShadow(
                color: AppTheme.primary.withValues(alpha: 0.3),
                blurRadius: 20, offset: const Offset(0, 8))],
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.check_circle_outline_rounded, color: Colors.white, size: 22),
            const SizedBox(width: 8),
            Text(_saving ? 'Processing...' : 'Confirm Transaction',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
          ]),
        ),
      ),
    );
  }

  String _monthName(int m) =>
      const ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][m - 1];
}

class _NumberPad extends StatelessWidget {
  final String amount;
  final void Function(String) onKey;
  final VoidCallback onDone;
  const _NumberPad({required this.amount, required this.onKey, required this.onDone});

  @override
  Widget build(BuildContext context) {
    final keys = [
      ['7','8','9','Empty'],
      ['4','5','6','-'],
      ['1','2','3','+'],
      ['.','0','⌫','='],
    ];
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(40)),
        boxShadow: [BoxShadow(color: Color(0x14000000), blurRadius: 40, offset: Offset(0, -10))],
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Center(child: Container(
          width: 48, height: 5,
          decoration: BoxDecoration(
            color: AppTheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(3),
          ),
        )),
        const SizedBox(height: 16),
        ...keys.map((row) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: row.map((k) {
            final isOp = ['Empty','-','+','='].contains(k);
            final isEquals = k == '=';
            return Expanded(child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: GestureDetector(
                onTap: () => onKey(k == '⌫' ? 'backspace' : k == 'Empty' ? 'empty' : k),
                child: Container(
                  height: 50,
                  decoration: BoxDecoration(
                    color: isEquals ? AppTheme.primary : (isOp ? const Color(0xFFE4EBEC) : const Color(0xFFF8F9FB)),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Center(child: k == '⌫'
                    ? Icon(Icons.backspace_outlined, size: 22, color: isEquals ? Colors.white : AppTheme.onSurface)
                    : Text(k, style: TextStyle(fontSize: isOp ? 18 : 22, fontWeight: FontWeight.w600, color: isEquals ? Colors.white : AppTheme.onSurface))),
                ),
              ),
            ));
          }).toList()),
        )),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: onDone,
          child: Container(
            height: 56, width: double.infinity,
            decoration: BoxDecoration(color: AppTheme.primary, borderRadius: BorderRadius.circular(24),
              boxShadow: [BoxShadow(color: AppTheme.primary.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 8))]),
            child: const Center(child: Text('Done', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white))),
          ),
        ),
      ]),
    );
  }
}

class _AccountSheetTile extends StatelessWidget {
  final Wallet wallet;
  final String emoji;
  final bool isSelected;
  final bool isDefault;
  final VoidCallback onTap;
  const _AccountSheetTile({
    super.key,
    required this.wallet,
    required this.emoji,
    required this.isSelected,
    this.isDefault = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.secondary.withValues(alpha: 0.06)
              : AppTheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: isSelected
              ? Border.all(color: AppTheme.secondary, width: 1.5)
              : null,
        ),
        child: Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: isSelected
                  ? AppTheme.secondary.withValues(alpha: 0.12)
                  : Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(child: Text(emoji, style: const TextStyle(fontSize: 20))),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(wallet.name,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: isSelected ? AppTheme.secondary : AppTheme.onSurface)),
              if (isDefault) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.secondary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('Default',
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
                          color: AppTheme.secondary, letterSpacing: 0.5)),
                ),
              ],
            ]),
            Text('RM ${wallet.balance.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 12, color: AppTheme.onSurfaceVariant)),
          ])),
          if (isSelected)
            Container(
              width: 24, height: 24,
              decoration: const BoxDecoration(
                  color: AppTheme.secondary, shape: BoxShape.circle),
              child: const Icon(Icons.check, color: Colors.white, size: 14),
            )
          else
            const Icon(Icons.drag_handle_rounded,
                color: AppTheme.onSurfaceVariant, size: 20),
        ]),
      ),
    );
  }
}

class _SourceOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _SourceOption({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: AppTheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppTheme.primary, size: 24),
          ),
          const SizedBox(width: 16),
          Text(
            label,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppTheme.onSurface,
            ),
          ),
        ]),
      ),
    );
  }
}

// ── Account selection bottom sheet — watches providers directly for live reorder ──

class _AccountSheet extends ConsumerStatefulWidget {
  final String initialSelectedId;
  final String Function(WalletType?) walletEmoji;
  final void Function(String) onSelect;
  const _AccountSheet({
    required this.initialSelectedId,
    required this.walletEmoji,
    required this.onSelect,
  });

  @override
  ConsumerState<_AccountSheet> createState() => _AccountSheetState();
}

class _AccountSheetState extends ConsumerState<_AccountSheet> {
  late String _selectedId;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.initialSelectedId;
  }

  @override
  Widget build(BuildContext context) {
    final rawWallets = ref.watch(walletsProvider).valueOrNull ?? <Wallet>[];
    final orderNotifier = ref.watch(walletOrderProvider.notifier);
    // Use a local mutable list that stays in sync with the provider order
    final wallets = orderNotifier.sort(rawWallets, (w) => w.id);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Center(child: Container(
          width: 48, height: 5,
          decoration: BoxDecoration(
            color: AppTheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(3),
          ),
        )),
        const SizedBox(height: 16),
        const Text('Select Account',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700,
                color: AppTheme.onSurface)),
        const SizedBox(height: 4),
        Text('Long-press to reorder',
            style: TextStyle(fontSize: 12,
                color: AppTheme.onSurfaceVariant.withValues(alpha: 0.7))),
        const SizedBox(height: 16),
        if (wallets.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text('No wallets found. Add one in the Wallet tab.',
                style: TextStyle(color: AppTheme.onSurfaceVariant),
                textAlign: TextAlign.center),
          )
        else
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.5,
            ),
            child: ReorderableListView.builder(
              shrinkWrap: true,
              itemCount: wallets.length,
              onReorder: (oldIndex, newIndex) {
                if (newIndex > oldIndex) newIndex--;
                final reordered = wallets.toList();
                final item = reordered.removeAt(oldIndex);
                reordered.insert(newIndex, item);
                ref.read(walletOrderProvider.notifier)
                    .saveOrder(reordered.map((w) => w.id).toList());
                // setState triggers rebuild which re-reads provider
                setState(() {});
              },
              itemBuilder: (_, i) {
                final w = wallets[i];
                final isSelected = _selectedId == w.id;
                final isDefault = i == 0;
                return _AccountSheetTile(
                  key: ValueKey(w.id),
                  wallet: w,
                  emoji: widget.walletEmoji(w.type),
                  isSelected: isSelected,
                  isDefault: isDefault,
                  onTap: () {
                    _selectedId = w.id;
                    widget.onSelect(w.id);
                    Navigator.pop(context);
                  },
                );
              },
            ),
          ),
      ]),
    );
  }
}
