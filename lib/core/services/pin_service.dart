import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_auth/local_auth.dart';

class PinService {
  static const _secureHashKey = 'app_pin_hash_v1';
  // Legacy plaintext key from before secure storage was introduced. Only
  // ever read once, to migrate; never written to again.
  static const _legacyPlaintextKey = 'app_pin';
  static const _biometricKey = 'biometric_enabled';
  // Fixed, app-specific salt (not a secret on its own) so a bare SHA-256
  // rainbow-table lookup of a raw 4-digit PIN doesn't work against this hash.
  static const _pinSalt = 'money_app_flutter::pin::v1';

  static const _storage = FlutterSecureStorage();
  static final LocalAuthentication _localAuth = LocalAuthentication();

  static String _hashPin(String pin) =>
      sha256.convert(utf8.encode('$_pinSalt:$pin')).toString();

  /// Migrates a legacy plaintext PIN (SharedPreferences) to the secure
  /// hashed representation, if one is still present. The old plaintext key
  /// is removed only after the secure write succeeds. Safe to call
  /// repeatedly — a no-op once migrated.
  static Future<void> _migrateLegacyPinIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final legacyPin = prefs.getString(_legacyPlaintextKey);
    if (legacyPin == null) return;
    await _storage.write(key: _secureHashKey, value: _hashPin(legacyPin));
    await prefs.remove(_legacyPlaintextKey);
  }

  /// Whether a PIN is currently set.
  static Future<bool> hasPin() async {
    await _migrateLegacyPinIfNeeded();
    final hash = await _storage.read(key: _secureHashKey);
    return hash != null;
  }

  static Future<void> setPin(String pin) async {
    await _storage.write(key: _secureHashKey, value: _hashPin(pin));
    // A freshly-set PIN supersedes any not-yet-migrated legacy value.
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_legacyPlaintextKey);
  }

  /// Compares [candidate] against the stored derived PIN value. Never
  /// exposes or logs the stored or entered PIN.
  static Future<bool> verifyPin(String candidate) async {
    await _migrateLegacyPinIfNeeded();
    final hash = await _storage.read(key: _secureHashKey);
    if (hash == null) return false;
    return hash == _hashPin(candidate);
  }

  static Future<void> deletePin() async {
    await _storage.delete(key: _secureHashKey);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_legacyPlaintextKey);
  }

  static Future<bool> isBiometricEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_biometricKey) ?? false;
  }

  static Future<void> setBiometricEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_biometricKey, enabled);
  }

  static Future<bool> canUseBiometric() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isDeviceSupported = await _localAuth.isDeviceSupported();
      return canCheck && isDeviceSupported;
    } catch (e) {
      return false;
    }
  }

  static bool isAuthenticating = false;

  static Future<bool> authenticateWithBiometric({String reason = 'Authenticate to unlock Money App'}) async {
    isAuthenticating = true;
    try {
      final result = await _localAuth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(stickyAuth: true, biometricOnly: true),
      );
      await Future.delayed(const Duration(milliseconds: 500));
      isAuthenticating = false;
      return result;
    } catch (e) {
      isAuthenticating = false;
      return false;
    }
  }
}
