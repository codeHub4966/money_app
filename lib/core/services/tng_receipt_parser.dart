import '../../domain/models/transaction.dart';
import 'receipt_scanner_service.dart' show FieldConfidence, ReceiptScannerService;

// Parses OCR text scanned from a Touch 'n Go eWallet screenshot — a
// different source and layout from a physical paper receipt, so this lives
// in its own file rather than extending [ReceiptScannerService]. Category
// suggestion is NOT reimplemented here: every parse* method below calls
// [ReceiptScannerService.suggestCategory] directly.
//
// Two distinct screenshot layouts ([TngFormat]) are supported, each with its
// own parsing path:
//  - Format A: the "Paid" / "Transferred" result screens
//    ([TngReceiptParser.parsePaidText] / [TngReceiptParser.parseTransferredText]).
//  - Format B: the "Activity / Details" screen, identified by an explicit
//    "Transaction Type" field ([TngReceiptParser.parseTngFormatB]).
// [TngReceiptParser.parse] detects which format [rawText] came from and
// routes to the matching parser.

/// Which TNG screenshot layout [TngReceiptParser] parsed. See the file-level
/// comment above for what distinguishes each.
enum TngFormat { a, b }

/// The semantic direction of a parsed TNG transaction — paid (a merchant/QR
/// payment) or transferred (a wallet-to-wallet transfer) — regardless of
/// which screen [TngFormat] produced it.
enum TngTransactionKind { paid, transferred }

class TngReceiptData {
  final TngTransactionKind kind;
  final TngFormat format;
  final TransactionType transactionType;
  final double? amount;
  final DateTime? date;

  /// The Merchant name (Paid) or Receiver/Transfer To name (Transferred).
  final String? counterpartyName;

  /// Null when not present on the parsed screen (a Format A Transferred
  /// screenshot has no Payment Details field at all).
  final String? paymentDetails;

  /// Null when not present on the parsed screen.
  final String? paymentMethod;

  /// Format A Transferred only — null otherwise.
  final String? remark;

  final String? note;
  final String? category;
  final String rawText;

  final FieldConfidence amountConfidence;
  final FieldConfidence dateConfidence;
  final FieldConfidence counterpartyConfidence;
  final FieldConfidence categoryConfidence;

  const TngReceiptData({
    required this.kind,
    this.format = TngFormat.a,
    required this.transactionType,
    this.amount,
    this.date,
    this.counterpartyName,
    this.paymentDetails,
    this.paymentMethod,
    this.remark,
    this.note,
    this.category,
    required this.rawText,
    this.amountConfidence = FieldConfidence.missing,
    this.dateConfidence = FieldConfidence.missing,
    this.counterpartyConfidence = FieldConfidence.missing,
    this.categoryConfidence = FieldConfidence.missing,
  });

  bool get hasData => amount != null || date != null || counterpartyName != null;
}

class TngReceiptParser {
  // ─────────────────────────── Field labels ───────────────────────────

  // Format A labels.
  static const String _paymentDetailsWords = r'payment\s*details?';
  static const String _paymentMethodWords = r'payment\s*method';
  static const String _remarkWords = r'remarks?';
  static const String _merchantWords = r'merchant(?:\s*name)?|paid\s*to|pay\s*to|to';
  static const String _receiverWords = r'receiver(?:\s*name)?|transfer\s*to|to';

  // Format B labels. Kept distinct from the Format A alternatives above:
  // Format B's "Merchant" field is always explicitly labelled (unlike
  // Format A's bare "To" fallback), and its "Transfer To" label must NOT
  // also match the "Transfer to Wallet" *value* of the Transaction Type
  // field, so no "(?:\s*wallet)?" suffix is added here.
  static const String _transactionTypeWords = r'transaction\s*type';
  static const String _transferToWords = r'transfer\s*to';
  static const String _formatBMerchantWords = r'merchant(?:\s*name)?';
  static const String _walletRefWords = r'wallet\s*ref\.?';
  static const String _transactionNoWords = r'transaction\s*no\.?';
  static const String _duitNowRefWords = r'duitnow\s*ref\s*no\.?';
  static const String _statusFieldWords = r'status';

  // Every label recognised above (plus generic reference/amount/date label
  // words) — used so a labelled value is never mistaken for the next
  // label's own line, and so the merchant/receiver name fallback below
  // skips them too.
  static const String _anyLabelWords =
      '$_paymentDetailsWords|$_paymentMethodWords|$_remarkWords|$_merchantWords|$_receiverWords|'
      '$_transactionTypeWords|$_transferToWords|$_walletRefWords|$_transactionNoWords|'
      '$_duitNowRefWords|$_statusFieldWords|'
      r'reference\s*no\.?|receipt\s*no\.?|amount|date(?:\s*[/&]\s*time)?';

  static final RegExp _anyKnownLabelLine = _standalonePattern(_anyLabelWords);
  static final RegExp _anyLabelInlineLine = _inlinePattern(_anyLabelWords);

  static final RegExp _statusLinePattern = RegExp(
    r'^(?:payment\s*|transfer\s*)?(?:successful|success|completed|failed|pending|processing)\b',
    caseSensitive: false,
  );

  // Format B screens carry chrome/nav text (tab bar, points balance,
  // barcode/refund instructions, ...) that must never be mistaken for a
  // merchant/receiver name by the fallback heuristic below.
  static final RegExp _uiNoiseLinePattern = RegExp(
    r'^(?:details|home|activity|profile|transfer)$|'
    r'^[+\-]?\d+(?:\.\d+)?\s*(?:points?|pts)\b.*$|'
    r'^(?:barcode|refund|scan|tap|show)\b.*$',
    caseSensitive: false,
  );

  // Matches a line that consists ONLY of the label (e.g. "Payment Details"
  // or "Payment Details:") — the TNG app's stacked layout, where the value
  // OCRs onto the following line.
  static RegExp _standalonePattern(String labelAlternation) {
    return RegExp(r'^(?:' + labelAlternation + r')\s*:?\s*$', caseSensitive: false);
  }

  // Matches "Label: value" / "Label - value" on a single line.
  static RegExp _inlinePattern(String labelAlternation) {
    return RegExp(r'^(?:' + labelAlternation + r')\s*[:\-]\s*(.+)$', caseSensitive: false);
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

  // "15/09/2026, 14:32" / "15-09-2026 2:32 PM" / "05/09/2026 17:29:48"
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

  // True for any line that marks the START of a new field (a known label,
  // inline-labelled, a status line, an amount, or a date) — i.e. a line that
  // can never be a continuation of the previous field's (possibly wrapped)
  // value.
  static bool _isFieldBoundaryLine(String line) {
    return _anyKnownLabelLine.hasMatch(line) ||
        _anyLabelInlineLine.hasMatch(line) ||
        _statusLinePattern.hasMatch(line) ||
        _amountPattern.hasMatch(line) ||
        _tryParseDateTimeFromLine(line) != null;
  }

  // Collects consecutive non-boundary lines starting at [startIndex] — this
  // is what lets a long value (e.g. a merchant name) that OCR wrapped across
  // multiple rows be reassembled into one value, joined by a single space.
  // Capped at 3 lines: a genuine TNG field value is never longer than that.
  static List<String> _collectWrappedContinuation(List<String> lines, int startIndex) {
    final collected = <String>[];
    for (var j = startIndex; j < lines.length && collected.length < 3; j++) {
      final next = lines[j].trim();
      if (next.isEmpty || _isFieldBoundaryLine(next)) break;
      collected.add(next);
    }
    return collected;
  }

  /// Reads a value introduced by [labelWords], either inline on the same
  /// line ("Label: value") or, as the TNG app's stacked layout usually OCRs,
  /// on the next non-empty line(s) below a standalone "Label" line — merging
  /// wrapped continuation lines when present. Returns null if the field was
  /// printed with nothing under it (the very next line is itself another
  /// known field).
  static String? _extractLabeledValue(List<String> lines, String labelWords) {
    final standalonePattern = _standalonePattern(labelWords);
    final inlinePattern = _inlinePattern(labelWords);

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();

      final inlineMatch = inlinePattern.firstMatch(line);
      if (inlineMatch != null) {
        final first = inlineMatch.group(1)!.trim();
        final parts = <String>[if (first.isNotEmpty) first, ..._collectWrappedContinuation(lines, i + 1)];
        final value = parts.join(' ').trim();
        if (value.isNotEmpty) return value;
      }

      if (standalonePattern.hasMatch(line)) {
        final parts = _collectWrappedContinuation(lines, i + 1);
        if (parts.isNotEmpty) return parts.join(' ').trim();
      }
    }
    return null;
  }

  // ─────────────────────────── Merchant / Receiver ───────────────────────────

  static bool _looksLikeCounterpartyName(String line) {
    if (line.length < 2 || line.length > 60) return false;
    if (_uiNoiseLinePattern.hasMatch(line)) return false;
    if (_isFieldBoundaryLine(line)) return false;

    final letterCount = line.replaceAll(RegExp(r'[^a-zA-Z]'), '').length;
    if (letterCount < 2) return false;
    final letterRatio = letterCount / line.length;
    return letterRatio >= 0.5;
  }

  /// Prefers an explicitly labelled value (a real TNG field, e.g. "To" or
  /// "Merchant"); falls back to the first plausible name-like line
  /// otherwise, since the counterparty name is sometimes printed prominently
  /// with no label at all.
  static (String?, FieldConfidence) _extractCounterparty(
    List<String> lines,
    String labelWords,
    Set<String?> excludeValues,
  ) {
    final labelled = _extractLabeledValue(lines, labelWords);
    if (labelled != null && labelled.isNotEmpty) {
      return (labelled, FieldConfidence.high);
    }

    for (final line in lines) {
      final trimmed = line.trim();
      if (excludeValues.contains(trimmed)) continue;
      if (_looksLikeCounterpartyName(trimmed)) {
        return (trimmed, FieldConfidence.low);
      }
    }
    return (null, FieldConfidence.missing);
  }

  static List<String> _splitLines(String rawText) {
    return rawText.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  }

  // ─────────────────────────── Format detection ───────────────────────────

  /// True when [rawText] looks like a Format B ("Activity / Details")
  /// screenshot: it carries an explicit "Transaction Type" field, or a
  /// reference-style field (Wallet Ref / Transaction No. / DuitNow Ref No.)
  /// together with a Merchant or Transfer To field.
  static bool isTngFormatB(String rawText) {
    final lines = _splitLines(rawText);
    bool hasLabel(String words) => lines.any(
          (l) => _standalonePattern(words).hasMatch(l) || _inlinePattern(words).hasMatch(l),
        );

    if (hasLabel(_transactionTypeWords)) return true;

    final hasRefMarker =
        hasLabel(_walletRefWords) || hasLabel(_transactionNoWords) || hasLabel(_duitNowRefWords);
    final hasMerchantOrTransferTo = hasLabel(_formatBMerchantWords) || hasLabel(_transferToWords);
    return hasRefMarker && hasMerchantOrTransferTo;
  }

  /// True when [rawText] does not look like Format B — i.e. it should be
  /// parsed as a Format A "Paid" / "Transferred" screenshot.
  static bool isTngFormatA(String rawText) => !isTngFormatB(rawText);

  // ─────────────────────────── Format A ───────────────────────────

  /// Parses a "TNG Paid" transaction-detail screenshot (a QR/DuitNow
  /// merchant payment). Transaction type is always [TransactionType.expense].
  ///
  /// - When Payment Details is present, the note is
  ///   "<Payment Details> - Paid to <Merchant>" and category is suggested
  ///   from the Payment Details text alone (never the merchant name).
  /// - When Payment Details is missing/empty, the note is
  ///   "Paid to <Merchant>" and no category is auto-selected.
  static TngReceiptData parsePaidText(
    String rawText, {
    List<String> existingCategoryLabels = const [],
  }) {
    final lines = _splitLines(rawText);

    final (amount, amountConfidence) = _extractAmount(lines);
    final (date, dateConfidence) = _extractDateTime(lines);
    final paymentDetails = _extractLabeledValue(lines, _paymentDetailsWords);
    final paymentMethod = _extractLabeledValue(lines, _paymentMethodWords);
    final (merchant, merchantConfidence) = _extractCounterparty(
      lines,
      _merchantWords,
      {paymentDetails, paymentMethod},
    );

    String? note;
    String? category;
    var categoryConfidence = FieldConfidence.missing;

    if (merchant != null && merchant.isNotEmpty) {
      if (paymentDetails != null && paymentDetails.isNotEmpty) {
        note = '$paymentDetails - Paid to $merchant';
        final (suggested, confidence) = ReceiptScannerService.suggestCategory(
          itemDescriptions: [paymentDetails],
          existingCategoryLabels: existingCategoryLabels,
        );
        category = suggested;
        categoryConfidence = confidence;
      } else {
        note = 'Paid to $merchant';
      }
    }

    return TngReceiptData(
      kind: TngTransactionKind.paid,
      format: TngFormat.a,
      transactionType: TransactionType.expense,
      amount: amount,
      date: date,
      counterpartyName: merchant,
      paymentDetails: paymentDetails,
      paymentMethod: paymentMethod,
      note: note,
      category: category,
      rawText: rawText,
      amountConfidence: amountConfidence,
      dateConfidence: dateConfidence,
      counterpartyConfidence: merchantConfidence,
      categoryConfidence: categoryConfidence,
    );
  }

  /// Parses a "TNG Transferred" transaction-detail screenshot (a
  /// person-to-person transfer). Transaction type is always
  /// [TransactionType.expense].
  ///
  /// - When Remark is exactly "Fund Transfer" (TNG's own default remark, or
  ///   the field could not be read at all), the note is
  ///   "Transfer to <Receiver>" and no category is auto-selected.
  /// - Otherwise the note is "<Remark> - Transfer to <Receiver>" and
  ///   category is suggested from the Remark text alone (never the
  ///   receiver name).
  static TngReceiptData parseTransferredText(
    String rawText, {
    List<String> existingCategoryLabels = const [],
  }) {
    final lines = _splitLines(rawText);

    final (amount, amountConfidence) = _extractAmount(lines);
    final (date, dateConfidence) = _extractDateTime(lines);
    final remark = _extractLabeledValue(lines, _remarkWords);
    final (receiver, receiverConfidence) = _extractCounterparty(
      lines,
      _receiverWords,
      {remark},
    );

    String? note;
    String? category;
    var categoryConfidence = FieldConfidence.missing;

    if (receiver != null && receiver.isNotEmpty) {
      final isFundTransfer = remark == null || remark.trim().toLowerCase() == 'fund transfer';
      if (isFundTransfer) {
        note = 'Transfer to $receiver';
      } else {
        note = '$remark - Transfer to $receiver';
        final (suggested, confidence) = ReceiptScannerService.suggestCategory(
          itemDescriptions: [remark],
          existingCategoryLabels: existingCategoryLabels,
        );
        category = suggested;
        categoryConfidence = confidence;
      }
    }

    return TngReceiptData(
      kind: TngTransactionKind.transferred,
      format: TngFormat.a,
      transactionType: TransactionType.expense,
      amount: amount,
      date: date,
      counterpartyName: receiver,
      remark: remark,
      note: note,
      category: category,
      rawText: rawText,
      amountConfidence: amountConfidence,
      dateConfidence: dateConfidence,
      counterpartyConfidence: receiverConfidence,
      categoryConfidence: categoryConfidence,
    );
  }

  /// Parses a Format A screenshot without the caller having to know in
  /// advance whether it's a "Paid" or "Transferred" screen: Format A's
  /// Transferred screen is the only one that ever carries a "Remark" field.
  static TngReceiptData parseTngFormatA(
    String rawText, {
    List<String> existingCategoryLabels = const [],
  }) {
    final lines = _splitLines(rawText);
    final hasRemarkLabel = lines.any(
      (l) => _standalonePattern(_remarkWords).hasMatch(l) || _inlinePattern(_remarkWords).hasMatch(l),
    );
    return hasRemarkLabel
        ? parseTransferredText(rawText, existingCategoryLabels: existingCategoryLabels)
        : parsePaidText(rawText, existingCategoryLabels: existingCategoryLabels);
  }

  // ─────────────────────────── Format B ───────────────────────────

  /// Parses a "TNG Activity / Details" screenshot. Transaction type is
  /// always [TransactionType.expense].
  ///
  /// - When Transaction Type is "Transfer to Wallet", the note is
  ///   "<Payment Details> - Transfer to <Transfer To>" (or just
  ///   "Transfer to <Transfer To>" when Payment Details is empty).
  /// - Otherwise (Payment / DuitNow QR / DuitNow QR TNGD / ...), the note is
  ///   set to exactly the Payment Details value — Merchant is parsed but
  ///   never appended to the note.
  ///
  /// In both cases, category is suggested from the Payment Details text
  /// alone (never the Merchant or Transfer To name); if there is no match,
  /// no category is auto-selected.
  static TngReceiptData parseTngFormatB(
    String rawText, {
    List<String> existingCategoryLabels = const [],
  }) {
    final lines = _splitLines(rawText);

    final (amount, amountConfidence) = _extractAmount(lines);
    final (date, dateConfidence) = _extractDateTime(lines);
    final formatBTransactionType = _extractLabeledValue(lines, _transactionTypeWords);
    final paymentDetails = _extractLabeledValue(lines, _paymentDetailsWords);
    final paymentMethod = _extractLabeledValue(lines, _paymentMethodWords);

    final isTransferToWallet = formatBTransactionType != null &&
        formatBTransactionType.trim().toLowerCase() == 'transfer to wallet';

    final excludeValues = <String?>{
      formatBTransactionType,
      paymentDetails,
      paymentMethod,
      _extractLabeledValue(lines, _walletRefWords),
      _extractLabeledValue(lines, _transactionNoWords),
      _extractLabeledValue(lines, _duitNowRefWords),
    };

    final (counterparty, counterpartyConfidence) = _extractCounterparty(
      lines,
      isTransferToWallet ? _transferToWords : _formatBMerchantWords,
      excludeValues,
    );

    String? note;
    if (isTransferToWallet) {
      if (counterparty != null && counterparty.isNotEmpty) {
        note = (paymentDetails != null && paymentDetails.isNotEmpty)
            ? '$paymentDetails - Transfer to $counterparty'
            : 'Transfer to $counterparty';
      }
    } else if (paymentDetails != null && paymentDetails.isNotEmpty) {
      note = paymentDetails;
    }

    String? category;
    var categoryConfidence = FieldConfidence.missing;
    if (paymentDetails != null && paymentDetails.isNotEmpty) {
      final (suggested, confidence) = ReceiptScannerService.suggestCategory(
        itemDescriptions: [paymentDetails],
        existingCategoryLabels: existingCategoryLabels,
      );
      category = suggested;
      categoryConfidence = confidence;
    }

    return TngReceiptData(
      kind: isTransferToWallet ? TngTransactionKind.transferred : TngTransactionKind.paid,
      format: TngFormat.b,
      transactionType: TransactionType.expense,
      amount: amount,
      date: date,
      counterpartyName: counterparty,
      paymentDetails: paymentDetails,
      paymentMethod: paymentMethod,
      note: note,
      category: category,
      rawText: rawText,
      amountConfidence: amountConfidence,
      dateConfidence: dateConfidence,
      counterpartyConfidence: counterpartyConfidence,
      categoryConfidence: categoryConfidence,
    );
  }

  // ─────────────────────────── Dispatch ───────────────────────────

  /// Detects which [TngFormat] [rawText] came from and routes to the
  /// matching parser ([parseTngFormatA] / [parseTngFormatB]).
  static TngReceiptData parse(
    String rawText, {
    List<String> existingCategoryLabels = const [],
  }) {
    return isTngFormatB(rawText)
        ? parseTngFormatB(rawText, existingCategoryLabels: existingCategoryLabels)
        : parseTngFormatA(rawText, existingCategoryLabels: existingCategoryLabels);
  }
}
