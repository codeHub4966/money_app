import 'package:shared_preferences/shared_preferences.dart';

/// Persists recently-handled [DetectedPayment.notificationKey]s so the same
/// underlying notification never produces two confirmation prompts — even
/// across app restarts, per the spec's "Duplicate protection" requirement
/// ("restarting the Flutter UI does not immediately re-trigger old
/// notifications"). Backed by `SharedPreferences`, matching the persistence
/// convention already used by `insight_notification_provider.dart`.
class DetectedPaymentDedupStore {
  static const _prefsKey = 'handled_payment_notification_keys';

  /// Capped so the persisted list can't grow unbounded over the app's
  /// lifetime — only the most recent entries need to be remembered, since
  /// older notifications will never be redelivered by the OS anyway.
  static const _maxEntries = 200;

  Future<bool> isHandled(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final handled = prefs.getStringList(_prefsKey) ?? const <String>[];
    return handled.contains(key);
  }

  Future<void> markHandled(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final handled = (prefs.getStringList(_prefsKey) ?? const <String>[]).toList();
    if (handled.contains(key)) return;
    handled.add(key);
    final trimmed =
        handled.length > _maxEntries ? handled.sublist(handled.length - _maxEntries) : handled;
    await prefs.setStringList(_prefsKey, trimmed);
  }
}
