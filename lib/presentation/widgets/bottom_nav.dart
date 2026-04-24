import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class BottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const BottomNavBar({super.key, required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      height: 72,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(48),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 40, offset: const Offset(0, 10))],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _NavItem(icon: Icons.swap_horiz_rounded, index: 0, current: currentIndex, onTap: onTap),
          _NavItem(icon: Icons.bar_chart_rounded, index: 1, current: currentIndex, onTap: onTap),
          _FabItem(onTap: () => onTap(2)),
          _NavItem(icon: Icons.account_balance_wallet_rounded, index: 3, current: currentIndex, onTap: onTap),
          _NavItem(icon: Icons.settings_rounded, index: 4, current: currentIndex, onTap: onTap),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final int index;
  final int current;
  final ValueChanged<int> onTap;

  const _NavItem({required this.icon, required this.index, required this.current, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final active = index == current;
    return GestureDetector(
      onTap: () => onTap(index),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 48,
        height: 48,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(icon, size: 28, color: active ? AppTheme.secondary : const Color(0xFFC5C6D2)),
            if (active)
              Positioned(
                bottom: 4,
                child: Container(width: 6, height: 6, decoration: const BoxDecoration(color: AppTheme.secondary, shape: BoxShape.circle)),
              ),
          ],
        ),
      ),
    );
  }
}

class _FabItem extends StatelessWidget {
  final VoidCallback onTap;
  const _FabItem({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Transform.translate(
        offset: const Offset(0, -20),
        child: Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: AppTheme.primary,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: AppTheme.primary.withOpacity(0.4), blurRadius: 16, offset: const Offset(0, 8))],
          ),
          child: const Icon(Icons.add, color: Colors.white, size: 32),
        ),
      ),
    );
  }
}
