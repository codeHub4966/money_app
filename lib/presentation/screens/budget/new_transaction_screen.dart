import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/repositories/transaction_repository.dart';
import '../../../domain/models/transaction.dart';
import '../../providers/app_providers.dart';

const _categories = [
  {'id': 'food', 'icon': '🍲', 'label': 'Food'},
  {'id': 'goods', 'icon': '🧻', 'label': 'Goods'},
  {'id': 'snacks', 'icon': '🍩', 'label': 'Snacks'},
  {'id': 'fruit', 'icon': '🍉', 'label': 'Fruit'},
  {'id': 'vegetables', 'icon': '🥬', 'label': 'Vegetables'},
  {'id': 'games', 'icon': '🎮', 'label': 'Games'},
  {'id': 'clothing', 'icon': '👕', 'label': 'Clothing'},
  {'id': 'shopping', 'icon': '🛍️', 'label': 'Shopping'},
];

class NewTransactionScreen extends ConsumerStatefulWidget {
  final String? title;
  final String? initialCategoryId;
  final String? initialAmount;
  const NewTransactionScreen({super.key, this.title, this.initialCategoryId, this.initialAmount});

  @override
  ConsumerState<NewTransactionScreen> createState() => _State();
}

class _State extends ConsumerState<NewTransactionScreen> {
  late String? _selectedId;
  late String _amount;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.initialCategoryId;
    _amount = widget.initialAmount ?? '';
  }

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

  Future<void> _done() async {
    final amount = double.tryParse(_amount);
    if (amount == null || amount <= 0 || _selectedId == null) return;
    final repo = ref.read(transactionRepositoryProvider);
    await repo.add(Transaction(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: TransactionType.expense,
      amount: amount,
      category: _selectedId!,
      accountId: 'cash',
      date: DateTime.now(),
    ));
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: SafeArea(
        child: Column(children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(children: [
              IconButton(icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.secondary),
                  onPressed: () => context.pop()),
              const SizedBox(width: 4),
              Text(widget.title ?? 'New Transaction', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppTheme.primary)),
              const Spacer(),
              const Icon(Icons.more_vert_rounded, color: AppTheme.primary),
            ]),
          ),
          // Category section
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('STEP 01', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                    letterSpacing: 2, color: AppTheme.onSurfaceVariant)),
                const SizedBox(height: 4),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('Select Category', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppTheme.primary)),
                  Row(children: [
                    Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppTheme.secondary, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Container(width: 8, height: 8, decoration: BoxDecoration(color: AppTheme.surfaceContainerLow, shape: BoxShape.circle,
                        border: Border.all(color: AppTheme.onSurfaceVariant.withOpacity(0.3)))),
                  ]),
                ]),
                const SizedBox(height: 24),
                GridView.count(
                  crossAxisCount: 4,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 0.85,
                  children: _categories.map((cat) {
                    final selected = _selectedId == cat['id'];
                    return GestureDetector(
                      onTap: () => setState(() => _selectedId = cat['id'] as String),
                      child: Column(children: [
                        Container(
                          width: 64, height: 64,
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(18),
                            border: selected ? Border.all(color: AppTheme.primary.withOpacity(0.3), width: 2) : null,
                          ),
                          child: Center(child: Text(cat['icon'] as String, style: const TextStyle(fontSize: 30))),
                        ),
                        const SizedBox(height: 6),
                        Text(cat['label'] as String,
                          style: TextStyle(fontSize: 12, fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                              color: selected ? AppTheme.primary : AppTheme.onSurfaceVariant)),
                      ]),
                    );
                  }).toList(),
                ),
              ]),
            ),
          ),
          // Number pad (shown when category selected)
          if (_selectedId != null) GestureDetector(
            onVerticalDragEnd: (d) {
              if (d.primaryVelocity != null && d.primaryVelocity! > 300) {
                setState(() => _selectedId = null);
              }
            },
            child: _NumberPad(
              amount: _amount,
              categoryLabel: (_categories.firstWhere((c) => c['id'] == _selectedId, orElse: () => _categories.first))['label'] as String,
              onKey: _onKey,
              onDone: _done,
            ),
          ),
        ]),
      ),
    );
  }
}

class _NumberPad extends StatelessWidget {
  final String amount, categoryLabel;
  final void Function(String) onKey;
  final VoidCallback onDone;
  const _NumberPad({required this.amount, required this.categoryLabel, required this.onKey, required this.onDone});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(40)),
        boxShadow: [BoxShadow(color: Color(0x14000000), blurRadius: 40, offset: Offset(0, -10))],
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Remaining limit: RM900', style: TextStyle(fontSize: 13, color: AppTheme.onSurfaceVariant)),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(color: AppTheme.onSurfaceVariant.withOpacity(0.2), width: 2, style: BorderStyle.solid),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(children: [
            Text(categoryLabel, style: const TextStyle(fontSize: 15, color: AppTheme.onSurfaceVariant)),
            Text(amount.isEmpty ? '0' : amount, style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w700, color: AppTheme.onSurface)),
          ]),
        ),
        const SizedBox(height: 12),
        _buildGrid(),
        const SizedBox(height: 16),
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

  Widget _buildGrid() {
    final keys = [
      ['7','8','9','Empty'],
      ['4','5','6','×'],
      ['1','2','3','+/-'],
      ['.','0','⌫','='],
    ];
    return Column(children: keys.map((row) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: row.map((k) {
        final isSpecial = ['Empty','×','+/-','='].contains(k);
        return Expanded(child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: GestureDetector(
            onTap: () => onKey(k == '⌫' ? 'backspace' : k == 'Empty' ? 'empty' : k == '×' ? 'x' : k),
            child: Container(
              height: 50,
              decoration: BoxDecoration(
                color: isSpecial ? const Color(0xFFE4EBEC) : const Color(0xFFF8F9FB),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
              ),
              child: Center(child: k == '⌫'
                ? const Icon(Icons.backspace_outlined, size: 22, color: AppTheme.onSurface)
                : Text(k, style: TextStyle(fontSize: isSpecial ? 16 : 22, fontWeight: FontWeight.w600, color: AppTheme.onSurface))),
            ),
          ),
        ));
      }).toList()),
    )).toList());
  }
}
