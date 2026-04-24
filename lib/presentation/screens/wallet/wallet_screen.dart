import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/models/wallet.dart';
import '../../providers/app_providers.dart';

class WalletScreen extends ConsumerWidget {
  const WalletScreen({super.key});

  static const _typeIcons = {
    'bank': Icons.account_balance_rounded,
    'savings': Icons.savings_rounded,
    'credit': Icons.credit_card_rounded,
    'crypto': Icons.currency_bitcoin_rounded,
    'cash': Icons.payments_rounded,
    'other': Icons.account_balance_wallet_rounded,
  };

  static const _typeColors = {
    'bank': AppTheme.primary,
    'savings': AppTheme.primary,
    'credit': AppTheme.secondary,
    'crypto': Color(0xFF7C3AED),
    'cash': AppTheme.primary,
    'other': AppTheme.primary,
  };

  static const _typeLabels = {
    'bank': 'Bank Accounts', 'savings': 'Savings', 'credit': 'Credit Cards',
    'crypto': 'Crypto', 'cash': 'Cash', 'other': 'E-Wallets',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallets = ref.watch(walletsProvider).valueOrNull ?? [];
    final total = wallets.where((w) => w.includeInTotal).fold(0.0, (s, w) => s + w.balance);

    // Group by type
    final Map<String, List<Wallet>> grouped = {};
    for (final w in wallets) {
      grouped.putIfAbsent(w.type.name, () => []).add(w);
    }

    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 100),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Wallets', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppTheme.primary)),
                Container(padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(50),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)]),
                  child: const Icon(Icons.notifications_none_rounded, size: 20, color: AppTheme.primary)),
              ]),
            ),
            // Hero card
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF00113A), Color(0xFF0D2260)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(32),
                  boxShadow: [BoxShadow(color: const Color(0xFF00113A).withOpacity(0.3), blurRadius: 30, offset: const Offset(0, 12))],
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Total Combined Balance', style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.6),
                          fontWeight: FontWeight.w800, letterSpacing: 1.5)),
                      const SizedBox(height: 4),
                      Text('RM${total.toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: Colors.white)),
                    ]),
                  ]),
                  Divider(color: Colors.white.withOpacity(0.1), height: 32),
                  Row(children: [
                    Expanded(child: GestureDetector(
                      onTap: () => context.push('/add-wallet'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(color: AppTheme.secondary, borderRadius: BorderRadius.circular(14),
                          boxShadow: [BoxShadow(color: AppTheme.secondary.withOpacity(0.4), blurRadius: 12)]),
                        child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.add_circle_outline_rounded, color: Colors.white, size: 18),
                          SizedBox(width: 8),
                          Text('Add Wallet', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                        ]),
                      ),
                    )),
                    const SizedBox(width: 12),
                    Expanded(child: GestureDetector(
                      onTap: () => context.push('/transfer'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white.withOpacity(0.2))),
                        child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.send_rounded, color: Colors.white, size: 18),
                          SizedBox(width: 8),
                          Text('Transfer', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                        ]),
                      ),
                    )),
                  ]),
                ]),
              ),
            ),
            const SizedBox(height: 24),
            if (wallets.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: Text('No wallets yet. Tap Add Wallet to get started.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.onSurfaceVariant))),
              )
            else
              ...grouped.entries.map((entry) {
                final groupTotal = entry.value.fold(0.0, (s, w) => s + w.balance);
                return Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 16)]),
                    child: Column(children: [
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Text(_typeLabels[entry.key] ?? entry.key,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.primary)),
                        Text('RM${groupTotal.toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 14, color: AppTheme.onSurfaceVariant)),
                      ]),
                      const SizedBox(height: 20),
                      ...entry.value.map((w) => Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: GestureDetector(
                          onTap: () => context.push('/wallet-account',
                            extra: {'id': w.id, 'name': w.name, 'type': w.type.name, 'balance': w.balance, 'includeInTotal': w.includeInTotal}),
                          child: Row(children: [
                            Container(width: 48, height: 48,
                              decoration: BoxDecoration(color: AppTheme.surfaceContainerLow, borderRadius: BorderRadius.circular(14)),
                              child: Icon(_typeIcons[w.type.name] ?? Icons.account_balance_wallet_rounded,
                                color: _typeColors[w.type.name] ?? AppTheme.primary, size: 24)),
                            const SizedBox(width: 16),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(w.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.onSurface)),
                              Text(w.type.name.toUpperCase(),
                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                                    color: AppTheme.onSurfaceVariant, letterSpacing: 0.5)),
                            ])),
                            Text('RM${w.balance.toStringAsFixed(2)}',
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.primary)),
                          ]),
                        ),
                      )),
                    ]),
                  ),
                );
              }),
          ]),
        ),
      ),
    );
  }
}
