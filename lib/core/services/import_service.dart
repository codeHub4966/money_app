import 'dart:io';
import 'dart:typed_data';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import '../../data/repositories/transaction_repository.dart';
import '../../data/repositories/wallet_repository.dart';
import '../../domain/models/transaction.dart';
import '../../domain/models/wallet.dart';
import 'export_service.dart' show pdfRowPrefix;
import 'pdf_text_extractor.dart';

/// Thrown when a picked file is not a CSV/PDF this app produced, or is
/// otherwise damaged/unreadable. The message is safe to show to the user.
class ImportValidationException implements Exception {
  final String message;
  ImportValidationException(this.message);
  @override
  String toString() => message;
}

class ImportSummary {
  final int imported;
  final int skippedDuplicates;
  final int invalidRows;

  const ImportSummary({
    required this.imported,
    required this.skippedDuplicates,
    required this.invalidRows,
  });

  @override
  String toString() =>
      'Imported: $imported, Skipped duplicates: $skippedDuplicates, Invalid rows: $invalidRows';
}

/// Asked when one or more rows reference a wallet id that doesn't exist in
/// this app. Should return the id of an existing wallet to use instead, or
/// `null` if the user cancelled (those rows are then reported as invalid).
typedef FallbackWalletResolver = Future<String?> Function(
    List<Wallet> existingWallets);

class _RawRow {
  final String id;
  final String type;
  final String amount;
  final String category;
  final String accountId;
  final String date;
  final String note;
  const _RawRow({
    required this.id,
    required this.type,
    required this.amount,
    required this.category,
    required this.accountId,
    required this.date,
    required this.note,
  });
}

class _PendingTx {
  final String id;
  final TransactionType type;
  final double amount;
  final String category;
  final String accountId;
  final String? note;
  final DateTime date;
  const _PendingTx({
    required this.id,
    required this.type,
    required this.amount,
    required this.category,
    required this.accountId,
    required this.note,
    required this.date,
  });

  _PendingTx withAccountId(String newAccountId) => _PendingTx(
        id: id,
        type: type,
        amount: amount,
        category: category,
        accountId: newAccountId,
        note: note,
        date: date,
      );
}

class ImportService {
  static const _csvHeader = [
    'id',
    'type',
    'amount',
    'category',
    'account',
    'note',
    'date'
  ];

  // ── CSV ─────────────────────────────────────────────────────────────────

  static List<_RawRow> _parseCsvRows(String content) {
    List<List<dynamic>> rows;
    try {
      // Accept files with either Unix (\n) or Windows (\r\n) line endings:
      // splitting on \n alone and trimming each field below absorbs a
      // trailing \r left on the last field of a \r\n-terminated row.
      rows = const CsvToListConverter(eol: '\n').convert(content);
    } catch (_) {
      throw ImportValidationException('This file is not a valid CSV file.');
    }
    if (rows.isEmpty) {
      throw ImportValidationException('This CSV file is empty.');
    }

    final header =
        rows.first.map((e) => e.toString().trim().toLowerCase()).toList();
    if (header.length < _csvHeader.length ||
        _csvHeader.asMap().entries.any((e) => header[e.key] != e.value)) {
      throw ImportValidationException(
          'This CSV file was not exported by this app.');
    }

    final result = <_RawRow>[];
    for (var i = 1; i < rows.length; i++) {
      final r = rows[i];
      if (r.isEmpty || (r.length == 1 && r[0].toString().trim().isEmpty))
        continue;
      result.add(_RawRow(
        id: r.isNotEmpty ? r[0].toString() : '',
        type: r.length > 1 ? r[1].toString() : '',
        amount: r.length > 2 ? r[2].toString() : '',
        category: r.length > 3 ? r[3].toString() : '',
        accountId: r.length > 4 ? r[4].toString() : '',
        note: r.length > 5 ? r[5].toString() : '',
        date: r.length > 6 ? r[6].toString() : '',
      ));
    }
    return result;
  }

  static Future<ImportSummary?> importCsv({
    required ITransactionRepository txRepo,
    required IWalletRepository walletRepo,
    required FallbackWalletResolver resolveFallbackWallet,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    if (result == null || result.files.single.path == null) return null;

    final content = File(result.files.single.path!).readAsStringSync();
    return importCsvContent(content,
        txRepo: txRepo,
        walletRepo: walletRepo,
        resolveFallbackWallet: resolveFallbackWallet);
  }

  /// Parses and imports [content] directly (no file picker) - the entry
  /// point used by [importCsv] and by tests.
  static Future<ImportSummary> importCsvContent(
    String content, {
    required ITransactionRepository txRepo,
    required IWalletRepository walletRepo,
    required FallbackWalletResolver resolveFallbackWallet,
  }) {
    final rawRows = _parseCsvRows(content);
    return _processRows(rawRows,
        txRepo: txRepo,
        walletRepo: walletRepo,
        resolveFallbackWallet: resolveFallbackWallet);
  }

  // ── PDF ─────────────────────────────────────────────────────────────────

  static List<_RawRow> _extractPdfRows(Uint8List bytes) {
    final lines = PdfTextExtractor.extractLines(bytes);
    final rowLines =
        lines.where((l) => l.startsWith('$pdfRowPrefix|')).toList();
    if (rowLines.isEmpty) {
      throw ImportValidationException('This PDF was not exported by this app.');
    }

    final result = <_RawRow>[];
    for (final line in rowLines) {
      final parts = line.split('|');
      // ROW|id|type|amount|category|accountId|date|note(optional, may itself
      // contain further '|' if it survived sanitization at export time)
      if (parts.length < 7) continue;
      result.add(_RawRow(
        id: parts[1],
        type: parts[2],
        amount: parts[3],
        category: parts[4],
        accountId: parts[5],
        date: parts[6],
        note: parts.length > 7 ? parts.sublist(7).join('|') : '',
      ));
    }
    return result;
  }

  static Future<ImportSummary?> importPdf({
    required ITransactionRepository txRepo,
    required IWalletRepository walletRepo,
    required FallbackWalletResolver resolveFallbackWallet,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result == null || result.files.single.path == null) return null;

    final bytes = File(result.files.single.path!).readAsBytesSync();
    return importPdfBytes(bytes,
        txRepo: txRepo,
        walletRepo: walletRepo,
        resolveFallbackWallet: resolveFallbackWallet);
  }

  /// Parses and imports [bytes] directly (no file picker) - the entry point
  /// used by [importPdf] and by tests.
  static Future<ImportSummary> importPdfBytes(
    Uint8List bytes, {
    required ITransactionRepository txRepo,
    required IWalletRepository walletRepo,
    required FallbackWalletResolver resolveFallbackWallet,
  }) {
    final rawRows = _extractPdfRows(bytes);
    return _processRows(rawRows,
        txRepo: txRepo,
        walletRepo: walletRepo,
        resolveFallbackWallet: resolveFallbackWallet);
  }

  // ── Shared validation / dedup / persistence ────────────────────────────

  static Future<ImportSummary> _processRows(
    List<_RawRow> rawRows, {
    required ITransactionRepository txRepo,
    required IWalletRepository walletRepo,
    required FallbackWalletResolver resolveFallbackWallet,
  }) async {
    final existingIds =
        (await txRepo.watchAll().first).map((t) => t.id).toSet();
    final wallets = await walletRepo.watchAll().first;
    final walletsById = {for (final w in wallets) w.id: w};

    var invalid = 0;
    var duplicates = 0;
    final seenIds = <String>{};
    final accepted = <_PendingTx>[];
    final needsFallback = <_PendingTx>[];

    for (final raw in rawRows) {
      final id = raw.id.trim();
      final amount = double.tryParse(raw.amount.trim());
      final category = raw.category.trim();
      final accountId = raw.accountId.trim();
      final date = DateTime.tryParse(raw.date.trim());
      final note = raw.note.trim();

      TransactionType? type;
      try {
        type = TransactionType.values.byName(raw.type.trim().toLowerCase());
      } catch (_) {
        type = null;
      }

      if (id.isEmpty ||
          type == null ||
          amount == null ||
          amount <= 0 ||
          category.isEmpty ||
          date == null ||
          accountId.isEmpty ||
          accountId == 'imported') {
        invalid++;
        continue;
      }

      if (existingIds.contains(id) || seenIds.contains(id)) {
        duplicates++;
        continue;
      }
      seenIds.add(id);

      final pending = _PendingTx(
        id: id,
        type: type,
        amount: amount,
        category: category,
        accountId: accountId,
        note: note.isEmpty ? null : note,
        date: date,
      );

      if (walletsById.containsKey(accountId)) {
        accepted.add(pending);
      } else {
        needsFallback.add(pending);
      }
    }

    if (needsFallback.isNotEmpty) {
      final fallbackId = await resolveFallbackWallet(wallets);
      if (fallbackId != null &&
          walletsById.containsKey(fallbackId) &&
          fallbackId != 'imported') {
        for (final p in needsFallback) {
          accepted.add(p.withAccountId(fallbackId));
        }
      } else {
        invalid += needsFallback.length;
      }
    }

    final balanceDelta = <String, double>{};
    for (final p in accepted) {
      await txRepo.add(Transaction(
        id: p.id,
        type: p.type,
        amount: p.amount,
        category: p.category,
        accountId: p.accountId,
        note: p.note,
        date: p.date,
      ));
      final delta = switch (p.type) {
        TransactionType.income => p.amount,
        TransactionType.expense => -p.amount,
        TransactionType.transfer => 0.0,
      };
      balanceDelta[p.accountId] = (balanceDelta[p.accountId] ?? 0) + delta;
    }

    for (final entry in balanceDelta.entries) {
      final wallet = walletsById[entry.key];
      if (wallet != null && entry.value != 0) {
        await walletRepo.updateBalance(wallet.id, wallet.balance + entry.value);
      }
    }

    return ImportSummary(
      imported: accepted.length,
      skippedDuplicates: duplicates,
      invalidRows: invalid,
    );
  }
}
