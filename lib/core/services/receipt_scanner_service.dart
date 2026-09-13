import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'receipt_text_layout.dart';

/// How much the local parser trusts a field it extracted.
/// Used to decide whether the Gemini backend fallback should be consulted.
enum FieldConfidence { high, low, missing }

class ReceiptData {
  final double? amount;
  final DateTime? date;
  final String? merchantName;
  final List<String> itemDescriptions;
  final String? suggestedNote;
  final String? detectedPaymentKeyword;
  final String rawText;
  final FieldConfidence amountConfidence;
  final FieldConfidence dateConfidence;
  final FieldConfidence merchantConfidence;

  ReceiptData({
    this.amount,
    this.date,
    this.merchantName,
    this.itemDescriptions = const [],
    this.suggestedNote,
    this.detectedPaymentKeyword,
    required this.rawText,
    this.amountConfidence = FieldConfidence.missing,
    this.dateConfidence = FieldConfidence.missing,
    this.merchantConfidence = FieldConfidence.missing,
  });

  bool get hasData => amount != null || date != null || merchantName != null;
}

class ReceiptScannerService {
  static final _textRecognizer = TextRecognizer();

  static const int _minCategoryScore = 2;
  static const int _highCategoryScore = 6;

  // Category keywords - used as default classification knowledge only.
  // Item extraction does NOT depend on this map (see _extractItemDescriptions).
  static final Map<String, List<String>> _categoryKeywords = {
    'Food & Dining': [
      // Merchants
      'restaurant', 'cafe', 'coffee', 'starbucks', 'mcdonald', 'kfc', 'pizza',
      'burger', 'kitchen', 'bakery', 'dining', 'bistro', 'bar', 'pub',
      'nasi', 'makan', 'restoran', 'kedai', 'warung', 'mamak', 'subway',
      'domino', 'pizza hut', 'tealive', 'chatime', 'oldtown', 'kopitiam',
      // Food items
      'rice', 'noodle', 'chicken', 'beef', 'fish', 'soup', 'curry', 'bread',
      'sandwich', 'meal', 'breakfast', 'lunch', 'dinner', 'drink', 'beverage',
      'coffee', 'tea', 'juice', 'water', 'roti', 'nasi lemak', 'mee', 'laksa',
    ],
    'Groceries': [
      'supermarket', 'market', 'grocery', 'tesco', 'giant', 'aeon', 'jaya',
      'mart', 'store', 'speedmart', '99speedmart', 'mydin', 'lotus', 'econsave',
      'vegetables', 'fruits', 'milk', 'eggs', 'bread', 'meat', 'seafood',
    ],
    // Kept as its own bucket (rather than folded into "Shopping") because
    // most user category sets have a dedicated "Clothing" label, and
    // _matchExistingLabel() prefers an exact bucket-name-to-label match —
    // a merged "Shopping" bucket would always win that exact match and
    // fashion items would never resolve to "Clothing".
    'Clothing': [
      'uniqlo', 'zara', 'h&m', 'nike', 'adidas', 'fashion', 'clothing',
      'apparel', 'shoes', 'bag', 'shirt', 'tee', 't-shirt', 'pants', 'pant',
      'jeans', 'dress', 'skirt', 'jacket', 'sweater', 'hoodie', 'sneakers',
      'sandals', 'watch', 'accessories', 'hat', 'cap', 'socks', 'underwear',
      'belt', 'boutique',
    ],
    'Shopping': [
      'mall', 'shop', 'store',
      // Electronics & others
      'electronic', 'phone', 'laptop', 'gadget', 'computer', 'tablet',
      'headphone', 'speaker', 'camera', 'toy', 'book', 'stationery',
    ],
    'Transportation': [
      'grab', 'uber', 'taxi', 'parking', 'petrol', 'shell', 'petronas',
      'fuel', 'car wash', 'bus', 'train', 'lrt', 'mrt', 'toll', 'touch n go',
      'caltex', 'bnp', 'diesel', 'ron95', 'ron97', 'tng', 'smarttag',
    ],
    'Healthcare': [
      'clinic', 'hospital', 'pharmacy', 'guardian', 'watsons', 'medical',
      'doctor', 'dental', 'health', 'medicine', 'vitamin', 'supplement',
      'mask', 'sanitizer', 'bandage', 'clinic',
    ],
    'Entertainment': [
      'cinema', 'movie', 'gsc', 'tgv', 'concert', 'ticket', 'game',
      'karaoke', 'bowling', 'arcade', 'theme park', 'zoo', 'museum',
      'netflix', 'spotify', 'steam', 'xbox', 'playstation',
    ],
    'Utilities': [
      'electric', 'water', 'internet', 'phone', 'telekom', 'maxis', 'digi',
      'celcom', 'unifi', 'astro', 'bill', 'subscription', 'tnb', 'syabas',
      'indah water', 'hotlink', 'yes', 'umobile',
    ],
  };

  // Payment method keywords for account matching. Order matters:
  // _detectPaymentKeyword returns the FIRST matching entry, so specific
  // evidence (a named bank or e-wallet, or cash) is listed ahead of generic
  // card-network words (visa/mastercard/debit/credit) — a receipt printing
  // both, e.g. "MAYBANK VISA", must resolve to the specific brand ('maybank')
  // rather than the generic card network that says nothing about which
  // wallet was actually used.
  static final Map<String, List<String>> _accountKeywords = {
    'maybank': ['maybank', 'may bank', 'mbb'],
    'cimb': ['cimb'],
    'public bank': ['public bank', 'pbb'],
    'hong leong': ['hong leong', 'hlb'],
    'rhb': ['rhb'],
    'ambank': ['ambank', 'am bank'],
    'touch n go': ['touch n go', 'tng', 'touchngo', 'touch & go'],
    'boost': ['boost'],
    'grabpay': ['grabpay', 'grab pay'],
    'shopeepay': ['shopeepay', 'shopee pay'],
    'cash': ['cash', 'tunai'],
    'visa': ['visa'],
    'mastercard': ['mastercard', 'master card'],
    'debit': ['debit'],
    'credit': ['credit'],
  };

  // Generic receipt headers/stamps that are never the merchant name —
  // including common "noise" stamps (watermarks, reprint/void markers) that
  // can print above the actual store name.
  static final RegExp _genericHeaderPattern = RegExp(
    r'^(welcome|receipt|tax\s*invoice|invoice|official\s*receipt|customer\s*copy|merchant\s*copy|'
    r'secure\s*copy|original\s*copy|duplicate\s*copy|reprint|watermark|specimen|void)\b',
    caseSensitive: false,
  );

  // Lines that commonly appear before/around item lines but are not items
  // themselves (dates, phone numbers, registration numbers, addresses...).
  static final RegExp _metadataSkipPattern = RegExp(
    r'\b(tel|phone|fax|email|gst\s*no|sst\s*no|reg(?:istration)?\s*no|co\.?\s*no)\b[:.]?',
    caseSensitive: false,
  );

  // Lines that mark the start of the totals/payment/footer section — once
  // one of these is seen, item extraction stops.
  static final RegExp _totalsSectionPattern = RegExp(
    r'\b(sub\s*total|subtotal|grand\s*total|total\s*payable|net\s*total|total\s*due|'
    r'balance\s*due|amount\s*payable|amount\s*due|final\s*total|total|'
    r'service\s*charge|rounding|discount|cash|change|tendered|received|'
    r'visa|mastercard|debit|credit|receipt\s*no|invoice\s*no|order\s*no|'
    r'transaction\s*id|cashier|counter|thank\s*you)\b',
    caseSensitive: false,
  );

  static final RegExp _priceToken = RegExp(
    r'(?:rm|myr)?\s*(\d{1,3}(?:[.,]\d{3})*[.,]\d{2})',
    caseSensitive: false,
  );

  static Future<ReceiptData> scanReceipt(String imagePath) async {
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final recognizedText = await _textRecognizer.processImage(inputImage);
      final rawText = _readingOrderText(recognizedText);
      return parseReceiptText(rawText);
    } catch (e) {
      return ReceiptData(rawText: '');
    }
  }

  /// Runs the local parser over already-recognised OCR text, with no ML Kit
  /// dependency at all. This is the seam tests use to feed OCR-text
  /// fixtures directly, instead of needing a real camera/ML Kit pipeline.
  static ReceiptData parseReceiptText(String rawText, {DateTime? now}) {
    final lines = rawText.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

    final (merchantName, merchantConfidence) = _extractMerchant(lines);
    final itemDescriptions = _extractItemDescriptions(lines, merchantName);
    final (amount, amountConfidence) = _extractAmount(lines);
    final (date, dateConfidence) = _extractDate(lines, now: now);
    final detectedPaymentKeyword = _detectPaymentKeyword(rawText);
    final suggestedNote = _buildNote(merchantName, itemDescriptions);

    return ReceiptData(
      amount: amount,
      date: date,
      merchantName: merchantName,
      itemDescriptions: itemDescriptions,
      suggestedNote: suggestedNote,
      detectedPaymentKeyword: detectedPaymentKeyword,
      rawText: rawText,
      amountConfidence: amountConfidence,
      dateConfidence: dateConfidence,
      merchantConfidence: merchantConfidence,
    );
  }

  // ML Kit's own `RecognizedText.text` concatenates blocks in whatever
  // order its internal grouping algorithm picked — that is NOT guaranteed
  // to match top-to-bottom visual reading order, and even where blocks are
  // roughly top-to-bottom, a single visual row (e.g. a "TOTAL" label and its
  // amount printed side by side) can be split into separate lines or even
  // separate blocks, breaking the label/amount association the parser
  // relies on. `groupIntoRows` re-derives rows directly from every line's
  // bounding box (regardless of which block it came from), so same-row
  // label/amount pairs stay together and are emitted left-to-right.
  static String _readingOrderText(RecognizedText recognizedText) {
    final positioned = <PositionedLine>[
      for (final block in recognizedText.blocks)
        for (final line in block.lines)
          PositionedLine(
            text: line.text,
            top: line.boundingBox.top.toDouble(),
            bottom: line.boundingBox.bottom.toDouble(),
            left: line.boundingBox.left.toDouble(),
          ),
    ];
    return groupIntoRows(positioned).join('\n');
  }

  // Whole-word match so short keywords like "bar" or "cap" don't fire on
  // substrings such as "barcode" or "capacity".
  static bool _containsKeyword(String text, String keyword) {
    final pattern = RegExp(r'\b' + RegExp.escape(keyword.toLowerCase()) + r'\b');
    return pattern.hasMatch(text);
  }

  // ─────────────────────────── Amount ───────────────────────────

  // Note: deliberately does NOT penalise tax/gst/sst wording when it shares
  // a line with "total" — many Malaysian receipts print the real grand
  // total as "TOTAL (INCL. GST)" or "TOTAL INCLUSIVE OF SST".
  static final RegExp _grandTotalKw = RegExp(
    r'\b(grand\s*total|total\s*payable|net\s*total|total\s*due|balance\s*due|'
    r'amount\s*payable|amount\s*due|final\s*total)\b',
    caseSensitive: false,
  );
  static final RegExp _bareTotalKw = RegExp(r'\btotal\b', caseSensitive: false);
  static final RegExp _subtotalKw = RegExp(r'\b(sub\s*total|subtotal)\b', caseSensitive: false);
  static final RegExp _cashTenderedKw =
      RegExp(r'\b(cash|tendered|received)\b', caseSensitive: false);
  static final RegExp _changeKw = RegExp(r'\b(change|balance\s*return(?:ed)?)\b', caseSensitive: false);
  static final RegExp _discountKw =
      RegExp(r'\b(discount|rounding|service\s*charge)\b', caseSensitive: false);
  static final RegExp _taxOnlyKw = RegExp(r'\b(gst|sst|vat|tax)\b', caseSensitive: false);

  /// Scores every line that carries (or, for a label with no inline price,
  /// borrows from the next line) a monetary value, instead of returning
  /// whichever "total"-like keyword happens to appear first. This is what
  /// lets the parser distinguish the final payable amount from a subtotal,
  /// a tax line, cash tendered, change, or an unrelated number, even when
  /// several of them appear on the receipt.
  static (double?, FieldConfidence) _extractAmount(List<String> lines) {
    final candidates = <({double value, int score, int lineIndex})>[];

    int scoreLine(String line) {
      var score = 0;
      final isGrandTotal = _grandTotalKw.hasMatch(line);
      final isBareTotal = !isGrandTotal && _bareTotalKw.hasMatch(line) && !_subtotalKw.hasMatch(line);
      if (isGrandTotal) score += 10;
      if (isBareTotal) score += 6;
      if (_subtotalKw.hasMatch(line)) score -= 8;
      if (_cashTenderedKw.hasMatch(line)) score -= 9;
      if (_changeKw.hasMatch(line)) score -= 9;
      if (_discountKw.hasMatch(line)) score -= 5;
      if (!isGrandTotal && !isBareTotal && _taxOnlyKw.hasMatch(line)) score -= 3;
      return score;
    }

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final inlinePrice = _extractFirstPrice(line);

      if (inlinePrice != null) {
        candidates.add((value: inlinePrice, score: scoreLine(line), lineIndex: i));
        continue;
      }

      // A total-ish label with no inline price: the value is likely printed
      // on the next line (a genuine multi-line layout, not an OCR-row
      // splitting issue — that's handled upstream by row grouping). Only
      // borrow forward when the next line isn't itself a different labelled
      // amount (subtotal/cash/change/discount), and score it slightly lower
      // since the association is indirect.
      final hasTotalLabel = _grandTotalKw.hasMatch(line) || _bareTotalKw.hasMatch(line);
      if (hasTotalLabel && i + 1 < lines.length) {
        final nextLine = lines[i + 1];
        final nextIsOtherLabel = _subtotalKw.hasMatch(nextLine) ||
            _cashTenderedKw.hasMatch(nextLine) ||
            _changeKw.hasMatch(nextLine) ||
            _discountKw.hasMatch(nextLine);
        final nextPrice = _extractFirstPrice(nextLine);
        if (!nextIsOtherLabel && nextPrice != null) {
          candidates.add((value: nextPrice, score: scoreLine(line) - 1, lineIndex: i + 1));
        }
      }
    }

    if (candidates.isEmpty) return (null, FieldConfidence.missing);

    // Prefer the highest score; break ties by preferring the amount that
    // appears later in the receipt (the payable total is printed after the
    // items and subtotal it sums, and after tax lines it includes).
    candidates.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return b.lineIndex.compareTo(a.lineIndex);
    });

    final best = candidates.first;

    // Ambiguous when another candidate with a materially different value
    // scored nearly as well — e.g. two differently-labelled "total" lines
    // that disagree. A keyword match alone should not buy high confidence
    // when the receipt itself is contradictory; this is what lets the
    // Gemini fallback be consulted for exactly this case.
    final isAmbiguous = candidates.skip(1).any(
          (c) => c.score >= best.score - 2 && (c.value - best.value).abs() > 0.01,
        );

    final confidence = (best.score >= 6 && !isAmbiguous) ? FieldConfidence.high : FieldConfidence.low;
    return (best.value, confidence);
  }

  static double? _extractFirstPrice(String text) {
    final match = _priceToken.firstMatch(text);
    if (match == null) return null;
    return _parseAmountString(match.group(1)!);
  }

  static double? _parseAmountString(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return null;
    final hasDot = s.contains('.');
    final hasComma = s.contains(',');

    if (hasDot && hasComma) {
      if (s.lastIndexOf(',') < s.lastIndexOf('.')) {
        s = s.replaceAll(',', '');
      } else {
        s = s.replaceAll('.', '').replaceAll(',', '.');
      }
    } else if (hasComma && !hasDot) {
      final idx = s.lastIndexOf(',');
      if (s.length - idx - 1 == 2) {
        s = s.replaceRange(idx, idx + 1, '.');
      } else {
        s = s.replaceAll(',', '');
      }
    }

    return double.tryParse(s);
  }

  // ─────────────────────────── Date ───────────────────────────

  static bool _isValidYMD(int y, int m, int d) {
    if (m < 1 || m > 12) return false;
    if (d < 1) return false;
    final isLeap = (y % 4 == 0 && (y % 100 != 0 || y % 400 == 0));
    const daysInMonth = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    final maxDay = m == 2 && isLeap ? 29 : daysInMonth[m - 1];
    return d <= maxDay;
  }

  // "Due date", "expiry date", "valid until" etc. also contain the word
  // "date" (or sit next to it) but are never the transaction date — without
  // this, a warranty/loyalty-card expiry line next to the word "date" would
  // wrongly earn high confidence just for being near that label.
  static final RegExp _dateLabelExclusion = RegExp(
    r'\b(exp(?:iry|ires|\.)?|best\s*before|valid\s*(?:until|thru|till)|due\s*date)\b',
    caseSensitive: false,
  );

  static (DateTime?, FieldConfidence) _extractDate(List<String> lines, {DateTime? now}) {
    final referenceNow = now ?? DateTime.now();
    final labelPattern = RegExp(r'\bdate\b', caseSensitive: false);

    final labelCandidates = <DateTime>[];
    final otherCandidates = <DateTime>[];

    for (final line in lines) {
      if (_dateLabelExclusion.hasMatch(line)) continue;

      final parsed = _tryParseDateFromLine(line);
      if (parsed == null || !_isPlausibleReceiptDate(parsed, referenceNow)) continue;

      if (labelPattern.hasMatch(line)) {
        labelCandidates.add(parsed);
      } else {
        otherCandidates.add(parsed);
      }
    }

    // A date found next to an explicit "date" label is high confidence —
    // but only when every such labelled date agrees. Several differently
    // labelled dates (e.g. an invoice date and an order date reading
    // differently due to OCR noise) is a genuine conflict, not a clean
    // high-confidence read, and should be left for the Gemini fallback.
    if (labelCandidates.isNotEmpty) {
      final distinctValues = labelCandidates.map((d) => d.toIso8601String()).toSet();
      final confidence = distinctValues.length == 1 ? FieldConfidence.high : FieldConfidence.low;
      return (labelCandidates.first, confidence);
    }

    if (otherCandidates.isNotEmpty) {
      return (otherCandidates.first, FieldConfidence.low);
    }

    return (null, FieldConfidence.missing);
  }

  // Rejects dates a real receipt could never carry: more than a day in the
  // future (allowing for timezone/midnight edge cases), or implausibly far
  // in the past — almost always a digit OCR misread rather than a genuine
  // multi-year-old receipt.
  static bool _isPlausibleReceiptDate(DateTime date, DateTime now) {
    if (date.isAfter(now.add(const Duration(days: 1)))) return false;
    if (date.isBefore(DateTime(now.year - 5))) return false;
    return true;
  }

  static DateTime? _tryParseDateFromLine(String line) {
    // '.' is included alongside '/' and '-' — dot-separated dates
    // (05.09.2026) are common on Malaysian receipts too. A stray decimal
    // price like "16.95" only has one separator, so it can't match this
    // 3-group pattern.
    //
    // The leading anchor is a "not preceded by a digit" lookbehind rather
    // than \b: digits and letters are both \w, so \b would refuse to match
    // right after a label with no space before the date — a common OCR
    // artifact (e.g. "Date05/09/2026" with the space dropped). The trailing
    // \b is kept, since a date immediately followed by more digits (no
    // separator) genuinely is ambiguous and should be rejected.
    final dmy =
        RegExp(r'(?<!\d)(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{2,4})\b').firstMatch(line);
    if (dmy != null) {
      final p1 = int.parse(dmy.group(1)!);
      final p2 = int.parse(dmy.group(2)!);
      var year = int.parse(dmy.group(3)!);
      if (year < 100) year += (year > 50 ? 1900 : 2000);

      // Malaysian convention: prefer DD/MM.
      if (_isValidYMD(year, p2, p1)) return DateTime(year, p2, p1);
      if (_isValidYMD(year, p1, p2)) return DateTime(year, p1, p2);
      return null;
    }

    final ymd = RegExp(r'(?<!\d)(\d{4})[/.\-](\d{1,2})[/.\-](\d{1,2})\b').firstMatch(line);
    if (ymd != null) {
      final year = int.parse(ymd.group(1)!);
      final month = int.parse(ymd.group(2)!);
      final day = int.parse(ymd.group(3)!);
      if (_isValidYMD(year, month, day)) return DateTime(year, month, day);
      return null;
    }

    final dmonthy = RegExp(
      r'(?<!\d)(\d{1,2})\s+(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\s+(\d{2,4})\b',
      caseSensitive: false,
    ).firstMatch(line);
    if (dmonthy != null) {
      final day = int.parse(dmonthy.group(1)!);
      const months = {
        'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
        'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
      };
      final month = months[dmonthy.group(2)!.toLowerCase().substring(0, 3)];
      var year = int.parse(dmonthy.group(3)!);
      if (year < 100) year += (year > 50 ? 1900 : 2000);
      if (month != null && _isValidYMD(year, month, day)) return DateTime(year, month, day);
      return null;
    }

    return null;
  }

  // ─────────────────────────── Merchant ───────────────────────────

  static bool _looksLikeMetadataLine(String line) {
    final l = line.trim();
    if (l.isEmpty) return true;
    if (RegExp(r'\d{1,2}[/-]\d{1,2}[/-]\d{2,4}').hasMatch(l)) return true;
    if (_metadataSkipPattern.hasMatch(l)) return true;

    final digitCount = l.replaceAll(RegExp(r'[^0-9]'), '').length;
    final letterCount = l.replaceAll(RegExp(r'[^a-zA-Z]'), '').length;
    if (digitCount >= 5 && digitCount > letterCount) return true;

    return false;
  }

  // A Malaysian street/area address line is never the business name — it
  // commonly sits right under the store name, so without this it would
  // occasionally win as "the first meaningful line" if the true name line
  // above it got skipped as metadata/noise.
  static final RegExp _addressLikePattern = RegExp(
    r'\b(jalan|jln|lorong|lrg|persiaran|taman|tmn|seksyen|blok|lot\s*\d|'
    r'wilayah\s*persekutuan|kuala\s*lumpur|petaling\s*jaya|shah\s*alam)\b',
    caseSensitive: false,
  );

  // The merchant name is simply the first meaningful line on the receipt —
  // only skip lines that are clearly not a business name (blank, a generic
  // header like "TAX INVOICE", metadata, or an address). Anything smarter
  // than that started second-guessing real merchant lines and picking an
  // address line instead.
  static (String?, FieldConfidence) _extractMerchant(List<String> lines) {
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.length < 2) continue;
      if (_genericHeaderPattern.hasMatch(trimmed)) continue;

      // Skip known metadata lines (tel/fax/email/GST no/SST no/reg no) that
      // sometimes print above the store name — these are never a business
      // name, so this only ever moves on to the next line, never guesses.
      if (_metadataSkipPattern.hasMatch(trimmed)) continue;
      if (_addressLikePattern.hasMatch(trimmed)) continue;

      final letterCount = trimmed.replaceAll(RegExp(r'[^a-zA-Z]'), '').length;

      // A line with zero letters (a border/rule of dashes or asterisks, a
      // barcode number, stray OCR noise from a logo graphic) can never be a
      // business name — skip it rather than returning it as the merchant.
      // Anything found by a line WITH letters is still returned even if
      // short/noisy, just flagged low confidence instead of dropped —
      // second-guessing further than that started picking address lines
      // over real merchant lines.
      if (letterCount == 0) continue;

      // High confidence requires more than just "has some letters": a very
      // short/very long line, or one that's mostly digits/punctuation with
      // only a few incidental letters, looks like a name but usually isn't
      // one — e.g. a receipt/order number, a till ID, or a stray OCR
      // fragment. None of that should buy high confidence merely for
      // sitting in the merchant-name position.
      final letterRatio = letterCount / trimmed.length;
      final looksLikeAPlausibleName =
          trimmed.length >= 3 && trimmed.length <= 40 && letterCount >= 3 && letterRatio >= 0.5;

      final confidence = looksLikeAPlausibleName ? FieldConfidence.high : FieldConfidence.low;
      return (trimmed, confidence);
    }
    return (null, FieldConfidence.missing);
  }

  // ─────────────────────────── Item descriptions ───────────────────────────

  static List<String> _extractItemDescriptions(List<String> lines, String? merchantName) {
    final items = <String>[];

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (trimmed == merchantName) continue;

      // Lines like "date", "tel", registration numbers etc. can appear
      // interspersed with items — skip them without ending extraction.
      if (_looksLikeMetadataLine(trimmed)) continue;

      // Once we reach the totals/payment/footer section, item lines are done.
      if (_totalsSectionPattern.hasMatch(trimmed)) break;

      // Trailing tax-code letters after the price (e.g. "12.50 SR", "89.90 Z")
      // are common on Malaysian receipts and are tolerated here — otherwise
      // the end-of-line anchor would reject the entire item line.
      final priceMatch = RegExp(
        r'(?:rm|myr)?\s*\d{1,3}(?:[.,]\d{3})*[.,]\d{2}(?:\s*[A-Z*]{1,2})?\s*$',
        caseSensitive: false,
      ).firstMatch(trimmed);
      if (priceMatch == null) continue;

      var description = trimmed.substring(0, priceMatch.start).trim();
      description = description.replaceFirst(RegExp(r'^\d+\s*[xX]\s*'), '');
      description = description.replaceAll(RegExp(r'\s{2,}'), ' ').trim();

      if (description.length < 2) continue;
      if (RegExp(r'^[\d\s.,:/\-]+$').hasMatch(description)) continue;

      items.add(_titleCase(description));
      if (items.length >= 5) break;
    }

    return items;
  }

  static String _titleCase(String s) {
    return s.split(RegExp(r'\s+')).map((w) {
      if (w.isEmpty) return w;
      if (RegExp(r'^[A-Za-z]').hasMatch(w)) {
        return w[0].toUpperCase() + w.substring(1).toLowerCase();
      }
      return w.toLowerCase();
    }).join(' ');
  }

  static String? _buildNote(String? merchantName, List<String> itemDescriptions) {
    if (merchantName != null && merchantName.isNotEmpty && itemDescriptions.isNotEmpty) {
      return '$merchantName — ${itemDescriptions.join(', ')}';
    }
    if (merchantName != null && merchantName.isNotEmpty) {
      return merchantName;
    }
    if (itemDescriptions.isNotEmpty) {
      return itemDescriptions.join(', ');
    }
    return null;
  }

  // ─────────────────────────── Category ───────────────────────────

  // Weights used by suggestCategory's scoring pass. Item descriptions and
  // merchant keywords are direct, structured evidence (what was actually
  // bought, from whom) and are weighted far above the raw OCR text, which
  // also contains totals/payment/footer noise ("MAYBANK", "VISA", "CASH",
  // "CARD", receipt/invoice numbers, "THANK YOU", ...) that must not be
  // allowed to meaningfully sway category selection.
  static const int _itemKeywordWeight = 5;
  static const int _merchantKeywordWeight = 3;
  static const int _rawTextKeywordWeight = 1;

  // Lines that are payment/footer noise, never category evidence — reusing
  // the same "start of totals section" boundary as item extraction, so the
  // weak raw-text fallback never sees "VISA", "CASH", "MAYBANK", receipt
  // numbers, "THANK YOU", etc.
  static String _stripFooterNoise(String rawText) {
    return rawText
        .split('\n')
        .where((line) => !_totalsSectionPattern.hasMatch(line))
        .join(' ');
  }

  /// Suggests a category using (in order of priority): a reliable, already
  /// majority-vetted merchant→category history entry (see
  /// [MerchantCategoryHistory] — this method does not itself decide
  /// reliability), extracted item descriptions, merchant-name keywords,
  /// existing category labels, and finally the raw OCR text as a very weak
  /// fallback that only contributes when item/merchant evidence is entirely
  /// absent. When [existingCategoryLabels] is non-empty, only a label from
  /// that list is ever returned — this method never invents a category.
  static (String?, FieldConfidence) suggestCategory({
    String? merchantName,
    List<String> itemDescriptions = const [],
    String rawText = '',
    List<String> existingCategoryLabels = const [],
    String? reliableMerchantCategory,
  }) {
    if (reliableMerchantCategory != null &&
        (existingCategoryLabels.isEmpty || existingCategoryLabels.contains(reliableMerchantCategory))) {
      if (kDebugMode) {
        debugPrint('[suggestCategory] using reliable merchant history: $reliableMerchantCategory');
      }
      return (reliableMerchantCategory, FieldConfidence.high);
    }

    final itemText = itemDescriptions.join(' ').toLowerCase();
    final merchantLower = (merchantName ?? '').toLowerCase();

    final primaryScores = <String, int>{};
    void addPrimaryScore(String category, int amount) {
      primaryScores[category] = (primaryScores[category] ?? 0) + amount;
    }

    for (final entry in _categoryKeywords.entries) {
      for (final keyword in entry.value) {
        final kw = keyword.toLowerCase();
        if (_containsKeyword(itemText, kw)) addPrimaryScore(entry.key, _itemKeywordWeight);
        if (merchantLower.isNotEmpty && _containsKeyword(merchantLower, kw)) {
          addPrimaryScore(entry.key, _merchantKeywordWeight);
        }
      }
    }

    // Let existing (possibly user-created) category labels act as their own
    // loose keywords, so a custom category like "Pets" can still be matched.
    for (final label in existingCategoryLabels) {
      final words = label.toLowerCase().split(RegExp(r'[^a-z]+')).where((w) => w.length >= 3);
      for (final word in words) {
        final singular = word.endsWith('s') ? word.substring(0, word.length - 1) : word;
        for (final form in {word, singular}) {
          if (itemText.contains(form)) addPrimaryScore(label, _itemKeywordWeight - 1);
          if (merchantLower.contains(form)) addPrimaryScore(label, _merchantKeywordWeight - 1);
        }
      }
    }

    // Raw OCR text is only ever consulted as a last resort, when items and
    // the merchant name gave literally no signal at all — never to
    // reinforce or override evidence that already exists, and never from
    // the totals/payment/footer section of the receipt.
    var scores = primaryScores;
    if (primaryScores.isEmpty && rawText.isNotEmpty) {
      final rawLower = _stripFooterNoise(rawText).toLowerCase();
      final rawScores = <String, int>{};
      for (final entry in _categoryKeywords.entries) {
        for (final keyword in entry.value) {
          if (_containsKeyword(rawLower, keyword.toLowerCase())) {
            rawScores[entry.key] = (rawScores[entry.key] ?? 0) + _rawTextKeywordWeight;
          }
        }
      }
      scores = rawScores;
    }

    if (kDebugMode) {
      debugPrint('[suggestCategory] candidate scores: $scores');
    }

    if (scores.isEmpty) return (null, FieldConfidence.missing);

    final resolved = <String, int>{};
    for (final entry in scores.entries) {
      final label = existingCategoryLabels.isEmpty
          ? entry.key
          : _matchExistingLabel(entry.key, existingCategoryLabels);
      if (label == null) continue;
      resolved[label] = (resolved[label] ?? 0) + entry.value;
    }

    if (resolved.isEmpty) return (null, FieldConfidence.missing);

    final ranked = resolved.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    if (ranked.first.value < _minCategoryScore) return (null, FieldConfidence.missing);

    // Two categories scoring nearly the same (e.g. a "cafe" that also sells
    // "bread" pulling both Food & Dining and Groceries) is a genuine
    // toss-up — a high score alone shouldn't buy high confidence when a
    // different category was almost as strong a match.
    final isAmbiguous = ranked.length > 1 &&
        ranked[1].key != ranked.first.key &&
        ranked[1].value >= ranked.first.value - 1;

    final confidence = (ranked.first.value >= _highCategoryScore && !isAmbiguous)
        ? FieldConfidence.high
        : FieldConfidence.low;
    if (kDebugMode) {
      debugPrint('[suggestCategory] resolved: ${ranked.first.key} ($confidence)');
    }
    return (ranked.first.key, confidence);
  }

  // A built-in keyword-map key (e.g. "Transportation", "Healthcare") rarely
  // equals a real app category label (e.g. "Transport", "Health") exactly,
  // so this resolves by loose substring overlap — between the key itself,
  // its keyword vocabulary, and each existing label — instead of requiring
  // an exact match, which would silently defeat auto-selection for most
  // real category sets (only "Shopping" happens to match exactly here).
  static String? _matchExistingLabel(String candidate, List<String> existingCategoryLabels) {
    final candidateLower = candidate.toLowerCase();

    for (final label in existingCategoryLabels) {
      if (label.toLowerCase() == candidateLower) return label;
    }

    final relatedWords = <String>{
      candidateLower,
      ...?_categoryKeywords[candidate]?.map((k) => k.toLowerCase()),
    };

    for (final label in existingCategoryLabels) {
      final cleanLabel = label.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
      if (cleanLabel.length < 3) continue;

      for (final word in relatedWords) {
        final cleanWord = word.replaceAll(RegExp(r'[^a-z]'), '');
        if (cleanWord.length < 3) continue;
        if (cleanWord.contains(cleanLabel) || cleanLabel.contains(cleanWord)) {
          return label;
        }
      }
    }

    return null;
  }

  // ─────────────────────────── Payment keyword ───────────────────────────

  static String? _detectPaymentKeyword(String rawText) {
    final lowerText = rawText.toLowerCase();

    for (final entry in _accountKeywords.entries) {
      for (final keyword in entry.value) {
        if (_containsKeyword(lowerText, keyword.toLowerCase())) {
          return entry.key;
        }
      }
    }

    return null;
  }

  static void dispose() {
    _textRecognizer.close();
  }
}
