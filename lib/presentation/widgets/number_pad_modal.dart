import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class NumberPadModal extends StatelessWidget {
  final String amount;
  final ValueChanged<String> onAmountChanged;
  final VoidCallback onDone;
  final String? title;
  final String? subtitle;

  const NumberPadModal({
    super.key,
    required this.amount,
    required this.onAmountChanged,
    required this.onDone,
    this.title,
    this.subtitle,
  });

  void _handleKey(String key) {
    switch (key) {
      case 'backspace':
        onAmountChanged(amount.length > 1 ? amount.substring(0, amount.length - 1) : '');
      case '.':
        if (!amount.contains('.')) onAmountChanged(amount.isEmpty ? '0.' : '$amount.');
      case 'empty':
        onAmountChanged('');
      case '+/-':
      case 'x':
      case '=':
        break;
      default:
        onAmountChanged(amount == '0' ? key : '$amount$key');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      GestureDetector(
        onTap: onDone,
        child: Container(color: Colors.black.withOpacity(0.2)),
      ),
      Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          decoration: const BoxDecoration(
            color: Color(0xF2FFFFFF),
            borderRadius: BorderRadius.vertical(top: Radius.circular(40)),
            boxShadow: [BoxShadow(color: Color(0x14000000), blurRadius: 40, offset: Offset(0, -10))],
          ),
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(subtitle!, style: const TextStyle(fontSize: 13, color: AppTheme.onSurfaceVariant)),
              ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                border: Border.all(color: AppTheme.onSurfaceVariant.withOpacity(0.3), width: 2, style: BorderStyle.solid),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(children: [
                if (title != null)
                  Text(title!, style: const TextStyle(fontSize: 15, color: AppTheme.onSurfaceVariant)),
                Text(amount.isEmpty ? '0' : amount,
                  style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w700, color: AppTheme.onSurface)),
              ]),
            ),
            const SizedBox(height: 16),
            _buildGrid(),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 64,
              child: ElevatedButton(
                onPressed: onDone,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.mint,
                  foregroundColor: AppTheme.onSurface,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  elevation: 0,
                ),
                child: const Text('Done', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ),
      ),
    ]);
  }

  Widget _buildGrid() {
    const numStyle = TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: AppTheme.onSurface);
    const opStyle = TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFF4E5D78));
    final keys = [
      ('7', numStyle), ('8', numStyle), ('9', numStyle), ('Empty', opStyle),
      ('4', numStyle), ('5', numStyle), ('6', numStyle), ('×', opStyle),
      ('1', numStyle), ('2', numStyle), ('3', numStyle), ('+/-', opStyle),
      ('.', numStyle), ('0', numStyle), ('⌫', numStyle), ('=', opStyle),
    ];
    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.6,
      children: keys.map((k) {
        final isOp = k.$2 == opStyle;
        return GestureDetector(
          onTap: () {
            final key = switch (k.$1) {
              '×' => 'x',
              '⌫' => 'backspace',
              'Empty' => 'empty',
              _ => k.$1.toLowerCase(),
            };
            _handleKey(key);
          },
          child: Container(
            decoration: BoxDecoration(
              color: isOp ? const Color(0xFFE4EBEC) : const Color(0xFFF8F9FB),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
            ),
            child: Center(
              child: k.$1 == '⌫'
                ? const Icon(Icons.backspace_outlined, size: 22, color: AppTheme.onSurface)
                : Text(k.$1, style: k.$2),
            ),
          ),
        );
      }).toList(),
    );
  }
}
