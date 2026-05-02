import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/backup_service.dart';
import '../../core/theme/app_theme.dart';
import '../providers/app_providers.dart';

class DataSheet extends ConsumerStatefulWidget {
  final bool isImport;
  final VoidCallback onClose;

  const DataSheet({super.key, required this.isImport, required this.onClose});

  @override
  ConsumerState<DataSheet> createState() => _DataSheetState();
}

class _DataSheetState extends ConsumerState<DataSheet> {
  bool _loading = false;
  String? _message;
  bool _isError = false;

  Future<void> _run() async {
    setState(() { _loading = true; _message = null; _isError = false; });

    try {
      if (widget.isImport) {
        final summary = await BackupService.importBackup(
          txRepo: ref.read(transactionRepositoryProvider),
          walletRepo: ref.read(walletRepositoryProvider),
          budgetRepo: ref.read(budgetRepositoryProvider),
        );
        // Reload categories from prefs into the notifier
        ref.read(categoriesProvider.notifier).reloadFromPrefs();
        // Reload wallet order
        ref.read(walletOrderProvider.notifier).reloadFromPrefs();
        setState(() { _message = '✅ Import successful!\n$summary'; _isError = false; });
      } else {
        await BackupService.exportBackup(
          txRepo: ref.read(transactionRepositoryProvider),
          walletRepo: ref.read(walletRepositoryProvider),
          budgetRepo: ref.read(budgetRepositoryProvider),
          categories: ref.read(categoriesProvider),
          walletOrder: ref.read(walletOrderProvider),
        );
        setState(() { _message = '✅ Backup file shared successfully!'; _isError = false; });
      }
    } catch (e) {
      setState(() { _message = '❌ ${e.toString()}'; _isError = true; });
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      GestureDetector(
        onTap: widget.onClose,
        child: Container(color: Colors.black.withOpacity(0.4)),
      ),
      Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [BoxShadow(color: Color(0x14001A3A), blurRadius: 60, offset: Offset(0, -20))],
          ),
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 48, height: 6, decoration: BoxDecoration(
              color: AppTheme.surfaceContainerLow, borderRadius: BorderRadius.circular(3))),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(widget.isImport ? 'Import Data' : 'Export Data',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppTheme.onSurface)),
              GestureDetector(
                onTap: widget.onClose,
                child: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(color: AppTheme.surfaceContainerLow, shape: BoxShape.circle),
                  child: const Icon(Icons.close, size: 18, color: AppTheme.onSurfaceVariant),
                ),
              ),
            ]),
            const SizedBox(height: 20),

            // Info card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(
                  widget.isImport ? Icons.upload_file_rounded : Icons.backup_rounded,
                  color: AppTheme.secondary, size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    widget.isImport ? 'Restore from Backup' : 'Backup All Data',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.onSurface),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.isImport
                        ? 'Select a .json backup file. Your existing data will be merged with the imported data.'
                        : 'Exports a .json file containing all your transactions, wallets, budgets, categories, and settings. Share or save it to restore later.',
                    style: const TextStyle(fontSize: 13, color: AppTheme.onSurfaceVariant, height: 1.4),
                  ),
                ])),
              ]),
            ),

            // Result message
            if (_message != null) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _isError
                      ? AppTheme.error.withOpacity(0.08)
                      : const Color(0xFF14B8A6).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _isError
                        ? AppTheme.error.withOpacity(0.3)
                        : const Color(0xFF14B8A6).withOpacity(0.3),
                  ),
                ),
                child: Text(
                  _message!,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _isError ? AppTheme.error : const Color(0xFF0D9488),
                    height: 1.5,
                  ),
                ),
              ),
            ],

            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _loading ? null : _run,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppTheme.primary.withOpacity(0.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                child: _loading
                    ? const SizedBox(
                        width: 22, height: 22,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                      )
                    : Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(widget.isImport ? Icons.upload_rounded : Icons.download_rounded, size: 20),
                        const SizedBox(width: 10),
                        Text(
                          widget.isImport ? 'SELECT BACKUP FILE' : 'EXPORT BACKUP',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 1.5),
                        ),
                      ]),
              ),
            ),
          ]),
        ),
      ),
    ]);
  }
}
