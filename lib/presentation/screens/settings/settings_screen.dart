import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/pin_service.dart';
import '../../../core/services/export_service.dart';
import '../../../core/services/backup_service.dart';
import '../../../data/repositories/wallet_repository.dart';
import '../../../data/repositories/budget_repository.dart';
import '../../../domain/models/app_category.dart';
import '../../../core/services/notification_service.dart';
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
  String _name = 'User';
  bool _editing = false;
  final _nameCtrl = TextEditingController();
  String? _savedPin;
  String? _profileImagePath;
  bool _reminderEnabled = false;
  TimeOfDay? _reminderTime;
  static const _profileImageKey = 'profile_image_path';
  static const _profileNameKey = 'profile_name';
  static const _reminderEnabledKey = 'reminder_enabled';
  static const _reminderTimeHourKey = 'reminder_time_hour';
  static const _reminderTimeMinuteKey = 'reminder_time_minute';

  @override
  void initState() {
    super.initState();
    PinService.getPin().then((p) => setState(() {
      _savedPin = p;
      _pinEnabled = p != null;
    }));
    PinService.isBiometricEnabled().then((b) => setState(() => _biometricEnabled = b));
    SharedPreferences.getInstance().then((prefs) {
      final path = prefs.getString(_profileImageKey);
      final name = prefs.getString(_profileNameKey);
      final remEnabled = prefs.getBool(_reminderEnabledKey) ?? false;
      final remHour = prefs.getInt(_reminderTimeHourKey);
      final remMinute = prefs.getInt(_reminderTimeMinuteKey);

      if (mounted) setState(() {
        if (path != null) _profileImagePath = path;
        if (name != null && name.isNotEmpty) {
          _name = name;
          _nameCtrl.text = name;
        }
        _reminderEnabled = remEnabled;
        if (remHour != null && remMinute != null) {
          _reminderTime = TimeOfDay(hour: remHour, minute: remMinute);
        }
      });
    });
  }

  Future<void> _pickProfileImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_profileImageKey, picked.path);
    if (mounted) setState(() => _profileImagePath = picked.path);
  }

  Future<void> _saveName() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_profileNameKey, name);
    if (mounted) setState(() { _name = name; _editing = false; });
  }

  void _onReminderToggle(bool value) async {
    if (!value) {
      setState(() => _reminderEnabled = false);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_reminderEnabledKey, false);
      await NotificationService().cancelReminder();
      return;
    }

    // Update toggle immediately so it feels responsive.
    setState(() => _reminderEnabled = true);

    // Always show permission sheet when enabling — lets user see + fix any missing permissions.
    final status = await NotificationService().checkPermissions();
    if (!mounted) { setState(() => _reminderEnabled = false); return; }

    // Debug: show raw permission values as a snackbar.
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        'Perms — Notif: ${status.notification} | Alarm: ${status.exactAlarm} | Battery: ${status.batteryOptimizationExempt}',
        style: const TextStyle(fontSize: 12),
      ),
      duration: const Duration(seconds: 5),
    ));

    if (!status.allGranted) {
      await _showReminderPermissionSheet(status);
      if (!mounted) { setState(() => _reminderEnabled = false); return; }
      final updated = await NotificationService().checkPermissions();
      if (!updated.notification) {
        setState(() => _reminderEnabled = false);
        return;
      }
    }

    final time = await showTimePicker(
      context: context,
      initialTime: _reminderTime ?? const TimeOfDay(hour: 20, minute: 0),
    );

    if (time != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_reminderEnabledKey, true);
      await prefs.setInt(_reminderTimeHourKey, time.hour);
      await prefs.setInt(_reminderTimeMinuteKey, time.minute);
      await NotificationService().scheduleDailyReminder(time.hour, time.minute);
      if (mounted) setState(() => _reminderTime = time);
    } else {
      if (mounted) setState(() => _reminderEnabled = false);
    }
  }

  Future<void> _showReminderPermissionSheet(ReminderPermissionStatus status) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (_) => _ReminderPermissionSheet(initialStatus: status),
    );
  }

  void _onPinToggle(bool v) {
    if (v) {
      _startCreatePin();
    } else {
      // Require current PIN before deleting
      final pinKey = GlobalKey<PinScreenState>();
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (ctx) => PinScreen(
            key: pinKey,
            title: 'Current PIN',
            subtitle: 'Enter your PIN to disable it',
            onSuccess: (pin) {
              if (pin != _savedPin) {
                pinKey.currentState?.showWrongPinError();
                return;
              }
              PinService.deletePin();
              setState(() {
                _savedPin = null;
                _pinEnabled = false;
              });
              Navigator.of(ctx, rootNavigator: true).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('PIN deleted.')));
            },
          ),
        ),
      );
    }
  }

  void _onBiometricToggle(bool v) async {
    if (v) {
      // Check if device supports biometric
      final canUse = await PinService.canUseBiometric();
      if (!canUse) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Biometric authentication not available on this device.')));
        }
        return;
      }
      // Enable biometric
      await PinService.setBiometricEnabled(true);
      setState(() => _biometricEnabled = true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Biometric authentication enabled.')));
      }
    } else {
      // Require biometric to disable
      final success = await PinService.authenticateWithBiometric(
        reason: 'Authenticate to disable Biometric Authentication',
      );
      if (!success) return;

      // Disable biometric
      await PinService.setBiometricEnabled(false);
      setState(() => _biometricEnabled = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Biometric authentication disabled.')));
      }
    }
  }

  void _startCreatePin() {
    String? firstPin;
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (ctx1) => PinScreen(
        title: 'Create PIN',
        subtitle: 'Enter a 4-digit PIN',
        onSuccess: (pin) {
          firstPin = pin;
          Navigator.of(ctx1, rootNavigator: true).pushReplacement(MaterialPageRoute(
            fullscreenDialog: true,
            builder: (ctx2) => PinScreen(
              title: 'Confirm PIN',
              subtitle: 'Re-enter your PIN to confirm',
              onSuccess: (confirm) {
                if (confirm == firstPin) {
                  PinService.setPin(confirm);
                  setState(() { _savedPin = confirm; _pinEnabled = true; });
                  Navigator.of(ctx2, rootNavigator: true).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('PIN created successfully.')));
                } else {
                  Navigator.of(ctx2, rootNavigator: true).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('PINs do not match. Try again.')));
                  setState(() => _pinEnabled = false);
                }
              },
            ),
          ));
        },
      ),
    ));
  }

  void _startEditPin() {
    final pinKey = GlobalKey<PinScreenState>();
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (ctx1) => PinScreen(
        key: pinKey,
        title: 'Current PIN',
        subtitle: 'Enter your current PIN',
        onSuccess: (pin) {
          if (pin != _savedPin) {
            pinKey.currentState?.showWrongPinError();
            return;
          }
          String? firstPin;
          Navigator.of(ctx1, rootNavigator: true).pushReplacement(MaterialPageRoute(
            fullscreenDialog: true,
            builder: (ctx2) => PinScreen(
              title: 'Create New PIN',
              subtitle: 'Enter a new 4-digit PIN',
              onSuccess: (newPin) {
                firstPin = newPin;
                Navigator.of(ctx2, rootNavigator: true).pushReplacement(MaterialPageRoute(
                  fullscreenDialog: true,
                  builder: (ctx3) => PinScreen(
                    title: 'Confirm PIN',
                    subtitle: 'Re-enter your new PIN',
                    onSuccess: (confirm) {
                      Navigator.of(ctx3, rootNavigator: true).pop();
                      if (confirm == firstPin) {
                        PinService.setPin(confirm);
                        setState(() => _savedPin = confirm);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('PIN updated successfully.')));
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('PINs do not match. Try again.')));
                      }
                    },
                  ),
                ));
              },
            ),
          ));
        },
      ),
    ));
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
                  GestureDetector(
                    onTap: _pickProfileImage,
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 36,
                          backgroundColor: AppTheme.surfaceContainerLow,
                          backgroundImage: _profileImagePath != null ? FileImage(File(_profileImagePath!)) : null,
                          child: _profileImagePath == null
                              ? const Icon(Icons.person, size: 36, color: AppTheme.onSurfaceVariant)
                              : null,
                        ),
                        Positioned(
                          bottom: 0, right: 0,
                          child: Container(
                            width: 22, height: 22,
                            decoration: BoxDecoration(
                              color: AppTheme.secondary,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: const Icon(Icons.camera_alt_rounded, size: 12, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (_editing)
                      TextField(controller: _nameCtrl, autofocus: true,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                        decoration: const InputDecoration(isDense: true, border: UnderlineInputBorder()))
                    else
                      Text(_name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppTheme.onSurface)),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () {
                        if (_editing) _saveName();
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
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8)]),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Row(children: [
                    Icon(Icons.tune_rounded, color: AppTheme.primary, size: 22),
                    SizedBox(width: 10),
                    Text('Preferences', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppTheme.onSurface)),
                  ]),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: () => context.push('/categories'),
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
                  Divider(color: AppTheme.surfaceContainerLow, height: 32),
                  Row(children: [
                    Container(width: 44, height: 44,
                      decoration: BoxDecoration(color: AppTheme.surfaceContainerLow, borderRadius: BorderRadius.circular(14)),
                      child: const Icon(Icons.notifications_active_rounded, color: AppTheme.primary, size: 22)),
                    const SizedBox(width: 16),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Daily Reminder', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.onSurface)),
                      Text(_reminderEnabled && _reminderTime != null 
                        ? 'Reminds you to record expenses at ${_reminderTime!.format(context)}' 
                        : 'Remind you to record expenses daily',
                        style: const TextStyle(fontSize: 12, color: AppTheme.onSurfaceVariant)),
                    ])),
                    Switch(value: _reminderEnabled, onChanged: _onReminderToggle, activeColor: AppTheme.secondary),
                  ]),
                ]),
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
                    onChanged: _onBiometricToggle,
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
            const SizedBox(height: 20),
            // Delete All Data card
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: GestureDetector(
                onTap: () => _showDeleteAllData(context),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8)],
                  ),
                  child: Row(children: [
                    Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(14)),
                      child: const Icon(Icons.delete_forever_rounded, color: Colors.red, size: 22),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Delete All Data', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.red)),
                      Text('Remove all transactions, wallets and budgets', style: TextStyle(fontSize: 12, color: AppTheme.onSurfaceVariant)),
                    ])),
                    const Icon(Icons.chevron_right_rounded, color: Colors.red),
                  ]),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  void _showExport(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (_) => _ExportSheet(
        categories: ref.read(categoriesProvider),
        walletOrder: ref.read(walletOrderProvider),
        txRepo: ref.read(transactionRepositoryProvider),
        walletRepo: ref.read(walletRepositoryProvider),
        budgetRepo: ref.read(budgetRepositoryProvider),
        transactions: ref.read(transactionsProvider).valueOrNull ?? [],
      ),
    );
  }

  void _showImport(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (_) => _ImportSheet(
        txRepo: ref.read(transactionRepositoryProvider),
        walletRepo: ref.read(walletRepositoryProvider),
        budgetRepo: ref.read(budgetRepositoryProvider),
        onImported: () {
          ref.read(categoriesProvider.notifier).reloadFromPrefs();
          ref.read(walletOrderProvider.notifier).reloadFromPrefs();
        },
      ),
    );
  }

  void _showDeleteAllData(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete All Data?'),
        content: const Text('This will permanently delete all transactions, wallets, and budgets. This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final db = ref.read(appDatabaseProvider);
      await db.deleteAllData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All data deleted successfully.')),
        );
      }
    }
  }
}

class _ToggleRow extends StatelessWidget {
  final String title, subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
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
  final Map<String, List<AppCategory>> categories;
  final List<String> walletOrder;
  final ITransactionRepository txRepo;
  final IWalletRepository walletRepo;
  final IBudgetRepository budgetRepo;

  const _ExportSheet({
    required this.transactions,
    required this.categories,
    required this.walletOrder,
    required this.txRepo,
    required this.walletRepo,
    required this.budgetRepo,
  });

  @override
  State<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<_ExportSheet> {
  String _format = 'json';
  bool _loading = false;
  String? _message;
  bool _isError = false;

  Future<void> _run() async {
    setState(() { _loading = true; _message = null; _isError = false; });
    try {
      if (_format == 'json') {
        await BackupService.exportBackup(
          txRepo: widget.txRepo,
          walletRepo: widget.walletRepo,
          budgetRepo: widget.budgetRepo,
          categories: widget.categories,
          walletOrder: widget.walletOrder,
        );
        setState(() { _message = '✅ Backup file shared!'; _isError = false; });
      } else if (_format == 'csv') {
        await ExportService.exportCsv(widget.transactions);
        setState(() { _message = '✅ CSV exported!'; _isError = false; });
      } else {
        await ExportService.exportPdf(widget.transactions);
        setState(() { _message = '✅ PDF exported!'; _isError = false; });
      }
    } catch (e) {
      setState(() { _message = '❌ $e'; _isError = true; });
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
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
        _FormatCard(
          id: 'json', icon: Icons.backup_rounded, iconBg: AppTheme.secondary,
          title: 'Full Backup (JSON)', sub: 'All data: wallets, budgets, categories & settings. Use this to restore on a new device.',
          selected: _format == 'json', onTap: () => setState(() => _format = 'json')),
        const SizedBox(height: 10),
        _FormatCard(id: 'csv', icon: Icons.table_chart_rounded, iconBg: AppTheme.primary,
          title: 'CSV – Transactions only', sub: 'Raw data for spreadsheets.',
          selected: _format == 'csv', onTap: () => setState(() => _format = 'csv')),
        const SizedBox(height: 10),
        _FormatCard(id: 'pdf', icon: Icons.picture_as_pdf_rounded, iconBg: const Color(0xFFEF4444),
          title: 'PDF – Transactions only', sub: 'Formatted visual report.',
          selected: _format == 'pdf', onTap: () => setState(() => _format = 'pdf')),
        if (_message != null) ...[const SizedBox(height: 14),
          _ResultBanner(message: _message!, isError: _isError)],
        const SizedBox(height: 20),
        GestureDetector(
          onTap: _loading ? null : _run,
          child: Container(height: 56, width: double.infinity,
            decoration: BoxDecoration(color: _loading ? AppTheme.primary.withOpacity(0.5) : AppTheme.primary,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [BoxShadow(color: AppTheme.primary.withOpacity(0.3), blurRadius: 16, offset: const Offset(0, 8))]),
            child: Center(child: _loading
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
              : const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.download_rounded, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text('EXPORT', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
                ])),
          ),
        ),
      ]),
    );
  }
}

class _ImportSheet extends StatefulWidget {
  final ITransactionRepository txRepo;
  final IWalletRepository walletRepo;
  final IBudgetRepository budgetRepo;
  final VoidCallback onImported;
  const _ImportSheet({
    required this.txRepo,
    required this.walletRepo,
    required this.budgetRepo,
    required this.onImported,
  });

  @override
  State<_ImportSheet> createState() => _ImportSheetState();
}

class _ImportSheetState extends State<_ImportSheet> {
  bool _loading = false;
  String? _message;
  bool _isError = false;

  Future<void> _run() async {
    setState(() { _loading = true; _message = null; _isError = false; });
    try {
      final summary = await BackupService.importBackup(
        txRepo: widget.txRepo,
        walletRepo: widget.walletRepo,
        budgetRepo: widget.budgetRepo,
      );
      widget.onImported();
      setState(() { _message = '✅ Import successful!\n$summary'; _isError = false; });
    } catch (e) {
      setState(() { _message = '❌ $e'; _isError = true; });
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Center(child: Container(width: 48, height: 5,
          decoration: BoxDecoration(color: AppTheme.surfaceContainerLow, borderRadius: BorderRadius.circular(3)))),
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Import Backup', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          GestureDetector(onTap: () => Navigator.pop(context),
            child: Container(width: 36, height: 36, decoration: BoxDecoration(
                color: AppTheme.surfaceContainerLow, shape: BoxShape.circle),
              child: const Icon(Icons.close_rounded, size: 18))),
        ]),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: AppTheme.surfaceContainerLow, borderRadius: BorderRadius.circular(16)),
          child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.info_outline_rounded, color: AppTheme.secondary, size: 20),
            SizedBox(width: 10),
            Expanded(child: Text(
              'Select a .json backup file exported from this app. All wallets, budgets, categories, and transactions will be merged into your current data.',
              style: TextStyle(fontSize: 13, color: AppTheme.onSurfaceVariant, height: 1.45),
            )),
          ]),
        ),
        if (_message != null) ...[const SizedBox(height: 14),
          _ResultBanner(message: _message!, isError: _isError)],
        const SizedBox(height: 20),
        GestureDetector(
          onTap: _loading ? null : _run,
          child: Container(height: 56, width: double.infinity,
            decoration: BoxDecoration(color: _loading ? AppTheme.primary.withOpacity(0.5) : AppTheme.primary,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [BoxShadow(color: AppTheme.primary.withOpacity(0.3), blurRadius: 16, offset: const Offset(0, 8))]),
            child: Center(child: _loading
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
              : const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.upload_rounded, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text('SELECT BACKUP FILE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
                ])),
          ),
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

class _ResultBanner extends StatelessWidget {
  final String message;
  final bool isError;
  const _ResultBanner({required this.message, required this.isError});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: isError ? Colors.red.withOpacity(0.08) : const Color(0xFF14B8A6).withOpacity(0.08),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: isError ? Colors.red.withOpacity(0.3) : const Color(0xFF14B8A6).withOpacity(0.3),
      ),
    ),
    child: Text(
      message,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: isError ? Colors.red : const Color(0xFF0D9488),
        height: 1.5,
      ),
    ),
  );
}

class _ReminderPermissionSheet extends StatefulWidget {
  final ReminderPermissionStatus initialStatus;
  const _ReminderPermissionSheet({required this.initialStatus});

  @override
  State<_ReminderPermissionSheet> createState() => _ReminderPermissionSheetState();
}

class _ReminderPermissionSheetState extends State<_ReminderPermissionSheet> {
  late bool _notifGranted;
  late bool _exactAlarmGranted;
  late bool _batteryGranted;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _notifGranted = widget.initialStatus.notification;
    _exactAlarmGranted = widget.initialStatus.exactAlarm;
    _batteryGranted = widget.initialStatus.batteryOptimizationExempt;
  }

  Future<void> _refresh() async {
    final s = await NotificationService().checkPermissions();
    if (mounted) {
      setState(() {
        _notifGranted = s.notification;
        _exactAlarmGranted = s.exactAlarm;
        _batteryGranted = s.batteryOptimizationExempt;
      });
    }
  }

  Widget _permRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String sub,
    required bool granted,
    required String buttonLabel,
    required Future<void> Function() onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              Text(sub, style: const TextStyle(fontSize: 12, color: AppTheme.onSurfaceVariant)),
            ],
          )),
          const SizedBox(width: 8),
          if (granted)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF14B8A6).withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.check_circle_rounded, size: 14, color: Color(0xFF0D9488)),
                SizedBox(width: 4),
                Text('Granted', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF0D9488))),
              ]),
            )
          else
            GestureDetector(
              onTap: _loading ? null : () async {
                setState(() => _loading = true);
                await onTap();
                await _refresh();
                setState(() => _loading = false);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(buttonLabel,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allDone = _notifGranted && _exactAlarmGranted && _batteryGranted;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      padding: EdgeInsets.fromLTRB(24, 16, 24, MediaQuery.of(context).viewInsets.bottom + 32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Center(child: Container(width: 48, height: 5,
          decoration: BoxDecoration(color: AppTheme.surfaceContainerLow, borderRadius: BorderRadius.circular(3)))),
        const SizedBox(height: 20),
        Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.notifications_active_rounded, color: AppTheme.primary, size: 24),
          ),
          const SizedBox(width: 14),
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Reminder Permissions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            Text('Grant these for reminders to work reliably', style: TextStyle(fontSize: 13, color: AppTheme.onSurfaceVariant)),
          ])),
        ]),
        const SizedBox(height: 20),
        _permRow(
          icon: Icons.notifications_rounded,
          iconColor: AppTheme.primary,
          title: 'Notification Permission',
          sub: 'Allow the app to show notifications',
          granted: _notifGranted,
          buttonLabel: 'Allow',
          onTap: () => NotificationService().requestNotificationPermission(),
        ),
        _permRow(
          icon: Icons.alarm_rounded,
          iconColor: const Color(0xFFF59E0B),
          title: 'Exact Alarm',
          sub: 'Schedule notifications at precise times',
          granted: _exactAlarmGranted,
          buttonLabel: 'Allow',
          onTap: () => NotificationService().openExactAlarmSettings(),
        ),
        _permRow(
          icon: Icons.battery_saver_rounded,
          iconColor: const Color(0xFF10B981),
          title: 'Battery Optimization',
          sub: 'Prevent the system from blocking reminders',
          granted: _batteryGranted,
          buttonLabel: 'Exempt',
          onTap: () => NotificationService().requestBatteryOptimizationExemption(),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            height: 52, width: double.infinity,
            decoration: BoxDecoration(
              color: allDone ? AppTheme.primary : AppTheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Center(
              child: Text(
                allDone ? 'Done — Set Reminder Time' : 'Continue Anyway',
                style: TextStyle(
                  color: allDone ? Colors.white : AppTheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
