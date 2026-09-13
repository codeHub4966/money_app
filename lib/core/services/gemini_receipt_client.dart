import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show compute, kDebugMode, debugPrint;
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
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
  /// Best-effort image MIME type from the file extension — the backend only
  /// uses this to tag the image part for Gemini's vision input.
  static String _mimeTypeFor(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.heic')) return 'image/heic';
    return 'image/jpeg';
  }

  // Longest edge the AI upload is downscaled to. The locally saved receipt
  // photo (used for OCR and re-viewing the transaction) is never touched —
  // this only affects the copy sent over the network, and this size is
  // still comfortably enough to keep receipt text legible.
  static const int _maxUploadDimension = 1600;
  static const int _uploadJpegQuality = 82;

  /// Runs off the UI isolate (via [compute]) since decode/resize/encode of a
  /// full-resolution photo can take real time. Returns null when the bytes
  /// aren't a format the `image` package can decode (e.g. HEIC) — the caller
  /// falls back to sending the original bytes unmodified in that case.
  static Uint8List? _compressForUpload(Uint8List original) {
    final decoded = img.decodeImage(original);
    if (decoded == null) return null;

    final needsResize = decoded.width > _maxUploadDimension || decoded.height > _maxUploadDimension;
    final resized = needsResize
        ? img.copyResize(
            decoded,
            width: decoded.width >= decoded.height ? _maxUploadDimension : null,
            height: decoded.height > decoded.width ? _maxUploadDimension : null,
          )
        : decoded;

    return Uint8List.fromList(img.encodeJpg(resized, quality: _uploadJpegQuality));
  }

  static Future<GeminiReceiptResult?> fetchEnhancement({
    required String ocrText,
    required List<String> lowConfidenceFields,
    required List<String> existingCategories,
    required List<String> existingWallets,
    String? merchant,
    List<String> itemDescriptions = const [],
    // Local parser's own best-guess values, sent as extra context so Gemini
    // can weigh them against what it sees in the image rather than starting
    // from scratch.
    double? localAmount,
    String? localDate,
    String? localCategory,
    String? localWallet,
    // Path to the original receipt photo on device — read and base64-encoded
    // here so Gemini can inspect the image itself, not just the OCR text.
    // Only sent when the user has explicitly opted into the AI check.
    String? imagePath,
  }) async {
    try {
      String? imageBase64;
      String? imageMimeType;
      if (imagePath != null) {
        final rawBytes = await File(imagePath).readAsBytes();
        // Downscale/recompress before upload — the original file on disk
        // (used for local OCR and later re-viewing the receipt) is never
        // modified, only this in-memory copy sent to the backend.
        final compressed = await compute(_compressForUpload, rawBytes);
        if (compressed != null) {
          imageBase64 = base64Encode(compressed);
          imageMimeType = 'image/jpeg';
        } else {
          // Format the `image` package couldn't decode (e.g. HEIC) — send
          // the original bytes rather than dropping the image entirely.
          imageBase64 = base64Encode(rawBytes);
          imageMimeType = _mimeTypeFor(imagePath);
        }
      }

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
              'merchant': merchant,
              'items': itemDescriptions,
              'localAmount': localAmount,
              'localDate': localDate,
              'localCategory': localCategory,
              'localWallet': localWallet,
              if (imageBase64 != null) 'imageBase64': imageBase64,
              if (imageMimeType != null) 'imageMimeType': imageMimeType,
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
