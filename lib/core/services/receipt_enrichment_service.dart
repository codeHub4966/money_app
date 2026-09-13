import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import '../../domain/models/wallet.dart';
import 'gemini_receipt_client.dart';
import 'receipt_scanner_service.dart';

/// Final, merged receipt fields to auto-fill into the Add Transaction form.
class ReceiptEnrichmentResult {
  final double? amount;
  final DateTime? date;
  final String? merchant;
  final String? category;
  final Wallet? wallet;

  /// True when the local parser and Gemini strongly disagreed on the total
  /// and the value being auto-filled is a best guess — the caller should
  /// nudge the user to double-check it before saving.
  final bool amountNeedsVerification;

  /// True when Gemini was actually called and contributed to the result
  /// (used only for UI messaging, e.g. "Enhanced with AI").
  final bool usedAi;

  const ReceiptEnrichmentResult({
    this.amount,
    this.date,
    this.merchant,
    this.category,
    this.wallet,
    this.amountNeedsVerification = false,
    this.usedAi = false,
  });
}

/// Orchestrates the "local parser first, Gemini as an explicit second pass"
/// flow: [lowConfidenceFieldsFor] decides whether the local result is
/// suspicious enough to even offer the AI check to the user; [enrich] is
/// only meant to be called after the user has explicitly opted in (e.g. by
/// answering "Yes" to the "Use AI to scan?" prompt), at which point Gemini
/// is treated as a full verification pass against the original receipt
/// image — its result may replace a field even if the local parser was
/// confident about it, since a confident local read can still be wrong.
class ReceiptEnrichmentService {
  /// Decides which fields are unreliable enough locally that the Gemini
  /// fallback should be consulted about them. Exposed as its own pure
  /// function (rather than inlined in [enrich]) so the trigger decision can
  /// be unit tested directly against fixture [ReceiptData]/wallet
  /// combinations, without making a real network call.
  static List<String> lowConfidenceFieldsFor({
    required ReceiptData local,
    required FieldConfidence localCategoryConfidence,
    required Wallet? localWallet,
  }) {
    final fields = <String>[];
    if (local.amountConfidence != FieldConfidence.high) fields.add('amount');
    if (local.dateConfidence != FieldConfidence.high) fields.add('date');
    if (local.merchantConfidence != FieldConfidence.high) fields.add('merchant');
    if (localCategoryConfidence != FieldConfidence.high) fields.add('category');

    // Wallet is a special case: only ask Gemini about it when the receipt
    // actually contains a payment clue that the local parser couldn't map
    // to one of the user's existing wallets. An unknown wallet with no
    // clue at all is not a reason to call Gemini.
    final walletUnresolved = local.detectedPaymentKeyword != null && localWallet == null;
    if (walletUnresolved) fields.add('wallet');

    return fields;
  }

  /// Runs the Gemini verification pass. Only meant to be called after the
  /// user has explicitly agreed to it (the "Use AI to scan?" prompt) — at
  /// that point Gemini inspects the original receipt image at [imagePath]
  /// and its result is allowed to replace ANY field, including ones the
  /// local parser was confident about, since a confident local read can
  /// still be the wrong number (e.g. a tax line misread as the total).
  static Future<ReceiptEnrichmentResult> enrich({
    required ReceiptData local,
    required String? localCategory,
    required FieldConfidence localCategoryConfidence,
    required Wallet? localWallet,
    required List<String> existingCategories,
    required List<Wallet> existingWallets,
    required String imagePath,
  }) async {
    final lowConfidenceFields = lowConfidenceFieldsFor(
      local: local,
      localCategoryConfidence: localCategoryConfidence,
      localWallet: localWallet,
    );

    final localResult = ReceiptEnrichmentResult(
      amount: local.amount,
      date: local.date,
      merchant: local.merchantName,
      category: localCategory,
      wallet: localWallet,
    );

    if (lowConfidenceFields.isEmpty) {
      if (kDebugMode) {
        debugPrint('[ReceiptEnrichmentService] Gemini trigger reason: none (all fields reliable)');
      }
      return localResult;
    }

    if (kDebugMode) {
      debugPrint('[ReceiptEnrichmentService] Gemini trigger reason: $lowConfidenceFields');
    }

    final gemini = await GeminiReceiptClient.fetchEnhancement(
      ocrText: local.rawText,
      lowConfidenceFields: lowConfidenceFields,
      existingCategories: existingCategories,
      existingWallets: existingWallets.map((w) => w.name).toList(),
      merchant: local.merchantName,
      itemDescriptions: local.itemDescriptions,
      localAmount: local.amount,
      localDate: local.date?.toIso8601String(),
      localCategory: localCategory,
      localWallet: localWallet?.name,
      imagePath: imagePath,
    );

    // Backend/Gemini failed, timed out, no internet, returned invalid data,
    // or the image upload failed — fall back to the local parser result
    // unchanged. Never crash the scan flow over this.
    if (gemini == null) return localResult;

    return _merge(
      local: local,
      localCategory: localCategory,
      localWallet: localWallet,
      existingCategories: existingCategories,
      existingWallets: existingWallets,
      gemini: gemini,
    );
  }

  /// Explicit, user-initiated full AI verification pass — always calls
  /// Gemini regardless of local field confidence (unlike [enrich], which
  /// only calls Gemini when [lowConfidenceFieldsFor] flags something
  /// suspicious). Backs a manual "Rescan with AI" action the user can
  /// trigger anytime after local OCR has already auto-filled the form.
  static Future<ReceiptEnrichmentResult> enrichForced({
    required ReceiptData local,
    required String? localCategory,
    required FieldConfidence localCategoryConfidence,
    required Wallet? localWallet,
    required List<String> existingCategories,
    required List<Wallet> existingWallets,
    required String imagePath,
  }) async {
    final lowConfidenceFields = lowConfidenceFieldsFor(
      local: local,
      localCategoryConfidence: localCategoryConfidence,
      localWallet: localWallet,
    );

    final localResult = ReceiptEnrichmentResult(
      amount: local.amount,
      date: local.date,
      merchant: local.merchantName,
      category: localCategory,
      wallet: localWallet,
    );

    if (kDebugMode) {
      debugPrint('[ReceiptEnrichmentService] forced rescan — low confidence fields: $lowConfidenceFields');
    }

    final gemini = await GeminiReceiptClient.fetchEnhancement(
      ocrText: local.rawText,
      lowConfidenceFields: lowConfidenceFields,
      existingCategories: existingCategories,
      existingWallets: existingWallets.map((w) => w.name).toList(),
      merchant: local.merchantName,
      itemDescriptions: local.itemDescriptions,
      localAmount: local.amount,
      localDate: local.date?.toIso8601String(),
      localCategory: localCategory,
      localWallet: localWallet?.name,
      imagePath: imagePath,
    );

    // Backend/Gemini failed, timed out, no internet, returned invalid data,
    // or the image upload failed — fall back to the current local result
    // unchanged. Never crash the rescan over this.
    if (gemini == null) return localResult;

    return _merge(
      local: local,
      localCategory: localCategory,
      localWallet: localWallet,
      existingCategories: existingCategories,
      existingWallets: existingWallets,
      gemini: gemini,
    );
  }

  static ReceiptEnrichmentResult _merge({
    required ReceiptData local,
    required String? localCategory,
    required Wallet? localWallet,
    required List<String> existingCategories,
    required List<Wallet> existingWallets,
    required GeminiReceiptResult gemini,
  }) {
    // Full verification pass: the user explicitly asked Gemini to check the
    // whole receipt, so its result may replace a field even if the local
    // parser was confident about it — only a null/empty AI value is skipped
    // in favor of the local value.
    double? amount = local.amount;
    bool amountNeedsVerification = false;
    if (gemini.totalAmount != null) {
      final priorGuess = local.amount;
      if (priorGuess != null && priorGuess != gemini.totalAmount) {
        final threshold = (priorGuess * 0.05).clamp(0.5, double.infinity);
        amountNeedsVerification = (priorGuess - gemini.totalAmount!).abs() > threshold;
      }
      amount = gemini.totalAmount;
    }

    final date = gemini.transactionDate ?? local.date;
    final merchant = gemini.merchant ?? local.merchantName;

    String? category = localCategory;
    if (gemini.suggestedCategory != null) {
      final validated = _matchIgnoreCase(existingCategories, gemini.suggestedCategory!);
      if (validated != null) category = validated;
    }

    Wallet? wallet = localWallet;
    if (gemini.suggestedWallet != null) {
      final validated = _matchWalletIgnoreCase(existingWallets, gemini.suggestedWallet!);
      if (validated != null) wallet = validated;
    }

    return ReceiptEnrichmentResult(
      amount: amount,
      date: date,
      merchant: merchant,
      category: category,
      wallet: wallet,
      amountNeedsVerification: amountNeedsVerification,
      usedAi: true,
    );
  }

  static String? _matchIgnoreCase(List<String> options, String value) {
    for (final option in options) {
      if (option.toLowerCase() == value.toLowerCase()) return option;
    }
    return null;
  }

  static Wallet? _matchWalletIgnoreCase(List<Wallet> wallets, String value) {
    for (final wallet in wallets) {
      if (wallet.name.toLowerCase() == value.toLowerCase()) return wallet;
    }
    return null;
  }
}
