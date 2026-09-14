import '../../domain/models/transaction.dart';
import 'receipt_scanner_service.dart' show FieldConfidence, ReceiptScannerService;

// Parses OCR text scanned from a Public Bank mobile-app transaction-detail
// screen ("Money Sent" / "Money Paid") — a different source and layout from
// both a physical paper receipt and a Touch 'n Go eWallet screenshot, so
// this lives in its own file rather than extending [ReceiptScannerService]
// or reusing [TngReceiptParser]'s label patterns. Category suggestion is NOT
// reimplemented here: both [PublicBankReceiptParser.parseMoneySentText] and
// [PublicBankReceiptParser.parseMoneyPaidText] call
// [ReceiptScannerService.suggestCategory] directly.

/// Which Public Bank screen a scanned screenshot came from. The two screens
/// carry different fields and different note-building rules (see
/// [PublicBankReceiptParser.parseMoneySentText] /
/// [PublicBankReceiptParser.parseMoneyPaidText]).
enum PublicBankTransactionKind { moneySent, moneyPaid }

class PublicBankReceiptData {
  final PublicBankTransactionKind kind;
  final TransactionType transactionType;
  final double? amount;
  final DateTime? date;

  /// Money Sent only — null for a Money Paid screenshot.
  final String? recipientReference;

  /// Money Sent only — null for a Money Paid screenshot. Preserves the
  /// recipient name/account text even when OCR splits it across two lines.
  final String? recipientAccount;

  /// Money Paid only — null for a Money Sent screenshot.
  final String? recipientName;

  /// "Recipient Bank" (Money Sent) or "Recipient's Bank" (Money Paid).
  final String? recipientBank;

  /// Money Sent only — null for a Money Paid screenshot.
  final String? transferMethod;

  /// Money Paid only — null for a Money Sent screenshot.
  final String? paymentMethod;

  final String? fromAccount;

  final String? note;
  final String? category;
  final String rawText;

  final FieldConfidence amountConfidence;
  final FieldConfidence dateConfidence;
  final FieldConfidence recipientConfidence;
  final FieldConfidence categoryConfidence;

  const PublicBankReceiptData({
    required this.kind,
    required this.transactionType,
    this.amount,
    this.date,
    this.recipientReference,
    this.recipientAccount,
    this.recipientName,
    this.recipientBank,
    this.transferMethod,
    this.paymentMethod,
    this.fromAccount,
    this.note,
    this.category,
    required this.rawText,
    this.amountConfidence = FieldConfidence.missing,
    this.dateConfidence = FieldConfidence.missing,
    this.recipientConfidence = FieldConfidence.missing,
    this.categoryConfidence = FieldConfidence.missing,
  });

  bool get hasData => amount != null || date != null || recipientAccount != null || recipientName != null;
}

class PublicBankReceiptParser {
  // ─────────────────────────── Field labels ───────────────────────────

  static const String _moneyPaidWords = r'money\s*paid';
  static const String _moneySentWords = r'money\s*sent';
  static const String _publicBankWords = r'public\s*bank';
  static const String _referenceNoWords = r'reference\s*no\.?';
  static const String _dateTimeWords = r'date\s*(?:&|and)?\s*time';
  static const String _fromAccountWords = r'from\s*account';
  static const String _recipientNameWords = r'recipient\s*name';
  static const String _recipientAccountWords = r'recipient\s*account';
  static const String _recipientReferenceWords = r'recipient\s*reference';
  static const String _recipientBankWords = r"recipient'?s?\s*bank";
  static const String _transferMethodWords = r'transfer\s*method';
  static const String _paymentMethodWords = r'payment\s*method';
  static const String _duitNowRefNoWords = r'duitnow\s*ref(?:erence)?\.?\s*no\.?';
  static const String _duitNowStatusCodeWords = r'duitnow\s*status\s*code';

  // Every per-field label recognised above (deliberately excluding the
  // "Money Sent"/"Money Paid"/"Public Bank" screen titles — those are only
  // ever page headers, and "Public Bank" in particular can legitimately be
  // a field VALUE too, e.g. a Recipient Bank of "Public Bank") — used so a
  // labelled value is never mistaken for the next label's own line, and so
  // a value split across two OCR lines (e.g. Recipient Account) knows where
  // to stop joining.
  static const String _anyLabelWords =
      '$_referenceNoWords|$_dateTimeWords|$_fromAccountWords|$_recipientNameWords|'
      '$_recipientAccountWords|$_recipientReferenceWords|$_recipientBankWords|'
      '$_transferMethodWords|$_paymentMethodWords|$_duitNowRefNoWords|$_duitNowStatusCodeWords|amount';

  static final RegExp _anyKnownLabelLine = _standalonePattern(_anyLabelWords);

  // Matches a line that consists ONLY of the label (e.g. "Recipient
  // Reference" or "Recipient Reference:") — the Public Bank app's stacked
  // layout, where the value OCRs onto the following line.
  static RegExp _standalonePattern(String labelAlternation) {
    return RegExp(r'^(?:' + labelAlternation + r')\s*:?\s*$', caseSensitive: false);
  }

  // Matches "Label: value" / "Label - value" on a single line.
  static RegExp _inlinePattern(String labelAlternation) {
    return RegExp(r'^(?:' + labelAlternation + r')\s*[:\-]\s*(.+)$', caseSensitive: false);
  }

  // ─────────────────────────── Detection ───────────────────────────

  static final RegExp _moneyPaidPattern = RegExp(_moneyPaidWords, caseSensitive: false);
  static final RegExp _moneySentPattern = RegExp(_moneySentWords, caseSensitive: false);
  static final RegExp _publicBankPattern = RegExp(_publicBankWords, caseSensitive: false);
  static final RegExp _referenceNoPattern = RegExp(_referenceNoWords, caseSensitive: false);
  static final RegExp _dateTimePattern = RegExp(_dateTimeWords, caseSensitive: false);
  static final RegExp _fromAccountPattern = RegExp(_fromAccountWords, caseSensitive: false);
  static final RegExp _recipientNamePattern = RegExp(_recipientNameWords, caseSensitive: false);
  static final RegExp _recipientAccountPattern = RegExp(_recipientAccountWords, caseSensitive: false);
  static final RegExp _recipientReferencePattern = RegExp(_recipientReferenceWords, caseSensitive: false);
  static final RegExp _duitNowRefNoPattern = RegExp(_duitNowRefNoWords, caseSensitive: false);
  static final RegExp _transferMethodPattern = RegExp(_transferMethodWords, caseSensitive: false);

  /// Whether [rawText] is confidently a Public Bank "Money Sent"/"Money
  /// Paid" transaction-detail screen, based on a combination of Public
  /// Bank-specific field labels rather than any single one of them (several
  /// of these labels, e.g. "Reference No." or "From Account", are generic
  /// enough to appear on other banking screenshots too).
  static bool looksLikePublicBankReceipt(String rawText) {
    var score = 0;
    if (_moneyPaidPattern.hasMatch(rawText)) score += 2;
    if (_moneySentPattern.hasMatch(rawText)) score += 2;
    if (_publicBankPattern.hasMatch(rawText)) score += 2;
    if (_referenceNoPattern.hasMatch(rawText)) score += 1;
    if (_dateTimePattern.hasMatch(rawText)) score += 1;
    if (_fromAccountPattern.hasMatch(rawText)) score += 1;
    if (_recipientNamePattern.hasMatch(rawText)) score += 1;
    if (_recipientAccountPattern.hasMatch(rawText)) score += 1;
    if (_recipientReferencePattern.hasMatch(rawText)) score += 1;
    if (_duitNowRefNoPattern.hasMatch(rawText)) score += 1;
    if (_transferMethodPattern.hasMatch(rawText)) score += 1;
    return score >= 3;
  }

  // ─────────────────────────── Amount ───────────────────────────

  static final RegExp _amountPattern = RegExp(
    r'[-+]?\s*(?:rm|myr)\s*(\d{1,3}(?:,\d{3})*\.\d{2})|'
    r'[-+]\s*(\d{1,3}(?:,\d{3})*\.\d{2})',
    caseSensitive: false,
  );

  static (double?, FieldConfidence) _extractAmount(List<String> lines) {
    for (final line in lines) {
      final match = _amountPattern.firstMatch(line);
      if (match == null) continue;
      final raw = (match.group(1) ?? match.group(2))!.replaceAll(',', '');
      final value = double.tryParse(raw);
      if (value != null) return (value, FieldConfidence.high);
    }
    return (null, FieldConfidence.missing);
  }

  // ─────────────────────────── Date/Time ───────────────────────────

  static const _months = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };

  // "15 Sep 2026, 2:32 PM" / "15 Sep 2026 14:32:10"
  static final RegExp _monthNameDatePattern = RegExp(
    r'(\d{1,2})\s+(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\s+(\d{4})'
    r'(?:[,]?\s*(\d{1,2}):(\d{2})(?::(\d{2}))?\s*(am|pm)?)?',
    caseSensitive: false,
  );

  // "15/09/2026, 14:32" / "15-09-2026 2:32 PM"
  static final RegExp _numericDatePattern = RegExp(
    r'(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{2,4})'
    r'(?:[,]?\s*(\d{1,2}):(\d{2})(?::(\d{2}))?\s*(am|pm)?)?',
  );

  static int _to24Hour(int hour, String? ampm) {
    if (ampm == null) return hour;
    final isPm = ampm.toLowerCase() == 'pm';
    if (isPm && hour != 12) return hour + 12;
    if (!isPm && hour == 12) return 0;
    return hour;
  }

  static DateTime? _tryParseDateTimeFromLine(String line) {
    final monthMatch = _monthNameDatePattern.firstMatch(line);
    if (monthMatch != null) {
      final day = int.parse(monthMatch.group(1)!);
      final month = _months[monthMatch.group(2)!.toLowerCase().substring(0, 3)];
      final year = int.parse(monthMatch.group(3)!);
      if (month == null) return null;
      final hour = monthMatch.group(4) != null ? int.parse(monthMatch.group(4)!) : 0;
      final minute = monthMatch.group(5) != null ? int.parse(monthMatch.group(5)!) : 0;
      final second = monthMatch.group(6) != null ? int.parse(monthMatch.group(6)!) : 0;
      return DateTime(year, month, day, _to24Hour(hour, monthMatch.group(7)), minute, second);
    }

    final numericMatch = _numericDatePattern.firstMatch(line);
    if (numericMatch != null) {
      final day = int.parse(numericMatch.group(1)!);
      final month = int.parse(numericMatch.group(2)!);
      var year = int.parse(numericMatch.group(3)!);
      if (year < 100) year += (year > 50 ? 1900 : 2000);
      if (month < 1 || month > 12) return null;
      final hour = numericMatch.group(4) != null ? int.parse(numericMatch.group(4)!) : 0;
      final minute = numericMatch.group(5) != null ? int.parse(numericMatch.group(5)!) : 0;
      final second = numericMatch.group(6) != null ? int.parse(numericMatch.group(6)!) : 0;
      return DateTime(year, month, day, _to24Hour(hour, numericMatch.group(7)), minute, second);
    }

    return null;
  }

  static (DateTime?, FieldConfidence) _extractDateTime(List<String> lines) {
    for (final line in lines) {
      final parsed = _tryParseDateTimeFromLine(line);
      if (parsed != null) return (parsed, FieldConfidence.high);
    }
    return (null, FieldConfidence.missing);
  }

  // ─────────────────────────── Labelled fields ───────────────────────────

  /// Reads a value introduced by [labelWords], either inline on the same
  /// line ("Label: value") or, as the Public Bank app's stacked layout
  /// usually OCRs, on the next non-empty line below a standalone "Label"
  /// line. Stops without a value if that next line is itself another known
  /// label — meaning the field was printed with nothing under it.
  static (String?, int?) _extractLabeledValueWithIndex(List<String> lines, String labelWords) {
    final standalonePattern = _standalonePattern(labelWords);
    final inlinePattern = _inlinePattern(labelWords);

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();

      final inlineMatch = inlinePattern.firstMatch(line);
      if (inlineMatch != null) {
        final value = inlineMatch.group(1)!.trim();
        if (value.isNotEmpty) return (value, i);
      }

      if (standalonePattern.hasMatch(line)) {
        for (var j = i + 1; j < lines.length; j++) {
          final next = lines[j].trim();
          if (next.isEmpty) continue;
          if (_anyKnownLabelLine.hasMatch(next)) return (null, null);
          return (next, j);
        }
      }
    }
    return (null, null);
  }

  /// Like [_extractLabeledValueWithIndex], but when [maxJoinLines] > 0 also
  /// appends up to that many further non-empty lines that follow the value
  /// — stopping as soon as a known label line is reached. This is what lets
  /// "Recipient Account" recombine a name line and an account-number line
  /// that OCR split apart (e.g. "CHANG NYET CHING O/B AU" then
  /// "4450438109"), without ever swallowing the next field's own label.
  static String? _extractLabeledValue(
    List<String> lines,
    String labelWords, {
    int maxJoinLines = 0,
  }) {
    final (value, index) = _extractLabeledValueWithIndex(lines, labelWords);
    if (value == null || index == null) return null;
    if (maxJoinLines <= 0) return value;

    final parts = [value];
    var joined = 0;
    for (var j = index + 1; j < lines.length && joined < maxJoinLines; j++) {
      final next = lines[j].trim();
      if (next.isEmpty) continue;
      if (_anyKnownLabelLine.hasMatch(next)) break;
      parts.add(next);
      joined++;
    }
    return parts.join(' ');
  }

  static List<String> _splitLines(String rawText) {
    return rawText.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  }

  // ─────────────────────────── Public API ───────────────────────────

  /// Parses a Public Bank "Money Sent" transaction-detail screenshot (a
  /// DuitNow/bank transfer). Transaction type is always
  /// [TransactionType.expense].
  ///
  /// - When Recipient Reference is present, the note is "<Recipient
  ///   Reference> - Sent to <Recipient Account>" and category is suggested
  ///   from the Recipient Reference text alone (never the account/bank).
  /// - When Recipient Reference is missing/empty, the note is "Sent to
  ///   <Recipient Account>" and no category is auto-selected.
  static PublicBankReceiptData parseMoneySentText(
    String rawText, {
    List<String> existingCategoryLabels = const [],
  }) {
    final lines = _splitLines(rawText);

    final (amount, amountConfidence) = _extractAmount(lines);
    final (date, dateConfidence) = _extractDateTime(lines);
    final recipientReference = _extractLabeledValue(lines, _recipientReferenceWords);
    final recipientAccount = _extractLabeledValue(
      lines,
      _recipientAccountWords,
      maxJoinLines: 1,
    );
    final recipientBank = _extractLabeledValue(lines, _recipientBankWords);
    final transferMethod = _extractLabeledValue(lines, _transferMethodWords);
    final fromAccount = _extractLabeledValue(lines, _fromAccountWords);

    final recipientConfidence =
        recipientAccount != null && recipientAccount.isNotEmpty ? FieldConfidence.high : FieldConfidence.missing;

    String? note;
    String? category;
    var categoryConfidence = FieldConfidence.missing;

    if (recipientAccount != null && recipientAccount.isNotEmpty) {
      if (recipientReference != null && recipientReference.isNotEmpty) {
        note = '$recipientReference - Sent to $recipientAccount';
        final (suggested, confidence) = ReceiptScannerService.suggestCategory(
          itemDescriptions: [recipientReference],
          existingCategoryLabels: existingCategoryLabels,
        );
        category = suggested;
        categoryConfidence = confidence;
      } else {
        note = 'Sent to $recipientAccount';
      }
    }

    return PublicBankReceiptData(
      kind: PublicBankTransactionKind.moneySent,
      transactionType: TransactionType.expense,
      amount: amount,
      date: date,
      recipientReference: recipientReference,
      recipientAccount: recipientAccount,
      recipientBank: recipientBank,
      transferMethod: transferMethod,
      fromAccount: fromAccount,
      note: note,
      category: category,
      rawText: rawText,
      amountConfidence: amountConfidence,
      dateConfidence: dateConfidence,
      recipientConfidence: recipientConfidence,
      categoryConfidence: categoryConfidence,
    );
  }

  /// Parses a Public Bank "Money Paid" transaction-detail screenshot (a
  /// merchant/biller payment). Transaction type is always
  /// [TransactionType.expense].
  ///
  /// - The note is always "Paid to <Recipient Name>".
  /// - Category is suggested from the Recipient Name text alone; a
  ///   payment never auto-selects a category just because it's a payment —
  ///   only when the name itself matches a keyword.
  static PublicBankReceiptData parseMoneyPaidText(
    String rawText, {
    List<String> existingCategoryLabels = const [],
  }) {
    final lines = _splitLines(rawText);

    final (amount, amountConfidence) = _extractAmount(lines);
    final (date, dateConfidence) = _extractDateTime(lines);
    final recipientName = _extractLabeledValue(lines, _recipientNameWords);
    final recipientBank = _extractLabeledValue(lines, _recipientBankWords);
    final paymentMethod = _extractLabeledValue(lines, _paymentMethodWords);
    final fromAccount = _extractLabeledValue(lines, _fromAccountWords);

    final recipientConfidence =
        recipientName != null && recipientName.isNotEmpty ? FieldConfidence.high : FieldConfidence.missing;

    String? note;
    String? category;
    var categoryConfidence = FieldConfidence.missing;

    if (recipientName != null && recipientName.isNotEmpty) {
      note = 'Paid to $recipientName';
      final (suggested, confidence) = ReceiptScannerService.suggestCategory(
        itemDescriptions: [recipientName],
        existingCategoryLabels: existingCategoryLabels,
      );
      category = suggested;
      categoryConfidence = confidence;
    }

    return PublicBankReceiptData(
      kind: PublicBankTransactionKind.moneyPaid,
      transactionType: TransactionType.expense,
      amount: amount,
      date: date,
      recipientName: recipientName,
      recipientBank: recipientBank,
      paymentMethod: paymentMethod,
      fromAccount: fromAccount,
      note: note,
      category: category,
      rawText: rawText,
      amountConfidence: amountConfidence,
      dateConfidence: dateConfidence,
      recipientConfidence: recipientConfidence,
      categoryConfidence: categoryConfidence,
    );
  }
}
