import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_theme.dart';
import '../../providers/app_providers.dart';
import '../../../domain/models/transaction.dart' as tx;
import '../../../domain/models/wallet.dart' as wl;

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transactions = ref.watch(transactionsProvider).valueOrNull ?? [];
    final wallets = ref.watch(walletsProvider).valueOrNull ?? <wl.Wallet>[];
    final budgets = ref.watch(budgetsProvider).valueOrNull ?? [];
    final allCats = ref.watch(categoriesProvider);

    final now = DateTime.now();
    final monthTx = transactions.where((t) => t.date.year == now.year && t.date.month == now.month);

    // Wallets excluded from total — their transactions don't count toward income/expense
    final excludedWalletIds = wallets.where((w) => !w.includeInTotal).map((w) => w.id).toSet();

    final income = monthTx
        .where((t) => t.type == tx.TransactionType.income && t.category != 'Transfer' && !excludedWalletIds.contains(t.accountId))
        .fold(0.0, (s, t) => s + t.amount);
    final expense = monthTx
        .where((t) => t.type == tx.TransactionType.expense && t.category != 'Transfer' && !excludedWalletIds.contains(t.accountId))
        .fold(0.0, (s, t) => s + t.amount);
    // Total balance = sum of all wallet balances included in total
    final totalBalance = wallets.where((w) => w.includeInTotal).fold(0.0, (s, w) => s + w.balance);
    final totalBudget = budgets.fold(0.0, (s, b) => s + b.monthlyLimit);
    final totalSpent = budgets.fold(0.0, (s, b) => s + b.spent);
    final budgetPct = totalBudget > 0 ? (totalSpent / totalBudget).clamp(0.0, 1.0) : 0.0;

    // Build a flat emoji lookup: categoryId AND label -> emoji
    final emojiMap = <String, String>{};
    for (final cats in allCats.values) {
      for (final c in cats) {
        emojiMap[c.id] = c.emoji;
        emojiMap[c.label] = c.emoji;
        emojiMap[c.label.toLowerCase()] = c.emoji;
      }
    }

    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Header(),
              const SizedBox(height: 8),
              _BalanceCard(totalBalance: totalBalance, income: income, expense: expense),
              const SizedBox(height: 16),
              _BudgetCard(onTap: () => context.go('/budget'), remaining: totalBudget - totalSpent, total: totalBudget, pct: budgetPct),
              const SizedBox(height: 24),
              _RecentActivity(
                transactions: transactions,
                emojiMap: emojiMap,
                excludedWalletIds: excludedWalletIds,
                onTap: (t) => context.push('/transaction-details', extra: t),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatefulWidget {
  @override
  State<_Header> createState() => _HeaderState();
}

class _HeaderState extends State<_Header> {
  String? _profileImagePath;
  String _profileName = 'Welcome';

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      final path = prefs.getString('profile_image_path');
      final name = prefs.getString('profile_name');
      if (mounted) setState(() {
        if (path != null) _profileImagePath = path;
        if (name != null && name.isNotEmpty) _profileName = name;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: AppTheme.surfaceContainerLow,
            backgroundImage: _profileImagePath != null ? FileImage(File(_profileImagePath!)) : null,
            child: _profileImagePath == null
                ? const Icon(Icons.person, color: AppTheme.onSurfaceVariant)
                : null,
          ),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('WELCOME BACK', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                letterSpacing: 1.5, color: AppTheme.onSurfaceVariant)),
            Text(_profileName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppTheme.onSurface)),
          ]),
          const Spacer(),
          Stack(children: [
            Container(padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(50),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)]),
              child: const Icon(Icons.notifications_none_rounded, size: 20, color: AppTheme.onSurfaceVariant)),
            Positioned(top: 10, right: 12,
              child: Container(width: 8, height: 8,
                decoration: BoxDecoration(color: Colors.red, shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5)))),
          ]),
        ],
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  final double totalBalance, income, expense;
  const _BalanceCard({required this.totalBalance, required this.income, required this.expense});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF00113A), Color(0xFF0D2260)],
            begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(32),
          boxShadow: [BoxShadow(color: const Color(0xFF00113A).withOpacity(0.3), blurRadius: 40, offset: const Offset(0, 20))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Text('TOTAL BALANCE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
              color: Colors.white.withOpacity(0.6), letterSpacing: 1.5)),
          const SizedBox(height: 8),
          RichText(text: TextSpan(children: [
            const TextSpan(text: 'RM ', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: Colors.white)),
            TextSpan(text: totalBalance.toStringAsFixed(0), style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800, color: Colors.white)),
            TextSpan(text: '.${(totalBalance % 1 * 100).toStringAsFixed(0).padLeft(2, '0')}',
              style: const TextStyle(fontSize: 20, color: Color(0x99FFFFFF))),
          ])),
          const SizedBox(height: 24),
          Divider(color: Colors.white.withOpacity(0.1)),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _BalanceStat(label: 'INCOME', amount: 'RM ${income.toStringAsFixed(0)}', dot: const Color(0xFF4FD1C5)),
            Container(width: 1, height: 32, color: Colors.white.withOpacity(0.1), margin: const EdgeInsets.symmetric(horizontal: 16)),
            _BalanceStat(label: 'EXPENSE', amount: 'RM ${expense.toStringAsFixed(0)}', dot: Colors.pinkAccent),
          ]),
        ]),
      ),
    );
  }
}

class _BalanceStat extends StatelessWidget {
  final String label, amount;
  final Color dot;
  const _BalanceStat({required this.label, required this.amount, required this.dot});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
          color: Colors.white.withOpacity(0.5), letterSpacing: 1.5)),
      const SizedBox(height: 4),
      Row(children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text(amount, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
      ]),
    ]);
  }
}

class _BudgetCard extends StatelessWidget {
  final VoidCallback onTap;
  final double remaining, total, pct;
  const _BudgetCard({required this.onTap, required this.remaining, required this.total, required this.pct});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 20)]),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(width: 32, height: 32, decoration: BoxDecoration(
                  color: AppTheme.secondary.withOpacity(0.1), shape: BoxShape.circle),
                child: const Icon(Icons.account_balance_wallet_rounded, size: 16, color: AppTheme.secondary)),
              const SizedBox(width: 12),
              const Text('Remaining Budget', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.onSurface)),
              const Spacer(),
              Text('${(pct * 100).toStringAsFixed(0)}%', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.onSurfaceVariant)),
            ]),
            const SizedBox(height: 12),
            RichText(text: TextSpan(children: [
              TextSpan(text: 'RM ${remaining.toStringAsFixed(2)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppTheme.onSurface)),
              TextSpan(text: ' / ${total.toStringAsFixed(0)}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                  color: AppTheme.onSurfaceVariant, letterSpacing: 1)),
            ])),
            const SizedBox(height: 12),
            ClipRRect(borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(value: pct, minHeight: 10,
                backgroundColor: AppTheme.surfaceContainer,
                valueColor: const AlwaysStoppedAnimation(AppTheme.secondary))),
          ]),
        ),
      ),
    );
  }
}

class _RecentActivity extends StatelessWidget {
  final List<tx.Transaction> transactions;
  final Map<String, String> emojiMap;
  final Set<String> excludedWalletIds;
  final void Function(tx.Transaction) onTap;
  const _RecentActivity({required this.transactions, required this.emojiMap, required this.excludedWalletIds, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // Filter out duplicate transfers - keep only one transaction per transfer
    final filteredTx = <tx.Transaction>[];
    final seenTransferIds = <String>{};

    for (final t in transactions) {
      if (t.category == 'Transfer') {
        // Extract base ID (remove _out or _in suffix)
        final baseId = t.id.replaceAll(RegExp(r'_(out|in)$'), '');
        if (!seenTransferIds.contains(baseId)) {
          seenTransferIds.add(baseId);
          filteredTx.add(t);
        }
      } else {
        filteredTx.add(t);
      }
    }

    final recent = filteredTx.toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Recent Activity', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.onSurface)),
        const SizedBox(height: 16),
        if (recent.isEmpty)
          const Center(child: Text('No transactions yet', style: TextStyle(color: AppTheme.onSurfaceVariant)))
        else
          ...recent.map((t) => GestureDetector(
            onTap: () => onTap(t),
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8)]),
              child: Row(children: [
                Container(width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: t.type == tx.TransactionType.income
                        ? const Color(0xFFEFFFF4)
                        : const Color(0xFFFFEDED),
                    borderRadius: BorderRadius.circular(14)),
                  child: Center(
                    child: emojiMap.containsKey(t.category)
                        ? Text(emojiMap[t.category]!, style: const TextStyle(fontSize: 22))
                        : Icon(
                            t.type == tx.TransactionType.income
                                ? Icons.arrow_downward_rounded
                                : Icons.arrow_upward_rounded,
                            color: t.type == tx.TransactionType.income
                                ? const Color(0xFF14B8A6)
                                : AppTheme.error,
                            size: 22,
                          ),
                  ),
                ),
                const SizedBox(width: 16),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t.category, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.onSurface)),
                  Text(t.category == 'Transfer' ? 'Transfer' : (excludedWalletIds.contains(t.accountId) ? 'Record' : t.type.name), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.onSurfaceVariant)),
                ]),
                const Spacer(),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(
                    t.category == 'Transfer'
                        ? 'RM${t.amount.toStringAsFixed(2)}'
                        : '${t.type == tx.TransactionType.income ? '+' : '-'}RM${t.amount.toStringAsFixed(2)}',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                      color: t.type == tx.TransactionType.income ? const Color(0xFF14B8A6) : AppTheme.error)),
                  Text(
                    '${t.date.day}/${t.date.month}/${t.date.year}',
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF9EA3B8))),
                ]),
              ]),
            ),
          )),
      ]),
    );
  }
}
