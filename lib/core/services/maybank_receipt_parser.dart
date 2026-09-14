import '../../domain/models/transaction.dart';
import 'receipt_scanner_service.dart' show FieldConfidence, ReceiptScannerService;

// Parses OCR text scanned from a Maybank app transaction-detail screen — a
// different source and layout from a physical paper receipt, a Touch 'n Go
// eWallet screenshot, and a Public Bank transaction-detail screen, so this
// lives in its own file rather than mixing Maybank-specific label patterns
// into [TngReceiptParser] or a traditional receipt parser. Category
// suggestion is NOT reimplemented here: every parse* method below calls
// [ReceiptScannerService.suggestCategory] directly, via the private
// [MaybankReceiptParser._suggestCategory] wrapper.
//
// Two Maybank receipt types ([MaybankReceiptType]) are supported, both
// always [TransactionType.expense]:
//  - DuitNow Transfer ([MaybankReceiptParser.parseDuitNowTransferText]) — a
//    bank-to-bank transfer identified by Beneficiary Name/Receiving Bank.
//  - Scan and Pay ([MaybankReceiptParser.parseScanAndPayText]) — a QR
//    merchant payment identified by Merchant Name.
// [MaybankReceiptParser.parse] detects which type [rawText] came from and
// routes to the matching parser.

/// Which Maybank receipt type [MaybankReceiptParser] parsed.
enum MaybankReceiptType { duitNowTransfer, scanAndPay }

class MaybankReceiptData {
  final MaybankReceiptType type;
  final TransactionType transactionType;
  final double? amount;
  final DateTime? date;

  /// Scan and Pay only — null for a DuitNow Transfer receipt.
  final String? merchantName;

  /// DuitNow Transfer only — null for a Scan and Pay receipt.
  final String? beneficiaryName;

  /// DuitNow Transfer only — null for a Scan and Pay receipt.
  final String? beneficiaryAccountNumber;

  /// DuitNow Transfer only — null for a Scan and Pay receipt.
  final String? receivingBank;

  /// Present on either receipt type when the field was printed.
  final String? recipientReference;

  /// Present on either receipt type when the field was printed.
  final String? referenceId;

  final String? note;
  final String? category;
  final String rawText;

  final FieldConfidence amountConfidence;
  final FieldConfidence dateConfidence;

  /// Confidence of the primary identifying field used to build [note] —
  /// [beneficiaryName] for a DuitNow Transfer, [merchantName] for a Scan and
  /// Pay receipt.
  final FieldConfidence counterpartyConfidence;
  final FieldConfidence categoryConfidence;

  const MaybankReceiptData({
    required this.type,
    required this.transactionType,
    this.amount,
    this.date,
    this.merchantName,
    this.beneficiaryName,
    this.beneficiaryAccountNumber,
    this.receivingBank,
    this.recipientReference,
    this.referenceId,
    this.note,
    this.category,
    required this.rawText,
    this.amountConfidence = FieldConfidence.missing,
    this.dateConfidence = FieldConfidence.missing,
    this.counterpartyConfidence = FieldConfidence.missing,
    this.categoryConfidence = FieldConfidence.missing,
  });

  bool get hasData => amount != null || date != null || merchantName != null || beneficiaryName != null;
}

class MaybankReceiptParser {
  // ─────────────────────────── Field labels ───────────────────────────

  static const String _beneficiaryNameWords = r'beneficiary\s*name';
  static const String _beneficiaryAccountWords =
      r'beneficiary\s*account\s*number|beneficiary\s*acc(?:ount)?\.?\s*no\.?';
  static const String _receivingBankWords = r'receiving\s*bank';
  static const String _recipientReferenceWords = r'recipient\s*reference';
  static const String _merchantNameWords = r'merchant\s*name';
  static const String _referenceIdWords = r'reference\s*id';
  static const String _dateTimeWords = r'date\s*(?:[/&]|and)?\s*time|transaction\s*date';
  static const String _amountWords = r'amount';

  // Every label recognised above — used so a labelled value is never
  // mistaken for the next label's own line, and so wrapped-value joining
  // knows where to stop.
  static const String _anyLabelWords =
      '$_beneficiaryNameWords|$_beneficiaryAccountWords|$_receivingBankWords|'
      '$_recipientReferenceWords|$_merchantNameWords|$_referenceIdWords|'
      '$_dateTimeWords|$_amountWords';

  static final RegExp _anyKnownLabelLine = _standalonePattern(_anyLabelWords);
  static final RegExp _anyLabelInlineLine = _inlinePattern(_anyLabelWords);

  // Receipt "chrome" that must never be swallowed into a wrapped field value
  // or mistaken for a field of its own: the Share Receipt button, the
  // Successful status banner, company registration text (e.g. "Malayan
  // Banking Berhad (196001000142)"), the computer-generated-receipt
  // disclaimer, and a bare phone-status-bar clock.
  static final RegExp _noiseLinePattern = RegExp(
    r'^share\s*receipt$|'
    r'^success(?:ful)?$|'
    r'.*(?:sdn\.?\s*bhd|berhad).*|'
    r'^this\s+receipt\s+is\s+(?:a\s+)?(?:system|computer)[\s-]*generated.*$|'
    r'^\d{1,2}:\d{2}\s*(?:am|pm)?$',
    caseSensitive: false,
  );

  static final RegExp _duitNowTransferPattern = RegExp(r'duit\s*now\s*transfer', caseSensitive: false);
  static final RegExp _scanAndPayPattern = RegExp(r'scan\s*(?:and|&)\s*pay', caseSensitive: false);

  // Matches a line that consists ONLY of the label (e.g. "Beneficiary Name"
  // or "Beneficiary Name:") — a stacked layout, where the value OCRs onto
  // the following line.
  static RegExp _standalonePattern(String labelAlternation) {
    return RegExp(r'^(?:' + labelAlternation + r')\s*:?\s*$', caseSensitive: false);
  }

  // Matches "Label: value" / "Label - value" on a single line.
  static RegExp _inlinePattern(String labelAlternation) {
    return RegExp(r'^(?:' + labelAlternation + r')\s*[:\-]\s*(.+)$', caseSensitive: false);
  }

  // True for any line that can never be a continuation of the previous
  // field's (possibly wrapped) value: a known label, inline-labelled,
  // receipt chrome/noise, an amount, or a date.
  static bool _isBoundaryLine(String line) {
    return _anyKnownLabelLine.hasMatch(line) ||
        _anyLabelInlineLine.hasMatch(line) ||
        _noiseLinePattern.hasMatch(line) ||
        _amountPattern.hasMatch(line) ||
        _tryParseDateTimeFromLine(line) != null;
  }

  // ─────────────────────────── Detection ───────────────────────────

  /// Whether [rawText] is confidently a Maybank transaction-detail screen,
  /// based on a combination of Maybank-specific field labels rather than any
  /// single one of them.
  static bool looksLikeMaybankReceipt(String rawText) {
    var score = 0;
    if (RegExp(r'maybank', caseSensitive: false).hasMatch(rawText)) score += 2;
    if (_duitNowTransferPattern.hasMatch(rawText)) score += 2;
    if (_scanAndPayPattern.hasMatch(rawText)) score += 2;

    final lines = _splitLines(rawText);
    bool hasLabel(String words) => lines.any(
          (l) => _standalonePattern(words).hasMatch(l) || _inlinePattern(words).hasMatch(l),
        );

    if (hasLabel(_beneficiaryNameWords)) score += 1;
    if (hasLabel(_beneficiaryAccountWords)) score += 1;
    if (hasLabel(_receivingBankWords)) score += 1;
    if (hasLabel(_recipientReferenceWords)) score += 1;
    if (hasLabel(_merchantNameWords)) score += 1;
    if (hasLabel(_referenceIdWords)) score += 1;
    return score >= 3;
  }

  /// Detects which [MaybankReceiptType] [rawText] came from, preferring an
  /// explicit "DuitNow Transfer" / "Scan and Pay" header when present and
  /// otherwise falling back to which fields were actually printed. Returns
  /// null when neither can be determined.
  static MaybankReceiptType? detectReceiptType(String rawText) {
    if (_duitNowTransferPattern.hasMatch(rawText)) return MaybankReceiptType.duitNowTransfer;
    if (_scanAndPayPattern.hasMatch(rawText)) return MaybankReceiptType.scanAndPay;

    final lines = _splitLines(rawText);
    bool hasLabel(String words) => lines.any(
          (l) => _standalonePattern(words).hasMatch(l) || _inlinePattern(words).hasMatch(l),
        );

    final hasBeneficiaryFields = hasLabel(_beneficiaryNameWords) || hasLabel(_receivingBankWords);
    final hasMerchantField = hasLabel(_merchantNameWords);

    if (hasBeneficiaryFields) return MaybankReceiptType.duitNowTransfer;
    if (hasMerchantField) return MaybankReceiptType.scanAndPay;
    return null;
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
  /// line ("Label: value") or, as a stacked layout usually OCRs, on the next
  /// non-empty line below a standalone "Label" line. Stops without a value
  /// if that next line is itself a boundary line ([_isBoundaryLine]) —
  /// meaning the field was printed with nothing under it.
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
          if (_isBoundaryLine(next)) return (null, null);
          return (next, j);
        }
      }
    }
    return (null, null);
  }

  /// Like [_extractLabeledValueWithIndex], but when [maxJoinLines] > 0 also
  /// appends up to that many further non-empty lines that follow the value —
  /// stopping as soon as a boundary line is reached ([_isBoundaryLine]).
  /// This is what lets a long Beneficiary Name or Merchant Name that OCR
  /// wrapped across multiple rows be reassembled into one value, without
  /// ever swallowing the next field, a noise line, or an amount/date.
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
      if (_isBoundaryLine(next)) break;
      parts.add(next);
      joined++;
    }
    return parts.join(' ');
  }

  static List<String> _splitLines(String rawText) {
    return rawText.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  }

  // ─────────────────────────── Note ───────────────────────────

  /// Builds a note from only the non-empty values among [recipientReference]
  /// and [primaryName] (Beneficiary Name for DuitNow Transfer, Merchant Name
  /// for Scan and Pay), joined as "<Recipient Reference> - <Name>". Never
  /// produces a leading/trailing separator, a stray "null", or an
  /// empty-placeholder note.
  static String? _buildNote(String? recipientReference, String? primaryName) {
    final parts = [recipientReference, primaryName]
        .where((value) => value != null && value.trim().isNotEmpty)
        .map((value) => value!.trim())
        .toList();
    if (parts.isEmpty) return null;
    return parts.join(' - ');
  }

  // ─────────────────────────── Category ───────────────────────────

  /// Suggests a category from whichever of Merchant Name, Beneficiary Name
  /// and Recipient Reference are actually present — never account number,
  /// receiving bank, reference ID, status text, or Maybank branding.
  static (String?, FieldConfidence) _suggestCategory({
    String? merchantName,
    String? beneficiaryName,
    String? recipientReference,
    List<String> existingCategoryLabels = const [],
  }) {
    final descriptions = [merchantName, beneficiaryName, recipientReference]
        .where((value) => value != null && value.trim().isNotEmpty)
        .map((value) => value!.trim())
        .toList();
    if (descriptions.isEmpty) return (null, FieldConfidence.missing);
    return ReceiptScannerService.suggestCategory(
      itemDescriptions: descriptions,
      existingCategoryLabels: existingCategoryLabels,
    );
  }

  // ─────────────────────────── Public API ───────────────────────────

  /// Parses a Maybank "DuitNow Transfer" transaction-detail screen (a
  /// bank-to-bank transfer). Transaction type is always
  /// [TransactionType.expense].
  ///
  /// - Note is built from only the non-empty values of Recipient Reference
  ///   and Beneficiary Name (see [_buildNote]).
  /// - Category is suggested from whichever of Recipient Reference and
  ///   Beneficiary Name are present; if neither matches, category is left
  ///   unselected.
  static MaybankReceiptData parseDuitNowTransferText(
    String rawText, {
    List<String> existingCategoryLabels = const [],
  }) {
    final lines = _splitLines(rawText);

    final (amount, amountConfidence) = _extractAmount(lines);
    final (date, dateConfidence) = _extractDateTime(lines);
    final beneficiaryName = _extractLabeledValue(lines, _beneficiaryNameWords, maxJoinLines: 1);
    final beneficiaryAccountNumber = _extractLabeledValue(lines, _beneficiaryAccountWords);
    final receivingBank = _extractLabeledValue(lines, _receivingBankWords);
    final recipientReference = _extractLabeledValue(lines, _recipientReferenceWords);
    final referenceId = _extractLabeledValue(lines, _referenceIdWords);

    final note = _buildNote(recipientReference, beneficiaryName);
    final (category, categoryConfidence) = _suggestCategory(
      beneficiaryName: beneficiaryName,
      recipientReference: recipientReference,
      existingCategoryLabels: existingCategoryLabels,
    );

    return MaybankReceiptData(
      type: MaybankReceiptType.duitNowTransfer,
      transactionType: TransactionType.expense,
      amount: amount,
      date: date,
      beneficiaryName: beneficiaryName,
      beneficiaryAccountNumber: beneficiaryAccountNumber,
      receivingBank: receivingBank,
      recipientReference: recipientReference,
      referenceId: referenceId,
      note: note,
      category: category,
      rawText: rawText,
      amountConfidence: amountConfidence,
      dateConfidence: dateConfidence,
      counterpartyConfidence:
          beneficiaryName != null && beneficiaryName.isNotEmpty ? FieldConfidence.high : FieldConfidence.missing,
      categoryConfidence: categoryConfidence,
    );
  }

  /// Parses a Maybank "Scan and Pay" transaction-detail screen (a QR
  /// merchant payment). Transaction type is always
  /// [TransactionType.expense].
  ///
  /// - Note is built from only the non-empty values of Recipient Reference
  ///   and Merchant Name (see [_buildNote]).
  /// - Category is suggested from whichever of Merchant Name and Recipient
  ///   Reference are present; if there is a match, it is auto-selected —
  ///   otherwise category is left unselected.
  static MaybankReceiptData parseScanAndPayText(
    String rawText, {
    List<String> existingCategoryLabels = const [],
  }) {
    final lines = _splitLines(rawText);

    final (amount, amountConfidence) = _extractAmount(lines);
    final (date, dateConfidence) = _extractDateTime(lines);
    final merchantName = _extractLabeledValue(lines, _merchantNameWords, maxJoinLines: 1);
    final recipientReference = _extractLabeledValue(lines, _recipientReferenceWords);
    final referenceId = _extractLabeledValue(lines, _referenceIdWords);

    final note = _buildNote(recipientReference, merchantName);
    final (category, categoryConfidence) = _suggestCategory(
      merchantName: merchantName,
      recipientReference: recipientReference,
      existingCategoryLabels: existingCategoryLabels,
    );

    return MaybankReceiptData(
      type: MaybankReceiptType.scanAndPay,
      transactionType: TransactionType.expense,
      amount: amount,
      date: date,
      merchantName: merchantName,
      recipientReference: recipientReference,
      referenceId: referenceId,
      note: note,
      category: category,
      rawText: rawText,
      amountConfidence: amountConfidence,
      dateConfidence: dateConfidence,
      counterpartyConfidence:
          merchantName != null && merchantName.isNotEmpty ? FieldConfidence.high : FieldConfidence.missing,
      categoryConfidence: categoryConfidence,
    );
  }

  /// Detects which [MaybankReceiptType] [rawText] came from and routes to
  /// the matching parser ([parseDuitNowTransferText] / [parseScanAndPayText]).
  /// Returns null when the receipt type could not be determined.
  static MaybankReceiptData? parse(
    String rawText, {
    List<String> existingCategoryLabels = const [],
  }) {
    switch (detectReceiptType(rawText)) {
      case MaybankReceiptType.duitNowTransfer:
        return parseDuitNowTransferText(rawText, existingCategoryLabels: existingCategoryLabels);
      case MaybankReceiptType.scanAndPay:
        return parseScanAndPayText(rawText, existingCategoryLabels: existingCategoryLabels);
      case null:
        return null;
    }
  }
}
