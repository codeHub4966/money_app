import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/models/transaction.dart';
import '../../../domain/models/wallet.dart';
import '../../../domain/models/app_category.dart';
import '../../providers/app_providers.dart';

// Fixed colour palette cycled per category index
const _kBgColors = [
  Color(0xFFFFF0E8), Color(0xFFF5F0FF), Color(0xFFEFF4FF), Color(0xFFFFF0F7),
  Color(0xFFEFFFF4), Color(0xFFFFFBEB), Color(0xFFF3F4F6), Color(0xFFECFEFF),
  Color(0xFFFEF9C3), Color(0xFFFFEDED), Color(0xFFE0F2FE), Color(0xFFF0FDF4),
];

class AddTransactionScreen extends ConsumerStatefulWidget {
  final Transaction? transaction;
  const AddTransactionScreen({super.key, this.transaction});

  @override
  ConsumerState<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends ConsumerState<AddTransactionScreen> {
  late TransactionType _type;
  late String _account;
  late String _category;
  late String _amount;
  late final TextEditingController _noteCtrl;
  late DateTime _date;
  bool _saving = false;
  bool _showNumberPad = false;

  @override
  void initState() {
    super.initState();
    final t = widget.transaction;
    _type = t?.type ?? TransactionType.expense;

    // Default to the transaction's account, or pick the first real wallet
    if (t?.accountId != null) {
      _account = t!.accountId;
    } else {
      final wallets = ref.read(walletsProvider).valueOrNull ?? [];
      final orderNotifier = ref.read(walletOrderProvider.notifier);
      final sorted = orderNotifier.sort(wallets, (w) => w.id);
      _account = sorted.isNotEmpty ? sorted.first.id : '';
    }

    _amount = t != null ? t.amount.toStringAsFixed(2) : '';
    _noteCtrl = TextEditingController(text: t?.note ?? '');
    _date = t?.date ?? DateTime.now();

    // Set initial category: use transaction's category or first in list
    if (t?.category != null) {
      _category = t!.category;
    } else {
      final key = _type == TransactionType.income ? 'income' : 'expense';
      final cats = ref.read(categoriesProvider)[key] ?? [];
      _category = cats.isNotEmpty ? cats.first.label : '';
    }
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

  List<AppCategory> _cats(Map<String, List<AppCategory>> all) =>
      all[_type == TransactionType.income ? 'income' : 'expense'] ?? [];

  Future<void> _save() async {
    final amount = double.tryParse(_amount);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a valid amount.')));
      return;
    }

    // Block save if no wallet selected
    final wallets = ref.read(walletsProvider).valueOrNull ?? [];
    final wallet = wallets.where((w) => w.id == _account).firstOrNull;
    if (wallet == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a wallet first.')),
      );
      return;
    }

    setState(() => _saving = true);
    final txRepo = ref.read(transactionRepositoryProvider);
    final walletRepo = ref.read(walletRepositoryProvider);

    double newBalance = wallet.balance;
    if (widget.transaction != null) {
      final old = widget.transaction!;
      newBalance += old.type == TransactionType.income ? -old.amount : old.amount;
    }
    newBalance += _type == TransactionType.income ? amount : -amount;

    await txRepo.add(Transaction(
      id: widget.transaction?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      type: _type,
      amount: amount,
      category: _category,
      accountId: _account,
      note: _noteCtrl.text.isEmpty ? null : _noteCtrl.text,
      date: _date,
    ));

    await walletRepo.add(Wallet(
        id: wallet.id, name: wallet.name, type: wallet.type,
        balance: newBalance, includeInTotal: wallet.includeInTotal));

    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final allCats = ref.watch(categoriesProvider);
    final cats = _cats(allCats);

    // Ensure _category is valid for the current type
    if (cats.isNotEmpty && !cats.any((c) => c.label == _category)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _category = cats.first.label);
      });
    }

    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: SafeArea(
        child: Column(children: [
          _buildHeader(),
          Expanded(child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 120),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _buildTypeToggle(allCats),
              const SizedBox(height: 24),
              _buildAmountInput(),
              const SizedBox(height: 24),
              _buildSectionLabel('ACCOUNT'),
              const SizedBox(height: 12),
              _buildAccountSelector(),
              const SizedBox(height: 24),
              _buildSectionLabel('CATEGORY'),
              const SizedBox(height: 12),
              _buildCategoryGrid(cats),
              const SizedBox(height: 24),
              _buildSectionLabel('DATE'),
              const SizedBox(height: 12),
              _buildDateRow(),
              const SizedBox(height: 24),
              _buildSectionLabel('NOTE'),
              const SizedBox(height: 12),
              _buildNoteField(),
              const SizedBox(height: 16),
              _buildAttachmentRow(),
            ]),
          )),
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
            _buildConfirmButton(),
        ]),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(children: [
        IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.secondary),
          onPressed: () => context.pop(),
        ),
        const SizedBox(width: 8),
        Text(widget.transaction != null ? 'Edit Transaction' : 'Add Transaction',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppTheme.onSurface)),
        const Spacer(),
        GestureDetector(
          onTap: _save,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(color: AppTheme.primary, borderRadius: BorderRadius.circular(20)),
            child: const Text('Save',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
          ),
        ),
      ]),
    );
  }

  Widget _buildTypeToggle(Map<String, List<AppCategory>> allCats) {
    const types = [TransactionType.expense, TransactionType.income];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
          color: AppTheme.surfaceContainerLow, borderRadius: BorderRadius.circular(50)),
      child: Row(children: types.map((t) {
        final active = _type == t;
        return Expanded(child: GestureDetector(
          onTap: () {
            final key = t == TransactionType.income ? 'income' : 'expense';
            final cats = allCats[key] ?? [];
            setState(() {
              _type = t;
              _category = cats.isNotEmpty ? cats.first.label : '';
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: active ? AppTheme.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(50),
            ),
            child: Text(t.name[0].toUpperCase() + t.name.substring(1),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                  color: active ? Colors.white : AppTheme.onSurfaceVariant)),
          ),
        ));
      }).toList()),
    );
  }

  Widget _buildAmountInput() {
    return GestureDetector(
      onTap: () => setState(() => _showNumberPad = true),
      child: Column(children: [
        Text('ENTER AMOUNT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
            letterSpacing: 2, color: AppTheme.onSurfaceVariant.withValues(alpha: 0.7))),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Text('RM', style: TextStyle(fontSize: 36, fontWeight: FontWeight.w700, color: AppTheme.secondary)),
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
    );
  }

  Widget _buildSectionLabel(String label) {
    return Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
        letterSpacing: 1, color: AppTheme.onSurfaceVariant));
  }

  Widget _buildAccountSelector() {
    final rawWallets = ref.watch(walletsProvider).valueOrNull ?? <Wallet>[];
    final orderNotifier = ref.watch(walletOrderProvider.notifier);
    final wallets = orderNotifier.sort(rawWallets, (w) => w.id);

    // Resolve the display name/emoji for the selected account
    final selected = wallets.where((w) => w.id == _account).firstOrNull;
    final label = selected?.name ?? 'Select Account';
    final emoji = _walletEmoji(selected?.type);

    return GestureDetector(
      onTap: () => _showAccountSheet(wallets),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected != null
                ? AppTheme.secondary.withValues(alpha: 0.4)
                : AppTheme.surfaceContainerLow,
            width: selected != null ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8)
          ],
        ),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: selected != null
                  ? AppTheme.secondary.withValues(alpha: 0.1)
                  : AppTheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(emoji, style: const TextStyle(fontSize: 18)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: selected != null ? AppTheme.onSurface : AppTheme.onSurfaceVariant,
              ),
            ),
          ),
          const Icon(Icons.keyboard_arrow_down_rounded,
              color: AppTheme.onSurfaceVariant, size: 22),
        ]),
      ),
    );
  }

  String _walletEmoji(WalletType? type) {
    switch (type) {
      case WalletType.bank:    return '🏦';
      case WalletType.credit:  return '💳';
      case WalletType.cash:    return '💵';
      case WalletType.crypto:  return '🪙';
      case WalletType.savings: return '🐷';
      case WalletType.other:   return '📂';
      default:                 return '👛';
    }
  }

  void _showAccountSheet(List<Wallet> wallets) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _AccountSheet(
        initialSelectedId: _account,
        walletEmoji: _walletEmoji,
        onSelect: (id) => setState(() => _account = id),
      ),
    );
  }

  Widget _buildCategoryGrid(List<AppCategory> cats) {
    const maxVisible = 8; // 2 rows × 4 cols
    final needMore = cats.length > maxVisible;
    // If we need a "More" button, show 7 real cats + 1 More = 8 cells
    final visible = needMore ? cats.take(maxVisible - 1).toList() : cats;
    final itemCount = visible.length + (needMore ? 1 : 0);

    return GridView.builder(
      itemCount: itemCount,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.85,
      ),
      itemBuilder: (_, i) {
        // "More" card
        if (needMore && i == visible.length) {
          return GestureDetector(
            onTap: () => _showMoreSheet(cats, cats.skip(maxVisible - 1).toList()),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03), blurRadius: 8)],
              ),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                      color: AppTheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.more_horiz_rounded,
                      size: 22, color: AppTheme.onSurfaceVariant)),
                const SizedBox(height: 6),
                const Text('More',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                        color: AppTheme.onSurface)),
              ]),
            ),
          );
        }

        final cat = visible[i];
        final selected = _category == cat.label;
        final bg = _kBgColors[i % _kBgColors.length];
        return GestureDetector(
          onTap: () => setState(() => _category = cat.label),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: selected
                  ? Border.all(
                      color: AppTheme.secondary.withValues(alpha: 0.4),
                      width: 1.5)
                  : null,
              boxShadow: [BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03), blurRadius: 8)],
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                      color: bg, borderRadius: BorderRadius.circular(12)),
                  child: Center(
                      child: Text(cat.emoji,
                          style: const TextStyle(fontSize: 20)))),
              const SizedBox(height: 6),
              Text(cat.label,
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: selected ? AppTheme.primary : AppTheme.onSurface),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ]),
          ),
        );
      },
    );
  }

  void _showMoreSheet(List<AppCategory> allCats, List<AppCategory> moreCats) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Center(child: Container(width: 48, height: 5,
                decoration: BoxDecoration(
                    color: AppTheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(3)))),
            const SizedBox(height: 16),
            const Text('More Categories',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700,
                    color: AppTheme.onSurface)),
            const SizedBox(height: 16),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: moreCats.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.85,
              ),
              itemBuilder: (_, i) {
                final cat = moreCats[i];
                final catIndex = allCats.indexOf(cat);
                final selected = _category == cat.label;
                final bg = _kBgColors[catIndex % _kBgColors.length];
                return GestureDetector(
                  onTap: () {
                    setState(() => _category = cat.label);
                    Navigator.pop(ctx);
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: selected
                          ? Border.all(
                              color: AppTheme.secondary.withValues(alpha: 0.4),
                              width: 1.5)
                          : null,
                      boxShadow: [BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 8)],
                    ),
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                              width: 40, height: 40,
                              decoration: BoxDecoration(
                                  color: bg,
                                  borderRadius: BorderRadius.circular(12)),
                              child: Center(
                                  child: Text(cat.emoji,
                                      style:
                                          const TextStyle(fontSize: 20)))),
                          const SizedBox(height: 6),
                          Text(cat.label,
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: selected
                                      ? AppTheme.primary
                                      : AppTheme.onSurface),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ]),
                  ),
                );
              },
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildDateRow() {
    return GestureDetector(
      onTap: () async {
        final picked = await showDatePicker(context: context,
            initialDate: _date, firstDate: DateTime(2020), lastDate: DateTime(2030));
        if (picked != null) setState(() => _date = picked);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
            color: AppTheme.surfaceContainerLow, borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          const Icon(Icons.calendar_today_rounded, size: 20, color: AppTheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Text('Today, ${_date.day} ${_monthName(_date.month)} ${_date.year}',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.onSurface)),
        ]),
      ),
    );
  }

  Widget _buildNoteField() {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8)]),
      child: TextField(
        controller: _noteCtrl,
        maxLines: 3,
        decoration: const InputDecoration(
          hintText: 'Add a description or receipt details...',
          hintStyle: TextStyle(color: Color(0xFFB0B5C8), fontSize: 14),
          border: InputBorder.none,
          contentPadding: EdgeInsets.all(16),
        ),
      ),
    );
  }

  Widget _buildAttachmentRow() {
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      _AttachBtn(icon: Icons.camera_alt_outlined, label: 'Receipt'),
    ]);
  }

  Widget _buildConfirmButton() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
            colors: [AppTheme.surface.withValues(alpha: 0), AppTheme.surface],
            begin: Alignment.topCenter, end: Alignment.bottomCenter),
      ),
      child: GestureDetector(
        onTap: _saving ? null : _save,
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            color: AppTheme.primary,
            borderRadius: BorderRadius.circular(50),
            boxShadow: [BoxShadow(
                color: AppTheme.primary.withValues(alpha: 0.3),
                blurRadius: 20, offset: const Offset(0, 8))],
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.check_circle_outline_rounded, color: Colors.white, size: 22),
            const SizedBox(width: 8),
            Text(_saving ? 'Processing...' : 'Confirm Transaction',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
          ]),
        ),
      ),
    );
  }

  String _monthName(int m) =>
      const ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][m - 1];
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

class _AccountSheetTile extends StatelessWidget {
  final Wallet wallet;
  final String emoji;
  final bool isSelected;
  final bool isDefault;
  final VoidCallback onTap;
  const _AccountSheetTile({
    super.key,
    required this.wallet,
    required this.emoji,
    required this.isSelected,
    this.isDefault = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.secondary.withValues(alpha: 0.06)
              : AppTheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: isSelected
              ? Border.all(color: AppTheme.secondary, width: 1.5)
              : null,
        ),
        child: Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: isSelected
                  ? AppTheme.secondary.withValues(alpha: 0.12)
                  : Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(child: Text(emoji, style: const TextStyle(fontSize: 20))),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(wallet.name,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: isSelected ? AppTheme.secondary : AppTheme.onSurface)),
              if (isDefault) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.secondary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('Default',
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
                          color: AppTheme.secondary, letterSpacing: 0.5)),
                ),
              ],
            ]),
            Text('RM ${wallet.balance.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 12, color: AppTheme.onSurfaceVariant)),
          ])),
          if (isSelected)
            Container(
              width: 24, height: 24,
              decoration: const BoxDecoration(
                  color: AppTheme.secondary, shape: BoxShape.circle),
              child: const Icon(Icons.check, color: Colors.white, size: 14),
            )
          else
            const Icon(Icons.drag_handle_rounded,
                color: AppTheme.onSurfaceVariant, size: 20),
        ]),
      ),
    );
  }
}

class _AttachBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  const _AttachBtn({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, size: 20, color: AppTheme.onSurfaceVariant),
      const SizedBox(width: 6),
      Text(label, style: const TextStyle(
          fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.onSurfaceVariant)),
    ]);
  }
}

// ── Account selection bottom sheet — watches providers directly for live reorder ──

class _AccountSheet extends ConsumerStatefulWidget {
  final String initialSelectedId;
  final String Function(WalletType?) walletEmoji;
  final void Function(String) onSelect;
  const _AccountSheet({
    required this.initialSelectedId,
    required this.walletEmoji,
    required this.onSelect,
  });

  @override
  ConsumerState<_AccountSheet> createState() => _AccountSheetState();
}

class _AccountSheetState extends ConsumerState<_AccountSheet> {
  late String _selectedId;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.initialSelectedId;
  }

  @override
  Widget build(BuildContext context) {
    final rawWallets = ref.watch(walletsProvider).valueOrNull ?? <Wallet>[];
    final orderNotifier = ref.watch(walletOrderProvider.notifier);
    // Use a local mutable list that stays in sync with the provider order
    final wallets = orderNotifier.sort(rawWallets, (w) => w.id);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Center(child: Container(
          width: 48, height: 5,
          decoration: BoxDecoration(
            color: AppTheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(3),
          ),
        )),
        const SizedBox(height: 16),
        const Text('Select Account',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700,
                color: AppTheme.onSurface)),
        const SizedBox(height: 4),
        Text('Long-press to reorder',
            style: TextStyle(fontSize: 12,
                color: AppTheme.onSurfaceVariant.withValues(alpha: 0.7))),
        const SizedBox(height: 16),
        if (wallets.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text('No wallets found. Add one in the Wallet tab.',
                style: TextStyle(color: AppTheme.onSurfaceVariant),
                textAlign: TextAlign.center),
          )
        else
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.5,
            ),
            child: ReorderableListView.builder(
              shrinkWrap: true,
              itemCount: wallets.length,
              onReorder: (oldIndex, newIndex) {
                if (newIndex > oldIndex) newIndex--;
                final reordered = wallets.toList();
                final item = reordered.removeAt(oldIndex);
                reordered.insert(newIndex, item);
                ref.read(walletOrderProvider.notifier)
                    .saveOrder(reordered.map((w) => w.id).toList());
                // setState triggers rebuild which re-reads provider
                setState(() {});
              },
              itemBuilder: (_, i) {
                final w = wallets[i];
                final isSelected = _selectedId == w.id;
                final isDefault = i == 0;
                return _AccountSheetTile(
                  key: ValueKey(w.id),
                  wallet: w,
                  emoji: widget.walletEmoji(w.type),
                  isSelected: isSelected,
                  isDefault: isDefault,
                  onTap: () {
                    _selectedId = w.id;
                    widget.onSelect(w.id);
                    Navigator.pop(context);
                  },
                );
              },
            ),
          ),
      ]),
    );
  }
}
