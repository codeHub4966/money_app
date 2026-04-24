import 'dart:io';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import '../../domain/models/transaction.dart';
import '../../data/repositories/transaction_repository.dart';

class ExportService {
  static Future<void> exportCsv(List<Transaction> transactions) async {
    final rows = [
      ['ID', 'Type', 'Amount', 'Category', 'Account', 'Note', 'Date'],
      ...transactions.map((t) => [
        t.id, t.type.name, t.amount, t.category,
        t.accountId, t.note ?? '', t.date.toIso8601String(),
      ]),
    ];
    final csv = const ListToCsvConverter().convert(rows);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/transactions.csv')..writeAsStringSync(csv);
    await Share.shareXFiles([XFile(file.path)], subject: 'Transactions Export');
  }

  static Future<void> exportPdf(List<Transaction> transactions) async {
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      build: (ctx) => [
        pw.Text('Transaction History', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 16),
        pw.Table.fromTextArray(
          headers: ['Date', 'Type', 'Category', 'Amount', 'Note'],
          data: transactions.map((t) => [
            t.date.toLocal().toString().substring(0, 16),
            t.type.name,
            t.category,
            'RM${t.amount.toStringAsFixed(2)}',
            t.note ?? '',
          ]).toList(),
        ),
      ],
    ));
    await Printing.sharePdf(bytes: await doc.save(), filename: 'transactions.pdf');
  }

  static Future<void> importCsv(ITransactionRepository repo) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    if (result == null) return;
    final content = File(result.files.single.path!).readAsStringSync();
    final rows = const CsvToListConverter().convert(content);
    for (int i = 1; i < rows.length; i++) {
      final r = rows[i];
      if (r.length < 7) continue;
      await repo.add(Transaction(
        id: r[0].toString(),
        type: TransactionType.values.byName(r[1].toString()),
        amount: double.tryParse(r[2].toString()) ?? 0,
        category: r[3].toString(),
        accountId: r[4].toString(),
        note: r[5].toString().isEmpty ? null : r[5].toString(),
        date: DateTime.tryParse(r[6].toString()) ?? DateTime.now(),
      ));
    }
  }

  static Future<void> importPdf(ITransactionRepository repo) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result == null) return;
    // Parse lines matching: date | type | category | RM amount | note
    final bytes = File(result.files.single.path!).readAsBytesSync();
    final text = await _extractPdfText(bytes);
    final lines = text.split('\n').where((l) => l.contains('RM')).toList();
    for (final line in lines) {
      final parts = line.split(RegExp(r'\s{2,}'));
      if (parts.length < 4) continue;
      final amount = double.tryParse(parts[3].replaceAll('RM', '').trim());
      if (amount == null) continue;
      await repo.add(Transaction(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        type: TransactionType.values.byName(parts[1].trim().toLowerCase()),
        amount: amount,
        category: parts[2].trim(),
        accountId: 'imported',
        note: parts.length > 4 ? parts[4].trim() : null,
        date: DateTime.tryParse(parts[0].trim()) ?? DateTime.now(),
      ));
    }
  }

  static Future<String> _extractPdfText(List<int> bytes) async {
    final buffer = StringBuffer();
    await for (final page in Printing.raster(bytes as dynamic)) {
      buffer.writeln(page.toString());
    }
    return buffer.toString();
  }
}
