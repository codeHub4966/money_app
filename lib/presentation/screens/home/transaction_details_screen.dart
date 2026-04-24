import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/models/transaction.dart';
import '../../providers/app_providers.dart';

class TransactionDetailsScreen extends ConsumerWidget {
  final Transaction? transaction;
  const TransactionDetailsScreen({super.key, this.transaction});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch live from provider so edits reflect immediately
    final all = ref.watch(transactionsProvider).valueOrNull ?? [];
    final live = transaction != null
        ? all.where((t) => t.id == transaction!.id).firstOrNull ?? transaction
        : transaction;
    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: SafeArea(child: Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Row(children: [
            IconButton(icon: const Icon(Icons.close_rounded, color: AppTheme.onSurfaceVariant),
                onPressed: () => context.pop()),
            const Expanded(child: Text('Transaction Details', textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppTheme.primary))),
            const SizedBox(width: 48),
          ]),
        ),
        Expanded(child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 120),
          child: _ReceiptCard(transaction: live),
        )),
        Padding(
          padding: const EdgeInsets.only(bottom: 32),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _ActionBtn(
              icon: Icons.edit_outlined,
              color: Colors.orange,
              onTap: () => context.push('/edit-transaction', extra: live),
            ),
            const SizedBox(width: 32),
            _ActionBtn(
              icon: Icons.delete_outline_rounded,
              color: Colors.red,
              onTap: () async {
                if (transaction == null) return;
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Delete Transaction'),
                    content: const Text('Are you sure you want to delete this transaction?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                      TextButton(onPressed: () => Navigator.pop(context, true),
                          child: const Text('Delete', style: TextStyle(color: Colors.red))),
                    ],
                  ),
                );
                if (confirm == true && context.mounted) {
                  await ref.read(transactionRepositoryProvider).delete(transaction!.id);
                  if (context.mounted) context.pop();
                }
              },
            ),
          ]),
        ),
      ])),
    );
  }
}

class _ReceiptCard extends ConsumerWidget {
  final Transaction? transaction;
  const _ReceiptCard({this.transaction});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allCats = ref.watch(categoriesProvider);
    final emojiMap = <String, String>{};
    for (final cats in allCats.values) {
      for (final c in cats) emojiMap[c.id] = c.emoji;
    }
    final emoji = transaction != null ? emojiMap[transaction!.category] : null;

    final isIncome = transaction?.type == TransactionType.income;
    final amountColor = isIncome ? const Color(0xFF14B8A6) : AppTheme.error;
    final amountStr = isIncome
        ? '+RM${transaction?.amount.toStringAsFixed(2) ?? '100.00'}'
        : '-RM${transaction?.amount.toStringAsFixed(2) ?? '100.00'}';

    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 16)]),
      child: Column(children: [
        const SizedBox(height: 32),
        // Icon + category
        Column(children: [
          Container(width: 72, height: 72, decoration: BoxDecoration(
              color: isIncome ? const Color(0xFFEFFFF4) : const Color(0xFFFFEDED),
              shape: BoxShape.circle),
            child: Center(
              child: emoji != null
                  ? Text(emoji, style: const TextStyle(fontSize: 34))
                  : Icon(Icons.receipt_rounded, size: 32,
                      color: isIncome ? const Color(0xFF14B8A6) : AppTheme.error),
            )),
          const SizedBox(height: 12),
          Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(color: AppTheme.surfaceContainerLow, borderRadius: BorderRadius.circular(20)),
            child: Text(transaction?.category ?? 'Category',
              style: const TextStyle(fontSize: 14, color: AppTheme.onSurfaceVariant))),
        ]),
        const SizedBox(height: 24),
        // Dashed divider with cutouts
        Row(children: [
          Transform.translate(offset: const Offset(-12, 0),
            child: Container(width: 24, height: 24, decoration: BoxDecoration(
                color: AppTheme.surface, shape: BoxShape.circle,
                border: Border.all(color: Colors.grey.withOpacity(0.2))))),
          Expanded(child: LayoutBuilder(builder: (_, c) => CustomPaint(
            size: Size(c.maxWidth, 1),
            painter: _DashedLinePainter(),
          ))),
          Transform.translate(offset: const Offset(12, 0),
            child: Container(width: 24, height: 24, decoration: BoxDecoration(
                color: AppTheme.surface, shape: BoxShape.circle,
                border: Border.all(color: Colors.grey.withOpacity(0.2))))),
        ]),
        const SizedBox(height: 24),
        // Details
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(children: [
            _DetailRow(icon: Icons.attach_money_rounded, label: 'Amount',
              value: Text(amountStr, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: amountColor))),
            const SizedBox(height: 20),
            _DetailRow(icon: Icons.grid_view_rounded, label: 'Type',
              value: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(color: amountColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                child: Text(transaction?.type.name ?? 'income',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: amountColor)))),
            const SizedBox(height: 20),
            _DetailRow(icon: Icons.account_balance_wallet_rounded, label: 'Account',
              value: Text(transaction?.accountId ?? 'Cash',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.onSurface))),
            const SizedBox(height: 20),
            _DetailRow(icon: Icons.calendar_today_rounded, label: 'Date',
              value: Text(_formatDate(transaction?.date ?? DateTime.now()),
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.onSurface))),
            const SizedBox(height: 20),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.description_outlined, size: 20, color: AppTheme.onSurfaceVariant),
                const SizedBox(width: 12),
                const Text('Note', style: TextStyle(fontSize: 15, color: AppTheme.onSurfaceVariant)),
              ]),
              const SizedBox(height: 8),
              Padding(padding: const EdgeInsets.only(left: 32),
                child: Text(transaction?.note ?? '',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.onSurface))),
            ]),
          ]),
        ),
        const SizedBox(height: 32),
      ]),
    );
  }

  String _formatDate(DateTime d) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    const days = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    return '${months[d.month - 1]} ${d.day}, ${d.year} (${days[d.weekday - 1]}),\n${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}';
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget value;
  const _DetailRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, size: 20, color: AppTheme.onSurfaceVariant),
    const SizedBox(width: 12),
    Text(label, style: const TextStyle(fontSize: 15, color: AppTheme.onSurfaceVariant)),
    const Spacer(),
    value,
  ]);
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _ActionBtn({required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(width: 56, height: 56,
      decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: color.withOpacity(0.2), blurRadius: 16),
          BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8)]),
      child: Icon(icon, color: color, size: 24)),
  );
}

class _DashedLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.grey.withOpacity(0.3)..strokeWidth = 1.5;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(x + 6, 0), paint);
      x += 12;
    }
  }
  @override
  bool shouldRepaint(_) => false;
}
