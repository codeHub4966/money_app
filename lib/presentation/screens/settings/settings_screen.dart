import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/pin_service.dart';
import '../../../core/services/export_service.dart';
import '../settings/pin_screen.dart';
import '../../providers/app_providers.dart';
import '../../../domain/models/transaction.dart';
import '../../../data/repositories/transaction_repository.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _State();
}

class _State extends ConsumerState<SettingsScreen> {
  bool _pinEnabled = false;
  bool _biometricEnabled = false;
  String _name = 'Alexander Vance';
  bool _editing = false;
  late final _nameCtrl = TextEditingController(text: _name);
  String? _savedPin;

  @override
  void initState() {
    super.initState();
    PinService.getPin().then((p) => setState(() {
      _savedPin = p;
      _pinEnabled = p != null;
    }));
  }

  void _onPinToggle(bool v) {
    if (v) {
      _startCreatePin();
    } else {
      // Require current PIN before deleting
      Navigator.of(context, rootNavigator: true).push(
        PageRouteBuilder(
          opaque: true,
          fullscreenDialog: true,
          pageBuilder: (context, _, __) => PinScreen(
        title: 'Current PIN',
        subtitle: 'Enter your PIN to disable it',
        onSuccess: (pin) {
          if (pin != _savedPin) {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Incorrect PIN.')));
            return;
          }
          PinService.deletePin();
          setState(() { _savedPin = null; _pinEnabled = false; });
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('PIN deleted.')));
        },
      )));
    }
  }

  void _startCreatePin() {
    String? firstPin;
    Navigator.push(context, MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => PinScreen(
      title: 'Create PIN',
      subtitle: 'Enter a 4-digit PIN',
      onSuccess: (pin) {
        firstPin = pin;
        Navigator.pushReplacement(context, MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => PinScreen(
          title: 'Confirm PIN',
          subtitle: 'Re-enter your PIN to confirm',
          onSuccess: (confirm) {
            if (confirm == firstPin) {
              PinService.setPin(confirm);
              setState(() { _savedPin = confirm; _pinEnabled = true; });
              Navigator.pop(context);
            } else {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('PINs do not match. Try again.')));
              setState(() => _pinEnabled = false);
            }
          },
        )));
      },
    )));
  }

  void _startEditPin() {
    Navigator.push(context, MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => PinScreen(
      title: 'Current PIN',
      subtitle: 'Enter your current PIN',
      onSuccess: (pin) {
        if (pin != _savedPin) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Incorrect PIN.')));
          return;
        }
        String? firstPin;
        Navigator.pushReplacement(context, MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => PinScreen(
          title: 'Create New PIN',
          subtitle: 'Enter a new 4-digit PIN',
          onSuccess: (newPin) {
            firstPin = newPin;
            Navigator.pushReplacement(context, MaterialPageRoute(
              fullscreenDialog: true,
              builder: (_) => PinScreen(
              title: 'Confirm PIN',
              subtitle: 'Re-enter your new PIN',
              onSuccess: (confirm) {
                if (confirm == firstPin) {
                  PinService.setPin(confirm);
                  setState(() => _savedPin = confirm);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('PIN updated successfully.')));
                } else {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('PINs do not match. Try again.')));
                }
              },
            )));
          },
        )));
      },
    )));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 100),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: Text('Settings', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppTheme.primary)),
            ),
            // Profile card
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8)]),
                child: Row(children: [
                  CircleAvatar(radius: 36, backgroundColor: AppTheme.surfaceContainerLow,
                    child: const Icon(Icons.person, size: 36, color: AppTheme.onSurfaceVariant)),
                  const SizedBox(width: 16),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (_editing)
                      TextField(controller: _nameCtrl, autofocus: true,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                        decoration: const InputDecoration(isDense: true, border: UnderlineInputBorder()))
                    else
                      Text(_name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppTheme.onSurface)),
                    const Text('Private Client · Since 2021',
                      style: TextStyle(fontSize: 13, color: AppTheme.onSurfaceVariant)),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () {
                        if (_editing) setState(() { _name = _nameCtrl.text; _editing = false; });
                        else setState(() => _editing = true);
                      },
                      child: Row(children: [
                        Text(_editing ? 'Save Profile' : 'Manage Profile',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                              color: AppTheme.secondary, letterSpacing: 1)),
                        const Icon(Icons.chevron_right_rounded, size: 16, color: AppTheme.secondary),
                      ]),
                    ),
                  ])),
                ]),
              ),
            ),
            const SizedBox(height: 20),
            // Category Management card
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: GestureDetector(
                onTap: () => context.push('/categories'),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8)]),
                  child: Row(children: [
                    Container(width: 44, height: 44,
                      decoration: BoxDecoration(color: AppTheme.surfaceContainerLow, borderRadius: BorderRadius.circular(14)),
                      child: const Icon(Icons.category_rounded, color: AppTheme.primary, size: 22)),
                    const SizedBox(width: 16),
                    const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Category Management', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.onSurface)),
                      Text('Add, view and organise transaction categories',
                        style: TextStyle(fontSize: 12, color: AppTheme.onSurfaceVariant)),
                    ])),
                    const Icon(Icons.chevron_right_rounded, color: AppTheme.onSurfaceVariant),
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Security card
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8)]),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Row(children: [
                    Icon(Icons.shield_rounded, color: AppTheme.primary, size: 22),
                    SizedBox(width: 10),
                    Text('Security', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppTheme.onSurface)),
                  ]),
                  const SizedBox(height: 16),
                  _ToggleRow(
                    title: 'App PIN',
                    subtitle: 'Require a 4-digit PIN to access the vault',
                    value: _pinEnabled,
                    onChanged: _onPinToggle,
                  ),
                  if (_savedPin != null) ...[
                    Divider(color: AppTheme.surfaceContainerLow),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Edit PIN', style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.secondary)),
                      subtitle: const Text('Update your current 4-digit PIN'),
                      trailing: Container(width: 40, height: 40,
                        decoration: BoxDecoration(color: AppTheme.surfaceContainerLow, shape: BoxShape.circle),
                        child: const Icon(Icons.chevron_right_rounded, color: AppTheme.primary)),
                      onTap: _startEditPin,
                    ),
                  ],
                  Divider(color: AppTheme.surfaceContainerLow),
                  _ToggleRow(
                    title: 'Biometric Authentication',
                    subtitle: 'Use FaceID or Fingerprint to unlock',
                    value: _biometricEnabled,
                    onChanged: (v) => setState(() => _biometricEnabled = v),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 20),
            // Data management card
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8)]),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Row(children: [
                    Icon(Icons.folder_rounded, color: AppTheme.primary, size: 22),
                    SizedBox(width: 10),
                    Text('Data Management', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppTheme.onSurface)),
                  ]),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(child: _DataBtn(icon: Icons.download_rounded, label: 'Export Data',
                        sub: 'Download your transaction history', onTap: () => _showExport(context))),
                    const SizedBox(width: 12),
                    Expanded(child: _DataBtn(icon: Icons.upload_rounded, label: 'Import Data',
                        sub: 'Upload external statements', onTap: () => _showImport(context))),
                  ]),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  void _showExport(BuildContext context) {
    final transactions = ref.read(transactionsProvider).valueOrNull ?? [];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ExportSheet(transactions: transactions),
    );
  }

  void _showImport(BuildContext context) {
    final repo = ref.read(transactionRepositoryProvider);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ImportSheet(repo: repo),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final String title, subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _ToggleRow({required this.title, required this.subtitle, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => Row(children: [
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.onSurface)),
      Text(subtitle, style: const TextStyle(fontSize: 13, color: AppTheme.onSurfaceVariant)),
    ])),
    Switch(value: value, onChanged: onChanged, activeColor: AppTheme.secondary),
  ]);
}

class _DataBtn extends StatelessWidget {
  final IconData icon;
  final String label, sub;
  final VoidCallback onTap;
  const _DataBtn({required this.icon, required this.label, required this.sub, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppTheme.surfaceContainerLow, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 44, height: 44, decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          child: Icon(icon, color: AppTheme.primary, size: 22)),
        const SizedBox(height: 10),
        Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.onSurface)),
        Text(sub, style: const TextStyle(fontSize: 11, color: AppTheme.onSurfaceVariant)),
      ]),
    ),
  );
}

class _ExportSheet extends StatefulWidget {
  final List<Transaction> transactions;
  const _ExportSheet({required this.transactions});

  @override
  State<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<_ExportSheet> {
  String _format = 'csv';

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Center(child: Container(width: 48, height: 5,
          decoration: BoxDecoration(color: AppTheme.surfaceContainerLow, borderRadius: BorderRadius.circular(3)))),
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Export Data', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          GestureDetector(onTap: () => Navigator.pop(context),
            child: Container(width: 36, height: 36, decoration: BoxDecoration(
                color: AppTheme.surfaceContainerLow, shape: BoxShape.circle),
              child: const Icon(Icons.close_rounded, size: 18))),
        ]),
        const SizedBox(height: 20),
        _FormatCard(id: 'csv', icon: Icons.table_chart_rounded, iconBg: AppTheme.primary,
          title: 'CSV Format', sub: 'Raw data for spreadsheets.',
          selected: _format == 'csv', onTap: () => setState(() => _format = 'csv')),
        const SizedBox(height: 12),
        _FormatCard(id: 'pdf', icon: Icons.picture_as_pdf_rounded, iconBg: AppTheme.surfaceContainerHigh,
          title: 'PDF Report', sub: 'Formatted visual report.',
          selected: _format == 'pdf', onTap: () => setState(() => _format = 'pdf')),
        const SizedBox(height: 24),
        GestureDetector(
          onTap: () {
            Navigator.pop(context);
            if (_format == 'csv') {
              ExportService.exportCsv(widget.transactions);
            } else {
              ExportService.exportPdf(widget.transactions);
            }
          },
          child: Container(height: 56, width: double.infinity,
            decoration: BoxDecoration(color: AppTheme.primary, borderRadius: BorderRadius.circular(24),
              boxShadow: [BoxShadow(color: AppTheme.primary.withOpacity(0.3), blurRadius: 16, offset: const Offset(0, 8))]),
            child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.download_rounded, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text('EXPORT DATA', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
            ])),
        ),
      ]),
    );
  }
}

class _ImportSheet extends StatefulWidget {
  final ITransactionRepository repo;
  const _ImportSheet({required this.repo});

  @override
  State<_ImportSheet> createState() => _ImportSheetState();
}

class _ImportSheetState extends State<_ImportSheet> {
  String _format = 'csv';

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Center(child: Container(width: 48, height: 5,
          decoration: BoxDecoration(color: AppTheme.surfaceContainerLow, borderRadius: BorderRadius.circular(3)))),
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Import Data', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          GestureDetector(onTap: () => Navigator.pop(context),
            child: Container(width: 36, height: 36, decoration: BoxDecoration(
                color: AppTheme.surfaceContainerLow, shape: BoxShape.circle),
              child: const Icon(Icons.close_rounded, size: 18))),
        ]),
        const SizedBox(height: 20),
        _FormatCard(id: 'csv', icon: Icons.table_chart_rounded, iconBg: AppTheme.primary,
          title: 'CSV Format', sub: 'Import from spreadsheet export.',
          selected: _format == 'csv', onTap: () => setState(() => _format = 'csv')),
        const SizedBox(height: 12),
        _FormatCard(id: 'pdf', icon: Icons.picture_as_pdf_rounded, iconBg: AppTheme.surfaceContainerHigh,
          title: 'PDF Report', sub: 'Import from PDF export.',
          selected: _format == 'pdf', onTap: () => setState(() => _format = 'pdf')),
        const SizedBox(height: 24),
        GestureDetector(
          onTap: () {
            Navigator.pop(context);
            if (_format == 'csv') {
              ExportService.importCsv(widget.repo);
            } else {
              ExportService.importPdf(widget.repo);
            }
          },
          child: Container(height: 56, width: double.infinity,
            decoration: BoxDecoration(color: AppTheme.primary, borderRadius: BorderRadius.circular(24),
              boxShadow: [BoxShadow(color: AppTheme.primary.withOpacity(0.3), blurRadius: 16, offset: const Offset(0, 8))]),
            child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.upload_rounded, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text('IMPORT DATA', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
            ])),
        ),
      ]),
    );
  }
}

class _FormatCard extends StatelessWidget {
  final String id, title, sub;
  final IconData icon;
  final Color iconBg;
  final bool selected;
  final VoidCallback onTap;
  const _FormatCard({required this.id, required this.icon, required this.iconBg,
    required this.title, required this.sub, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: selected ? Colors.white : AppTheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: selected ? Border.all(color: AppTheme.secondary.withOpacity(0.4), width: 1.5) : null,
      ),
      child: Row(children: [
        Container(width: 44, height: 44, decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: Colors.white, size: 22)),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          Text(sub, style: const TextStyle(fontSize: 13, color: AppTheme.onSurfaceVariant)),
        ])),
        if (selected) Container(width: 24, height: 24,
          decoration: const BoxDecoration(color: AppTheme.secondary, shape: BoxShape.circle),
          child: const Icon(Icons.check, color: Colors.white, size: 14)),
      ]),
    ),
  );
}
