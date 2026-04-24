import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';

class PinScreen extends StatefulWidget {
  final String title;
  final String subtitle;
  final void Function(String)? onSuccess;
  const PinScreen({super.key,
    this.title = 'Create PIN',
    this.subtitle = 'Create a 4-digit PIN for security',
    this.onSuccess});

  @override
  State<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends State<PinScreen> {
  String _pin = '';

  void _press(String d) {
    if (_pin.length >= 4) return;
    final next = _pin + d;
    setState(() => _pin = next);
    if (next.length == 4) {
      Future.delayed(const Duration(milliseconds: 150), () {
        widget.onSuccess?.call(next);
        if (mounted && widget.onSuccess == null) context.pop();
      });
    }
  }

  void _delete() => setState(() { if (_pin.isNotEmpty) _pin = _pin.substring(0, _pin.length - 1); });

  @override
  Widget build(BuildContext context) {
    return Material(
      child: Scaffold(
        backgroundColor: AppTheme.surface,
        body: SafeArea(child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(children: [
              IconButton(icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.secondary),
                  onPressed: () => context.pop()),
              const Expanded(child: Text('App PIN', textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppTheme.primary))),
              const SizedBox(width: 48),
            ]),
          ),
          Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(widget.title, style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800, color: AppTheme.onSurface)),
            const SizedBox(height: 12),
            Text(widget.subtitle, style: const TextStyle(fontSize: 16, color: AppTheme.onSurfaceVariant)),
            const SizedBox(height: 40),
            // Dot indicator
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 20)]),
              child: Row(mainAxisSize: MainAxisSize.min, children: List.generate(4, (i) => Container(
                margin: const EdgeInsets.symmetric(horizontal: 10),
                width: 16, height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < _pin.length ? AppTheme.primary : AppTheme.surfaceContainerHigh,
                ),
              ))),
            ),
            const SizedBox(height: 48),
            // Keypad
            SizedBox(width: 280, child: Column(children: [
              _row(['1','2','3']),
              const SizedBox(height: 24),
              _row(['4','5','6']),
              const SizedBox(height: 24),
              _row(['7','8','9']),
              const SizedBox(height: 24),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const SizedBox(width: 76),
                const SizedBox(width: 16),
                _DigitBtn(label: '0', onTap: () => _press('0')),
                const SizedBox(width: 16),
                _DeleteBtn(onTap: _delete),
              ]),
            ])),
          ])),
        ])),
      ),
    );
  }

  Widget _row(List<String> digits) => Row(mainAxisAlignment: MainAxisAlignment.center,
    children: digits.expand((d) => [
      _DigitBtn(label: d, onTap: () => _press(d)),
      if (d != digits.last) const SizedBox(width: 16),
    ]).toList());
}

class _DigitBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _DigitBtn({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(width: 76, height: 76,
      decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 16, offset: const Offset(0, 6))]),
      child: Center(child: Text(label, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w500, color: AppTheme.primary)))),
  );
}

class _DeleteBtn extends StatelessWidget {
  final VoidCallback onTap;
  const _DeleteBtn({required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(width: 76, height: 76,
      decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 16, offset: const Offset(0, 6))]),
      child: const Center(child: Icon(Icons.backspace_outlined, size: 28, color: AppTheme.onSurfaceVariant))),
  );
}
