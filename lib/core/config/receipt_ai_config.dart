/// Configuration for the Gemini receipt-fallback backend call.
///
/// Defaults to the deployed Render backend so the app works for a phone with
/// no connection to any dev machine at all (mobile data, a different Wi-Fi,
/// a real release build, ...). Override at build/run time for local dev
/// against the emulator alias or a LAN IP instead:
///   flutter run --dart-define=RECEIPT_AI_BACKEND_URL=http://10.0.2.2:8787
///   flutter run --dart-define=RECEIPT_AI_BACKEND_URL=http://192.168.1.50:8787
class ReceiptAiConfig {
  static const String backendBaseUrl = String.fromEnvironment(
    'RECEIPT_AI_BACKEND_URL',
    defaultValue: 'https://money-app-receipt-backend.onrender.com',
  );

  /// Client-side timeout for the whole backend round trip. Bounds how long
  /// receipt scanning can be blocked waiting on the AI fallback — past this,
  /// the local OCR/parser result is used instead. Kept well above the
  /// backend's own Gemini timeout (25s, see backend/server.js) so the
  /// backend can return a clean error response before the client gives up —
  /// and with extra headroom on top of that for Render's free-tier cold
  /// start, which can add 30-50s of delay before the request is even
  /// received when the backend has been idle.
  static const Duration timeout = Duration(seconds: 55);
}
