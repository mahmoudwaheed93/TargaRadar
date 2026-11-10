import '../../data/models/excel_vehicle_model.dart';

/// Ultra-fast Arabic voice plate normalizer & multi-plate extractor.
/// Engineered for 0ms latency with comprehensive Egyptian & Saudi dialect support,
/// continuous dictation parsing, and instant compound number resolution.
class ArabicVoiceNormalizer {
  ArabicVoiceNormalizer._();

  static const List<String> carBrands = [
    'مرسيدس', 'تويوتا', 'نيسان', 'هيونداي', 'كيا', 'فورد', 'شيفروليه', 'شفروليه',
    'النترا', 'كورولا', 'كامري', 'سوناتا', 'اكسنت', 'بي ام', 'بي ام دبليو', 'لكزس', 'مازدا', 
    'هافال', 'جيلي', 'ام جي', 'شانجان', 'هوندا', 'ميتسوبيشي', 'سوزوكي', 'ايسوزو', 'شيري', 
    'لاندكروزر', 'لاند كروزر', 'برادو', 'باترول', 'شاص', 'ددسن', 'هايلكس', 'افالون', 'ازيرا', 
    'كريتا', 'توسان', 'سنتافي', 'سبورتاج', 'سيراتو', 'ريو', 'اوبتيما', 'كادينزا', 'تشارجر', 
    'كابرس', 'تاهو', 'يوكن', 'سييرا', 'سلفرادو', 'رينجر', 'هايلاندر', 'راف فور', 'يارس'
  ];

  static const List<String> noteKeywords = [
    'جراج يمين', 'برحة يسار', 'برحه يسار', 'موقف مظلل',
    'عطلانة', 'عطلانه', 'مركونة', 'مركونه', 'ماشية', 'ماشيه', 'متحركة', 'متحركه',
    'مطربة', 'مطربه', 'مصدومة', 'مصدومه', 'مغبرة', 'مغبره', 'مهملة', 'مهمله',
    'مخالفة', 'مخالفه', 'بدون لوحة', 'بدون لوحه', 'مسروقة', 'مسروقه'
  ];

  /// Lookaround word boundary for Arabic text
  static String _w(String pattern) => '(?<![ء-ي])(?:$pattern)(?![ء-ي])';

  // --- ARABIC NUMBER DEFINITIONS ---

  static final List<MapEntry<RegExp, int>> numThousands = [
    MapEntry(RegExp(_w('(?:و\\s*)?(?:تسع[هة]?\\s*الاف|تسعة\\s*الاف)')), 9000),
    MapEntry(RegExp(_w('(?:و\\s*)?(?:تماني[هة]?\\s*الاف|تمان\\s*الاف|ثماني[هة]?\\s*الاف|ثمان\\s*الاف)')), 8000),
    MapEntry(RegExp(_w('(?:و\\s*)?(?:سبع[هة]?\\s*الاف|سبعة\\s*الاف)')), 7000),
    MapEntry(RegExp(_w('(?:و\\s*)?(?:ست[هة]?\\s*الاف|ستة\\s*الاف)')), 6000),
    MapEntry(RegExp(_w('(?:و\\s*)?(?:خمس[هة]?\\s*الاف|خمسة\\s*الاف)')), 5000),
    MapEntry(RegExp(_w('(?:و\\s*)?(?:اربع[هة]?\\s*الاف|اربعة\\s*الاف)')), 4000),
    MapEntry(RegExp(_w('(?:و\\s*)?(?:تلت[هة]?\\s*الاف|تلات[هة]?\\s*الاف|ثلاث[هة]?\\s*الاف)')), 3000),
    MapEntry(RegExp(_w('(?:و\\s*)?(?:الفين|الفان)')), 2000),
    MapEntry(RegExp(_w('(?:و\\s*)?الف')), 1000),
  ];

  static final List<MapEntry<RegExp, int>> numHundreds = [
    MapEntry(RegExp(_w('(?:و\\s*)?(?:تسعم[يئ][هة]|تسعمائ[هة])')), 900),
    MapEntry(RegExp(_w('(?:و\\s*)?(?:تمنم[يئ][هة]|تمانم[يئ][هة]|ثمانم[يئ][هة]|ثمانمائ[هة])')), 800),
    MapEntry(RegExp(_w('(?:و\\s*)?(?:سبعم[يئ][هة]|سبعمائ[هة])')), 700),
    MapEntry(RegExp(_w('(?:و\\s*)?(?:ستم[يئ][هة]|ستمائ[هة])')), 600),
    MapEntry(RegExp(_w('(?:و\\s*)?(?:خمسم[يئ][هة]|خمسمائ[هة])')), 500),
    MapEntry(RegExp(_w('(?:و\\s*)?(?:اربعم[يئ][هة]|اربعمائ[هة])')), 400),
    MapEntry(RegExp(_w('(?:و\\s*)?(?:تلتم[يئ][هة]|تلاتم[يئ][هة]|ثلاثم[يئ][هة]|ثلاثمائ[هة])')), 300),
    MapEntry(RegExp(_w('(?:و\\s*)?(?:ميتين|مائتان|مئتان)')), 200),
    MapEntry(RegExp(_w('(?:و\\s*)?(?:م[يئ][هة]|مائ[هة]|مائه)')), 100),
  ];

  static final List<MapEntry<RegExp, int>> numTeens = [
    MapEntry(RegExp(_w('(?:و\\s*)?(?:تسعتاشر|تسع[هة]?\\s*عشر)')), 19),
    MapEntry(RegExp(_w('(?:و\\s*)?(?:تمانتاشر|تمنتاشر|ثماني[هة]?\\s*عشر)')), 18),
    MapEntry(RegExp(_w('(?:و\\s*)?(?:سبعتاشر|سبع[هة]?\\s*عشر)')), 17),
    MapEntry(RegExp(_w('(?:و\\s*)?(?:ستاشر|ست[هة]?\\s*عشر)')), 16),
    MapEntry(RegExp(_w('(?:و\\s*)?(?:خمستاشر|خمس[هة]?\\s*عشر)')), 15),
    MapEntry(RegExp(_w('(?:و\\s*)?(?:اربعتاشر|اربع[هة]?\\s*عشر)')), 14),
    MapEntry(RegExp(_w('(?:و\\s*)?(?:تلاتاشر|تلتاشر|ثلاث[هة]?\\s*عشر)')), 13),
    MapEntry(RegExp(_w('(?:و\\s*)?(?:اتناشر|اثنا\\s*عشر|اثناعشر)')), 12),
    MapEntry(RegExp(_w('(?:و\\s*)?(?:حداشر|احداشر|احد\\s*عشر)')), 11),
    MapEntry(RegExp(_w('(?:و\\s*)?(?:عشر[هة]|عشر)')), 10),
  ];

  static final List<MapEntry<String, int>> numTensRaw = [
    const MapEntry('تسعين', 90),
    const MapEntry('تمانين', 80),
    const MapEntry('ثمانين', 80),
    const MapEntry('سبعين', 70),
    const MapEntry('ستين', 60),
    const MapEntry('خمسين', 50),
    const MapEntry('اربعين', 40),
    const MapEntry('تلاتين', 30),
    const MapEntry('ثلاثين', 30),
    const MapEntry('عشرين', 20),
  ];

  static final List<MapEntry<String, int>> numUnitsRaw = [
    const MapEntry('تسع[هة]?', 9),
    const MapEntry('تماني[هة]?|تمان|ثماني[هة]?|ثمان', 8),
    const MapEntry('سبع[هة]?', 7),
    const MapEntry('ست[هة]?', 6),
    const MapEntry('خمس[هة]?', 5),
    const MapEntry('اربع[هة]?', 4),
    const MapEntry('تلات[هة]?|ثلاث[هة]?', 3),
    const MapEntry('اتنين|اثنين', 2),
    const MapEntry('واحد', 1),
  ];

  static final List<MapEntry<RegExp, String>> arNumRules = _initNumRules();

  static List<MapEntry<RegExp, String>> _initNumRules() {
    final rules = <MapEntry<RegExp, String>>[];

    // 1. Compound units + tens: "خمسة وعشرين" -> 25, "ثمانية وعشرين" -> 28
    for (final ten in numTensRaw) {
      for (final unit in numUnitsRaw) {
        final pattern = '(?:و\\s*)?(?:${unit.key})\\s*و\\s*(?:${ten.key})(?![ء-ي])';
        rules.add(MapEntry(RegExp('(?<![ء-ي])$pattern'), '${ten.value + unit.value}'));
      }
    }

    // 2. Thousands
    for (final th in numThousands) {
      rules.add(MapEntry(th.key, '${th.value}'));
    }

    // 3. Hundreds
    for (final h in numHundreds) {
      rules.add(MapEntry(h.key, '${h.value}'));
    }

    // 4. Teens (10 - 19)
    for (final t in numTeens) {
      rules.add(MapEntry(t.key, '${t.value}'));
    }

    // 5. Tens (20, 30 ... 90)
    for (final ten in numTensRaw) {
      rules.add(MapEntry(RegExp(_w('(?:و\\s*)?${ten.key}')), '${ten.value}'));
    }

    // 6. Units (0 - 9)
    rules.addAll([
      MapEntry(RegExp(_w('(?:و\\s*)?(?:صفر|زيرو)')), '0'),
      MapEntry(RegExp(_w('(?:و\\s*)?واحد')), '1'),
      MapEntry(RegExp(_w('(?:و\\s*)?(?:اثنين|اتنين)')), '2'),
      MapEntry(RegExp(_w('(?:و\\s*)?(?:ثلاث[هة]?|تلات[هة]?)')), '3'),
      MapEntry(RegExp(_w('(?:و\\s*)?اربع[هة]?')), '4'),
      MapEntry(RegExp(_w('(?:و\\s*)?خمس[هة]?')), '5'),
      MapEntry(RegExp(_w('(?:و\\s*)?ست[هة]?')), '6'),
      MapEntry(RegExp(_w('(?:و\\s*)?سبع[هة]?')), '7'),
      MapEntry(RegExp(_w('(?:و\\s*)?(?:ثماني[هة]?|تماني[هة]?|ثمان|تمان)')), '8'),
      MapEntry(RegExp(_w('(?:و\\s*)?تسع[هة]?')), '9'),
    ]);

    return rules;
  }

  /// Spoken letter names including colloquial Arabic/Egyptian speech recognition variants
  static final List<MapEntry<RegExp, String>> arLetterNames = [
    MapEntry(RegExp(_w('الف')), 'ا'),
    MapEntry(RegExp(_w('باء|به')), 'ب'),
    MapEntry(RegExp(_w('تاء|ته')), 'ت'),
    MapEntry(RegExp(_w('ثاء|ثه')), 'ث'),
    MapEntry(RegExp(_w('جيم')), 'ج'),
    MapEntry(RegExp(_w('حاء|حا|حه')), 'ح'),
    MapEntry(RegExp(_w('خاء|خا|خه')), 'خ'),
    MapEntry(RegExp(_w('دال|ده')), 'د'),
    MapEntry(RegExp(_w('ذال|ذه')), 'ذ'),
    MapEntry(RegExp(_w('راء|را|ره')), 'ر'),
    MapEntry(RegExp(_w('زاي|زا|زه')), 'ز'),
    MapEntry(RegExp(_w('سين|سا')), 'س'),
    MapEntry(RegExp(_w('شين|شا')), 'ش'),
    MapEntry(RegExp(_w('صاد|صا')), 'ص'),
    MapEntry(RegExp(_w('ضاد|ضا')), 'ض'),
    MapEntry(RegExp(_w('طاء|طا|طه')), 'ط'),
    MapEntry(RegExp(_w('ظاء|ظا|ظه')), 'ظ'),
    MapEntry(RegExp(_w('عين|عا|عه')), 'ع'),
    MapEntry(RegExp(_w('غين|غا|غه')), 'غ'),
    MapEntry(RegExp(_w('فاء|فا|فه')), 'ف'),
    MapEntry(RegExp(_w('قاف|قا|قه')), 'ق'),
    MapEntry(RegExp(_w('كاف|كا|كه')), 'ك'),
    MapEntry(RegExp(_w('لام|لا')), 'ل'),
    MapEntry(RegExp(_w('ميم|ما|مه')), 'م'),
    MapEntry(RegExp(_w('نون|نا|نه')), 'ن'),
    MapEntry(RegExp(_w('هاء|ها|هه')), 'ه'),
    MapEntry(RegExp(_w('واو|وا')), 'و'),
    MapEntry(RegExp(_w('ياء|يه|يا')), 'ي'),
  ];

  static String? _memoIn;
  static String _memoOut = '';

  /// Normalize raw Arabic speech transcript into canonical letters and digits
  static String normalizeArabicSpoken(String text) {
    if (text.isEmpty) return '';
    if (text == _memoIn) return _memoOut;
    final out = _normalizeUncached(text);
    _memoIn = text;
    _memoOut = out;
    return out;
  }

  static String _normalizeUncached(String text) {
    // Convert Hindi/Eastern digits to Western Arabic digits
    const arabicDigits = '٠١٢٣٤٥٦٧٨٩';
    var cleaned = text.replaceAllMapped(RegExp(r'[٠-٩]'), (match) {
      final digit = match.group(0)!;
      return '${arabicDigits.indexOf(digit)}';
    });

    // Normalize Arabic letters
    cleaned = cleaned
        .replaceAll(RegExp(r'[أإآ]'), 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي');

    // Replace Spoken Letter Names
    for (final entry in arLetterNames) {
      cleaned = cleaned.replaceAll(entry.key, ' ${entry.value} ');
    }

    // Replace Spoken Numbers & Compounds
    for (final entry in arNumRules) {
      cleaned = cleaned.replaceAll(entry.key, ' ${entry.value} ');
    }

    // Collapse compound numbers: thousands + hundreds + remainder (e.g. 2000 800 16 -> 2816)
    cleaned = cleaned.replaceAllMapped(RegExp(r'\b(\d{4})\s+(\d{3})\s+(\d{1,2})\b'), (m) {
      final sum = (int.tryParse(m.group(1)!) ?? 0) +
          (int.tryParse(m.group(2)!) ?? 0) +
          (int.tryParse(m.group(3)!) ?? 0);
      return '$sum';
    });
    cleaned = cleaned.replaceAllMapped(RegExp(r'\b(\d{4})\s+(\d{3})\b'), (m) {
      final sum = (int.tryParse(m.group(1)!) ?? 0) + (int.tryParse(m.group(2)!) ?? 0);
      return '$sum';
    });
    cleaned = cleaned.replaceAllMapped(RegExp(r'\b(\d{4})\s+(\d{1,2})\b'), (m) {
      final sum = (int.tryParse(m.group(1)!) ?? 0) + (int.tryParse(m.group(2)!) ?? 0);
      return '$sum';
    });
    cleaned = cleaned.replaceAllMapped(RegExp(r'\b(\d{3})\s+(\d{1,2})\b'), (m) {
      final sum = (int.tryParse(m.group(1)!) ?? 0) + (int.tryParse(m.group(2)!) ?? 0);
      return '$sum';
    });

    // Collapse continuous adjacent digits (e.g. "2 8 1 6" -> "2816")
    var prev = '';
    while (prev != cleaned) {
      prev = cleaned;
      cleaned = cleaned.replaceAllMapped(RegExp(r'(\d+)\s+(\d+)'), (m) => '${m.group(1)}${m.group(2)}');
    }

    return cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Normalizer for plate string matching (removes all whitespace, standardizes alefs/yahs/digits)
  static String normalizePlateForMatch(String plate) {
    if (plate.isEmpty) return '';
    const arabicDigits = '٠١٢٣٤٥٦٧٨٩';
    return plate
        .replaceAllMapped(RegExp(r'[٠-٩]'), (m) => '${arabicDigits.indexOf(m.group(0)!)}')
        .replaceAll(RegExp(r'[أإآ]'), 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي')
        .replaceAll(RegExp(r'\s+'), '')
        .trim();
  }

  /// Canon format key for fast O(1) index matching
  static String plateKey(String plate) => normalizePlateForMatch(plate);

  static final RegExp _singleLetter = RegExp(r'^[ا-ي]$');
  static final RegExp _digitsOnly = RegExp(r'^\d+$');

  static bool _isLetter(String t) => _singleLetter.hasMatch(t);
  static bool _isDigits(String t) => _digitsOnly.hasMatch(t);

  /// Supports 2 to 4 digits (standard Egyptian & Saudi plates)
  static bool _isPlateDigits(String t) => _isDigits(t) && t.length >= 2 && t.length <= 4;

  static final RegExp _noteTriggerRe = RegExp(r'^(?:ال)?(?:ملحوظ|ملاحظ)');
  static bool _isNoteTrigger(String t) => t == 'نوت' || _noteTriggerRe.hasMatch(t);
  static const String _noteMark = '\u0001';

  /// True when a new plate starts at token [k]
  static bool _startsPlate(List<String> tokens, int k) {
    var j = k;
    var n = 0;
    while (j < tokens.length && _isLetter(tokens[j])) {
      n++;
      j++;
    }
    if (n >= 2 && n <= 4 && j < tokens.length && _isPlateDigits(tokens[j])) return true;
    if (n == 0 &&
        k + 1 < tokens.length &&
        tokens[k].length >= 2 &&
        tokens[k].length <= 4 &&
        RegExp(r'^[ا-ي]+$').hasMatch(tokens[k]) &&
        _isPlateDigits(tokens[k + 1])) {
      return true;
    }
    return false;
  }

  static const List<String> _controlWords = ['بدايه', 'انتهي', 'انتهت'];

  /// Multi-plate scanner (token based)
  static List<ParsedPlateData> extractPlatesFromTranscript(
    String transcriptChunk, {
    String? stickyNote,
  }) {
    final normalized = normalizeArabicSpoken(transcriptChunk);
    return extractPlatesFromNormalized(normalized, stickyNote: stickyNote);
  }

  /// Multi-plate scanner from already normalized string
  static List<ParsedPlateData> extractPlatesFromNormalized(
    String normalized, {
    String? stickyNote,
  }) {
    final results = <ParsedPlateData>[];
    if (normalized.isEmpty) return results;

    final tokens = normalized.split(' ').where((t) => t.isNotEmpty).toList();
    int i = 0;

    while (i < tokens.length) {
      final letters = <String>[];
      int j = i;

      // Case A: letters spoken one by one -> "د ب ن"
      while (j < tokens.length && _isLetter(tokens[j])) {
        letters.add(tokens[j]);
        j++;
      }

      // Case B: recogniser glued the letters into one word -> "دبن 2816"
      if (letters.isEmpty &&
          j + 1 < tokens.length &&
          tokens[j].length >= 2 &&
          tokens[j].length <= 4 &&
          RegExp(r'^[ا-ي]+$').hasMatch(tokens[j]) &&
          _isPlateDigits(tokens[j + 1])) {
        letters.addAll(tokens[j].split(''));
        j++;
      }

      if (letters.length >= 2 && letters.length <= 4 && j < tokens.length && _isPlateDigits(tokens[j])) {
        final digits = tokens[j];
        j++;

        // Free words attached to this plate: brand / note
        final freeWords = <String>[];
        while (j < tokens.length && !_startsPlate(tokens, j)) {
          final tok = tokens[j];
          if (_controlWords.any((c) => tok.startsWith(c))) break;
          freeWords.add(tok);
          j++;
        }

        String brand = '-';
        String note = stickyNote ?? '-';

        if (freeWords.isNotEmpty) {
          final noteIdx = freeWords.indexWhere(_isNoteTrigger);
          if (noteIdx != -1) {
            freeWords[noteIdx] = _noteMark;
          }

          final brandMatch = carBrands.firstWhere(
            (b) => freeWords.any((w) => w == b || w.contains(b)),
            orElse: () => '',
          );
          if (brandMatch.isNotEmpty) {
            brand = brandMatch;
            freeWords.removeWhere((w) => w == brandMatch);
          }

          final explicitWords = <String>[];
          bool afterTrigger = false;
          for (final w in freeWords) {
            if (w == _noteMark) {
              afterTrigger = true;
              continue;
            }
            if (afterTrigger) {
              explicitWords.add(w);
            }
          }

          if (explicitWords.isNotEmpty) {
            note = explicitWords.join(' ');
          } else {
            final kw = noteKeywords.firstWhere(
              (k) => freeWords.any((w) => w == k || w.contains(k)),
              orElse: () => '',
            );
            if (kw.isNotEmpty) {
              note = kw;
            } else if (freeWords.isNotEmpty && !freeWords.contains(_noteMark)) {
              final candidate = freeWords.join(' ').trim();
              if (candidate.isNotEmpty) note = candidate;
            }
          }
        }

        bool isComplete = true;
        if (digits.length == 4) {
          isComplete = true;
        } else if (j < tokens.length && _startsPlate(tokens, j)) {
          isComplete = true;
        } else if (freeWords.isNotEmpty || brand != '-') {
          isComplete = true;
        } else if (j == tokens.length && digits.length < 4) {
          isComplete = false;
        }

        results.add(ParsedPlateData(
          fullPlate: '${letters.join(' ')} $digits',
          letters: letters.join(' '),
          digits: digits,
          detectedBrand: brand,
          detectedNote: note,
          isComplete: isComplete,
        ));

        i = j;
        continue;
      }

      i = j > i ? j : i + 1;
    }

    return results;
  }

  /// Extracts visualizer slot values for 7 slots from already extracted plates
  static Map<String, String> extractSlotsFromPlates(List<ParsedPlateData> plates) {
    if (plates.isEmpty) return const {};
    final p = plates.last;
    final lClean = p.letters.replaceAll(RegExp(r'\s+'), '');
    final lSlots = lClean.length > 3 ? lClean.substring(lClean.length - 3) : lClean;
    final lList = lSlots.split('');
    final dList = p.digits.split('');

    return {
      'l1': lList.isNotEmpty ? lList[0] : '-',
      'l2': lList.length > 1 ? lList[1] : '-',
      'l3': lList.length > 2 ? lList[2] : '-',
      'd1': dList.isNotEmpty ? dList[0] : '-',
      'd2': dList.length > 1 ? dList[1] : '-',
      'd3': dList.length > 2 ? dList[2] : '-',
      'd4': dList.length > 3 ? dList[3] : '-',
    };
  }

  /// Extracts visualizer slot values for 7 slots
  static Map<String, String> extractSlots(String transcript) {
    return extractSlotsFromPlates(extractPlatesFromTranscript(transcript));
  }

  /// Orphan note spoken after a pause without a plate (from already normalized string)
  static String? orphanNoteFromNormalized(String normalized) {
    if (normalized.isEmpty) return null;
    final tokens = normalized.split(' ').where((t) => t.isNotEmpty).toList();
    if (tokens.isEmpty) return null;

    final kw = noteKeywords.firstWhere(
      (k) => tokens.any((t) => t == k || t.contains(k)),
      orElse: () => '',
    );
    if (kw.isNotEmpty) return kw;

    final idx = tokens.indexWhere(_isNoteTrigger);
    if (idx != -1 && idx + 1 < tokens.length) {
      return tokens.sublist(idx + 1).join(' ').trim();
    }
    return null;
  }

  /// Orphan note spoken after a pause without a plate
  static String? orphanNote(String transcript) {
    return orphanNoteFromNormalized(normalizeArabicSpoken(transcript));
  }
}
