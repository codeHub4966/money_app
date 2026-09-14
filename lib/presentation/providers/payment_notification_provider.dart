import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/detected_payment_dedup_store.dart';
import '../../core/services/notification_service.dart';
import '../../core/services/payment_notification_listener.dart';
import '../../core/services/payment_notification_router.dart';
import '../../core/services/payment_notification_wallet_matcher.dart';
import '../../domain/models/detected_payment.dart';
import 'app_providers.dart';

/// Set (by `NotificationService`) when the user taps "Yes" on a detected-
/// payment confirmation notification; consumed once by `MoneyApp` to push
/// the prefilled Add Transaction route, then cleared back to null.
final pendingDetectedPaymentProvider = StateProvider<DetectedPayment?>((ref) => null);

/// Watches the native notification listener for the lifetime of the app and,
/// for every captured TNG/Gmail notification, routes it to a parser, skips
/// it if already handled (duplicate protection), resolves a best-effort
/// wallet suggestion, and shows the "Did you spend/transfer...?" confirmation
/// notification. Read once (e.g. `ref.watch(paymentNotificationWatcherProvider)`)
/// near the app root, mirroring `insightNotificationWatcherProvider`. Never
/// saves a transaction itself — that only happens once the user confirms via
/// the notification and then presses "Confirm Transaction" on the prefilled
/// Add Transaction screen.
final paymentNotificationWatcherProvider = Provider<void>((ref) {
  final dedupStore = DetectedPaymentDedupStore();
  final notifications = NotificationService();

  final subscription = PaymentNotificationListener().notifications.listen((raw) async {
    final categoryLabels =
        (ref.read(categoriesProvider)['expense'] ?? const []).map((c) => c.label).toList();
    final payment = PaymentNotificationRouter.route(raw, existingCategoryLabels: categoryLabels);
    if (payment == null) return;

    if (await dedupStore.isHandled(payment.notificationKey)) return;
    await dedupStore.markHandled(payment.notificationKey);

    final wallets = ref.read(walletsProvider).valueOrNull ?? const [];
    final wallet = PaymentNotificationWalletMatcher.match(
      sourceApp: payment.sourceApp,
      sourceName: payment.sourceName,
      wallets: wallets,
    );
    final withWallet = wallet == null
        ? payment
        : DetectedPayment(
            amount: payment.amount,
            merchantOrReceiver: payment.merchantOrReceiver,
            note: payment.note,
            suggestedCategory: payment.suggestedCategory,
            suggestedWalletId: wallet.id,
            sourceApp: payment.sourceApp,
            sourceName: payment.sourceName,
            dateTime: payment.dateTime,
            notificationKey: payment.notificationKey,
            isTransfer: payment.isTransfer,
          );

    final permissions = await notifications.checkPermissions();
    if (!permissions.notification) {
      final granted = await notifications.requestNotificationPermission();
      if (!granted) return;
    }
    await notifications.showDetectedPaymentNotification(withWallet);
  });

  ref.onDispose(subscription.cancel);
});
