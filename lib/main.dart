import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/services/pin_service.dart';
import 'core/services/notification_service.dart';
import 'presentation/providers/insight_notification_provider.dart';
import 'presentation/screens/settings/pin_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService().initialize();
  runApp(const ProviderScope(child: MoneyApp()));
}

class MoneyApp extends ConsumerStatefulWidget {
  const MoneyApp({super.key});

  @override
  ConsumerState<MoneyApp> createState() => _MoneyAppState();
}

class _MoneyAppState extends ConsumerState<MoneyApp> with WidgetsBindingObserver {
  bool _isUnlocked = false;
  bool _isLoading = true;
  String? _savedPin;
  bool _biometricEnabled = false;
  bool _canUseBio = false;
  final GlobalKey<PinScreenState> _pinKey = GlobalKey<PinScreenState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkSecurity();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    // Do not lock the app if we are currently showing the biometric prompt
    if (PinService.isAuthenticating) return;

    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _lockIfRequired();
    } else if (state == AppLifecycleState.resumed) {
      _checkSecurity();
    }
  }

  Future<void> _lockIfRequired() async {
    final pin = await PinService.getPin();
    final bio = await PinService.isBiometricEnabled();
    final canUseBio = await PinService.canUseBiometric();
    if (pin != null || (bio && canUseBio)) {
      if (mounted) {
        setState(() => _isUnlocked = false);
      }
    }
  }

  Future<void> _checkSecurity() async {
    final pin = await PinService.getPin();
    final bioEnabled = await PinService.isBiometricEnabled();
    final canUseBio = await PinService.canUseBiometric();

    final requiresAuth = pin != null || (bioEnabled && canUseBio);

    setState(() {
      _savedPin = pin;
      _biometricEnabled = bioEnabled;
      _canUseBio = canUseBio;
      _isLoading = false;
      _isUnlocked = !requiresAuth; // Unlock immediately if no security
    });

    // Auto-trigger biometric on launch if it's available and no PIN is set
    if (!_isUnlocked && bioEnabled && canUseBio && pin == null) {
      _tryBiometric();
    }
  }

  Future<void> _tryBiometric() async {
    final success = await PinService.authenticateWithBiometric();
    if (success) _unlock();
  }

  void _unlock() {
    setState(() => _isUnlocked = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return MaterialApp(
        theme: AppTheme.light,
        debugShowCheckedModeBanner: false,
        home: const Scaffold(
          backgroundColor: AppTheme.surface,
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    // Biometric-only mode (no PIN set but biometric is enabled)
    if (!_isUnlocked && _savedPin == null && _biometricEnabled && _canUseBio) {
      return MaterialApp(
        theme: AppTheme.light,
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: AppTheme.surface,
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.fingerprint_rounded, size: 72, color: AppTheme.secondary),
                const SizedBox(height: 24),
                const Text('Biometric Required', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppTheme.onSurface)),
                const SizedBox(height: 8),
                const Text('Authenticate to access your data', style: TextStyle(fontSize: 14, color: AppTheme.onSurfaceVariant)),
                const SizedBox(height: 32),
                ElevatedButton.icon(
                  onPressed: _tryBiometric,
                  icon: const Icon(Icons.fingerprint_rounded),
                  label: const Text('Authenticate'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.secondary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // PIN (+ optional biometric) mode
    if (!_isUnlocked && _savedPin != null) {
      return MaterialApp(
        theme: AppTheme.light,
        debugShowCheckedModeBanner: false,
        home: PinScreen(
          key: _pinKey,
          title: 'Welcome Back',
          subtitle: 'Enter your PIN to unlock',
          showBackButton: false,
          showBiometricButton: _biometricEnabled && _canUseBio,
          onBiometricPressed: _tryBiometric,
          onSuccess: (pin) {
            if (pin == _savedPin) {
              _unlock();
            } else {
              _pinKey.currentState?.showWrongPinError();
            }
          },
        ),
      );
    }

    ref.watch(insightNotificationWatcherProvider);
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: 'Money App',
      theme: AppTheme.light,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}

