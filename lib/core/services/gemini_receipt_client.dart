import 'dart:convert';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:http/http.dart' as http;
import '../config/receipt_ai_config.dart';

/// Result returned by the backend's Gemini receipt-parsing endpoint.
/// Every field is nullable — Gemini is instructed to return null rather
/// than guess when it isn't confident.
class GeminiReceiptResult {
  final String? merchant;
  final DateTime? transactionDate;
  final double? totalAmount;
  final String? currency;
  final String? suggestedCategory;
  final String? suggestedWallet;

  const GeminiReceiptResult({
    this.merchant,
    this.transactionDate,
    this.totalAmount,
    this.currency,
    this.suggestedCategory,
    this.suggestedWallet,
  });

  factory GeminiReceiptResult.fromJson(Map<String, dynamic> json) {
    return GeminiReceiptResult(
      merchant: _asNonEmptyString(json['merchant']),
      transactionDate: _parseDate(json['transaction_date']),
      totalAmount: _asDouble(json['total_amount']),
      currency: _asNonEmptyString(json['currency']),
      suggestedCategory: _asNonEmptyString(json['suggested_category']),
      suggestedWallet: _asNonEmptyString(json['suggested_wallet']),
    );
  }

  static String? _asNonEmptyString(dynamic v) {
    if (v is! String) return null;
    final trimmed = v.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static double? _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  static DateTime? _parseDate(dynamic v) {
    if (v is! String || v.trim().isEmpty) return null;
    return DateTime.tryParse(v.trim());
  }
}

/// Calls the backend receipt-parsing endpoint, which in turn calls Gemini
/// Flash. The Gemini API key never touches the client — it lives only in
/// the backend's environment.
class GeminiReceiptClient {
  static Future<GeminiReceiptResult?> fetchEnhancement({
    required String ocrText,
    required List<String> lowConfidenceFields,
    required List<String> existingCategories,
    required List<String> existingWallets,
  }) async {
    try {
      final uri = Uri.parse('${ReceiptAiConfig.backendBaseUrl}/api/receipt/parse');
      final response = await http
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'ocrText': ocrText,
              'lowConfidenceFields': lowConfidenceFields,
              'categories': existingCategories,
              'wallets': existingWallets,
            }),
          )
          .timeout(ReceiptAiConfig.timeout);

      if (response.statusCode != 200) {
        if (kDebugMode) {
          debugPrint('[GeminiReceiptClient] backend returned ${response.statusCode}: ${response.body}');
        }
        return null;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;
      return GeminiReceiptResult.fromJson(decoded);
    } catch (e) {
      // Network error, timeout, rate limit, backend down, malformed
      // response — always fall back to the local parser result.
      if (kDebugMode) {
        debugPrint('[GeminiReceiptClient] fallback to local result: $e');
      }
      return null;
    }
  }
}
