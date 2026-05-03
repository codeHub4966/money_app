import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_auth/local_auth.dart';

class PinService {
  static const _key = 'app_pin';
  static const _biometricKey = 'biometric_enabled';
  static final LocalAuthentication _localAuth = LocalAuthentication();

  static Future<String?> getPin() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key);
  }

  static Future<void> setPin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, pin);
  }

  static Future<void> deletePin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
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
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );
      // Slight delay to ensure app lifecycle resumes before clearing the flag
      await Future.delayed(const Duration(milliseconds: 500));
      isAuthenticating = false;
      return result;
    } catch (e) {
      isAuthenticating = false;
      return false;
    }
  }
}
