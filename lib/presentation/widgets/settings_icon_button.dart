import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';

// Top-right settings entry point shared by the main screens now that
// Settings is no longer a bottom-nav tab (its slot was taken by the
// Prediction Dashboard).
class SettingsIconButton extends StatelessWidget {
  const SettingsIconButton({super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/settings'),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppTheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Icon(Icons.settings_rounded, size: 20, color: AppTheme.onSurface),
      ),
    );
  }
}
