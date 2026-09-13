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

/// Orchestrates the "local parser, then Gemini fallback if needed" flow:
/// decides whether Gemini should be called, calls the backend, and merges
/// the Gemini result with the local result without ever discarding a
/// high-confidence local field.
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

  static Future<ReceiptEnrichmentResult> enrich({
    required ReceiptData local,
    required String? localCategory,
    required FieldConfidence localCategoryConfidence,
    required Wallet? localWallet,
    required List<String> existingCategories,
    required List<Wallet> existingWallets,
  }) async {
    final lowConfidenceFields = lowConfidenceFieldsFor(
      local: local,
      localCategoryConfidence: localCategoryConfidence,
      localWallet: localWallet,
    );
    final walletUnresolved = local.detectedPaymentKeyword != null && localWallet == null;

    final localResult = ReceiptEnrichmentResult(
      amount: local.amount,
      date: local.date,
      merchant: local.merchantName,
      category: localCategory,
      wallet: localWallet,
    );

    if (lowConfidenceFields.isEmpty) return localResult;

    final gemini = await GeminiReceiptClient.fetchEnhancement(
      ocrText: local.rawText,
      lowConfidenceFields: lowConfidenceFields,
      existingCategories: existingCategories,
      existingWallets: existingWallets.map((w) => w.name).toList(),
    );

    // Backend/Gemini failed, timed out, no internet, or rate-limited —
    // fall back to the local parser result unchanged.
    if (gemini == null) return localResult;

    return _merge(
      local: local,
      localCategory: localCategory,
      localCategoryConfidence: localCategoryConfidence,
      localWallet: localWallet,
      walletUnresolved: walletUnresolved,
      existingCategories: existingCategories,
      existingWallets: existingWallets,
      gemini: gemini,
    );
  }

  static ReceiptEnrichmentResult _merge({
    required ReceiptData local,
    required String? localCategory,
    required FieldConfidence localCategoryConfidence,
    required Wallet? localWallet,
    required bool walletUnresolved,
    required List<String> existingCategories,
    required List<Wallet> existingWallets,
    required GeminiReceiptResult gemini,
  }) {
    // Amount: never override a high-confidence local read. Otherwise prefer
    // Gemini's structured total, but flag it for verification if it
    // strongly disagrees with whatever weak local guess existed.
    double? amount = local.amount;
    bool amountNeedsVerification = false;
    if (local.amountConfidence != FieldConfidence.high && gemini.totalAmount != null) {
      final priorGuess = local.amount;
      if (priorGuess != null) {
        final threshold = (priorGuess * 0.05).clamp(0.5, double.infinity);
        amountNeedsVerification = (priorGuess - gemini.totalAmount!).abs() > threshold;
      }
      amount = gemini.totalAmount;
    }

    DateTime? date = local.date;
    if (local.dateConfidence != FieldConfidence.high && gemini.transactionDate != null) {
      date = gemini.transactionDate;
    }

    String? merchant = local.merchantName;
    if (local.merchantConfidence != FieldConfidence.high && gemini.merchant != null) {
      merchant = gemini.merchant;
    }

    String? category = localCategory;
    if (localCategoryConfidence != FieldConfidence.high && gemini.suggestedCategory != null) {
      final validated = _matchIgnoreCase(existingCategories, gemini.suggestedCategory!);
      if (validated != null) category = validated;
    }

    Wallet? wallet = localWallet;
    if (walletUnresolved && gemini.suggestedWallet != null) {
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
