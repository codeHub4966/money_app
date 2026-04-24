import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/models/budget.dart';
import '../../providers/app_providers.dart';

class AddBudgetScreen extends ConsumerStatefulWidget {
  final String? initialId;
  final String? initialCategory;
  final double? initialLimit;
  const AddBudgetScreen({super.key, this.initialId, this.initialCategory, this.initialLimit});

  @override
  ConsumerState<AddBudgetScreen> createState() => _State();
}

class _State extends ConsumerState<AddBudgetScreen> {
  late String? _selectedId;
  late String _amount;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.initialCategory;
    _amount = widget.initialLimit?.toStringAsFixed(0) ?? '';
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

  Future<void> _save() async {
    final limit = double.tryParse(_amount);
    if (limit == null || limit <= 0 || _selectedId == null) return;
    await ref.read(budgetRepositoryProvider).add(Budget(
      id: widget.initialId ?? DateTime.now().millisecondsSinceEpoch.toString(),
      categoryName: _selectedId!,
      monthlyLimit: limit,
      spent: 0,
    ));
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(children: [
              IconButton(icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.secondary),
                  onPressed: () => context.pop()),
              Text(widget.initialId != null ? 'Edit Budget' : 'Add Budget',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppTheme.primary)),
            ]),
          ),
          Expanded(child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('SELECT CATEGORY', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                  letterSpacing: 2, color: AppTheme.onSurfaceVariant)),
              const SizedBox(height: 16),
              GridView.count(
                crossAxisCount: 4,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 0.85,
                children: ref.watch(categoriesProvider)['expense']!.asMap().entries.map((entry) {
                  final cat = entry.value;
                  final selected = _selectedId == cat.id;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedId = cat.id),
                    child: Column(children: [
                      Container(
                        width: 64, height: 64,
                        decoration: BoxDecoration(
                          color: selected ? AppTheme.primary.withValues(alpha: 0.1) : AppTheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(18),
                          border: selected ? Border.all(color: AppTheme.primary, width: 2) : null,
                        ),
                        child: Center(child: Text(cat.emoji, style: const TextStyle(fontSize: 28)))),
                      const SizedBox(height: 6),
                      Text(cat.label,
                        textAlign: TextAlign.center,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                            color: selected ? AppTheme.primary : AppTheme.onSurfaceVariant)),
                    ]),
                  );
                }).toList(),
              ),
            ]),
          )),
          if (_selectedId != null) GestureDetector(
            onVerticalDragEnd: (d) {
              if (d.primaryVelocity != null && d.primaryVelocity! > 300) setState(() => _selectedId = null);
            },
            child: _NumberPad(amount: _amount, label: _selectedId!, onKey: _onKey, onDone: _save),
          ),
        ]),
      ),
    );
  }
}

class _NumberPad extends StatelessWidget {
  final String amount, label;
  final void Function(String) onKey;
  final VoidCallback onDone;
  const _NumberPad({required this.amount, required this.label, required this.onKey, required this.onDone});

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
        borderRadius: BorderRadius.vertical(top: Radius.circular(40)),
        boxShadow: [BoxShadow(color: Color(0x14000000), blurRadius: 40, offset: Offset(0, -10))],
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(color: AppTheme.onSurfaceVariant.withValues(alpha: 0.2), width: 2),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(children: [
            Text('Monthly limit for $label', style: const TextStyle(fontSize: 13, color: AppTheme.onSurfaceVariant)),
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
        GestureDetector(
          onTap: onDone,
          child: Container(
            height: 56, width: double.infinity,
            decoration: BoxDecoration(color: AppTheme.primary, borderRadius: BorderRadius.circular(24),
              boxShadow: [BoxShadow(color: AppTheme.primary.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 8))]),
            child: const Center(child: Text('Save Budget', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white))),
          ),
        ),
      ]),
    );
  }
}
