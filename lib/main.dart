import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/services/pin_service.dart';
import 'presentation/screens/settings/pin_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
  final GlobalKey<PinScreenState> _pinKey = GlobalKey<PinScreenState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPin();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Lock the app when it goes to background
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      if (_savedPin != null) {
        setState(() => _isUnlocked = false);
      }
    }
  }

  Future<void> _checkPin() async {
    final pin = await PinService.getPin();
    final bioEnabled = await PinService.isBiometricEnabled();
    final canUseBio = await PinService.canUseBiometric();

    setState(() {
      _savedPin = pin;
      _biometricEnabled = bioEnabled && canUseBio;
      _isLoading = false;
      _isUnlocked = pin == null; // If no PIN set, unlock immediately
    });
  }

  Future<void> _tryBiometric() async {
    final success = await PinService.authenticateWithBiometric();
    if (success) {
      _unlock();
    }
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

    if (!_isUnlocked && _savedPin != null) {
      return MaterialApp(
        theme: AppTheme.light,
        debugShowCheckedModeBanner: false,
        home: PinScreen(
          key: _pinKey,
          title: 'Welcome Back',
          subtitle: 'Enter your PIN to unlock',
          showBackButton: false,
          showBiometricButton: _biometricEnabled,
          onBiometricPressed: _tryBiometric,
          onSuccess: (pin) {
            if (pin == _savedPin) {
              _unlock();
            } else {
              // Show error feedback in PIN screen
              _pinKey.currentState?.showWrongPinError();
            }
          },
        ),
      );
    }

    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: 'Money App',
      theme: AppTheme.light,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
