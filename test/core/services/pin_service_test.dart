import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:money_app_flutter/core/services/pin_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final Map<String, String> secureStore = {};

  setUp(() {
    secureStore.clear();
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, (call) async {
      switch (call.method) {
        case 'write':
          secureStore[call.arguments['key'] as String] =
              call.arguments['value'] as String;
          return null;
        case 'read':
          return secureStore[call.arguments['key'] as String];
        case 'delete':
          secureStore.remove(call.arguments['key'] as String);
          return null;
        case 'deleteAll':
          secureStore.clear();
          return null;
        case 'containsKey':
          return secureStore.containsKey(call.arguments['key'] as String);
        case 'readAll':
          return secureStore;
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, null);
  });

  group('PinService secure storage', () {
    test('verifyPin succeeds for the PIN that was set', () async {
      await PinService.setPin('1234');
      expect(await PinService.verifyPin('1234'), isTrue);
    });

    test('verifyPin rejects a wrong PIN', () async {
      await PinService.setPin('1234');
      expect(await PinService.verifyPin('0000'), isFalse);
    });

    test('verifyPin returns false when no PIN has ever been set', () async {
      expect(await PinService.verifyPin('1234'), isFalse);
    });

    test('hasPin reflects whether a PIN is currently set', () async {
      expect(await PinService.hasPin(), isFalse);
      await PinService.setPin('4321');
      expect(await PinService.hasPin(), isTrue);
    });

    test('never stores the raw PIN digits in secure storage', () async {
      await PinService.setPin('5678');
      expect(secureStore.values, isNot(contains('5678')));
    });

    test('deletePin removes the stored secure credential', () async {
      await PinService.setPin('1111');
      await PinService.deletePin();
      expect(await PinService.hasPin(), isFalse);
      expect(await PinService.verifyPin('1111'), isFalse);
    });
  });

  group('PinService legacy plaintext migration', () {
    test('verifyPin migrates a legacy plaintext PIN and removes the old key',
        () async {
      SharedPreferences.setMockInitialValues({'app_pin': '9999'});

      expect(await PinService.verifyPin('9999'), isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('app_pin'), isNull,
          reason: 'legacy plaintext key must be removed once migrated');
      expect(secureStore.values, isNot(contains('9999')),
          reason: 'the migrated value must be hashed, not stored raw');

      // Still verifies correctly against the now-secure representation.
      expect(await PinService.verifyPin('9999'), isTrue);
      expect(await PinService.verifyPin('0000'), isFalse);
    });

    test('hasPin migrates a legacy plaintext PIN too', () async {
      SharedPreferences.setMockInitialValues({'app_pin': '4242'});

      expect(await PinService.hasPin(), isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('app_pin'), isNull);
    });

    test('deletePin removes a legacy plaintext PIN as well', () async {
      SharedPreferences.setMockInitialValues({'app_pin': '1212'});

      await PinService.deletePin();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('app_pin'), isNull);
      expect(await PinService.hasPin(), isFalse);
    });

    test('a freshly-set PIN supersedes any un-migrated legacy value',
        () async {
      SharedPreferences.setMockInitialValues({'app_pin': '0001'});

      await PinService.setPin('9876');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('app_pin'), isNull);
      expect(await PinService.verifyPin('9876'), isTrue);
      expect(await PinService.verifyPin('0001'), isFalse);
    });
  });
}
