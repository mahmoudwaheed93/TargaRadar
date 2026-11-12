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

  /// Common 2-4 char Arabic words that must NEVER be treated as glued plate letters.
  static const Set<String> stopWords = {
    'في', 'من', 'عن', 'على', 'علي', 'الى', 'الي', 'مع', 'بين', 'تحت', 'فوق', 'جنب', 'عند', 'ورا', 'امام',
    'ده', 'دي', 'دا', 'دو', 'دول', 'هذا', 'هذه', 'تلك', 'ذلك', 'هو', 'هي', 'هم', 'هن', 'انا', 'انت', 'احنا',
    'بس', 'كل', 'مش', 'ما', 'لا', 'لم', 'لن', 'او', 'ولا', 'ثم', 'حتى', 'حتي', 'لما', 'لو', 'ان', 'كان',
    'يمين', 'يسار', 'شمال', 'صف', 'تاني', 'ثاني', 'غلط', 'صح', 'جراج', 'برحه', 'برحة', 'موقف', 'باب', 'لون',
    'احمر', 'ازرق', 'اسود', 'ابيض', 'فضي', 'رمادي', 'رصاصي', 'اخضر', 'اصفر', 'بني', 'ذهبي', 'كحلي', 'بيج', 'نبيتي',
    'جديد', 'قديم', 'صفر', 'مكرر', 'كنسل', 'الغي', 'الغاء', 'حذف', 'مسح', 'وقف', 'ايقاف', 'ابدا', 'بدايه', 'بداية', 'انتهي', 'انتهت',
    'تمام', 'حاضر', 'ماشي', 'اوكي', 'شكرا', 'يلا', 'بص', 'شوف',
    'جيب', 'اوبل', 'اودي', 'لادا', 'دايو', 'ملاكي', 'اجره', 'نقل', 'شيري', 'تيجو', 'بيك',
  };

  static String _normWord(String w) => w
      .replaceAll('ة', 'ه')
      .replaceAll(RegExp(r'[أإآ]'), 'ا')
      .replaceAll('ى', 'ي');

  static final Set<String> _nonLetterTokens = {
    ...fillerWords,
    ...stopWords,
    ...noteTriggers,
    ...carBrands.where((b) => !b.contains(' ')),
    ...noteKeywords.where((n) => !n.contains(' ')),
  }.map(_normWord).toSet();

  static final List<List<String>> _multiWordPhrases = [
    ...carBrands,
    ...noteKeywords,
  ]
      .where((p) => p.contains(' '))
      .map((p) => _normWord(p).split(' ').where((w) => w.isNotEmpty).toList())
      .toList();

  static const List<String> noteTriggers = [
    'ملحوظة', 'ملحوظه', 'ملاحظة', 'ملاحظه', 'نوت', 'اكتب', 'سجل'
  ];

  /// Lookaround word boundary for Arabic text
  static String _w(String pattern) => '(?<![ء-ي])(?:$pattern)(?![ء-ي])';

  // --- ARABIC NUMBER DEFINITIONS ---

  static final List<MapEntry<RegExp, int>> numThousands = [
    MapEntry(RegExp(_w('(?:و\\s*)?(?:تسع[هة]?\\s*(?:الاف|تلاف)|تسعالاف)')), 9000),
    MapEntry(RegExp(_w('(?:و\\s*)?(?:تماني?[هة]?\\s*(?:الاف|تلاف)|ثماني?[هة]?\\s*(?:الاف|تلاف)|تمانالاف|ثمانالاف)')), 8000),
    MapEntry(RegExp(_w('(?:و\\s*)?(?:سبع[هة]?\\s*(?:الاف|تلاف)|سبعالاف)')), 7000),
    MapEntry(RegExp(_w('(?:و\\s*)?(?:ست[هة]?\\s*(?:الاف|تلاف)|ستالاف)')), 6000),
    MapEntry(RegExp(_w('(?:و\\s*)?(?:خمس[هة]?\\s*(?:الاف|تلاف)|خمسالاف)')), 5000),
    MapEntry(RegExp(_w('(?:و\\s*)?(?:اربع[هة]?\\s*(?:الاف|تلاف)|اربعالاف)')), 4000),
    MapEntry(RegExp(_w('(?:و\\s*)?(?:تلت[هة]?\\s*(?:الاف|تلاف)|تلات[هة]?\\s*(?:الاف|تلاف)|ثلاث[هة]?\\s*(?:الاف|تلاف)|تلاتالاف|تلتالاف)')), 3000),
    MapEntry(RegExp(_w('(?:و\\s*)?(?:الفين|الفان)')), 2000),
    MapEntry(RegExp(_w('(?:و\\s*)?الف')), 1000),
  ];

  static final List<MapEntry<RegExp, int>> numHundreds = [
    MapEntry(RegExp(_w('(?:و\\s*)?(?:تسع\\s*م[يئ][هة]|تسع\\s*مائ[هة])')), 900),
    MapEntry(RegExp(_w('(?:و\\s*)?(?:تمن\\s*م[يئ][هة]|تمان\\s*م[يئ][هة]|ثمان\\s*م[يئ][هة]|ثمان\\s*مائ[هة])')), 800),
    MapEntry(RegExp(_w('(?:و\\s*)?(?:سبع\\s*م[يئ][هة]|سبع\\s*مائ[هة])')), 700),
    MapEntry(RegExp(_w('(?:و\\s*)?(?:ست\\s*م[يئ][هة]|ست\\s*مائ[هة])')), 600),
    MapEntry(RegExp(_w('(?:و\\s*)?(?:خمس\\s*م[يئ][هة]|خمس\\s*مائ[هة])')), 500),
    MapEntry(RegExp(_w('(?:و\\s*)?(?:اربع\\s*م[يئ][هة]|ربعم[يئ][هة]|اربع\\s*مائ[هة])')), 400),
    MapEntry(RegExp(_w('(?:و\\s*)?(?:تلت\\s*م[يئ][هة]|تلات\\s*م[يئ][هة]|ثلاث\\s*م[يئ][هة]|ثلاث\\s*مائ[هة])')), 300),
    MapEntry(RegExp(_w('(?:و\\s*)?(?:ميتين|متين|مائتين|مئتين|مائتان|مئتان)')), 200),
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
    MapEntry(RegExp(_w('باء|به|با')), 'ب'),
    MapEntry(RegExp(_w('تاء|ته|تا|تي')), 'ت'),
    MapEntry(RegExp(_w('ثاء|ثه|ثا')), 'ث'),
    MapEntry(RegExp(_w('جيم')), 'ج'),
    MapEntry(RegExp(_w('حاء|حا|حه')), 'ح'),
    MapEntry(RegExp(_w('خاء|خا|خه')), 'خ'),
    MapEntry(RegExp(_w('دال|ده')), 'د'),
    MapEntry(RegExp(_w('ذال|ذه')), 'ذ'),
    MapEntry(RegExp(_w('راء|را|ره')), 'ر'),
    MapEntry(RegExp(_w('زاي|زا|زه')), 'ز'),
    MapEntry(RegExp(_w('سين|سا')), 'س'),
    MapEntry(RegExp(_w('شين|شا|شي')), 'ش'),
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
    // Strip Arabic diacritics & tatweel, convert Hindi/Eastern digits to Western Arabic digits
    const arabicDigits = '٠١٢٣٤٥٦٧٨٩';
    var cleaned = text
        .replaceAll(RegExp(r'[\u064B-\u065F\u0670\u0640]'), '')
        .replaceAllMapped(RegExp(r'[٠-٩]'), (match) {
      final digit = match.group(0)!;
      return '${arabicDigits.indexOf(digit)}';
    });

    // Normalize Arabic letter variants
    cleaned = cleaned
        .replaceAll(RegExp(r'[أإآ]'), 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي');

    // Convert "الف" = 1000 BEFORE letter substitution when followed by number words
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'(?<![ء-ي])الف(?=\s+(?:و\s*)?(?:م[يئ][هة]|متين|ميتين|مئتين|مائ|تلات|تلت|ثلاث|اربع|خمس|ست|سبع|تمان|تمن|ثمان|تسع|عشر|احد|حداشر|اتناشر|تلتاشر|اربعتاشر|خمستاشر|ستاشر|سبعتاشر|تمانتاشر|تسعتاشر|واحد|اتنين|اثنين))(?![ء-ي])'),
      (m) => ' 1000 ',
    );

    // Replace Spoken Letter Names
    for (final entry in arLetterNames) {
      cleaned = cleaned.replaceAll(entry.key, ' ${entry.value} ');
    }

    // Replace Spoken Numbers & Compounds
    for (final entry in arNumRules) {
      cleaned = cleaned.replaceAll(entry.key, ' ${entry.value} ');
    }

    // Collapse compound place-value numbers ONLY (e.g. 2000 800 16 -> 2816),
    // never adding onto a finished 4-digit plate like 2816.
    cleaned = cleaned.replaceAllMapped(RegExp(r'\b([1-9]000)\s+([1-9]00)\s+(\d{1,2})\b'), (m) {
      final sum = (int.tryParse(m.group(1)!) ?? 0) +
          (int.tryParse(m.group(2)!) ?? 0) +
          (int.tryParse(m.group(3)!) ?? 0);
      return '$sum';
    });
    cleaned = cleaned.replaceAllMapped(RegExp(r'\b([1-9]000)\s+([1-9]00)\b'), (m) {
      final sum = (int.tryParse(m.group(1)!) ?? 0) + (int.tryParse(m.group(2)!) ?? 0);
      return '$sum';
    });
    cleaned = cleaned.replaceAllMapped(RegExp(r'\b([1-9]000)\s+(\d{1,2})\b'), (m) {
      final sum = (int.tryParse(m.group(1)!) ?? 0) + (int.tryParse(m.group(2)!) ?? 0);
      return '$sum';
    });
    cleaned = cleaned.replaceAllMapped(RegExp(r'\b([1-9]00)\s+(\d{1,2})\b'), (m) {
      final sum = (int.tryParse(m.group(1)!) ?? 0) + (int.tryParse(m.group(2)!) ?? 0);
      return '$sum';
    });

    // Collapse adjacent digit tokens up to 4 digits per plate in one O(N) pass
    // (e.g. "2816 3 2 5 3" -> "2816 3253", never merging across two consecutive plates).
    final rawTokens = cleaned.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    final mergedTokens = <String>[];
    for (final tok in rawTokens) {
      if (mergedTokens.isNotEmpty &&
          _digitsOnly.hasMatch(mergedTokens.last) &&
          _digitsOnly.hasMatch(tok) &&
          mergedTokens.last.length + tok.length <= 4) {
        mergedTokens[mergedTokens.length - 1] = '${mergedTokens.last}$tok';
      } else {
        mergedTokens.add(tok);
      }
    }

    return mergedTokens.join(' ');
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

  static final Map<String, String> _plateKeyCache = {};

  /// Canon format key for fast O(1) index matching (always letters + digits, strips punctuation)
  static String plateKey(String plate) {
    if (plate.isEmpty) return '';
    final cached = _plateKeyCache[plate];
    if (cached != null) return cached;
    final norm = normalizePlateForMatch(plate)
        .replaceAll(RegExp(r'[\u064B-\u065F\u0670\u0640]'), '');
    if (norm.isEmpty) return '';
    final letters = norm.replaceAll(RegExp(r'[^ا-ي]'), '');
    final digits = norm.replaceAll(RegExp(r'[^\d]'), '');
    final out = '$letters$digits';
    if (_plateKeyCache.length >= 500) {
      _plateKeyCache.remove(_plateKeyCache.keys.first);
    }
    _plateKeyCache[plate] = out;
    return out;
  }

  static final RegExp _singleLetter = RegExp(r'^[ا-ي]$');
  static final RegExp _digitsOnly = RegExp(r'^\d+$');
  static final RegExp _gluedLetters = RegExp(r'^[ا-ي]{2,4}$');

  static bool _isLetter(String t) => _singleLetter.hasMatch(t);
  static bool _isDigits(String t) => _digitsOnly.hasMatch(t);
  static bool _isPlateDigits(String t) => _isDigits(t) && t.length >= 2 && t.length <= 4;
  static bool _isGluedLetters(String t) =>
      _gluedLetters.hasMatch(t) && !_nonLetterTokens.contains(t);

  static int _phraseLengthAt(List<String> tokens, int idx) {
    for (final pTokens in _multiWordPhrases) {
      if (idx + pTokens.length <= tokens.length) {
        bool ok = true;
        for (int k = 0; k < pTokens.length; k++) {
          if (tokens[idx + k] != pTokens[k]) {
            ok = false;
            break;
          }
        }
        if (ok) return pTokens.length;
      }
    }
    return 0;
  }

  /// Collects up to 4 Arabic plate letters starting at [start], handling both
  /// separated letters ("ب ن ق") and mixed glued tokens ("بن ق" / "ب نق").
  static ({List<String> letters, int nextIdx}) _collectLetters(List<String> tokens, int start) {
    final chars = <String>[];
    int idx = start;
    while (idx < tokens.length) {
      if (_phraseLengthAt(tokens, idx) > 0) break;
      final t = tokens[idx];
      if (_isLetter(t)) {
        if (chars.length + 1 > 4) break;
        chars.add(t);
        idx++;
      } else if (_isGluedLetters(t)) {
        if (chars.length + t.length > 4) break;
        chars.addAll(t.split(''));
        idx++;
      } else {
        break;
      }
    }
    return (letters: chars, nextIdx: idx);
  }

  /// Returns true when [newPlate] is an incremental continuation of [prevPlate]
  /// (either trailing digits added or trailing letters added after digits).
  static bool isPlateUpgrade(String prevPlate, String newPlate) {
    final prevNorm = normalizePlateForMatch(prevPlate);
    final newNorm = normalizePlateForMatch(newPlate);
    if (prevNorm.isEmpty || newNorm.length <= prevNorm.length) return false;
    if (newNorm.startsWith(prevNorm)) return true;

    final prevLetters = prevNorm.replaceAll(RegExp(r'\d'), '');
    final newLetters = newNorm.replaceAll(RegExp(r'\d'), '');
    final prevDigits = prevNorm.replaceAll(RegExp(r'[^\d]'), '');
    final newDigits = newNorm.replaceAll(RegExp(r'[^\d]'), '');

    if (prevLetters.isEmpty || prevDigits.isEmpty) return false;
    if (prevDigits == newDigits &&
        newLetters.length > prevLetters.length &&
        newLetters.startsWith(prevLetters)) {
      return true;
    }
    if (prevLetters == newLetters &&
        newDigits.length > prevDigits.length &&
        newDigits.startsWith(prevDigits)) {
      return true;
    }
    return false;
  }

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

  /// Extract Note from a list of words, strictly honoring explicit triggers and note keywords.
  /// Stray letters or unrecognized words are NEVER captured as notes.
  static String _extractNoteFromWords(List<String> words, {String? stickyNote}) {
    if (words.isEmpty) return stickyNote ?? '-';

    // 1. Explicit triggers: "ملحوظة ...", "ملاحظة ...", "نوت ..."
    for (int i = 0; i < words.length; i++) {
      if (noteTriggers.contains(words[i])) {
        final explicit = words.sublist(i + 1)
            .where((w) => !fillerWords.contains(w) && !_isLetter(w))
            .join(' ')
            .trim();
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

    // Strictly return stickyNote or '-': NEVER invent notes or record stray letters!
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
      // Skip multi-word car brands / note phrases so they are never swallowed as letters
      final phraseLen = _phraseLengthAt(tokens, i);
      if (phraseLen > 0) {
        i += phraseLen;
        continue;
      }

      // Pattern A/B: Letters (separated, glued, or mixed like "بن ق") then Digits
      final colA = _collectLetters(tokens, i);
      if (colA.letters.length >= 2 &&
          colA.letters.length <= 4 &&
          colA.nextIdx < tokens.length &&
          _isPlateDigits(tokens[colA.nextIdx])) {
        final letters = colA.letters.join(' ');
        final digits = tokens[colA.nextIdx];
        matches.add(_PlateMatch(
          startIndex: i,
          endIndex: colA.nextIdx + 1,
          letters: letters,
          digits: digits,
          fullPlate: '$letters $digits',
          isDigitsFirst: false,
        ));
        i = colA.nextIdx + 1;
        continue;
      }

      // Pattern C/D: Digits then Letters (separated, glued, or mixed like "3253 بن ق")
      if (_isPlateDigits(tokens[i])) {
        // Check if letters bridge directly to another plate's digits (e.g. "3253 ب ن ق د ب ن 2816")
        final bridgeChars = <String>[];
        final bridgeTokenStops = <int>[];
        int bIdx = i + 1;
        while (bIdx < tokens.length && _phraseLengthAt(tokens, bIdx) == 0) {
          final t = tokens[bIdx];
          if (_isLetter(t)) {
            bridgeChars.add(t);
            bridgeTokenStops.add(bIdx + 1);
            bIdx++;
          } else if (_isGluedLetters(t)) {
            for (final ch in t.split('')) {
              bridgeChars.add(ch);
              bridgeTokenStops.add(bIdx + 1);
            }
            bIdx++;
          } else {
            break;
          }
        }

        if (bridgeChars.length >= 5 && bIdx < tokens.length && _isPlateDigits(tokens[bIdx])) {
          // Split cleanly at 3 letters leaving >=2 letters for the next plate
          final take = (bridgeChars.length - 3 >= 2) ? 3 : 2;
          final cutIdx = bridgeTokenStops[take - 1];
          int actualTake = take;
          while (actualTake < bridgeChars.length && bridgeTokenStops[actualTake] == cutIdx) {
            actualTake++;
          }
          if (actualTake <= 4 && bridgeChars.length - actualTake >= 2) {
            final letters = bridgeChars.sublist(0, actualTake).join(' ');
            final digits = tokens[i];
            matches.add(_PlateMatch(
              startIndex: i,
              endIndex: cutIdx,
              letters: letters,
              digits: digits,
              fullPlate: '$letters $digits',
              isDigitsFirst: true,
            ));
            i = cutIdx;
            continue;
          }
        }

        final colC = _collectLetters(tokens, i + 1);
        if (colC.letters.length >= 2 && colC.letters.length <= 4) {
          final letters = colC.letters.join(' ');
          final digits = tokens[i];
          matches.add(_PlateMatch(
            startIndex: i,
            endIndex: colC.nextIdx,
            letters: letters,
            digits: digits,
            fullPlate: '$letters $digits',
            isDigitsFirst: true,
          ));
          i = colC.nextIdx;
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

      final hasTrailingContext = pIdx + 1 < matches.length ||
          nextWords.isNotEmpty ||
          brandRes.brand != '-' ||
          note != (stickyNote ?? '-');
      // Zero-millisecond instant commit for any 4-digit plate; any late trailing
      // letter ("ب ن 3253" -> "ب ن ق 3253") upgrades the card in place at 0ms.
      final isComplete = match.digits.length == 4 || hasTrailingContext;

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

  /// Extracts live 7-slot values at 0ms even while a plate is still being spoken
  /// (e.g. "د ب", "325", or "3253 ب" before the full plate pattern completes).
  static Map<String, String> extractLiveSlots(String normalized, List<ParsedPlateData> plates) {
    final tail = extractUnparsedTail(normalized);
    if (tail.isNotEmpty) {
      final tokens = tail.split(' ').where((t) => t.isNotEmpty).toList();
      final liveLetters = <String>[];
      final liveDigits = <String>[];
      for (int i = 0; i < tokens.length; i++) {
        if (_phraseLengthAt(tokens, i) > 0) break;
        final t = tokens[i];
        if (_isLetter(t)) {
          liveLetters.add(t);
        } else if (_isGluedLetters(t)) {
          liveLetters.addAll(t.split(''));
        } else if (_isDigits(t)) {
          liveDigits.addAll(t.split(''));
        }
      }
      if (liveLetters.isNotEmpty || liveDigits.isNotEmpty) {
        final lSlots = liveLetters.length > 3 ? liveLetters.sublist(liveLetters.length - 3) : liveLetters;
        final dSlots = liveDigits.length > 4 ? liveDigits.sublist(liveDigits.length - 4) : liveDigits;
        return {
          'l1': lSlots.isNotEmpty ? lSlots[0] : '-',
          'l2': lSlots.length > 1 ? lSlots[1] : '-',
          'l3': lSlots.length > 2 ? lSlots[2] : '-',
          'd1': dSlots.isNotEmpty ? dSlots[0] : '-',
          'd2': dSlots.length > 1 ? dSlots[1] : '-',
          'd3': dSlots.length > 2 ? dSlots[2] : '-',
          'd4': dSlots.length > 3 ? dSlots[3] : '-',
        };
      }
    }
    return extractSlotsFromPlates(plates);
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
    if (normalized.isEmpty) return const OrphanVoiceData();
    final tokens = normalized.split(' ').where((t) => t.isNotEmpty).toList();
    if (tokens.isEmpty) return const OrphanVoiceData();

    // Never treat speech consisting purely of individual letters as orphan brand or note
    if (tokens.every((t) => _isLetter(t))) {
      return const OrphanVoiceData();
    }

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

  /// Returns tokens in [normalized] that follow the last matched plate, or all of
  /// [normalized] when no plate was matched yet. Enables AI fallback on later
  /// plates inside a continuous dictation buffer.
  static String extractUnparsedTail(String normalized) {
    if (normalized.isEmpty) return '';
    final tokens = normalized.split(' ').where((t) => t.isNotEmpty).toList();
    if (tokens.isEmpty) return '';
    final matches = _findPlateMatches(tokens);
    if (matches.isEmpty) return normalized;
    final tail = tokens.sublist(matches.last.endIndex);
    return tail.join(' ').trim();
  }

  /// Returns ONLY the live speech not yet committed as a finished 4-digit plate
  /// so the on-screen ticker clears completed plates automatically for the next one.
  static String extractActiveTickerText(String normalized) {
    if (normalized.isEmpty) return '';
    final tokens = normalized.split(' ').where((t) => t.isNotEmpty).toList();
    if (tokens.isEmpty) return '';
    final matches = _findPlateMatches(tokens);
    if (matches.isEmpty) return normalized;
    final last = matches.last;
    // If the latest matched plate is still waiting for trailing digits (<4)
    // and has nothing after it, keep it visible until completed.
    if (last.digits.length < 4 && last.endIndex == tokens.length) {
      return tokens.sublist(last.startIndex).join(' ').trim();
    }
    return tokens.sublist(last.endIndex).join(' ').trim();
  }

  /// Validates whether [rawTranscript] genuinely contains an explicit note
  /// trigger or verified note keyword (guards AI output against stray-letter notes).
  static bool hasValidNoteTriggerOrKeyword(String rawTranscript) {
    final norm = normalizeArabicSpoken(rawTranscript);
    if (norm.isEmpty) return false;
    final words = norm.split(' ').where((w) => w.isNotEmpty).toList();
    return _extractNoteFromWords(words) != '-';
  }

  static int _scorePlates(List<ParsedPlateData> plates, String unparsedTail) {
    if (plates.isEmpty) return 0;
    int score = 0;
    for (final p in plates) {
      final lCount = p.letters.replaceAll(' ', '').length;
      final dCount = p.digits.length;
      if (p.isComplete) score += 100;
      score += (lCount >= 3 ? 25 : lCount * 7);
      score += (dCount == 4 ? 25 : dCount * 5);
      if (p.detectedBrand != '-') score += 5;
      if (p.detectedNote != '-') score += 5;
    }
    if (!RegExp(r'\d{2,}').hasMatch(unparsedTail)) {
      score += 10;
    }
    return score;
  }

  /// Selects the strongest transcription across Google STT N-best alternates in <0.2ms.
  static ({
    String rawTranscript,
    String normalized,
    List<ParsedPlateData> plates,
  }) selectBestCandidate(List<String> candidates) {
    if (candidates.isEmpty) {
      return (rawTranscript: '', normalized: '', plates: const []);
    }

    final primaryRaw = candidates.first;
    final primaryNorm = normalizeArabicSpoken(primaryRaw);
    final primaryPlates = extractPlatesFromNormalized(primaryNorm);

    if (candidates.length == 1) {
      return (rawTranscript: primaryRaw, normalized: primaryNorm, plates: primaryPlates);
    }

    final primaryTail = extractUnparsedTail(primaryNorm);
    if (primaryPlates.isNotEmpty &&
        primaryPlates.last.isComplete &&
        primaryPlates.last.letters.replaceAll(' ', '').length >= 3 &&
        primaryPlates.last.digits.length == 4 &&
        !RegExp(r'\d{2,}').hasMatch(primaryTail)) {
      return (rawTranscript: primaryRaw, normalized: primaryNorm, plates: primaryPlates);
    }

    var bestRaw = primaryRaw;
    var bestNorm = primaryNorm;
    var bestPlates = primaryPlates;
    var bestScore = _scorePlates(primaryPlates, primaryTail);

    for (final altRaw in candidates.skip(1).take(4)) {
      final altNorm = normalizeArabicSpoken(altRaw);
      final altPlates = extractPlatesFromNormalized(altNorm);
      final altTail = extractUnparsedTail(altNorm);
      final altScore = _scorePlates(altPlates, altTail);
      if (altScore > bestScore) {
        bestScore = altScore;
        bestRaw = altRaw;
        bestNorm = altNorm;
        bestPlates = altPlates;
      }
    }

    return (rawTranscript: bestRaw, normalized: bestNorm, plates: bestPlates);
  }
}
