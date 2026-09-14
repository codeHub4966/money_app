import 'package:flutter/services.dart';

import 'payment_notification_router.dart';

/// Dart-side wrapper around the native Android `NotificationListenerService`
/// (`PaymentNotificationListenerService.kt`) — exposes a stream of
/// [RawPaymentNotification]s captured from the TNG/Gmail apps, plus
/// permission helpers. No-op (empty stream, `false`/no-op methods) on any
/// non-Android platform.
class PaymentNotificationListener {
  static final PaymentNotificationListener _instance = PaymentNotificationListener._();
  factory PaymentNotificationListener() => _instance;
  PaymentNotificationListener._();

  static const _methodChannel = MethodChannel('money_app/notification_access');
  static const _eventChannel = EventChannel('money_app/notification_events');

  Stream<RawPaymentNotification>? _stream;

  /// A broadcast stream of every notification the native listener captured
  /// from the monitored packages while this stream had a listener attached
  /// (plus a short buffered backlog from just before attaching).
  Stream<RawPaymentNotification> get notifications {
    return _stream ??= _eventChannel.receiveBroadcastStream().map((event) {
      return RawPaymentNotification.fromMap(Map<Object?, Object?>.from(event as Map));
    });
  }

  Future<bool> isAccessGranted() async {
    final granted = await _methodChannel.invokeMethod<bool>('isAccessGranted');
    return granted ?? false;
  }

  /// Opens the system "Notification access" settings page so the user can
  /// grant this app permission to read other apps' notifications.
  Future<void> openAccessSettings() async {
    await _methodChannel.invokeMethod<void>('openSettings');
  }
}
