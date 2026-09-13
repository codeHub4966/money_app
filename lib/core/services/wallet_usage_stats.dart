import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import '../../domain/models/transaction.dart';
import '../../domain/models/wallet.dart';

/// Ranks wallets by how much the user actually relies on them, so an
/// ambiguous receipt clue (a generic card network, a generic e-wallet
/// mention, or no clue at all) can fall back to "whichever wallet of the
/// right kind the user already uses most" instead of guessing blindly or
/// leaving the field empty.
class WalletUsageStats {
  WalletUsageStats._();

  /// Returns the most-used wallet among [wallets] whose [Wallet.type] is in
  /// [allowedTypes], or null when there are no wallets of those types at all.
  ///
  /// "Most used" is defined by past transaction COUNT — never balance.
  /// Primary sort: usage count descending. Tie-breaker: most recently used
  /// (latest transaction date) descending. Still tied (including wallets
  /// with zero transactions): the order [wallets] was given in, so the
  /// result is always deterministic rather than an arbitrary pick.
  static Wallet? findMostUsedWallet({
    required List<Wallet> wallets,
    required List<Transaction> transactions,
    required Set<WalletType> allowedTypes,
  }) {
    final candidates = wallets.where((w) => allowedTypes.contains(w.type)).toList();
    if (candidates.isEmpty) return null;

    final usageCount = <String, int>{};
    final lastUsed = <String, DateTime>{};
    for (final tx in transactions) {
      usageCount[tx.accountId] = (usageCount[tx.accountId] ?? 0) + 1;
      final existing = lastUsed[tx.accountId];
      if (existing == null || tx.date.isAfter(existing)) {
        lastUsed[tx.accountId] = tx.date;
      }
    }

    Wallet? best;
    var bestCount = -1;
    DateTime? bestLastUsed;
    for (final wallet in candidates) {
      final count = usageCount[wallet.id] ?? 0;
      final recency = lastUsed[wallet.id];
      final isBetter = best == null ||
          count > bestCount ||
          (count == bestCount && (recency ?? DateTime(0)).isAfter(bestLastUsed ?? DateTime(0)));
      if (isBetter) {
        best = wallet;
        bestCount = count;
        bestLastUsed = recency;
      }
    }

    if (kDebugMode) {
      final counts = {for (final w in candidates) w.name: usageCount[w.id] ?? 0};
      debugPrint('[WalletUsageStats] allowedTypes=$allowedTypes usageCounts=$counts -> most-used: ${best?.name}');
    }

    return best;
  }
}
