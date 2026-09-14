package com.moneyapp.money_app_flutter

import android.content.Intent
import android.provider.Settings
import androidx.core.app.NotificationManagerCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val notificationAccessChannel = "money_app/notification_access"
    private val notificationEventsChannel = "money_app/notification_events"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, notificationAccessChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isAccessGranted" -> {
                        val enabled = NotificationManagerCompat.getEnabledListenerPackages(this)
                        result.success(enabled.contains(packageName))
                    }
                    "openSettings" -> {
                        startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, notificationEventsChannel)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    PaymentNotificationListenerService.attachSink(events)
                }

                override fun onCancel(arguments: Any?) {
                    PaymentNotificationListenerService.detachSink()
                }
            })
    }
}
