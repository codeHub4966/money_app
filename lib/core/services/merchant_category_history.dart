import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import '../../domain/models/transaction.dart';
import '../utils/merchant_identity.dart' as merchant_identity;

/// Per-merchant category counts accumulated from confirmed transactions.
class MerchantCategoryStats {
  final Map<String, int> categoryCounts;
  const MerchantCategoryStats(this.categoryCounts);

  int get total => categoryCounts.values.fold(0, (a, b) => a + b);
}

/// Learns merchant -> category associations from the user's own confirmed
/// transaction history, using majority/dominance across ALL matching past
/// transactions instead of "whichever category the most recent matching
/// transaction happened to use". A single accidental past category should
/// not permanently bias future scans for that merchant.
class MerchantCategoryHistory {
  MerchantCategoryHistory._();

  /// A merchant needs at least this many confirmed past transactions before
  /// its history is trusted at all.
  static const int minimumSamples = 2;

  /// Of those, the dominant category must account for at least this share —
  /// otherwise the merchant's spending is genuinely mixed and history should
  /// not override normal category scoring.
  static const double minimumDominanceRatio = 0.70;

  /// Lowercases, trims, and collapses repeated whitespace so trivially
  /// different renderings of the same merchant name ("Tealive", " tealive ",
  /// "Tealive  SS15") group together. Punctuation is left largely intact —
  /// only whitespace is normalized — to avoid merging genuinely different
  /// merchant names that happen to share words.
  static String normalizeMerchant(String merchant) {
    final normalized = merchant_identity.normalizeMerchant(merchant);
    if (kDebugMode) {
      debugPrint('[MerchantCategoryHistory] normalize "$merchant" -> "$normalized"');
    }
    return normalized;
  }

  /// Aggregates every confirmed transaction's (merchant, category) pair.
  /// The merchant name isn't stored on [Transaction] directly — it's read
  /// back from the leading "Merchant — items..." note format written by the
  /// receipt scanner's `_buildNote`, matching how the app already recovers
  /// merchant identity from past transactions.
  static Map<String, MerchantCategoryStats> build(List<Transaction> transactions) {
    final counts = <String, Map<String, int>>{};
    for (final t in transactions) {
      final merchant = merchant_identity.extractMerchant(t.note);
      if (merchant == null) continue;
      final key = normalizeMerchant(merchant);
      final catCounts = counts.putIfAbsent(key, () => {});
      catCounts[t.category] = (catCounts[t.category] ?? 0) + 1;
    }
    final history = counts.map((k, v) => MapEntry(k, MerchantCategoryStats(v)));
    if (kDebugMode) {
      for (final entry in history.entries) {
        debugPrint('[MerchantCategoryHistory] "${entry.key}" counts: ${entry.value.categoryCounts}');
      }
    }
    return history;
  }

  /// Returns the dominant category for [merchant], but only when it's
  /// backed by at least [minimumSamples] confirmed transactions AND that
  /// category accounts for at least [minimumDominanceRatio] of them.
  /// Returns null otherwise — the caller should fall back to normal
  /// category scoring (or Gemini) rather than trust a thin/mixed history.
  static String? dominantCategory(Map<String, MerchantCategoryStats> history, String merchant) {
    final stats = history[normalizeMerchant(merchant)];
    if (stats == null) return null;

    final total = stats.total;
    if (total < minimumSamples) {
      if (kDebugMode) {
        debugPrint('[MerchantCategoryHistory] "$merchant": only $total sample(s), '
            'need >= $minimumSamples — not trusted');
      }
      return null;
    }

    final sorted = stats.categoryCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final top = sorted.first;
    final ratio = top.value / total;

    if (kDebugMode) {
      debugPrint('[MerchantCategoryHistory] "$merchant": dominant "${top.key}" '
          '${top.value}/$total (${(ratio * 100).toStringAsFixed(0)}%)');
    }

    if (ratio >= minimumDominanceRatio) return top.key;
    return null;
  }
}
