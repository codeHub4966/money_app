import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/models/transaction.dart';
import '../../providers/app_providers.dart';

class WalletAccountScreen extends ConsumerWidget {
  final String id;
  final String name;
  final String type;
  final double balance;
  final bool includeInTotal;
  const WalletAccountScreen({super.key, required this.id, required this.name, required this.type, required this.balance, this.includeInTotal = true});

  static const _typeLabels = {
    'bank': 'Bank Account', 'savings': 'Savings Account', 'credit': 'Credit Card',
    'cash': 'Physical Cash', 'crypto': 'Crypto Wallet', 'other': 'E-Wallet',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allTx = ref.watch(transactionsProvider).valueOrNull ?? [];
    final txs = allTx.where((t) => t.accountId == id).toList();
    final allCats = ref.watch(categoriesProvider);
    final emojiMap = <String, String>{};
    for (final cats in allCats.values) {
      for (final c in cats) emojiMap[c.id] = c.emoji;
    }

    // Group by date
    final Map<String, List<Transaction>> grouped = {};
    for (final t in txs) {
      final key = DateFormat('d MMM yyyy').format(t.date).toUpperCase();
      grouped.putIfAbsent(key, () => []).add(t);
    }

    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: SafeArea(child: Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(children: [
            IconButton(icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.secondary),
                onPressed: () => context.pop()),
            const Expanded(child: Text('Wallet Account', textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.primary))),
            IconButton(icon: const Icon(Icons.edit_outlined, color: Color(0xFF9EA3B8)),
                onPressed: () => context.push('/add-wallet', extra: {'id': id, 'name': name, 'type': type, 'balance': balance, 'includeInTotal': includeInTotal})),
            IconButton(icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFF9EA3B8)),
                onPressed: () async {
                  final confirm = await showDialog<bool>(context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Delete Wallet'),
                      content: const Text('Are you sure?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
                      ],
                    ));
                  if (confirm == true) {
                    await ref.read(walletRepositoryProvider).delete(id);
                    if (context.mounted) context.pop();
                  }
                }),
          ]),
        ),
        Expanded(child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            GestureDetector(
              onTap: () => context.push('/add-wallet', extra: {'id': id, 'name': name, 'type': type, 'balance': balance, 'includeInTotal': includeInTotal}),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 16)]),
                child: Row(children: [
                  Container(width: 48, height: 48,
                    decoration: BoxDecoration(color: AppTheme.secondary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
                    child: const Center(child: Text('🏦', style: TextStyle(fontSize: 22)))),
                  const SizedBox(width: 16),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppTheme.primary)),
                    Text(_typeLabels[type] ?? 'Account',
                      style: TextStyle(fontSize: 12, color: AppTheme.onSurfaceVariant.withValues(alpha: 0.7))),
                  ])),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('BALANCE', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
                        letterSpacing: 1.5, color: AppTheme.secondary.withValues(alpha: 0.6))),
                    Text('RM${balance.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppTheme.primary)),
                  ]),
                ]),
              ),
            ),
            const SizedBox(height: 24),
            const Text('Wallet details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.primary)),
            const SizedBox(height: 16),
            if (grouped.isEmpty)
              const Center(child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('No transactions for this wallet.', style: TextStyle(color: AppTheme.onSurfaceVariant)),
              ))
            else
              ...grouped.entries.map((e) => _TxGroup(
                label: e.key,
                transactions: e.value,
                emojiMap: emojiMap,
                onTap: (t) => context.push('/transaction-details', extra: t),
              )),
          ]),
        )),
      ])),
    );
  }
}

class _TxGroup extends StatelessWidget {
  final String label;
  final List<Transaction> transactions;
  final Map<String, String> emojiMap;
  final void Function(Transaction) onTap;
  const _TxGroup({required this.label, required this.transactions, required this.emojiMap, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8)]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
              letterSpacing: 1.5, color: AppTheme.onSurfaceVariant.withValues(alpha: 0.6))),
        ),
        ...transactions.asMap().entries.map((e) {
          final t = e.value;
          final isIncome = t.type == TransactionType.income;
          final emoji = emojiMap[t.category];
          return Column(children: [
            if (e.key > 0) Divider(height: 1, color: AppTheme.surfaceContainerLow),
            GestureDetector(
              onTap: () => onTap(t),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(children: [
                  Container(width: 40, height: 40, decoration: BoxDecoration(
                      color: isIncome ? const Color(0xFFEFFFF4) : const Color(0xFFFFEDED),
                      shape: BoxShape.circle),
                    child: Center(
                      child: emoji != null
                          ? Text(emoji, style: const TextStyle(fontSize: 20))
                          : Icon(Icons.receipt_rounded, size: 20,
                              color: isIncome ? const Color(0xFF16A34A) : AppTheme.error),
                    )),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t.category, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.primary)),
                    Text(DateFormat('HH:mm').format(t.date),
                      style: const TextStyle(fontSize: 11, color: AppTheme.onSurfaceVariant)),
                  ])),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('${isIncome ? '+' : '-'}RM${t.amount.toStringAsFixed(2)}',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800,
                          color: isIncome ? const Color(0xFF16A34A) : AppTheme.error)),
                    Text('SETTLED', style: TextStyle(fontSize: 9, letterSpacing: 1,
                        color: AppTheme.onSurfaceVariant.withValues(alpha: 0.5))),
                  ]),
                ]),
              ),
            ),
          ]);
        }),
      ]),
    );
  }
}
