import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:money_app_flutter/core/services/receipt_file_service.dart';

void main() {
  group('deleteReceiptFileBestEffort', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('receipt_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('deletes an existing file', () async {
      final file = File('${tempDir.path}/receipt.jpg');
      await file.writeAsBytes([1, 2, 3]);
      expect(await file.exists(), isTrue);

      await deleteReceiptFileBestEffort(file.path);

      expect(await file.exists(), isFalse);
    });

    test('does nothing (and does not throw) when path is null', () async {
      await deleteReceiptFileBestEffort(null);
    });

    test('does not throw when the file does not exist', () async {
      final missing = '${tempDir.path}/does_not_exist.jpg';
      await deleteReceiptFileBestEffort(missing);
    });

    test('a failure never propagates as an exception (best-effort)', () async {
      // A directory path passed as if it were a file — File.delete() on it
      // fails, but the helper must swallow that rather than throw.
      final dirAsFile = tempDir.path;
      await deleteReceiptFileBestEffort(dirAsFile);
      // Directory itself is untouched/still there — nothing corrupted.
      expect(await tempDir.exists(), isTrue);
    });
  });
}
