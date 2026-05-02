import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/local/app_database.dart';
import '../../data/repositories/transaction_repository.dart';
import '../../data/repositories/wallet_repository.dart';
import '../../data/repositories/budget_repository.dart';
import '../../domain/models/transaction.dart' as tx;
import '../../domain/models/wallet.dart' as wl;
import '../../domain/models/budget.dart' as bg;
import '../../domain/models/app_category.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final transactionRepositoryProvider = Provider<ITransactionRepository>((ref) {
  return LocalTransactionRepository(ref.watch(appDatabaseProvider));
});

final walletRepositoryProvider = Provider<IWalletRepository>((ref) {
  return LocalWalletRepository(ref.watch(appDatabaseProvider));
});

final budgetRepositoryProvider = Provider<IBudgetRepository>((ref) {
  return LocalBudgetRepository(ref.watch(appDatabaseProvider));
});

final transactionsProvider = StreamProvider<List<tx.Transaction>>((ref) {
  return ref.watch(transactionRepositoryProvider).watchAll();
});

final walletsProvider = StreamProvider<List<wl.Wallet>>((ref) {
  return ref.watch(walletRepositoryProvider).watchAll();
});

final budgetsProvider = StreamProvider<List<bg.Budget>>((ref) {
  final transactions = ref.watch(transactionsProvider).valueOrNull ?? [];
  return ref.watch(budgetRepositoryProvider).watchAll().map((budgets) {
    final now = DateTime.now();
    return budgets.map((b) {
      final spent = transactions
          .where((t) =>
              t.type == tx.TransactionType.expense &&
              t.category.toLowerCase() == b.categoryName.toLowerCase() &&
              t.date.year == now.year &&
              t.date.month == now.month)
          .fold(0.0, (s, t) => s + t.amount);
      return bg.Budget(id: b.id, categoryName: b.categoryName, monthlyLimit: b.monthlyLimit, spent: spent);
    }).toList();
  });
});

// ── Category Management ──────────────────────────────────────────────────────

class CategoryNotifier extends StateNotifier<Map<String, List<AppCategory>>> {
  static const _prefsKey = 'app_categories_v1';

  static const _defaultExpense = [
    AppCategory(id: 'food',       label: 'Food',       emoji: '🍲'),
    AppCategory(id: 'goods',      label: 'Goods',      emoji: '🧻'),
    AppCategory(id: 'snacks',     label: 'Snacks',     emoji: '🍩'),
    AppCategory(id: 'fruit',      label: 'Fruit',      emoji: '🍉'),
    AppCategory(id: 'vegetables', label: 'Vegetab.',   emoji: '🥬'),
    AppCategory(id: 'games',      label: 'Games',      emoji: '🎮'),
    AppCategory(id: 'clothing',   label: 'Clothing',   emoji: '👕'),
    AppCategory(id: 'shopping',   label: 'Shopping',   emoji: '🛍️'),
    AppCategory(id: 'transport',  label: 'Transport',  emoji: '🚗'),
    AppCategory(id: 'movies',     label: 'Movies',     emoji: '🎬'),
    AppCategory(id: 'health',     label: 'Health',     emoji: '💊'),
    AppCategory(id: 'fitness',    label: 'Fitness',    emoji: '💪'),
    AppCategory(id: 'gifts',      label: 'Gifts',      emoji: '🎁'),
    AppCategory(id: 'study',      label: 'Study',      emoji: '📚'),
    AppCategory(id: 'travel',     label: 'Travel',     emoji: '✈️'),
    AppCategory(id: 'pets',       label: 'Pets',       emoji: '🐾'),
  ];

  static const _defaultIncome = [
    AppCategory(id: 'salary',     label: 'Salary',     emoji: '💰'),
    AppCategory(id: 'bonus',      label: 'Bonus',      emoji: '🏅'),
    AppCategory(id: 'investment', label: 'Investment', emoji: '📈'),
    AppCategory(id: 'gift',       label: 'Gift',       emoji: '🎁'),
    AppCategory(id: 'freelance',  label: 'Freelance',  emoji: '💻'),
    AppCategory(id: 'rental',     label: 'Rental',     emoji: '🏠'),
    AppCategory(id: 'dividend',   label: 'Dividend',   emoji: '📊'),
    AppCategory(id: 'other',      label: 'Other',      emoji: '📦'),
  ];

  CategoryNotifier()
      : super({'expense': _defaultExpense, 'income': _defaultIncome}) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      state = {
        'expense': (data['expense'] as List)
            .map((e) => AppCategory.fromJson(e as Map<String, dynamic>))
            .toList(),
        'income': (data['income'] as List)
            .map((e) => AppCategory.fromJson(e as Map<String, dynamic>))
            .toList(),
      };
    } catch (_) {}
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode({
      'expense': state['expense']!.map((c) => c.toJson()).toList(),
      'income':  state['income']!.map((c) => c.toJson()).toList(),
    }));
  }

  void add(String type, AppCategory cat) {
    state = {...state, type: [...state[type]!, cat]};
    _persist();
  }

  Future<void> reloadFromPrefs() => _load();

  Future<void> remove(String type, String id, WidgetRef ref) async {
    // Check if category is in use
    final transactions = ref.read(transactionsProvider).valueOrNull ?? [];
    final budgets = ref.read(budgetsProvider).valueOrNull ?? [];

    final isUsedInTransactions = transactions.any((t) => t.category.toLowerCase() == id.toLowerCase());
    final isUsedInBudgets = budgets.any((b) => b.categoryName.toLowerCase() == id.toLowerCase());

    if (isUsedInTransactions || isUsedInBudgets) {
      throw Exception('Cannot delete category: it is currently in use by transactions or budgets');
    }

    state = {...state, type: state[type]!.where((c) => c.id != id).toList()};
    _persist();
  }

  void reorder(String type, int from, int to) {
    final list = [...state[type]!];
    final item = list.removeAt(from);
    list.insert(to, item);
    state = {...state, type: list};
    _persist();
  }
}

final categoriesProvider =
    StateNotifierProvider<CategoryNotifier, Map<String, List<AppCategory>>>(
  (ref) => CategoryNotifier(),
);

// ── Wallet Order ─────────────────────────────────────────────────────────────

class WalletOrderNotifier extends StateNotifier<List<String>> {
  static const _prefsKey = 'wallet_order_v1';

  WalletOrderNotifier() : super([]) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefsKey);
    if (raw != null) state = raw;
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, state);
  }

  /// Returns [wallets] sorted according to the stored order.
  /// Wallets not in the order list appear at the end.
  List<T> sort<T>(List<T> wallets, String Function(T) getId) {
    if (state.isEmpty) return wallets;
    final ordered = <T>[];
    for (final id in state) {
      final match = wallets.where((w) => getId(w) == id).firstOrNull;
      if (match != null) ordered.add(match);
    }
    // Append any wallets not in the saved order
    for (final w in wallets) {
      if (!ordered.contains(w)) ordered.add(w);
    }
    return ordered;
  }

  void saveOrder(List<String> ids) {
    state = ids;
    _persist();
  }

  Future<void> reloadFromPrefs() => _load();
}

final walletOrderProvider =
    StateNotifierProvider<WalletOrderNotifier, List<String>>(
  (ref) => WalletOrderNotifier(),
);
