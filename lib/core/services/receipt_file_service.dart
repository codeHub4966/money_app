import 'dart:io';

/// Best-effort deletion of a receipt image file at [path]. Never throws — a
/// failed cleanup (e.g. the file is already gone, or a transient I/O error)
/// must never corrupt or roll back otherwise-valid transaction data. Callers
/// should only invoke this after the related database write has succeeded.
Future<void> deleteReceiptFileBestEffort(String? path) async {
  if (path == null) return;
  try {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  } catch (_) {
    // Best-effort cleanup only — ignore failures.
  }
}
