import 'dart:io';
import 'dart:typed_data';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import '../../domain/models/transaction.dart';

/// Marker line prefix for the machine-readable transaction rows embedded in
/// exported PDFs, so [ImportService] can find them again while ignoring the
/// human-readable summary table around them.
const String pdfRowPrefix = 'ROW';

class ExportService {
  static String buildCsvString(List<Transaction> transactions) {
    final rows = [
      ['ID', 'Type', 'Amount', 'Category', 'Account', 'Note', 'Date'],
      ...transactions.map((t) => [
            t.id,
            t.type.name,
            t.amount,
            t.category,
            t.accountId,
            t.note ?? '',
            t.date.toIso8601String(),
          ]),
    ];
    return const ListToCsvConverter().convert(rows);
  }

  static Future<void> exportCsv(List<Transaction> transactions) async {
    final csv = buildCsvString(transactions);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/transactions.csv')..writeAsStringSync(csv);
    await Share.shareXFiles([XFile(file.path)], subject: 'Transactions Export');
  }

  /// A field that must survive the round-trip through the PDF's plain-text
  /// data rows without being confused for the `|` field separator or
  /// splitting across multiple lines.
  static String _sanitizeField(String s) =>
      s.replaceAll('|', '/').replaceAll(RegExp(r'\s+'), ' ').trim();

  static Future<Uint8List> buildPdfBytes(List<Transaction> transactions) async {
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      build: (ctx) => [
        pw.Text('Transaction History',
            style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 16),
        pw.Table.fromTextArray(
          headers: ['Date', 'Type', 'Category', 'Amount', 'Note'],
          data: transactions
              .map((t) => [
                    t.date.toLocal().toString().substring(0, 16),
                    t.type.name,
                    t.category,
                    'RM${t.amount.toStringAsFixed(2)}',
                    t.note ?? '',
                  ])
              .toList(),
        ),
        pw.SizedBox(height: 24),
        pw.Text('Import Data (auto-generated - do not edit)',
            style: pw.TextStyle(fontSize: 8, fontStyle: pw.FontStyle.italic)),
        pw.SizedBox(height: 4),
        // One machine-readable line per transaction so this exact file can be
        // re-imported later with full fidelity (id, wallet and exact date),
        // which the visual table above intentionally omits for readability.
        ...transactions.map((t) => pw.Text(
              [
                pdfRowPrefix,
                _sanitizeField(t.id),
                t.type.name,
                t.amount.toString(),
                _sanitizeField(t.category),
                _sanitizeField(t.accountId),
                t.date.toIso8601String(),
                _sanitizeField(t.note ?? ''),
              ].join('|'),
              style: pw.TextStyle(fontSize: 6),
              softWrap: false,
              maxLines: 1,
            )),
      ],
    ));
    return doc.save();
  }

  static Future<void> exportPdf(List<Transaction> transactions) async {
    final bytes = await buildPdfBytes(transactions);
    await Printing.sharePdf(bytes: bytes, filename: 'transactions.pdf');
  }
}
