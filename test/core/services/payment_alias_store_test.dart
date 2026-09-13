import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:money_app_flutter/core/services/payment_alias_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('PaymentAliasStore.extractFingerprint', () {
    test('extracts only the last 4 digits from a masked card number', () {
      expect(PaymentAliasStore.extractFingerprint('VISA ****1234'), 'last4:1234');
      expect(PaymentAliasStore.extractFingerprint('CARD XXXX-5678'), 'last4:5678');
    });

    test('never captures a full card number as the fingerprint', () {
      final fingerprint = PaymentAliasStore.extractFingerprint('CARD NO: 4111111111111234');
      // No masking run ("****"/"xxxx") precedes the digits here, so this is
      // not treated as a card-last-4 clue at all — a full PAN must never be
      // stored, masked or not.
      expect(fingerprint, isNull);
    });

    test('returns null when there is no card clue at all', () {
      expect(PaymentAliasStore.extractFingerprint('CASH\nTOTAL 10.00'), isNull);
    });
  });

  group('PaymentAliasStore learning', () {
    test('a confirmed wallet choice is learned and can be looked up later', () async {
      await PaymentAliasStore.learn('last4:1234', 'wallet-maybank');
      expect(await PaymentAliasStore.lookup('last4:1234'), 'wallet-maybank');
    });

    test('an unknown fingerprint has no learned mapping', () async {
      expect(await PaymentAliasStore.lookup('last4:9999'), isNull);
    });

    test('re-confirming the same wallet keeps the mapping', () async {
      await PaymentAliasStore.learn('last4:1234', 'wallet-maybank');
      await PaymentAliasStore.learn('last4:1234', 'wallet-maybank');
      expect(await PaymentAliasStore.lookup('last4:1234'), 'wallet-maybank');
    });

    test('a conflicting confirmation does not silently remap to the new wallet', () async {
      await PaymentAliasStore.learn('last4:1234', 'wallet-maybank');
      // A different wallet confirmed for the same fingerprint is a genuine
      // conflict — it must not silently flip to the new wallet.
      await PaymentAliasStore.learn('last4:1234', 'wallet-cimb');
      final result = await PaymentAliasStore.lookup('last4:1234');
      expect(result, isNot('wallet-cimb'));
    });

    test('a fingerprint conflict does not affect other fingerprints', () async {
      await PaymentAliasStore.learn('last4:1234', 'wallet-maybank');
      await PaymentAliasStore.learn('last4:5678', 'wallet-cimb');
      await PaymentAliasStore.learn('last4:1234', 'wallet-cimb'); // conflict on 1234 only

      expect(await PaymentAliasStore.lookup('last4:5678'), 'wallet-cimb');
    });
  });

  group('PaymentAliasStore.clearAll', () {
    test('removes every learned mapping, e.g. as part of Delete All Data', () async {
      await PaymentAliasStore.learn('last4:1234', 'wallet-maybank');
      await PaymentAliasStore.learn('last4:5678', 'wallet-cimb');

      await PaymentAliasStore.clearAll();

      expect(await PaymentAliasStore.lookup('last4:1234'), isNull);
      expect(await PaymentAliasStore.lookup('last4:5678'), isNull);
    });
  });
}
