/// Configuration for the Gemini receipt-fallback backend call.
///
/// The backend URL defaults to the Android emulator's alias for the host
/// machine's localhost (10.0.2.2). Override at build/run time for a physical
/// device, iOS simulator, or a deployed backend:
///   flutter run --dart-define=RECEIPT_AI_BACKEND_URL=http://192.168.1.50:8787
class ReceiptAiConfig {
  static const String backendBaseUrl = String.fromEnvironment(
    'RECEIPT_AI_BACKEND_URL',
    defaultValue: 'http://10.0.2.2:8787',
  );

  /// Client-side timeout for the whole backend round trip. Kept above the
  /// backend's own Gemini timeout (25s, see backend/server.js) so the
  /// backend can return a clean error response before the client gives up.
  static const Duration timeout = Duration(seconds: 30);
}
