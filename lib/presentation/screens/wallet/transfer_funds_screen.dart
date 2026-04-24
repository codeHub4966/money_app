import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/models/wallet.dart';
import '../../../domain/models/transaction.dart';
import '../../providers/app_providers.dart';

class TransferFundsScreen extends ConsumerStatefulWidget {
  const TransferFundsScreen({super.key});

  @override
  ConsumerState<TransferFundsScreen> createState() => _State();
}

class _State extends ConsumerState<TransferFundsScreen> {
  String? _fromId;
  String? _toId;
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  DateTime _date = DateTime.now();

  Future<void> _transfer(List<Wallet> wallets) async {
    final amount = double.tryParse(_amountCtrl.text);
    if (amount == null || amount <= 0 || _fromId == null || _toId == null || _fromId == _toId) return;
    final from = wallets.firstWhere((w) => w.id == _fromId);
    final to = wallets.firstWhere((w) => w.id == _toId);
    if (from.balance < amount) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Insufficient balance.')));
      return;
    }
    final walletRepo = ref.read(walletRepositoryProvider);
    final txRepo = ref.read(transactionRepositoryProvider);
    final now = DateTime.now();
    final note = _noteCtrl.text.isEmpty ? 'Transfer to ${to.name}' : _noteCtrl.text;
    await walletRepo.add(Wallet(id: from.id, name: from.name, type: from.type, balance: from.balance - amount, includeInTotal: from.includeInTotal));
    await walletRepo.add(Wallet(id: to.id, name: to.name, type: to.type, balance: to.balance + amount, includeInTotal: to.includeInTotal));
    await txRepo.add(Transaction(
      id: '${now.microsecondsSinceEpoch}_out',
      type: TransactionType.expense,
      amount: amount,
      category: 'Transfer',
      accountId: from.id,
      note: note,
      date: now,
    ));
    await txRepo.add(Transaction(
      id: '${now.microsecondsSinceEpoch}_in',
      type: TransactionType.income,
      amount: amount,
      category: 'Transfer',
      accountId: to.id,
      note: 'Transfer from ${from.name}',
      date: now,
    ));
    if (mounted) context.pop();
  }

  void _swap() => setState(() { final t = _fromId; _fromId = _toId; _toId = t; });

  void _showPicker(bool isFrom, List<Wallet> wallets) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _WalletSheet(
        wallets: wallets,
        selectedId: isFrom ? _fromId : _toId,
        onSelect: (id) => setState(() { if (isFrom) _fromId = id; else _toId = id; }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wallets = ref.watch(walletsProvider).valueOrNull ?? [];

    Wallet? from = wallets.where((w) => w.id == _fromId).firstOrNull;
    Wallet? to = wallets.where((w) => w.id == _toId).firstOrNull;

    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: SafeArea(child: Column(children: [
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Row(children: [
            IconButton(icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.secondary), onPressed: () => context.pop()),
            const Expanded(child: Text('Transfer Funds', textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppTheme.onSurface))),
            const Icon(Icons.history_rounded, color: AppTheme.onSurfaceVariant),
            const SizedBox(width: 12),
          ]),
        ),
        Expanded(child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 100),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // From/To cards
            Stack(children: [
              Column(children: [
                _WalletCard(label: 'FROM', wallet: from, amount: _amountCtrl.text,
                    onTap: () => _showPicker(true, wallets), onAmountTap: () {}),
                const SizedBox(height: 8),
                _WalletCard(label: 'TO', wallet: to, amount: _amountCtrl.text,
                    onTap: () => _showPicker(false, wallets), onAmountTap: () {}),
              ]),
              Positioned(left: 0, right: 0, top: 0, bottom: 0,
                child: Center(child: GestureDetector(
                  onTap: _swap,
                  child: Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(color: AppTheme.primary, shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.surface, width: 4),
                      boxShadow: [BoxShadow(color: AppTheme.primary.withOpacity(0.4), blurRadius: 12)]),
                    child: const Icon(Icons.swap_vert_rounded, color: Colors.white, size: 20),
                  ),
                ))),
            ]),
            const SizedBox(height: 24),
            // Amount input
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8)]),
              child: Row(children: [
                const Text('RM', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppTheme.secondary)),
                const SizedBox(width: 12),
                Expanded(child: TextField(
                  controller: _amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppTheme.primary),
                  decoration: const InputDecoration(
                    hintText: '0.00',
                    hintStyle: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Color(0xFFCDD0E0)),
                    border: InputBorder.none, isDense: true,
                  ),
                  onChanged: (_) => setState(() {}),
                )),
              ]),
            ),
            const SizedBox(height: 32),
            const Text('Others', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.onSurface)),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8)]),
              child: Column(children: [
                _OtherRow(icon: Icons.description_outlined, label: 'Notes',
                  child: TextField(controller: _noteCtrl,
                    decoration: const InputDecoration(hintText: 'Tap to Input', border: InputBorder.none,
                      hintStyle: TextStyle(color: Color(0xFFB0B5C8)), isDense: true),
                    style: const TextStyle(fontSize: 14, color: AppTheme.onSurface))),
                Divider(height: 1, color: AppTheme.surfaceContainerLow),
                _OtherRow(icon: Icons.calendar_today_rounded, label: 'Date',
                  child: GestureDetector(
                    onTap: () async {
                      final p = await showDatePicker(context: context,
                          initialDate: _date, firstDate: DateTime(2020), lastDate: DateTime(2030));
                      if (p != null) setState(() => _date = p);
                    },
                    child: Text('${_date.day}/${_date.month}/${_date.year}',
                      style: const TextStyle(fontSize: 14, color: AppTheme.onSurfaceVariant)),
                  )),
              ]),
            ),
          ]),
        )),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: GestureDetector(
            onTap: () => _transfer(wallets),
            child: Container(height: 56, width: double.infinity,
              decoration: BoxDecoration(color: AppTheme.primary, borderRadius: BorderRadius.circular(24),
                boxShadow: [BoxShadow(color: AppTheme.primary.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 8))]),
              child: const Center(child: Text('Transfer',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)))),
          ),
        ),
      ])),
    );
  }
}

class _WalletCard extends StatelessWidget {
  final String label;
  final Wallet? wallet;
  final String amount;
  final VoidCallback onTap, onAmountTap;
  const _WalletCard({required this.label, this.wallet, required this.amount, required this.onTap, required this.onAmountTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8)]),
        child: Row(children: [
          Container(width: 48, height: 48, decoration: BoxDecoration(
              color: wallet != null ? AppTheme.secondary.withOpacity(0.1) : Colors.red.withOpacity(0.1),
              shape: BoxShape.circle),
            child: Icon(wallet != null ? Icons.account_balance_wallet_rounded : Icons.help_outline_rounded,
              color: wallet != null ? AppTheme.secondary : Colors.red, size: 24)),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                letterSpacing: 2, color: AppTheme.onSurfaceVariant)),
            const SizedBox(height: 4),
            Text(wallet?.name ?? 'Not selected',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppTheme.onSurface)),
          ])),
          if (wallet != null)
            Text('RM${amount.isEmpty ? '0' : amount}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.primary)),
        ]),
      ),
    );
  }
}

class _OtherRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget child;
  const _OtherRow({required this.icon, required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(children: [
        Container(width: 40, height: 40, decoration: BoxDecoration(
            color: AppTheme.secondary.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, size: 20, color: AppTheme.secondary)),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.onSurface)),
          const SizedBox(height: 4),
          child,
        ])),
      ]),
    );
  }
}

class _WalletSheet extends StatelessWidget {
  final List<Wallet> wallets;
  final String? selectedId;
  final ValueChanged<String?> onSelect;
  const _WalletSheet({required this.wallets, this.selectedId, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(40))),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width: 48, height: 5, decoration: BoxDecoration(
            color: AppTheme.surfaceContainerLow, borderRadius: BorderRadius.circular(3)))),
        const SizedBox(height: 16),
        const Text('Choose wallet', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppTheme.onSurface)),
        const SizedBox(height: 16),
        // Select None
        ListTile(
          onTap: () { onSelect(null); Navigator.pop(context); },
          leading: Container(width: 48, height: 48, decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(16)),
            child: const Icon(Icons.block_rounded, color: Colors.red)),
          title: const Text('Select None', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
        ...wallets.map((w) {
          final sel = w.id == selectedId;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: sel ? AppTheme.secondary.withOpacity(0.05) : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              border: sel ? Border.all(color: AppTheme.secondary.withOpacity(0.3)) : null,
            ),
            child: ListTile(
              onTap: () { onSelect(w.id); Navigator.pop(context); },
              leading: Container(width: 48, height: 48, decoration: BoxDecoration(
                  color: AppTheme.secondary.withOpacity(0.1), borderRadius: BorderRadius.circular(16)),
                child: const Icon(Icons.account_balance_wallet_rounded, color: AppTheme.secondary)),
              title: Text(w.name, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('Balance RM${w.balance.toStringAsFixed(0)}'),
              trailing: sel
                ? Container(width: 24, height: 24, decoration: const BoxDecoration(color: AppTheme.secondary, shape: BoxShape.circle),
                    child: const Icon(Icons.check, color: Colors.white, size: 14))
                : Container(width: 24, height: 24, decoration: BoxDecoration(
                    shape: BoxShape.circle, border: Border.all(color: AppTheme.onSurfaceVariant.withOpacity(0.4)))),
            ),
          );
        }),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(height: 52, width: double.infinity,
            decoration: BoxDecoration(color: AppTheme.surfaceContainerLow, borderRadius: BorderRadius.circular(24)),
            child: const Center(child: Text('Close', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)))),
        ),
      ]),
    );
  }
}
