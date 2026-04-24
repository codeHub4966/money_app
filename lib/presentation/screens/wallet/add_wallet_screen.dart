import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/repositories/wallet_repository.dart';
import '../../../domain/models/wallet.dart';
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
  late final TextEditingController _amountCtrl;
  late String _type;
  bool _includeInTotal = true;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialName ?? '');
    _amountCtrl = TextEditingController(text: widget.initialBalance != null ? widget.initialBalance!.toStringAsFixed(2) : '');
    _type = widget.initialType ?? 'credit';
    _includeInTotal = widget.initialIncludeInTotal ?? true;
  }

  Future<void> _save() async {
    final balance = double.tryParse(_amountCtrl.text) ?? 0;
    if (_nameCtrl.text.isEmpty) return;
    await ref.read(walletRepositoryProvider).add(Wallet(
      id: widget.initialId ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: _nameCtrl.text,
      type: WalletType.values.byName(_type),
      balance: balance,
      includeInTotal: _includeInTotal,
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
              Text(widget.initialName != null ? 'Edit Wallet' : 'Add Wallet', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.onSurface)),
            ]),
          ),
          Expanded(child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 120),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Amount
              Center(child: Column(children: [
                Text('ENTER AMOUNT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                    letterSpacing: 2, color: AppTheme.onSurfaceVariant.withOpacity(0.6))),
                const SizedBox(height: 8),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Text('RM', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: AppTheme.secondary)),
                  const SizedBox(width: 8),
                  IntrinsicWidth(child: TextField(
                    controller: _amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(fontSize: 56, fontWeight: FontWeight.w800, color: AppTheme.primary),
                    decoration: const InputDecoration(
                      hintText: '0.00',
                      hintStyle: TextStyle(fontSize: 56, fontWeight: FontWeight.w800, color: Color(0xFFCDD0E0)),
                      border: InputBorder.none,
                    ),
                  )),
                ]),
              ])),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8)]),
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
                    boxShadow: [BoxShadow(color: AppTheme.primary.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 8))]),
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
