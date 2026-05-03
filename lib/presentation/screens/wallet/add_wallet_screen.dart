import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/repositories/wallet_repository.dart';
import '../../../domain/models/wallet.dart';
import '../../../domain/models/transaction.dart';
import '../../providers/app_providers.dart';

const _types = [
  {'id': 'bank', 'icon': '🏛️', 'label': 'Bank'},
  {'id': 'credit', 'icon': '💳', 'label': 'Credit'},
  {'id': 'cash', 'icon': '💵', 'label': 'Cash'},
  {'id': 'crypto', 'icon': '🪙', 'label': 'Crypto'},
  {'id': 'savings', 'icon': '🐷', 'label': 'Savings'},
  {'id': 'other', 'icon': '📁', 'label': 'Other'},
];

class AddWalletScreen extends ConsumerStatefulWidget {
  final String? initialId;
  final String? initialName;
  final String? initialType;
  final double? initialBalance;
  final bool? initialIncludeInTotal;
  const AddWalletScreen({super.key, this.initialId, this.initialName, this.initialType, this.initialBalance, this.initialIncludeInTotal});

  @override
  ConsumerState<AddWalletScreen> createState() => _State();
}

class _State extends ConsumerState<AddWalletScreen> {
  late final TextEditingController _nameCtrl;
  late String _amount;
  late String _type;
  bool _includeInTotal = true;
  bool _showNumberPad = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialName ?? '');
    _amount = widget.initialBalance != null ? widget.initialBalance!.toStringAsFixed(2) : '';
    _type = widget.initialType ?? 'credit';
    _includeInTotal = widget.initialIncludeInTotal ?? true;
  }

  void _onKey(String key) {
    setState(() {
      if (key == 'backspace') {
        if (_amount.isNotEmpty) _amount = _amount.substring(0, _amount.length - 1);
      } else if (key == 'empty') {
        _amount = '';
      } else if (key == '.') {
        if (_amount.isEmpty) {
          _amount = '0.';
        } else {
          final lastNum = _getLastNumber(_amount);
          if (!lastNum.contains('.')) {
            _amount = '$_amount.';
          }
        }
      } else if (key == '+' || key == '-') {
        if (_amount.isEmpty) return;
        final lastChar = _amount[_amount.length - 1];
        if ('+-'.contains(lastChar)) {
          _amount = _amount.substring(0, _amount.length - 1) + key;
        } else {
          _amount = '$_amount$key';
        }
      } else if (key == '=') {
        final result = _evaluateExpression(_amount);
        if (result != null) {
          _amount = result.toString();
        }
      } else {
        _amount = _amount == '0' ? key : '$_amount$key';
      }
    });
  }

  String _getLastNumber(String expr) {
    if (expr.isEmpty) return '';
    int i = expr.length - 1;
    while (i >= 0 && !'+-'.contains(expr[i])) {
      i--;
    }
    return expr.substring(i + 1);
  }

  double? _evaluateExpression(String expr) {
    if (expr.isEmpty) return null;
    try {
      while (expr.isNotEmpty && '+-'.contains(expr[expr.length - 1])) {
        expr = expr.substring(0, expr.length - 1);
      }
      if (expr.isEmpty) return null;

      final tokens = <String>[];
      String currentNum = '';

      for (int i = 0; i < expr.length; i++) {
        final char = expr[i];
        if ('+-'.contains(char)) {
          if (currentNum.isNotEmpty) {
            tokens.add(currentNum);
            currentNum = '';
          }
          tokens.add(char);
        } else {
          currentNum += char;
        }
      }
      if (currentNum.isNotEmpty) tokens.add(currentNum);

      if (tokens.isEmpty) return null;

      final values = <double>[];
      final operators = <String>[];

      for (final token in tokens) {
        if ('+-'.contains(token)) {
          operators.add(token);
        } else {
          final num = double.tryParse(token);
          if (num == null) return null;
          values.add(num);
        }
      }

      if (values.isEmpty) return null;

      int i = 0;
      while (i < operators.length) {
        if (operators[i] == '+') {
          values[i] = values[i] + values[i + 1];
          values.removeAt(i + 1);
          operators.removeAt(i);
        } else if (operators[i] == '-') {
          values[i] = values[i] - values[i + 1];
          values.removeAt(i + 1);
          operators.removeAt(i);
        } else {
          i++;
        }
      }

      final result = values[0];
      return result % 1 == 0 ? result.roundToDouble() : result;
    } catch (e) {
      return null;
    }
  }

  Future<void> _save() async {
    final balance = double.tryParse(_amount) ?? 0;
    if (_nameCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a wallet name.')));
      return;
    }

    final walletRepo = ref.read(walletRepositoryProvider);
    final txRepo = ref.read(transactionRepositoryProvider);

    // If editing existing wallet, check if balance changed
    if (widget.initialId != null && widget.initialBalance != null) {
      final oldBalance = widget.initialBalance!;
      final difference = balance - oldBalance;

      if (difference != 0) {
        // Create adjustment transaction
        final now = DateTime.now();
        await txRepo.add(Transaction(
          id: now.microsecondsSinceEpoch.toString(),
          type: difference > 0 ? TransactionType.income : TransactionType.expense,
          amount: difference.abs(),
          category: 'Balance Adjustment',
          accountId: widget.initialId!,
          note: '',
          date: now,
        ));
      }
    }

    await walletRepo.add(Wallet(
      id: widget.initialId ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: _nameCtrl.text,
      type: WalletType.values.byName(_type),
      balance: balance,
      includeInTotal: _includeInTotal,
    ));
    if (mounted) context.pop(true);
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
              Text(widget.initialName != null ? 'Edit Wallet' : 'Add Wallet', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.onSurface)),
            ]),
          ),
          Expanded(child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 120),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Amount
              Center(child: GestureDetector(
                onTap: () => setState(() => _showNumberPad = true),
                child: Column(children: [
                  Text('ENTER AMOUNT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                      letterSpacing: 2, color: AppTheme.onSurfaceVariant.withOpacity(0.6))),
                  const SizedBox(height: 8),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Text('RM', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: AppTheme.secondary)),
                    const SizedBox(width: 8),
                    Text(
                      _amount.isEmpty ? '0.00' : _amount,
                      style: TextStyle(
                        fontSize: 56,
                        fontWeight: FontWeight.w800,
                        color: _amount.isEmpty ? const Color(0xFFCDD0E0) : AppTheme.primary,
                      ),
                    ),
                  ]),
                ]),
              )),
              const SizedBox(height: 32),
              // Account Name
              const Text('ACCOUNT NAME', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                  letterSpacing: 1.5, color: AppTheme.onSurfaceVariant)),
              const SizedBox(height: 8),
              TextField(
                controller: _nameCtrl,
                decoration: InputDecoration(
                  hintText: 'e.g. Personal Savings',
                  hintStyle: const TextStyle(color: Color(0xFFB0B5C8)),
                  filled: true,
                  fillColor: AppTheme.surfaceContainerLow,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                ),
              ),
              const SizedBox(height: 24),
              // Account Type
              const Text('ACCOUNT TYPE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                  letterSpacing: 1.5, color: AppTheme.onSurfaceVariant)),
              const SizedBox(height: 12),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.9,
                children: _types.map((t) {
                  final sel = _type == t['id'];
                  return GestureDetector(
                    onTap: () => setState(() => _type = t['id'] as String),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                        color: sel ? AppTheme.primary : Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: sel
                            ? [BoxShadow(color: AppTheme.primary.withOpacity(0.3), blurRadius: 16, offset: const Offset(0, 8))]
                            : [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8)],
                      ),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Container(
                          width: 48, height: 48,
                          decoration: BoxDecoration(
                            color: sel ? Colors.white.withOpacity(0.2) : AppTheme.surfaceContainerLow,
                            shape: BoxShape.circle,
                          ),
                          child: Center(child: Text(t['icon'] as String, style: const TextStyle(fontSize: 22))),
                        ),
                        const SizedBox(height: 8),
                        Text(t['label'] as String, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                            color: sel ? Colors.white : AppTheme.primary)),
                      ]),
                    ),
                  );
                }).toList(),
              ),
            ]),
          )),
          // Bottom
          if (_showNumberPad)
            GestureDetector(
              onVerticalDragEnd: (d) {
                if (d.primaryVelocity != null && d.primaryVelocity! > 300) {
                  setState(() => _showNumberPad = false);
                }
              },
              child: _NumberPad(amount: _amount, onKey: _onKey, onDone: () {
                setState(() => _showNumberPad = false);
              }),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8)]),
                  child: Row(children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Include in Total Balance', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.primary)),
                      const SizedBox(height: 2),
                      Text('Value will be calculated in global net worth',
                        style: TextStyle(fontSize: 10, color: AppTheme.onSurfaceVariant)),
                    ])),
                    Switch(value: _includeInTotal, onChanged: (v) => setState(() => _includeInTotal = v),
                      activeColor: AppTheme.secondary),
                  ]),
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: _save,
                  child: Container(
                    height: 56, width: double.infinity,
                    decoration: BoxDecoration(color: AppTheme.primary, borderRadius: BorderRadius.circular(24),
                      boxShadow: [BoxShadow(color: AppTheme.primary.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 8))]),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(widget.initialName != null ? 'Save Changes' : 'Add Account', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                      const SizedBox(width: 8),
                      const Icon(Icons.chevron_right_rounded, color: Colors.white),
                    ]),
                  ),
                ),
              ]),
            ),
        ]),
      ),
    );
  }
}

class _NumberPad extends StatelessWidget {
  final String amount;
  final void Function(String) onKey;
  final VoidCallback onDone;
  const _NumberPad({required this.amount, required this.onKey, required this.onDone});

  @override
  Widget build(BuildContext context) {
    final keys = [
      ['7','8','9','Empty'],
      ['4','5','6','-'],
      ['1','2','3','+'],
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
        Center(child: Container(
          width: 48, height: 5,
          decoration: BoxDecoration(
            color: AppTheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(3),
          ),
        )),
        const SizedBox(height: 16),
        ...keys.map((row) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: row.map((k) {
            final isOp = ['Empty','-','+','='].contains(k);
            final isEquals = k == '=';
            return Expanded(child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: GestureDetector(
                onTap: () => onKey(k == '⌫' ? 'backspace' : k == 'Empty' ? 'empty' : k),
                child: Container(
                  height: 50,
                  decoration: BoxDecoration(
                    color: isEquals ? AppTheme.primary : (isOp ? const Color(0xFFE4EBEC) : const Color(0xFFF8F9FB)),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Center(child: k == '⌫'
                    ? Icon(Icons.backspace_outlined, size: 22, color: isEquals ? Colors.white : AppTheme.onSurface)
                    : Text(k, style: TextStyle(fontSize: isOp ? 18 : 22, fontWeight: FontWeight.w600, color: isEquals ? Colors.white : AppTheme.onSurface))),
                ),
              ),
            ));
          }).toList()),
        )),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: onDone,
          child: Container(
            height: 56, width: double.infinity,
            decoration: BoxDecoration(color: AppTheme.primary, borderRadius: BorderRadius.circular(24),
              boxShadow: [BoxShadow(color: AppTheme.primary.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 8))]),
            child: const Center(child: Text('Done', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white))),
          ),
        ),
      ]),
    );
  }
}
