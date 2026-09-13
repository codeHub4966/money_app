import 'package:flutter_test/flutter_test.dart';
import 'package:money_app_flutter/core/services/merchant_category_history.dart';
import 'package:money_app_flutter/domain/models/transaction.dart';

Transaction _tx({required String category, required String merchant, List<String> items = const []}) {
  final note = items.isEmpty ? merchant : '$merchant — ${items.join(', ')}';
  return Transaction(
    id: 'id-${DateTime.now().microsecondsSinceEpoch}-${category.hashCode}-${note.hashCode}',
    type: TransactionType.expense,
    amount: 10,
    category: category,
    accountId: 'acc-1',
    note: note,
    date: DateTime(2026, 1, 1),
  );
}

void main() {
  group('MerchantCategoryHistory — majority-based learning', () {
    test('one historical transaction is not enough to be trusted (below minimumSamples)', () {
      final history = MerchantCategoryHistory.build([_tx(category: 'Food', merchant: 'Tealive')]);
      expect(MerchantCategoryHistory.dominantCategory(history, 'Tealive'), isNull);
    });

    test('two or more consistent historical transactions become trusted', () {
      final history = MerchantCategoryHistory.build([
        _tx(category: 'Food', merchant: 'Tealive'),
        _tx(category: 'Food', merchant: 'Tealive'),
      ]);
      expect(MerchantCategoryHistory.dominantCategory(history, 'Tealive'), 'Food');
    });

    test('mixed history uses the majority category', () {
      final history = MerchantCategoryHistory.build([
        _tx(category: 'Food', merchant: 'Tealive'),
        _tx(category: 'Food', merchant: 'Tealive'),
        _tx(category: 'Food', merchant: 'Tealive'),
        _tx(category: 'Food', merchant: 'Tealive'),
        _tx(category: 'Food', merchant: 'Tealive'),
        _tx(category: 'Snacks', merchant: 'Tealive'),
      ]);
      // Matches the spec example: Food=5, Snacks=1 -> learned category "Food".
      expect(MerchantCategoryHistory.dominantCategory(history, 'Tealive'), 'Food');
    });

    test('dominance below 70% is not trusted even with enough samples', () {
      final history = MerchantCategoryHistory.build([
        _tx(category: 'Food', merchant: 'Tealive'),
        _tx(category: 'Food', merchant: 'Tealive'),
        _tx(category: 'Food', merchant: 'Tealive'),
        _tx(category: 'Snacks', merchant: 'Tealive'),
        _tx(category: 'Snacks', merchant: 'Tealive'),
      ]);
      // 3/5 = 60%, below the 70% dominance threshold.
      expect(MerchantCategoryHistory.dominantCategory(history, 'Tealive'), isNull);
    });

    test('a single most-recent minority category does not override an established majority', () {
      // Regression: the old "latest transaction wins" behavior would have
      // returned "Snacks" here, purely because it happened most recently.
      final transactions = [
        _tx(category: 'Food', merchant: 'Tealive'),
        _tx(category: 'Food', merchant: 'Tealive'),
        _tx(category: 'Food', merchant: 'Tealive'),
        _tx(category: 'Food', merchant: 'Tealive'),
        _tx(category: 'Snacks', merchant: 'Tealive'), // most recent, but a minority
      ];
      final history = MerchantCategoryHistory.build(transactions);
      expect(MerchantCategoryHistory.dominantCategory(history, 'Tealive'), 'Food');
    });

    test('normalizes merchant name casing/whitespace before grouping', () {
      final history = MerchantCategoryHistory.build([
        _tx(category: 'Food', merchant: 'Tealive'),
        _tx(category: 'Food', merchant: '  TEALIVE  '),
        _tx(category: 'Food', merchant: 'tealive'),
      ]);
      expect(MerchantCategoryHistory.dominantCategory(history, 'TeaLive'), 'Food');
    });

    test('an unknown merchant with no history returns null', () {
      final history = MerchantCategoryHistory.build([_tx(category: 'Food', merchant: 'Tealive')]);
      expect(MerchantCategoryHistory.dominantCategory(history, 'Some Other Shop'), isNull);
    });

    test('transactions with no note (no recoverable merchant) are ignored', () {
      final noNote = Transaction(
        id: 'x',
        type: TransactionType.expense,
        amount: 5,
        category: 'Food',
        accountId: 'acc-1',
        date: DateTime(2026, 1, 1),
      );
      final history = MerchantCategoryHistory.build([noNote]);
      expect(history, isEmpty);
    });
  });
}
