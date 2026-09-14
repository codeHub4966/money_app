import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/services/pin_service.dart';
import 'core/services/notification_service.dart';
import 'domain/models/detected_payment.dart';
import 'presentation/providers/app_providers.dart';
import 'presentation/providers/insight_notification_provider.dart';
import 'presentation/providers/payment_notification_provider.dart';
import 'presentation/screens/settings/pin_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService().initialize();

  // Created explicitly (rather than via ProviderScope) so
  // NotificationService.onDetectedPaymentConfirmed can reach into Riverpod
  // state from outside the widget tree when the user taps "Yes" on a
  // detected-payment confirmation notification.
  final container = ProviderContainer();
  NotificationService().onDetectedPaymentConfirmed = (payment) {
    container.read(pendingDetectedPaymentProvider.notifier).state = payment;
  };

  // Picks up a "Yes" tap that happened while the app process was fully
  // terminated (persisted by notificationTapBackgroundHandler, which runs in
  // an isolate with no Riverpod access) so it isn't lost.
  final prefs = await SharedPreferences.getInstance();
  final pendingPayload = prefs.getString(kPendingDetectedPaymentPrefsKey);
  if (pendingPayload != null) {
    await prefs.remove(kPendingDetectedPaymentPrefsKey);
    try {
      final payment = DetectedPayment.fromJson(jsonDecode(pendingPayload) as Map<String, dynamic>);
      container.read(pendingDetectedPaymentProvider.notifier).state = payment;
    } catch (_) {}
  }

  runApp(UncontrolledProviderScope(container: container, child: const MoneyApp()));
}

class MoneyApp extends ConsumerStatefulWidget {
  const MoneyApp({super.key});

  @override
  ConsumerState<MoneyApp> createState() => _MoneyAppState();
}

class _MoneyAppState extends ConsumerState<MoneyApp>
    with WidgetsBindingObserver {
  bool _isUnlocked = false;
  bool _isLoading = true;
  bool _hasPin = false;
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

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _lockIfRequired();
    } else if (state == AppLifecycleState.resumed) {
      _checkSecurity();
    }
  }

  Future<void> _lockIfRequired() async {
    final hasPin = await PinService.hasPin();
    final bio = await PinService.isBiometricEnabled();
    final canUseBio = await PinService.canUseBiometric();
    if (hasPin || (bio && canUseBio)) {
      if (mounted) {
        setState(() => _isUnlocked = false);
        ref.read(isAppUnlockedProvider.notifier).state = false;
      }
    }
  }

  Future<void> _checkSecurity() async {
    final hasPin = await PinService.hasPin();
    final bioEnabled = await PinService.isBiometricEnabled();
    final canUseBio = await PinService.canUseBiometric();

    final requiresAuth = hasPin || (bioEnabled && canUseBio);

    setState(() {
      _hasPin = hasPin;
      _biometricEnabled = bioEnabled;
      _canUseBio = canUseBio;
      _isLoading = false;
      _isUnlocked = !requiresAuth; // Unlock immediately if no security
    });
    ref.read(isAppUnlockedProvider.notifier).state = _isUnlocked;

    // Auto-trigger biometric on launch if it's available and no PIN is set
    if (!_isUnlocked && bioEnabled && canUseBio && !hasPin) {
      _tryBiometric();
    }
  }

  Future<void> _tryBiometric() async {
    final success = await PinService.authenticateWithBiometric();
    if (success) _unlock();
  }

  void _unlock() {
    setState(() => _isUnlocked = true);
    ref.read(isAppUnlockedProvider.notifier).state = true;
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
    if (!_isUnlocked && !_hasPin && _biometricEnabled && _canUseBio) {
      return MaterialApp(
        theme: AppTheme.light,
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: AppTheme.surface,
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.fingerprint_rounded,
                    size: 72, color: AppTheme.secondary),
                const SizedBox(height: 24),
                const Text('Biometric Required',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.onSurface)),
                const SizedBox(height: 8),
                const Text('Authenticate to access your data',
                    style: TextStyle(
                        fontSize: 14, color: AppTheme.onSurfaceVariant)),
                const SizedBox(height: 32),
                ElevatedButton.icon(
                  onPressed: _tryBiometric,
                  icon: const Icon(Icons.fingerprint_rounded),
                  label: const Text('Authenticate'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.secondary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // PIN (+ optional biometric) mode
    if (!_isUnlocked && _hasPin) {
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
          onSuccess: (pin) async {
            final ok = await PinService.verifyPin(pin);
            if (ok) {
              _unlock();
            } else {
              _pinKey.currentState?.showWrongPinError();
            }
          },
        ),
      );
    }

    ref.watch(insightNotificationWatcherProvider);
    ref.watch(paymentNotificationWatcherProvider);
    final router = ref.watch(appRouterProvider);

    // Reachable only once the app is unlocked (the lock-screen branches above
    // return early). Handles both a live "Yes" tap (fires via listen) and a
    // payload that was already pending before this widget first built (e.g.
    // a "Yes" tap while the app process was terminated, picked up in
    // main()) — ref.listen alone wouldn't see that initial value.
    void consumePendingPayment(DetectedPayment? payment) {
      if (payment == null) return;
      ref.read(pendingDetectedPaymentProvider.notifier).state = null;
      router.push('/add-transaction', extra: payment.toPrefillMap());
    }

    ref.listen<DetectedPayment?>(pendingDetectedPaymentProvider, (previous, next) {
      consumePendingPayment(next);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      consumePendingPayment(ref.read(pendingDetectedPaymentProvider));
    });

    return MaterialApp.router(
      title: 'Money App',
      theme: AppTheme.light,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
