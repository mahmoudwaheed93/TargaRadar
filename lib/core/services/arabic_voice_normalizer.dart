export '../../data/models/excel_vehicle_model.dart' show OrphanVoiceData, ParsedPlateData;
import '../../data/models/excel_vehicle_model.dart';

class _PlateMatch {
  final int startIndex;
  final int endIndex;
  final String letters;
  final String digits;
  final String fullPlate;
  final bool isDigitsFirst;

  const _PlateMatch({
    required this.startIndex,
    required this.endIndex,
    required this.letters,
    required this.digits,
    required this.fullPlate,
    required this.isDigitsFirst,
  });
}

class _BrandResult {
  final String brand;
  final List<String> remaining;
  const _BrandResult(this.brand, this.remaining);
}

class _SplitWords {
  final List<String> forPlate1;
  final List<String> forPlate2;
  const _SplitWords(this.forPlate1, this.forPlate2);
}

/// Ultra-fast Arabic voice plate normalizer, multi-plate extractor, and semantic classifier.
/// Engineered for 0ms latency with comprehensive Egyptian & Saudi dialect support,
/// flexible word ordering (brand / plate / note in any order), bidirectional plate matching,
/// and live continuous dictation parsing.
class ArabicVoiceNormalizer {
  ArabicVoiceNormalizer._();

  // Comprehensive Car Brands & Models (Sorted: Multi-word first, then single-word)
  static const List<String> carBrands = [
    // Multi-word phrases first
    'لاند كروزر', 'لاندكروزر', 'بي ام دبليو', 'بي ام', 'جراند شيروكي', 'فورد تورس', 'فورد اكسبلورر',
    'فورد فيوجن', 'مرسيدس بنز', 'مرسيدس', 'ام جي زد اس', 'ام جي 5', 'ام جي 6', 'ام جي',
    'راف فور', 'سي اكس 9', 'سي اكس 5', 'جي ام سي', 'بي واي دي', 'فولكس فاجن', 'كيا k5',
    'كيا سيراتو', 'كيا سبورتاج', 'تويوتا كامري', 'تويوتا كورولا', 'تويوتا يارس', 'تويوتا هايلكس',
    'تويوتا برادو', 'تويوتا افالون', 'هيونداي النترا', 'هيونداي سوناتا', 'هيونداي اكسنت',
    'هيونداي ازيرا', 'هيونداي توسان', 'هيونداي كريتا', 'هيونداي سنتافي', 'نيسان باترول',
    'نيسان صني', 'نيسان التيما', 'نيسان مكسيما', 'شفروليه كابرس', 'شفروليه تاهو', 'شفروليه سلفرادو',
    'دي ماكس', 'ديماكس', 'ام يو اكس',

    // Single-word brands and models
    'تويوتا', 'نيسان', 'هيونداي', 'كيا', 'فورد', 'شيفروليه', 'شفروليه', 'شفر', 'جمس',
    'النترا', 'كورولا', 'كامري', 'سوناتا', 'اكسنت', 'ازيرا', 'افالون', 'يارس', 'تاهو', 'يوكن',
    'لكزس', 'مازدا', 'هافال', 'جيلي', 'شانجان', 'هوندا', 'ميتسوبيشي', 'سوزوكي', 'ايسوزو', 'شيري',
    'برادو', 'باترول', 'شاص', 'ددسن', 'هايلكس', 'فورتشنر', 'انوفا', 'كريتا', 'توسان', 'سنتافي',
    'سبورتاج', 'سيراتو', 'ريو', 'اوبتيما', 'كادينزا', 'تشارجر', 'دورانجو', 'تشالنجر', 'كابرس',
    'سلفرادو', 'سييرا', 'رينجر', 'هايلاندر', 'صني', 'سنترا', 'التيما', 'مكسيما', 'ماكسيما',
    'اكورد', 'سيفيك', 'باجيرو', 'لانسر', 'ديزاير', 'سويفت', 'كولراي', 'امجراند', 'توغيلا',
    'مونجارو', 'تيجو', 'اريزو', 'شيروكي', 'باسات', 'تيجوان', 'جولف', 'بيجو', 'رينو', 'ميجان',
    'داستر', 'لوجان', 'فيات', 'تيبو', 'دينا', 'سطحة', 'تريلا', 'باص', 'ميكروباص', 'فان', 'وانيت'
  ];

  // Comprehensive Note Keywords (Multi-word first, then single-word)
  static const List<String> noteKeywords = [
    // Multi-word phrases
    'واقفة صف تاني', 'واقفة صف ثاني', 'صف تاني', 'صف ثاني',
    'واقفة غلط', 'واقفه غلط', 'موقف غلط',
    'جراج يمين', 'برحة يسار', 'برحه يسار', 'موقف مظلل', 'في البايكة', 'في البايكه', 'تحت المظلة', 'تحت المظله', 'على الرصيف',
    'في الممنوع', 'ممنوع الوقوف', 'عكس السير', 'سادة الطريق', 'ساد الطريق',
    'بدون لوحة', 'بدون لوحه', 'بدون لوحات', 'بدون استمارة', 'بدون استماره',
    'لوحة طايحة', 'لوحه طايحه', 'لوحة مطموسة', 'لوحه مطموسه', 'عليها غبار',

    // Single-word keywords
    'مركونة', 'مركونه', 'واقفة', 'واقفه',
    'ماشية', 'ماشيه', 'متحركة', 'متحركه', 'بتتحرك', 'متحرك',
    'عطلانة', 'عطلانه', 'خربانة', 'خربانه', 'معطلة', 'معطله',
    'مطربة', 'مطربه', 'متربة', 'متربه', 'مغبرة', 'مغبره', 'مغبر',
    'مهملة', 'مهمله', 'تالفة', 'تالفه', 'سكراب', 'تشليح', 'خردة', 'خرده',
    'مصدومة', 'مصدومه', 'مكسورة', 'مكسوره', 'محروقة', 'محروقه',
    'مخالفة', 'مخالفه', 'مخالف', 'مسروقة', 'مسروقه'
  ];

  static const Set<String> fillerWords = {
    'نوعها', 'نوع', 'ماركة', 'ماركه', 'موديل', 'سيارة', 'سياره', 'عربية', 'عربيه',
    'لوحة', 'لوحه', 'نمرة', 'نمره', 'رقم'
  };

  static const List<String> noteTriggers = [
    'ملحوظة', 'ملحوظه', 'ملاحظة', 'ملاحظه', 'نوت', 'اكتب', 'سجل'
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
        final pattern = '(?:و\\s*)?(?:' + unit.key + ')\\s*و\\s*(?:' + ten.key + ')(?![ء-ي])';
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
      rules.add(MapEntry(RegExp(_w('(?:و\\s*)?' + ten.key)), '${ten.value}'));
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

    // Normalize Arabic letter variants
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
  static final RegExp _gluedLetters = RegExp(r'^[ا-ي]{2,4}$');

  static bool _isLetter(String t) => _singleLetter.hasMatch(t);
  static bool _isDigits(String t) => _digitsOnly.hasMatch(t);
  static bool _isPlateDigits(String t) => _isDigits(t) && t.length >= 2 && t.length <= 4;
  static bool _isGluedLetters(String t) =>
      _gluedLetters.hasMatch(t) && !fillerWords.contains(t) && !carBrands.contains(t) && !noteKeywords.contains(t);

  /// Extract Brand from a list of words, returning detected brand and the remaining words
  static _BrandResult _extractBrandFromWords(List<String> words) {
    if (words.isEmpty) return _BrandResult('-', words);
    final str = words.join(' ');

    for (final b in carBrands) {
      final bNorm = b.replaceAll('ة', 'ه').replaceAll(RegExp(r'[أإآ]'), 'ا').replaceAll('ى', 'ي');
      final padded = ' $str ';
      if (padded.contains(' $bNorm ')) {
        final bTokens = bNorm.split(' ');
        final remaining = <String>[];
        int i = 0;
        while (i < words.length) {
          if (i + bTokens.length <= words.length &&
              words.sublist(i, i + bTokens.length).join(' ') == bNorm) {
            i += bTokens.length;
          } else {
            remaining.add(words[i]);
            i++;
          }
        }
        return _BrandResult(b, remaining);
      }
    }
    return _BrandResult('-', words);
  }

  /// Extract Note from a list of words, honoring explicit triggers, note keywords, and free text
  static String _extractNoteFromWords(List<String> words, {String? stickyNote}) {
    if (words.isEmpty) return stickyNote ?? '-';

    // 1. Explicit triggers: "ملحوظة ...", "نوت ..."
    for (int i = 0; i < words.length; i++) {
      if (noteTriggers.contains(words[i])) {
        final explicit = words.sublist(i + 1).where((w) => !fillerWords.contains(w)).join(' ').trim();
        if (explicit.isNotEmpty) return explicit;
      }
    }

    // 2. Note keywords (multi-word first)
    final str = words.join(' ');
    for (final kw in noteKeywords) {
      final kwNorm = kw.replaceAll('ة', 'ه').replaceAll(RegExp(r'[أإآ]'), 'ا').replaceAll('ى', 'ي');
      if ((' $str ').contains(' $kwNorm ')) {
        return kw;
      }
    }

    // 3. Meaningful non-filler words
    final useful = words.where((w) => !fillerWords.contains(w)).toList();
    if (useful.isNotEmpty) {
      return useful.join(' ').trim();
    }

    return stickyNote ?? '-';
  }

  /// Splits tokens occurring between two plates so that leading notes belong to Plate 1
  /// and trailing brand/filler belongs to Plate 2.
  static _SplitWords _splitWordsBetweenPlates(List<String> betweenWords) {
    if (betweenWords.isEmpty) {
      return const _SplitWords([], []);
    }

    int brandStart = -1;
    final str = betweenWords.join(' ');
    for (final b in carBrands) {
      final bNorm = b.replaceAll('ة', 'ه').replaceAll(RegExp(r'[أإآ]'), 'ا').replaceAll('ى', 'ي');
      if ((' $str ').contains(' $bNorm ')) {
        final bTokens = bNorm.split(' ');
        for (int i = 0; i <= betweenWords.length - bTokens.length; i++) {
          if (betweenWords.sublist(i, i + bTokens.length).join(' ') == bNorm) {
            if (i > 0 && fillerWords.contains(betweenWords[i - 1])) {
              brandStart = i - 1;
            } else {
              brandStart = i;
            }
            break;
          }
        }
        break;
      }
    }

    if (brandStart != -1) {
      return _SplitWords(
        betweenWords.sublist(0, brandStart),
        betweenWords.sublist(brandStart),
      );
    }

    return _SplitWords(
      betweenWords,
      const [],
    );
  }

  /// Internal match representation
  static List<_PlateMatch> _findPlateMatches(List<String> tokens) {
    final matches = <_PlateMatch>[];
    int i = 0;

    while (i < tokens.length) {
      // Pattern A: Letters then Digits ("د ب ن 2816")
      final lA = <String>[];
      int j = i;
      while (j < tokens.length && _isLetter(tokens[j])) {
        lA.add(tokens[j]);
        j++;
      }
      if (lA.length >= 2 && lA.length <= 4 && j < tokens.length && _isPlateDigits(tokens[j])) {
        matches.add(_PlateMatch(
          startIndex: i,
          endIndex: j + 1,
          letters: lA.join(' '),
          digits: tokens[j],
          fullPlate: '${lA.join(' ')} ${tokens[j]}',
          isDigitsFirst: false,
        ));
        i = j + 1;
        continue;
      }

      // Pattern B: GluedLetters then Digits ("دبن 2816")
      if (_isGluedLetters(tokens[i]) && i + 1 < tokens.length && _isPlateDigits(tokens[i + 1])) {
        final letters = tokens[i].split('').join(' ');
        matches.add(_PlateMatch(
          startIndex: i,
          endIndex: i + 2,
          letters: letters,
          digits: tokens[i + 1],
          fullPlate: '$letters ${tokens[i + 1]}',
          isDigitsFirst: false,
        ));
        i = i + 2;
        continue;
      }

      // Pattern C: Digits then Letters ("2816 د ب ن")
      if (_isPlateDigits(tokens[i])) {
        final lC = <String>[];
        int k = i + 1;
        while (k < tokens.length && _isLetter(tokens[k])) {
          lC.add(tokens[k]);
          k++;
        }
        if (lC.length >= 2 && lC.length <= 4) {
          matches.add(_PlateMatch(
            startIndex: i,
            endIndex: k,
            letters: lC.join(' '),
            digits: tokens[i],
            fullPlate: '${lC.join(' ')} ${tokens[i]}',
            isDigitsFirst: true,
          ));
          i = k;
          continue;
        }

        // Pattern D: Digits then GluedLetters ("2816 دبن")
        if (i + 1 < tokens.length && _isGluedLetters(tokens[i + 1])) {
          final letters = tokens[i + 1].split('').join(' ');
          matches.add(_PlateMatch(
            startIndex: i,
            endIndex: i + 2,
            letters: letters,
            digits: tokens[i],
            fullPlate: '$letters ${tokens[i]}',
            isDigitsFirst: true,
          ));
          i = i + 2;
          continue;
        }
      }

      i++;
    }

    return matches;
  }

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
    final matches = _findPlateMatches(tokens);
    if (matches.isEmpty) return results;

    // Build context window per plate: preceding words + succeeding words
    final platePrev = List<List<String>>.generate(matches.length, (_) => []);
    final plateNext = List<List<String>>.generate(matches.length, (_) => []);

    platePrev[0] = tokens.sublist(0, matches[0].startIndex);
    plateNext[matches.length - 1] = tokens.sublist(matches.last.endIndex);

    for (int i = 0; i < matches.length - 1; i++) {
      final between = tokens.sublist(matches[i].endIndex, matches[i + 1].startIndex);
      final split = _splitWordsBetweenPlates(between);
      plateNext[i] = split.forPlate1;
      platePrev[i + 1] = split.forPlate2;
    }

    for (int pIdx = 0; pIdx < matches.length; pIdx++) {
      final match = matches[pIdx];
      final prevWords = platePrev[pIdx];
      final nextWords = plateNext[pIdx];
      final contextWords = [...prevWords, ...nextWords];

      final brandRes = _extractBrandFromWords(contextWords);
      final note = _extractNoteFromWords(brandRes.remaining, stickyNote: stickyNote);

      final isComplete = match.digits.length == 4 ||
          pIdx + 1 < matches.length ||
          nextWords.isNotEmpty ||
          brandRes.brand != '-' ||
          note != (stickyNote ?? '-');

      results.add(ParsedPlateData(
        fullPlate: match.fullPlate,
        letters: match.letters,
        digits: match.digits,
        detectedBrand: brandRes.brand,
        detectedNote: note,
        isComplete: isComplete,
      ));
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

  /// Extract standalone car brand and/or note spoken after a pause without a plate
  static OrphanVoiceData extractOrphanBrandAndNote(String normalized) {
    if (normalized.isEmpty) return const OrphanVoiceData(brand: '-', note: '-');
    final tokens = normalized.split(' ').where((t) => t.isNotEmpty).toList();
    if (tokens.isEmpty) return const OrphanVoiceData(brand: '-', note: '-');

    final brandRes = _extractBrandFromWords(tokens);
    final note = _extractNoteFromWords(brandRes.remaining);

    return OrphanVoiceData(
      brand: brandRes.brand != '-' ? brandRes.brand : null,
      note: note != '-' ? note : null,
    );
  }

  /// Orphan note spoken after a pause without a plate (from already normalized string)
  static String? orphanNoteFromNormalized(String normalized) {
    final orphan = extractOrphanBrandAndNote(normalized);
    return orphan.note;
  }

  /// Orphan note spoken after a pause without a plate
  static String? orphanNote(String transcript) {
    return orphanNoteFromNormalized(normalizeArabicSpoken(transcript));
  }
}
