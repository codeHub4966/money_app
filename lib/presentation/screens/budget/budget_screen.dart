import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/models/budget.dart';
import '../../providers/app_providers.dart';

class BudgetScreen extends ConsumerWidget {
  const BudgetScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final budgets = ref.watch(budgetsProvider).valueOrNull ?? [];
    final allCats = ref.watch(categoriesProvider);
    final emojiMap = <String, String>{};
    final labelMap = <String, String>{};
    for (final cats in allCats.values) {
      for (final c in cats) {
        emojiMap[c.id] = c.emoji;
        emojiMap[c.label] = c.emoji;
        emojiMap[c.label.toLowerCase()] = c.emoji;
        labelMap[c.id] = c.label;
        labelMap[c.label] = c.label;
        labelMap[c.label.toLowerCase()] = c.label;
      }
    }

    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 100),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: Text('Budgets', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppTheme.primary)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _SummaryCard(budgets: budgets),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Category Budgets', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppTheme.primary)),
                GestureDetector(
                  onTap: () => context.push('/add-budget'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(color: AppTheme.surfaceContainerLow, borderRadius: BorderRadius.circular(20)),
                    child: const Row(children: [
                      Icon(Icons.add, size: 16, color: AppTheme.primary),
                      SizedBox(width: 4),
                      Text('Add New', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.primary)),
                    ]),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 16),
            if (budgets.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: Text('No budgets yet. Tap Add New to create one.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.onSurfaceVariant))),
              )
            else
              ...budgets.map((b) => Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                child: _CategoryCard(
                  budget: b,
                  emoji: emojiMap[b.categoryName] ?? emojiMap[b.categoryName.toLowerCase()],
                  displayName: labelMap[b.categoryName] ?? b.categoryName,
                  onTap: () => context.push('/budget/${b.categoryName}'),
                ),
              )),
          ]),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatefulWidget {
  final List<Budget> budgets;
  const _SummaryCard({required this.budgets});
  @override
  State<_SummaryCard> createState() => _SummaryCardState();
}

class _SummaryCardState extends State<_SummaryCard> {
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

  @override
  Widget build(BuildContext context) {
    final total = widget.budgets.fold(0.0, (s, b) => s + b.monthlyLimit);
    final spent = widget.budgets.fold(0.0, (s, b) => s + b.spent);
    final remaining = total - spent;
    final pct = total > 0 ? (spent / total).clamp(0.0, 1.0) : 0.0;
    final now = DateTime.now();
    final daysInMonth = DateTimeRange(start: DateTime(now.year, now.month), end: DateTime(now.year, now.month + 1)).duration.inDays;
    final daysLeft = daysInMonth - now.day;

    return Column(children: [
      GestureDetector(
        onTap: () => setState(() => _showPad = true),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppTheme.primary,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [BoxShadow(color: AppTheme.primary.withOpacity(0.3), blurRadius: 30, offset: const Offset(0, 12))],
          ),
          child: Column(children: [
            Text('TOTAL BUDGET: RM${total.toStringAsFixed(0)}', style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.6),
                fontWeight: FontWeight.w700, letterSpacing: 1.5)),
            const SizedBox(height: 4),
            Text('REMAINING', style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.6),
                fontWeight: FontWeight.w700, letterSpacing: 1.5)),
            const SizedBox(height: 8),
            Text('RM${remaining.toStringAsFixed(2)}', style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w800, color: Colors.white)),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(value: pct, minHeight: 8,
                backgroundColor: Colors.white.withOpacity(0.1),
                valueColor: const AlwaysStoppedAnimation(AppTheme.secondary)),
            ),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              _Stat(label: 'SPENT', value: 'RM${spent.toStringAsFixed(0)}'),
              _Stat(label: 'USAGE', value: '${(pct * 100).toStringAsFixed(1)}%', valueColor: const Color(0xFF93C5FD)),
              _Stat(label: 'DAYS LEFT', value: '$daysLeft', align: CrossAxisAlignment.end),
            ]),
          ]),
        ),
      ),
      if (_showPad) GestureDetector(
        onVerticalDragEnd: (d) {
          if (d.primaryVelocity != null && d.primaryVelocity! > 300) setState(() => _showPad = false);
        },
        child: _BudgetNumberPad(
          amount: _amount,
          label: 'Total Budget',
          onKey: _onKey,
          onDone: () => setState(() => _showPad = false),
        ),
      ),
    ]);
  }
}

class _Stat extends StatelessWidget {
  final String label, value;
  final Color? valueColor;
  final CrossAxisAlignment align;
  const _Stat({required this.label, required this.value, this.valueColor, this.align = CrossAxisAlignment.start});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: align, children: [
      Text(label, style: TextStyle(fontSize: 9, color: Colors.white.withOpacity(0.5),
          fontWeight: FontWeight.w700, letterSpacing: 1.5)),
      const SizedBox(height: 4),
      Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
          color: valueColor ?? Colors.white)),
    ]);
  }
}

class _CategoryCard extends StatelessWidget {
  final Budget budget;
  final String? emoji;
  final String displayName;
  final VoidCallback onTap;
  const _CategoryCard({required this.budget, this.emoji, required this.displayName, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final pct = (budget.spent / budget.monthlyLimit).clamp(0.0, 1.0);
    final over = budget.isOverBudget;
    final left = budget.remaining.abs();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: over ? const Border(left: BorderSide(color: Color(0xFFD32F2F), width: 4)) : null,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 16)],
        ),
        child: Column(children: [
          Row(children: [
            Container(width: 48, height: 48,
              decoration: BoxDecoration(
                color: over ? const Color(0xFFFFDAD6) : AppTheme.secondary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14)),
              child: Center(
                child: emoji != null
                    ? Text(emoji!, style: const TextStyle(fontSize: 24))
                    : Icon(Icons.category_rounded, size: 24,
                        color: over ? AppTheme.error : AppTheme.secondary),
              )),
            const SizedBox(width: 16),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(displayName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.onSurface)),
              Text(over ? '100% OVER BUDGET' : '${(pct * 100).toStringAsFixed(2)}% USED',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1,
                    color: over ? AppTheme.error : AppTheme.onSurfaceVariant)),
            ])),
            Text('RM${left.toStringAsFixed(2)} ${over ? 'Over' : 'Left'}',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                  color: over ? AppTheme.error : AppTheme.onSurface)),
          ]),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(value: pct, minHeight: 8,
              backgroundColor: over ? const Color(0xFFFFDAD6) : AppTheme.surfaceContainer,
              valueColor: AlwaysStoppedAnimation(over ? AppTheme.error : AppTheme.secondary)),
          ),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Used: RM${budget.spent.toStringAsFixed(2)}',
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1,
                  color: over ? AppTheme.error : AppTheme.onSurfaceVariant)),
            Text('Total: RM${budget.monthlyLimit.toStringAsFixed(2)}',
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1,
                  color: over ? AppTheme.error : AppTheme.onSurfaceVariant)),
          ]),
        ]),
      ),
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
            child: const Center(child: Text('Done', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.onSurface))),
          ),
        ),
      ]),
    );
  }
}
