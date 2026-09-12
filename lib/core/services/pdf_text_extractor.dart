import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Extracts plain-text lines from a PDF's content streams.
///
/// This is intentionally not a general-purpose PDF text extractor: it only
/// understands the subset of PDF that `package:pdf` (used by
/// [ExportService]) produces for simple, non-embedded (Type1/base-14) fonts
/// - literal `Tj`/`TJ` text-showing operators positioned with `Td`/`TD`.
/// That is enough to recover the machine-readable rows this app writes into
/// its own PDF exports so they can be re-imported.
class PdfTextExtractor {
  static final _streamRe = RegExp(r'stream\r?\n');
  static final _btBlockRe = RegExp(r'BT(.*?)ET', dotAll: true);
  static final _tdRe = RegExp(r'(-?\d+\.?\d*)\s+(-?\d+\.?\d*)\s+T[dD]');
  static final _tjArrayRe = RegExp(r'\[(.*?)\]\s*TJ');
  static final _tjSingleRe = RegExp(r'\((?:[^()\\]|\\.)*\)\s*Tj');
  static final _literalRe = RegExp(r'\((?:[^()\\]|\\.)*\)');

  /// Returns every reconstructed text line found across all decodable
  /// content streams in [bytes], in no particular order.
  static List<String> extractLines(Uint8List bytes) {
    final raw = latin1.decode(bytes, allowInvalid: true);
    final lines = <String>[];

    for (final match in _streamRe.allMatches(raw)) {
      final start = match.end;
      final endIdx = raw.indexOf('endstream', start);
      if (endIdx == -1) continue;

      var streamBytes = bytes.sublist(start, endIdx);
      while (streamBytes.isNotEmpty &&
          (streamBytes.last == 0x0A || streamBytes.last == 0x0D)) {
        streamBytes = streamBytes.sublist(0, streamBytes.length - 1);
      }

      List<int> decoded;
      try {
        decoded = zlib.decode(streamBytes);
      } catch (_) {
        continue;
      }

      final content = latin1.decode(decoded, allowInvalid: true);
      lines.addAll(_extractLinesFromContentStream(content));
    }

    return lines;
  }

  static List<String> _extractLinesFromContentStream(String content) {
    // Group text fragments by their Y position so words drawn on the same
    // baseline (package:pdf emits one Tj/TJ per word) are reassembled back
    // into full lines, ordered left-to-right by X position.
    final byY = <double, List<MapEntry<double, String>>>{};

    for (final block in _btBlockRe.allMatches(content)) {
      final body = block.group(1)!;

      final tdMatches = _tdRe.allMatches(body).toList();
      if (tdMatches.isEmpty) continue;
      final lastTd = tdMatches.last;
      final x = double.tryParse(lastTd.group(1)!);
      final y = double.tryParse(lastTd.group(2)!);
      if (x == null || y == null) continue;

      final text = _extractText(body);
      if (text.isEmpty) continue;

      byY.putIfAbsent(y, () => []).add(MapEntry(x, text));
    }

    return byY.values.map((fragments) {
      fragments.sort((a, b) => a.key.compareTo(b.key));
      return fragments.map((e) => e.value).join(' ');
    }).toList();
  }

  static String _extractText(String btBody) {
    final arrayMatch = _tjArrayRe.firstMatch(btBody);
    if (arrayMatch != null) {
      final inner = arrayMatch.group(1)!;
      final buffer = StringBuffer();
      for (final lit in _literalRe.allMatches(inner)) {
        buffer.write(_decodeLiteral(lit.group(0)!));
      }
      return buffer.toString();
    }

    final singleMatch = _tjSingleRe.firstMatch(btBody);
    if (singleMatch != null) {
      final lit = _literalRe.firstMatch(singleMatch.group(0)!);
      if (lit != null) return _decodeLiteral(lit.group(0)!);
    }

    return '';
  }

  /// Decodes a PDF literal string `(...)`, handling the escapes package:pdf
  /// (and the PDF spec) may emit: `\n \r \t \( \) \\` and octal `\ddd`.
  static String _decodeLiteral(String literal) {
    final inner = literal.substring(1, literal.length - 1);
    final buffer = StringBuffer();
    for (var i = 0; i < inner.length; i++) {
      final c = inner[i];
      if (c != '\\' || i == inner.length - 1) {
        buffer.write(c);
        continue;
      }
      final next = inner[i + 1];
      switch (next) {
        case 'n':
          buffer.write('\n');
          i++;
          break;
        case 'r':
          buffer.write('\r');
          i++;
          break;
        case 't':
          buffer.write('\t');
          i++;
          break;
        case '(':
        case ')':
        case '\\':
          buffer.write(next);
          i++;
          break;
        default:
          if (RegExp(r'[0-7]').hasMatch(next)) {
            var j = i + 1;
            var octal = '';
            while (j < inner.length &&
                octal.length < 3 &&
                RegExp(r'[0-7]').hasMatch(inner[j])) {
              octal += inner[j];
              j++;
            }
            buffer.writeCharCode(int.parse(octal, radix: 8));
            i = j - 1;
          } else {
            buffer.write(next);
            i++;
          }
      }
    }
    return buffer.toString();
  }
}
