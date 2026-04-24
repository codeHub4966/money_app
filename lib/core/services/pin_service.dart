import 'package:shared_preferences/shared_preferences.dart';

class PinService {
  static const _key = 'app_pin';

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
}
