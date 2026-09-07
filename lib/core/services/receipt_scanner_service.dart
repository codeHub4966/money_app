import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class ReceiptData {
  final double? amount;
  final DateTime? date;
  final String? merchantName;
  final List<String> itemDescriptions;
  final String? suggestedNote;
  final String? detectedPaymentKeyword;
  final String rawText;

  ReceiptData({
    this.amount,
    this.date,
    this.merchantName,
    this.itemDescriptions = const [],
    this.suggestedNote,
    this.detectedPaymentKeyword,
    required this.rawText,
  });

  bool get hasData => amount != null || date != null || merchantName != null;
}

class ReceiptScannerService {
  static final _textRecognizer = TextRecognizer();

  static const int _minCategoryScore = 2;

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
    'Shopping': [
      // Fashion
      'mall', 'shop', 'boutique', 'uniqlo', 'zara', 'h&m', 'nike',
      'adidas', 'fashion', 'clothing', 'apparel', 'shoes', 'bag',
      'shirt', 'tee', 't-shirt', 'pants', 'jeans', 'dress', 'skirt',
      'jacket', 'sweater', 'hoodie', 'sneakers', 'sandals', 'watch',
      'accessories', 'hat', 'cap', 'socks', 'underwear', 'belt',
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

  // Payment method keywords for account matching.
  static final Map<String, List<String>> _accountKeywords = {
    'visa': ['visa'],
    'mastercard': ['mastercard', 'master card'],
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
    'debit': ['debit'],
    'credit': ['credit'],
  };

  // Generic receipt headers that are never the merchant name.
  static final RegExp _genericHeaderPattern = RegExp(
    r'^(welcome|receipt|tax\s*invoice|invoice|official\s*receipt|customer\s*copy|merchant\s*copy)\b',
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
      final rawText = recognizedText.text;
      final lines = rawText.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

      final merchantName = _extractMerchant(lines);
      final itemDescriptions = _extractItemDescriptions(lines, merchantName);
      final amount = _extractAmount(lines);
      final date = _extractDate(lines);
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
      );
    } catch (e) {
      return ReceiptData(rawText: '');
    }
  }

  // Whole-word match so short keywords like "bar" or "cap" don't fire on
  // substrings such as "barcode" or "capacity".
  static bool _containsKeyword(String text, String keyword) {
    final pattern = RegExp(r'\b' + RegExp.escape(keyword.toLowerCase()) + r'\b');
    return pattern.hasMatch(text);
  }

  // ─────────────────────────── Amount ───────────────────────────

  static double? _extractAmount(List<String> lines) {
    // Note: deliberately does NOT exclude tax/gst/sst — many Malaysian
    // receipts print the real grand total as "TOTAL (INCL. GST)" or
    // "TOTAL INCLUSIVE OF SST", and excluding those words caused the actual
    // total line to be skipped entirely.
    final exclusion = RegExp(
      r'\b(sub\s*total|subtotal|cash|change|discount|'
      r'service\s*charge|rounding|tendered|received)\b',
      caseSensitive: false,
    );

    // Checked in priority order — the first keyword family with a valid,
    // non-excluded match wins. Word-boundary matching means "total" alone
    // never matches inside "subtotal".
    final priorityKeywords = <RegExp>[
      RegExp(r'\bgrand\s*total\b', caseSensitive: false),
      RegExp(r'\btotal\s*payable\b', caseSensitive: false),
      RegExp(r'\bnet\s*total\b', caseSensitive: false),
      RegExp(r'\btotal\s*due\b', caseSensitive: false),
      RegExp(r'\bbalance\s*due\b', caseSensitive: false),
      RegExp(r'\bamount\s*payable\b', caseSensitive: false),
      RegExp(r'\bamount\s*due\b', caseSensitive: false),
      RegExp(r'\bfinal\s*total\b', caseSensitive: false),
      RegExp(r'\btotal\b', caseSensitive: false),
    ];

    for (final keywordPattern in priorityKeywords) {
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (!keywordPattern.hasMatch(line)) continue;
        if (exclusion.hasMatch(line) && keywordPattern.pattern == r'\btotal\b') continue;

        final kwMatch = keywordPattern.firstMatch(line)!;
        final afterKeyword = _extractFirstPrice(line.substring(kwMatch.end));
        if (afterKeyword != null) return afterKeyword;

        final anywhereOnLine = _extractFirstPrice(line);
        if (anywhereOnLine != null) return anywhereOnLine;

        if (i + 1 < lines.length && !exclusion.hasMatch(lines[i + 1])) {
          final nextLineAmount = _extractFirstPrice(lines[i + 1]);
          if (nextLineAmount != null) return nextLineAmount;
        }
      }
    }

    // Fallback: no total/grand total/amount due keyword was recognised at
    // all (OCR garbled the label, or the receipt phrases it unusually).
    // Rather than leave the amount blank, fall back to the largest money
    // amount on the receipt — it's usually the grand total since it's the
    // sum of everything above it. This never overrides a keyword match.
    final allAmounts = <double>[];
    for (final line in lines) {
      final price = _extractFirstPrice(line);
      if (price != null) allAmounts.add(price);
    }
    if (allAmounts.isNotEmpty) {
      allAmounts.sort();
      return allAmounts.last;
    }

    return null;
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

  static DateTime? _extractDate(List<String> lines) {
    final labelPattern = RegExp(r'\bdate\b', caseSensitive: false);
    final labelLines = lines.where((l) => labelPattern.hasMatch(l));
    final otherLines = lines.where((l) => !labelPattern.hasMatch(l));

    for (final line in [...labelLines, ...otherLines]) {
      final result = _tryParseDateFromLine(line);
      if (result != null) return result;
    }

    return null;
  }

  static DateTime? _tryParseDateFromLine(String line) {
    final dmy = RegExp(r'\b(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})\b').firstMatch(line);
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

    final ymd = RegExp(r'\b(\d{4})[/-](\d{1,2})[/-](\d{1,2})\b').firstMatch(line);
    if (ymd != null) {
      final year = int.parse(ymd.group(1)!);
      final month = int.parse(ymd.group(2)!);
      final day = int.parse(ymd.group(3)!);
      if (_isValidYMD(year, month, day)) return DateTime(year, month, day);
      return null;
    }

    final dmonthy = RegExp(
      r'\b(\d{1,2})\s+(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\s+(\d{2,4})\b',
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

  // The merchant name is simply the first meaningful line on the receipt —
  // only skip lines that are clearly not a business name (blank, or a
  // generic header like "TAX INVOICE"). Anything smarter than that started
  // second-guessing real merchant lines and picking an address line instead.
  static String? _extractMerchant(List<String> lines) {
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.length < 2) continue;
      if (_genericHeaderPattern.hasMatch(trimmed)) continue;
      return trimmed;
    }
    return null;
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

      final priceMatch = RegExp(
        r'(?:rm|myr)?\s*\d{1,3}(?:[.,]\d{3})*[.,]\d{2}\s*$',
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

  /// Suggests a category using (in order of confidence): learned
  /// merchant→category history, extracted item descriptions, the merchant
  /// name, existing category labels, and finally the raw OCR text as a weak
  /// fallback. When [existingCategoryLabels] is non-empty, only a label from
  /// that list is ever returned — this method never invents a category.
  static String? suggestCategory({
    String? merchantName,
    List<String> itemDescriptions = const [],
    String rawText = '',
    List<String> existingCategoryLabels = const [],
    Map<String, String> merchantCategoryHistory = const {},
  }) {
    if (merchantName != null && merchantName.isNotEmpty) {
      final learned = merchantCategoryHistory[merchantName.toLowerCase().trim()];
      if (learned != null &&
          (existingCategoryLabels.isEmpty || existingCategoryLabels.contains(learned))) {
        return learned;
      }
    }

    final itemText = itemDescriptions.join(' ').toLowerCase();
    final merchantLower = (merchantName ?? '').toLowerCase();
    final rawLower = rawText.toLowerCase();

    final scores = <String, int>{};
    void addScore(String category, int amount) {
      scores[category] = (scores[category] ?? 0) + amount;
    }

    for (final entry in _categoryKeywords.entries) {
      for (final keyword in entry.value) {
        final kw = keyword.toLowerCase();
        if (_containsKeyword(itemText, kw)) addScore(entry.key, 4);
        if (merchantLower.isNotEmpty && _containsKeyword(merchantLower, kw)) addScore(entry.key, 2);
        if (_containsKeyword(rawLower, kw)) addScore(entry.key, 1);
      }
    }

    // Let existing (possibly user-created) category labels act as their own
    // loose keywords, so a custom category like "Pets" can still be matched.
    for (final label in existingCategoryLabels) {
      final words = label.toLowerCase().split(RegExp(r'[^a-z]+')).where((w) => w.length >= 3);
      for (final word in words) {
        final singular = word.endsWith('s') ? word.substring(0, word.length - 1) : word;
        for (final form in {word, singular}) {
          if (itemText.contains(form)) addScore(label, 3);
          if (merchantLower.contains(form)) addScore(label, 2);
        }
      }
    }

    if (scores.isEmpty) return null;

    final resolved = <String, int>{};
    for (final entry in scores.entries) {
      final label = existingCategoryLabels.isEmpty
          ? entry.key
          : _matchExistingLabel(entry.key, existingCategoryLabels);
      if (label == null) continue;
      resolved[label] = (resolved[label] ?? 0) + entry.value;
    }

    if (resolved.isEmpty) return null;

    final ranked = resolved.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    if (ranked.first.value < _minCategoryScore) return null;
    return ranked.first.key;
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
