import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/models/budget.dart';
import '../../../domain/models/transaction.dart';
import '../../providers/app_providers.dart';

class BudgetDetailScreen extends ConsumerStatefulWidget {
  final String? categoryName;
  const BudgetDetailScreen({super.key, this.categoryName});

  @override
  ConsumerState<BudgetDetailScreen> createState() => _BudgetDetailScreenState();
}

class _BudgetDetailScreenState extends ConsumerState<BudgetDetailScreen> {
  bool _showPad = false;
  String _amount = '';

  void _onKey(String key) {
    setState(() {
      if (key == 'backspace') {
        if (_amount.isNotEmpty) _amount = _amount.substring(0, _amount.length - 1);
      } else if (key == 'empty') {
        _amount = '';
      } else if (key == '.') {
        if (!_amount.contains('.')) _amount = _amount.isEmpty ? '0.' : '$_amount.';
      } else if (key == '+/-' || key == 'x' || key == '=') {
        // no-op
      } else {
        _amount = _amount == '0' ? key : '$_amount$key';
      }
    });
  }

  Future<void> _saveLimit(Budget budget) async {
    final limit = double.tryParse(_amount);
    if (limit == null || limit <= 0) return;
    await ref.read(budgetRepositoryProvider).add(Budget(
      id: budget.id,
      categoryName: budget.categoryName,
      monthlyLimit: limit,
      spent: budget.spent,
    ));
    setState(() { _showPad = false; _amount = ''; });
  }

  Future<void> _deleteBudget(String id) async {
    final confirm = await showDialog<bool>(context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Budget'),
        content: const Text('Are you sure?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ));
    if (confirm == true) {
      await ref.read(budgetRepositoryProvider).delete(id);
      if (mounted) context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.categoryName ?? '';
    final budgets = ref.watch(budgetsProvider).valueOrNull ?? [];
    final budget = budgets.where((b) => b.categoryName == name).firstOrNull;
    final allTx = ref.watch(transactionsProvider).valueOrNull ?? [];
    final allCats = ref.watch(categoriesProvider);
    final emojiMap = <String, String>{};
    for (final cats in allCats.values) {
      for (final c in cats) emojiMap[c.id] = c.emoji;
    }
    final headerEmoji = emojiMap[name.toLowerCase()] ?? emojiMap[name];
    final now = DateTime.now();
    final txs = allTx.where((t) =>
        t.type == TransactionType.expense &&
        t.category.toLowerCase() == name.toLowerCase() &&
        t.date.year == now.year &&
        t.date.month == now.month).toList();

    // Group by date
    final Map<String, List<Transaction>> grouped = {};
    for (final t in txs) {
      final key = DateFormat('d MMM yyyy').format(t.date).toUpperCase();
      grouped.putIfAbsent(key, () => []).add(t);
    }

    final pct = budget != null && budget.monthlyLimit > 0
        ? (budget.spent / budget.monthlyLimit).clamp(0.0, 1.0)
        : 0.0;

    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: SafeArea(child: Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(children: [
            IconButton(icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.secondary),
                onPressed: () => context.pop()),
            const Expanded(child: Text('Budget Detail', textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.primary))),
            IconButton(
              icon: const Icon(Icons.edit_outlined, color: Color(0xFF9EA3B8)),
              onPressed: () => budget != null ? context.push('/add-budget', extra: {
                'id': budget.id,
                'category': budget.categoryName,
                'limit': budget.monthlyLimit,
              }) : null,
            ),
            if (budget != null)
              IconButton(icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFF9EA3B8)),
                  onPressed: () => _deleteBudget(budget.id)),
          ]),
        ),
        Expanded(child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            GestureDetector(
              onTap: () => setState(() { _amount = budget?.monthlyLimit.toStringAsFixed(0) ?? ''; _showPad = true; }),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 16)]),
                child: Column(children: [
                  Row(children: [
                    Container(width: 48, height: 48,
                      decoration: BoxDecoration(color: AppTheme.secondary.withValues(alpha: 0.08), shape: BoxShape.circle),
                      child: Center(
                        child: headerEmoji != null
                            ? Text(headerEmoji, style: const TextStyle(fontSize: 24))
                            : const Icon(Icons.category_rounded, size: 24, color: AppTheme.secondary),
                      )),
                    const SizedBox(width: 16),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppTheme.primary)),
                      Text('RM${budget?.monthlyLimit.toStringAsFixed(0) ?? '0'}/month',
                        style: TextStyle(fontSize: 12, color: AppTheme.onSurfaceVariant.withValues(alpha: 0.7))),
                    ])),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text('REMAINING', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
                          letterSpacing: 1.5, color: AppTheme.secondary.withValues(alpha: 0.6))),
                      Text('RM${budget?.remaining.toStringAsFixed(2) ?? '0'}',
                        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppTheme.primary)),
                    ]),
                  ]),
                  const SizedBox(height: 16),
                  ClipRRect(borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(value: pct, minHeight: 10,
                      backgroundColor: const Color(0xFFE8EAF2),
                      valueColor: AlwaysStoppedAnimation(budget?.isOverBudget == true ? AppTheme.error : AppTheme.secondary))),
                  const SizedBox(height: 8),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text('${(pct * 100).toStringAsFixed(1)}% used',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                          color: budget?.isOverBudget == true ? AppTheme.error : AppTheme.secondary)),
                    Text('Spent RM${budget?.spent.toStringAsFixed(2) ?? '0'}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.onSurfaceVariant)),
                  ]),
                ]),
              ),
            ),
            const SizedBox(height: 24),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Expenses details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.primary)),
              Text('${txs.length} transactions', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.secondary)),
            ]),
            const SizedBox(height: 16),
            if (grouped.isEmpty)
              const Center(child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('No expenses this month.', style: TextStyle(color: AppTheme.onSurfaceVariant)),
              ))
            else
              ...grouped.entries.map((e) => _TxGroup(label: e.key, transactions: e.value,
                emojiMap: emojiMap,
                onTap: (t) => context.push('/transaction-details', extra: t))),
          ]),
        )),
        if (_showPad) GestureDetector(
          onVerticalDragEnd: (d) {
            if (d.primaryVelocity != null && d.primaryVelocity! > 300) setState(() => _showPad = false);
          },
          child: _BudgetNumberPad(
            amount: _amount,
            label: name,
            onKey: _onKey,
            onDone: () => budget != null ? _saveLimit(budget) : setState(() => _showPad = false),
          ),
        ),
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
          final emoji = emojiMap[t.category];
          return Column(children: [
            if (e.key > 0) Divider(height: 1, color: AppTheme.surfaceContainerLow),
            GestureDetector(
              onTap: () => onTap(t),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(children: [
                  Container(width: 40, height: 40, decoration: BoxDecoration(
                      color: const Color(0xFFFFEDED), shape: BoxShape.circle),
                    child: Center(
                      child: emoji != null
                          ? Text(emoji, style: const TextStyle(fontSize: 20))
                          : const Icon(Icons.receipt_rounded, size: 20, color: AppTheme.onSurfaceVariant),
                    )),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t.note ?? t.category, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.primary)),
                    Text(DateFormat('HH:mm').format(t.date), style: const TextStyle(fontSize: 11, color: AppTheme.onSurfaceVariant)),
                  ])),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('-RM${t.amount.toStringAsFixed(2)}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppTheme.error)),
                    Text('SETTLED', style: TextStyle(fontSize: 9, letterSpacing: 1, color: AppTheme.onSurfaceVariant.withValues(alpha: 0.5))),
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

class _BudgetNumberPad extends StatelessWidget {
  final String amount, label;
  final void Function(String) onKey;
  final VoidCallback onDone;
  const _BudgetNumberPad({required this.amount, required this.label, required this.onKey, required this.onDone});

  @override
  Widget build(BuildContext context) {
    final keys = [
      ['7','8','9','Empty'],
      ['4','5','6','×'],
      ['1','2','3','+/-'],
      ['.','0','⌫','='],
    ];
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: [BoxShadow(color: Color(0x14000000), blurRadius: 40, offset: Offset(0, -10))],
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 40, height: 4, decoration: BoxDecoration(color: AppTheme.surfaceContainer, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(color: AppTheme.onSurfaceVariant.withValues(alpha: 0.2), width: 2),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(children: [
            Text(label, style: const TextStyle(fontSize: 14, color: AppTheme.onSurfaceVariant)),
            Text(amount.isEmpty ? '0' : amount, style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w700, color: AppTheme.onSurface)),
          ]),
        ),
        const SizedBox(height: 12),
        ...keys.map((row) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: row.map((k) {
            final isOp = ['Empty','×','+/-','='].contains(k);
            return Expanded(child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: GestureDetector(
                onTap: () => onKey(k == '⌫' ? 'backspace' : k == 'Empty' ? 'empty' : k == '×' ? 'x' : k),
                child: Container(
                  height: 50,
                  decoration: BoxDecoration(
                    color: isOp ? const Color(0xFFE4EBEC) : const Color(0xFFF8F9FB),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Center(child: k == '⌫'
                    ? const Icon(Icons.backspace_outlined, size: 22, color: AppTheme.onSurface)
                    : Text(k, style: TextStyle(fontSize: isOp ? 16 : 22, fontWeight: FontWeight.w600, color: AppTheme.onSurface))),
                ),
              ),
            ));
          }).toList()),
        )),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: onDone,
          child: Container(
            height: 56, width: double.infinity,
            decoration: BoxDecoration(color: AppTheme.mint, borderRadius: BorderRadius.circular(24)),
            child: const Center(child: Text('Save', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.onSurface))),
          ),
        ),
      ]),
    );
  }
}
