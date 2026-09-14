import 'package:flutter_test/flutter_test.dart';
import 'package:money_app_flutter/core/services/detected_payment_dedup_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('DetectedPaymentDedupStore', () {
    test('an unseen key is not handled', () async {
      final store = DetectedPaymentDedupStore();
      expect(await store.isHandled('tng|key1|5.40|65 ondo-gunung rapat|2026-09-14'), isFalse);
    });

    test('duplicate notification: a key marked handled is reported handled afterwards', () async {
      final store = DetectedPaymentDedupStore();
      const key = 'tng|key1|5.40|65 ondo-gunung rapat|2026-09-14';

      await store.markHandled(key);

      expect(await store.isHandled(key), isTrue);
    });

    test('marking the same key handled twice does not duplicate the entry', () async {
      final store = DetectedPaymentDedupStore();
      const key = 'tng|key1|5.40|65 ondo-gunung rapat|2026-09-14';

      await store.markHandled(key);
      await store.markHandled(key);

      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getStringList('handled_payment_notification_keys') ?? [];
      expect(stored.where((k) => k == key).length, 1);
    });

    test('persists across a fresh store instance (survives a Flutter UI restart)', () async {
      const key = 'gmail|key2|0.01|au xiao yew|2026-09-14T10:00:00.000';
      await DetectedPaymentDedupStore().markHandled(key);

      // A new instance (simulating a restarted Flutter UI) still sees it as
      // handled, since the underlying SharedPreferences state persists.
      final freshStore = DetectedPaymentDedupStore();
      expect(await freshStore.isHandled(key), isTrue);
    });

    test('an unrelated key is not affected by another key being marked handled', () async {
      final store = DetectedPaymentDedupStore();
      await store.markHandled('tng|key1|5.40|merchant a|2026-09-14');
      expect(await store.isHandled('tng|key2|5.40|merchant b|2026-09-14'), isFalse);
    });
  });
}
