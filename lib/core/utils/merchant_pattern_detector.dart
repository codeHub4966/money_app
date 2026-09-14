import 'dart:math';

import '../../domain/models/transaction.dart' as tx;
import 'merchant_identity.dart';

/// Shared merchant-pattern math used by both the Insights tab and the
/// notification detector. Merchant identity comes solely from
/// `merchant_identity.dart` — category is never used to group or identify a
/// merchant pattern.

/// Minimum transactions at the same merchant within the current month before
/// it's called a "repeated spending" pattern.
const int kMinRepeatedMerchantCount = 3;

/// Minimum transactions (spaced ~monthly) before a merchant is called a
/// "recurring payment" pattern.
const int kMinRecurringMerchantCount = 3;

/// Accepted day range between consecutive charges for a "monthly" interval.
const int kRecurringMinIntervalDays = 25;
const int kRecurringMaxIntervalDays = 35;

enum MerchantPatternType { repeated, recurring }

/// A detected repeated or recurring merchant spending pattern.
class MerchantPattern {
  final MerchantPatternType type;
  final String merchant;
  final double amount;
  final int count;
  final DateTime lastDate;
  const MerchantPattern({
    required this.type,
    required this.merchant,
    required this.amount,
    required this.count,
    required this.lastDate,
  });
}

bool _amountsSimilar(double a, double b) {
  final tolerance = max(max(a.abs(), b.abs()) * 0.05, 2.0);
  return (a - b).abs() <= tolerance;
}

Map<String, List<tx.Transaction>> _groupByMerchant(
    List<tx.Transaction> transactions) {
  final groups = <String, List<tx.Transaction>>{};
  for (final t in transactions) {
    final merchant = extractMerchant(t.note);
    if (merchant == null || isGenericMerchant(merchant)) continue;
    groups.putIfAbsent(normalizeMerchant(merchant), () => []).add(t);
  }
  return groups;
}

List<List<tx.Transaction>> _splitIntoMonthlyRuns(
    List<tx.Transaction> merchantTx) {
  final sorted = [...merchantTx]..sort((a, b) => a.date.compareTo(b.date));
  final runs = <List<tx.Transaction>>[];
  var current = <tx.Transaction>[];
  for (final t in sorted) {
    if (current.isEmpty) {
      current = [t];
      continue;
    }
    final last = current.last;
    final gapDays = t.date.difference(last.date).inDays;
    final withinInterval =
        gapDays >= kRecurringMinIntervalDays && gapDays <= kRecurringMaxIntervalDays;
    if (withinInterval && _amountsSimilar(last.amount, t.amount)) {
      current.add(t);
    } else {
      runs.add(current);
      current = [t];
    }
  }
  if (current.isNotEmpty) runs.add(current);
  return runs;
}

/// Detects repeated-this-month and recurring-monthly merchant spending
/// patterns.
///
/// [currentMonthTx] (already `isAnomalyEligibleExpense`-filtered to the
/// current month) is used for the "repeated this month" pattern.
/// [allEligibleTx] (filtered via `isEligibleExpense`, spanning every month)
/// is used for the "recurring monthly payment" pattern, since a recurring
/// charge can only be recognized across several months of history.
List<MerchantPattern> detectMerchantPatterns({
  required List<tx.Transaction> currentMonthTx,
  required List<tx.Transaction> allEligibleTx,
}) {
  final patterns = <MerchantPattern>[];

  for (final entry in _groupByMerchant(currentMonthTx).entries) {
    final txns = entry.value;
    if (txns.length < kMinRepeatedMerchantCount) continue;
    final sorted = [...txns]..sort((a, b) => a.date.compareTo(b.date));
    final display = extractMerchant(sorted.last.note)!;
    patterns.add(MerchantPattern(
      type: MerchantPatternType.repeated,
      merchant: display,
      amount: txns.fold(0.0, (s, t) => s + t.amount),
      count: txns.length,
      lastDate: sorted.last.date,
    ));
  }

  for (final entry in _groupByMerchant(allEligibleTx).entries) {
    final runs = _splitIntoMonthlyRuns(entry.value)
        .where((r) => r.length >= kMinRecurringMerchantCount)
        .toList();
    if (runs.isEmpty) continue;
    runs.sort((a, b) => b.last.date.compareTo(a.last.date));
    final run = runs.first;
    final display = extractMerchant(run.last.note)!;
    patterns.add(MerchantPattern(
      type: MerchantPatternType.recurring,
      merchant: display,
      amount: run.fold(0.0, (s, t) => s + t.amount) / run.length,
      count: run.length,
      lastDate: run.last.date,
    ));
  }

  return patterns;
}
