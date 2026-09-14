package com.moneyapp.money_app_flutter

import android.app.Notification
import android.os.Handler
import android.os.Looper
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import io.flutter.plugin.common.EventChannel

/**
 * Listens for notifications posted by the Touch 'n Go eWallet and Gmail apps
 * and forwards them to the Dart side (see `payment_notification_listener.dart`)
 * via [EventChannel]. This is the "Payment Notification Monitoring" module's
 * native entry point — it does not itself parse or decide anything about the
 * notification content, it only relays the raw title/text/bigText/subText.
 *
 * Requires the user to grant "Notification access" for this app in Android
 * system settings (see `MainActivity.openSettings` / `isAccessGranted`).
 *
 * While no Dart [EventChannel.EventSink] is attached (the Flutter engine
 * hasn't started yet, or the app process was killed and later relaunched), a
 * short capped backlog is buffered and flushed to the next sink that
 * attaches. This is a best-effort relay, not a guaranteed background queue —
 * the Dart side de-duplicates against a persisted key store
 * (`DetectedPaymentDedupStore`) so a flushed backlog never re-prompts for a
 * notification the user already confirmed/dismissed in an earlier session.
 */
class PaymentNotificationListenerService : NotificationListenerService() {

    companion object {
        private const val TNG_PACKAGE = "my.com.tngdigital.ewallet"
        private const val GMAIL_PACKAGE = "com.google.android.gm"
        private const val MAX_BUFFERED = 50

        @Volatile
        private var eventSink: EventChannel.EventSink? = null
        private val mainHandler = Handler(Looper.getMainLooper())
        private val buffer = ArrayDeque<Map<String, Any?>>()

        /** Called by [MainActivity] when a Dart listener attaches. */
        @Synchronized
        fun attachSink(sink: EventChannel.EventSink) {
            eventSink = sink
            while (buffer.isNotEmpty()) {
                val event = buffer.removeFirst()
                mainHandler.post { sink.success(event) }
            }
        }

        /** Called by [MainActivity] when the Dart listener detaches. */
        @Synchronized
        fun detachSink() {
            eventSink = null
        }

        @Synchronized
        private fun emit(event: Map<String, Any?>) {
            val sink = eventSink
            if (sink != null) {
                mainHandler.post { sink.success(event) }
            } else {
                if (buffer.size >= MAX_BUFFERED) buffer.removeFirst()
                buffer.addLast(event)
            }
        }
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        val packageName = sbn.packageName
        if (packageName != TNG_PACKAGE && packageName != GMAIL_PACKAGE) return

        val extras = sbn.notification.extras
        val event = mapOf(
            "packageName" to packageName,
            "key" to sbn.key,
            "postTime" to sbn.postTime,
            "title" to extras.getCharSequence(Notification.EXTRA_TITLE)?.toString(),
            "text" to extras.getCharSequence(Notification.EXTRA_TEXT)?.toString(),
            "bigText" to extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString(),
            "subText" to extras.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString()
        )
        emit(event)
    }
}
