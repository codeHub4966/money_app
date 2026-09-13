import 'dart:convert';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

/// Lightweight learned mapping from a non-sensitive "payment fingerprint"
/// (currently: a card's last 4 digits) to a wallet id, so a generic clue
/// like "VISA ****1234" can resolve to a specific wallet once the user has
/// confirmed which wallet it actually is — without guessing on the very
/// first sighting, and without ever storing a full card number.
///
/// Backed by SharedPreferences (a single small JSON blob) rather than a new
/// database table/migration, since the amount of data involved is tiny.
class PaymentAliasStore {
  PaymentAliasStore._();

  static const _prefsKey = 'receipt_payment_aliases_v1';

  /// Card last-4 digits, e.g. from "VISA ****1234" or "CARD XXXX1234".
  /// Deliberately does NOT capture anything resembling a full card number —
  /// only ever the last 4 digits immediately after a masking run of `*`/`x`.
  static final RegExp _last4Pattern = RegExp(r'(?:\*{2,}|[xX]{2,})[\s-]*(\d{4})\b');

  /// Extracts a normalized payment fingerprint from raw receipt OCR text,
  /// or null when no such clue is present. Only ever returns a short,
  /// non-sensitive token (e.g. "last4:1234") — never a full card number.
  static String? extractFingerprint(String rawText) {
    final match = _last4Pattern.firstMatch(rawText);
    if (match == null) return null;
    return 'last4:${match.group(1)}';
  }

  static Future<Map<String, dynamic>> _readAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : {};
    } catch (_) {
      return {};
    }
  }

  static Future<void> _writeAll(Map<String, dynamic> map) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(map));
  }

  /// Looks up a previously-learned wallet id for [fingerprint], or null.
  static Future<String?> lookup(String fingerprint) async {
    final map = await _readAll();
    final walletId = map[fingerprint] as String?;
    if (kDebugMode) {
      debugPrint('[PaymentAliasStore] lookup "$fingerprint" -> $walletId');
    }
    return walletId;
  }

  /// Learns fingerprint -> [walletId], but ONLY from the user's final
  /// confirmed choice (call this at save time, never from an automatic
  /// guess). If the fingerprint already maps to a *different* wallet, this
  /// is a genuine conflict (e.g. a shared card, or a earlier mistaken
  /// confirmation) — rather than silently overwriting it, the stale mapping
  /// is cleared so it stops confidently suggesting the old wallet; a
  /// subsequent confirmation of the new wallet will then re-learn cleanly.
  static Future<void> learn(String fingerprint, String walletId) async {
    final map = await _readAll();
    final existing = map[fingerprint] as String?;

    if (existing != null && existing != walletId) {
      if (kDebugMode) {
        debugPrint('[PaymentAliasStore] conflict on "$fingerprint": '
            'was "$existing", now "$walletId" — clearing instead of overwriting');
      }
      map.remove(fingerprint);
    } else {
      if (kDebugMode) {
        debugPrint('[PaymentAliasStore] learned "$fingerprint" -> "$walletId"');
      }
      map[fingerprint] = walletId;
    }

    await _writeAll(map);
  }
}
