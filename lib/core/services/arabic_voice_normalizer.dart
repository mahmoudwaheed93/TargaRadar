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
/// Strictly enforces 3-letter plate boundaries (rejecting 2- and 4-letter false captures)
/// and auto-pads 3-digit plates with a trailing zero (`123` -> `1230`) on commit.
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
    'داستر', 'لوجان', 'فيات', 'تيبو', 'دينا', 'سطحة', 'تريلا', 'باص', 'ميكروباص', 'فان', 'وانيت',
    'جيب', 'اوبل', 'اودي', 'لادا', 'دايو',
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
    'مخالفة', 'مخالفه', 'مخالف', 'مسروقة', 'مسروقه',
  ];

  static const Set<String> fillerWords = {
    'نوعها', 'نوع', 'ماركة', 'ماركه', 'موديل', 'سيارة', 'سياره', 'عربية', 'عربيه',
    'لوحة', 'لوحه', 'نمرة', 'نمره', 'رقم',
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
    'ملاكي', 'اجره', 'نقل', 'بيك', 'يا', 'يه', 'ها', 'نا', 'تا', 'تي', 'سا',
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
    'ملحوظة', 'ملحوظه', 'ملاحظة', 'ملاحظه', 'نوت', 'اكتب', 'سجل',
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
    const MapEntry('تسعين|تسعون', 90),
    const MapEntry('تمانين|تمانون', 80),
    const MapEntry('ثمانين|ثمانون', 80),
    const MapEntry('سبعين|سبعون', 70),
    const MapEntry('ستين|ستون', 60),
    const MapEntry('خمسين|خمسون', 50),
    const MapEntry('اربعين|اربعون', 40),
    const MapEntry('تلاتين|تلاتون', 30),
    const MapEntry('ثلاثين|ثلاثون', 30),
    const MapEntry('عشرين|عشرون', 20),
  ];

  static final List<MapEntry<String, int>> numUnitsRaw = [
    const MapEntry('تسع[هة]?', 9),
    const MapEntry('تماني[هة]?|تمان|ثماني[هة]?|ثمان', 8),
    const MapEntry('سبع[هة]?', 7),
    const MapEntry('ست[هة]?', 6),
    const MapEntry('خمس[هة]?', 5),
    const MapEntry('اربع[هة]?', 4),
    const MapEntry('تلات[هة]?|ثلاث[هة]?', 3),
    const MapEntry('اتنين|اثنين|اتنان|اثنان', 2),
    const MapEntry('واحد', 1),
  ];

  static final List<MapEntry<RegExp, String>> arNumRules = _initNumRules();

  static List<MapEntry<RegExp, String>> _initNumRules() {
    final rules = <MapEntry<RegExp, String>>[];

    // 1. Compound units + tens: "خمسة وعشرين" -> 25
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

    // 5. Tens (20..90)
    for (final ten in numTensRaw) {
      rules.add(MapEntry(RegExp(_w('(?:و\\s*)?(?:${ten.key})')), '${ten.value}'));
    }

    // 6. Units (0 - 9)
    rules.addAll([
      MapEntry(RegExp(_w('(?:و\\s*)?(?:صفر|زيرو)')), '0'),
      MapEntry(RegExp(_w('(?:و\\s*)?واحد')), '1'),
      MapEntry(RegExp(_w('(?:و\\s*)?(?:اثنين|اتنين|اثنان|اتنان)')), '2'),
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

  /// Canonical spoken letter names (excludes Egyptian everyday words like ده، لا، يا، ما، تا)
  static final List<MapEntry<RegExp, String>> arLetterNames = [
    MapEntry(RegExp(_w('الف')), 'ا'),
    MapEntry(RegExp(_w('باء|به|با')), 'ب'),
    MapEntry(RegExp(_w('تاء')), 'ت'),
    MapEntry(RegExp(_w('ثاء|ثه|ثا')), 'ث'),
    MapEntry(RegExp(_w('جيم')), 'ج'),
    MapEntry(RegExp(_w('حاء|حا')), 'ح'),
    MapEntry(RegExp(_w('خاء|خا|خه')), 'خ'),
    MapEntry(RegExp(_w('دال')), 'د'),
    MapEntry(RegExp(_w('ذال|ذه')), 'ذ'),
    MapEntry(RegExp(_w('راء|را')), 'ر'),
    MapEntry(RegExp(_w('زاي|زا|زه')), 'ز'),
    MapEntry(RegExp(_w('سين')), 'س'),
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
    MapEntry(RegExp(_w('لام')), 'ل'),
    MapEntry(RegExp(_w('ميم')), 'م'),
    MapEntry(RegExp(_w('نون')), 'ن'),
    MapEntry(RegExp(_w('هاء')), 'ه'),
    MapEntry(RegExp(_w('واو|وا')), 'و'),
    MapEntry(RegExp(_w('ياء|يه')), 'ي'),
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
    const arabicDigits = '٠١٢٣٤٥٦٧٨٩';
    var cleaned = text
        .replaceAll(RegExp(r'[\u064B-\u065F\u0670\u0640]'), '')
        .replaceAllMapped(RegExp(r'[٠-٩]'), (match) {
      final digit = match.group(0)!;
      return '${arabicDigits.indexOf(digit)}';
    });

    cleaned = cleaned
        .replaceAll(RegExp(r'[أإآ]'), 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي');

    // Convert "الف" = 1000 when followed by ANY number word (hundreds, tens, teens, units, zero)
    // OR when immediately following 3 spoken letter tokens with no digits after it (e.g. "د ب ن الف").
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'(?<![ء-ي])(?:و\s*)?الف(?=\s+(?:و\s*)?(?:صفر|زيرو|م[يئ][هة]|متين|ميتين|مئتين|مائ|تلات|تلت|ثلاث|اربع|خمس|ست|سبع|تمان|تمن|ثمان|تسع|عشر|احد|حداشر|اتناشر|تلتاشر|اربعتاشر|خمستاشر|ستاشر|سبعتاشر|تمانتاشر|تسعتاشر|واحد|اتنين|اثن|عشرون|تلاتون|ثلاثون|اربعون|خمسون|ستون|سبعون|تمانون|ثمانون|تسعون))(?![ء-ي])'),
      (_) => ' 1000 ',
    );
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'(?<=^(?:\S+\s+){3})(?:و\s*)?الف(?![ء-ي])(?!\s*(?:[\u0621-\u064A]{1,2}\s+\d|\d))'),
      (_) => ' 1000 ',
    );

    // Replace Spoken Letter Names
    for (final entry in arLetterNames) {
      cleaned = cleaned.replaceAll(entry.key, ' ${entry.value} ');
    }

    // Replace Spoken Numbers & Compounds
    for (final entry in arNumRules) {
      cleaned = cleaned.replaceAll(entry.key, ' ${entry.value} ');
    }

    // Collapse compound place-value numbers ONLY (e.g. 2000 800 16 -> 2816, 1000 50 -> 1050)
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
  // Strictly 3-4 digit numbers (3 digits will finalize by padding a trailing '0')
  static bool _isPlateDigits(String t) => _isDigits(t) && t.length >= 3 && t.length <= 4;
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

  /// Collects up to [maxCollect] Arabic plate letters starting at [start],
  /// handling both separated letters ("ب ن ق") and glued tokens ("بن ق" / "ب نق").
  static ({List<String> letters, int nextIdx}) _collectLetters(
    List<String> tokens,
    int start, {
    int maxCollect = 4,
  }) {
    final chars = <String>[];
    int idx = start;
    while (idx < tokens.length) {
      if (_phraseLengthAt(tokens, idx) > 0) break;
      final t = tokens[idx];
      if (_isLetter(t)) {
        if (chars.length + 1 > maxCollect) break;
        chars.add(t);
        idx++;
      } else if (_isGluedLetters(t)) {
        if (chars.length + t.length > maxCollect) break;
        chars.addAll(t.split(''));
        idx++;
      } else {
        break;
      }
    }
    return (letters: chars, nextIdx: idx);
  }

  /// Pads a 3-digit pending plate with a trailing `'0'` (`123` -> `1230`) and marks it complete.
  static ParsedPlateData finalizeThreeDigitPlate(ParsedPlateData plate) {
    if (plate.digits.length == 4) {
      return plate.isComplete
          ? plate
          : ParsedPlateData(
              fullPlate: plate.fullPlate,
              letters: plate.letters,
              digits: plate.digits,
              detectedBrand: plate.detectedBrand,
              detectedNote: plate.detectedNote,
              isComplete: true,
            );
    }
    final paddedDigits = '${plate.digits}0';
    return ParsedPlateData(
      fullPlate: '${plate.letters} $paddedDigits',
      letters: plate.letters,
      digits: paddedDigits,
      detectedBrand: plate.detectedBrand,
      detectedNote: plate.detectedNote,
      isComplete: true,
    );
  }

  /// Returns true when [newPlate] is an incremental continuation of [prevPlate]
  /// (strictly same 3 letters with trailing digit extension, e.g. `ب ن ق 281` -> `ب ن ق 2816`).
  static bool isPlateUpgrade(String prevPlate, String newPlate) {
    final prevNorm = normalizePlateForMatch(prevPlate);
    final newNorm = normalizePlateForMatch(newPlate);
    if (prevNorm.isEmpty || newNorm.length <= prevNorm.length) return false;

    final prevLetters = prevNorm.replaceAll(RegExp(r'\d'), '');
    final newLetters = newNorm.replaceAll(RegExp(r'\d'), '');
    final prevDigits = prevNorm.replaceAll(RegExp(r'[^\d]'), '');
    final newDigits = newNorm.replaceAll(RegExp(r'[^\d]'), '');

    if (prevLetters.length != 3 || newLetters.length != 3) return false;
    if (prevLetters != newLetters) return false;
    return prevDigits.isNotEmpty &&
        newDigits.length > prevDigits.length &&
        newDigits.startsWith(prevDigits);
  }

  /// Extract Brand from a list of words
  static _BrandResult _extractBrandFromWords(List<String> words) {
    if (words.isEmpty) return _BrandResult('-', words);
    final str = words.join(' ');

    for (final b in carBrands) {
      final bNorm = _normWord(b);
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

  /// Extract Note from words, ignoring single letters and pure digit tokens.
  static String _extractNoteFromWords(List<String> words, {String? stickyNote}) {
    if (words.isEmpty) return stickyNote ?? '-';

    for (int i = 0; i < words.length; i++) {
      if (noteTriggers.contains(words[i])) {
        final explicit = words
            .sublist(i + 1)
            .where((w) => !fillerWords.contains(w) && !_isLetter(w) && !_isDigits(w))
            .join(' ')
            .trim();
        if (explicit.isNotEmpty) return explicit;
      }
    }

    final str = words.join(' ');
    for (final kw in noteKeywords) {
      final kwNorm = _normWord(kw);
      if ((' $str ').contains(' $kwNorm ')) {
        return kw;
      }
    }

    return stickyNote ?? '-';
  }

  static _SplitWords _splitWordsBetweenPlates(List<String> betweenWords) {
    if (betweenWords.isEmpty) {
      return const _SplitWords([], []);
    }

    int brandStart = -1;
    final str = betweenWords.join(' ');
    for (final b in carBrands) {
      final bNorm = _normWord(b);
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

    return _SplitWords(betweenWords, const []);
  }

  /// Strict 3-letter-only token matcher (rejects 2-letter and 4-letter groups).
  static List<_PlateMatch> _findPlateMatches(List<String> tokens) {
    final matches = <_PlateMatch>[];
    int i = 0;

    while (i < tokens.length) {
      final phraseLen = _phraseLengthAt(tokens, i);
      if (phraseLen > 0) {
        i += phraseLen;
        continue;
      }

      // Skip Arabic conjunction "و" when followed directly by a complete 3-letter plate
      if (tokens[i] == 'و') {
        final probeAfterWaw = _collectLetters(tokens, i + 1, maxCollect: 4);
        if (probeAfterWaw.letters.length == 3 &&
            probeAfterWaw.nextIdx < tokens.length &&
            _isPlateDigits(tokens[probeAfterWaw.nextIdx])) {
          i++;
          continue;
        }
      }

      // Pattern A/B: Letters (strictly 3) then Digits (3 or 4)
      final colA = _collectLetters(tokens, i, maxCollect: 4);
      if (colA.letters.length == 3 &&
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
      // Explicitly skip invalid 4-letter contiguous blocks so they cannot be sliced into 3
      if (colA.letters.length > 3) {
        i = colA.nextIdx;
        continue;
      }

      // Pattern C/D: Digits (3 or 4) then Letters (strictly 3)
      if (_isPlateDigits(tokens[i])) {
        // Bridge case: e.g. "3253 ب ن ق د ب ن 2816" (or with "و" between plates) -> split 3 + 3 cleanly
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

        if (bridgeChars.length >= 6 &&
            bIdx < tokens.length &&
            _isPlateDigits(tokens[bIdx])) {
          final cutIdx = bridgeTokenStops[2];
          // Check how many letters precede any bridging token stop cutIdx
          int actualTake = 3;
          while (actualTake < bridgeChars.length && bridgeTokenStops[actualTake] == cutIdx) {
            actualTake++;
          }
          final remaining = bridgeChars.length - actualTake;
          // Allow exact 3 + 3 OR 3 + 'و' + 3 (7 chars where 4th char is conjunction 'و')
          final validSplit = actualTake == 3 &&
              (remaining == 3 || (remaining == 4 && bridgeChars[3] == 'و'));
          if (validSplit) {
            final letters = bridgeChars.sublist(0, 3).join(' ');
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

        final colC = _collectLetters(tokens, i + 1, maxCollect: 4);
        if (colC.letters.length == 3) {
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
        if (colC.letters.length > 3) {
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

      if (match.digits.length == 4) {
        results.add(ParsedPlateData(
          fullPlate: match.fullPlate,
          letters: match.letters,
          digits: match.digits,
          detectedBrand: brandRes.brand,
          detectedNote: note,
          isComplete: true,
        ));
      } else if (hasTrailingContext) {
        // User already moved on past this 3-digit plate -> auto-pad trailing '0' at 0ms
        final paddedDigits = '${match.digits}0';
        results.add(ParsedPlateData(
          fullPlate: '${match.letters} $paddedDigits',
          letters: match.letters,
          digits: paddedDigits,
          detectedBrand: brandRes.brand,
          detectedNote: note,
          isComplete: true,
        ));
      } else {
        // At utterance tail with 3 digits: wait briefly (350ms / isFinal) then pad '0'
        results.add(ParsedPlateData(
          fullPlate: match.fullPlate,
          letters: match.letters,
          digits: match.digits,
          detectedBrand: brandRes.brand,
          detectedNote: note,
          isComplete: false,
        ));
      }
    }

    return results;
  }

  /// Extracts live 7-slot values at 0ms even while a plate is still being spoken
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

  static Map<String, String> extractSlots(String transcript) {
    return extractSlotsFromPlates(extractPlatesFromTranscript(transcript));
  }

  static OrphanVoiceData extractOrphanBrandAndNote(String normalized) {
    if (normalized.isEmpty) return const OrphanVoiceData();
    final tokens = normalized.split(' ').where((t) => t.isNotEmpty).toList();
    if (tokens.isEmpty) return const OrphanVoiceData();

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

  static String? orphanNoteFromNormalized(String normalized) =>
      extractOrphanBrandAndNote(normalized).note;

  static String? orphanNote(String transcript) =>
      orphanNoteFromNormalized(normalizeArabicSpoken(transcript));

  static String extractUnparsedTail(String normalized) {
    if (normalized.isEmpty) return '';
    final tokens = normalized.split(' ').where((t) => t.isNotEmpty).toList();
    if (tokens.isEmpty) return '';
    final matches = _findPlateMatches(tokens);
    if (matches.isEmpty) return normalized;
    final tail = tokens.sublist(matches.last.endIndex);
    return tail.join(' ').trim();
  }

  /// Returns ONLY the live upcoming speech not yet committed as a finished plate,
  /// clearing completed 4-digit plates (and finalized 3-digit plates) automatically.
  static String extractActiveTickerText(String normalized, {bool isFinal = false}) {
    if (normalized.isEmpty) return '';
    final tokens = normalized.split(' ').where((t) => t.isNotEmpty).toList();
    if (tokens.isEmpty) return '';
    final matches = _findPlateMatches(tokens);
    if (matches.isEmpty) return normalized;
    final last = matches.last;
    // Keep a trailing 3-digit plate visible briefly during live partial speech
    // until closed with trailing '0' on pause/final.
    if (!isFinal && last.digits.length < 4 && last.endIndex == tokens.length) {
      return tokens.sublist(last.startIndex).join(' ').trim();
    }
    return tokens.sublist(last.endIndex).join(' ').trim();
  }

  static bool hasValidNoteTriggerOrKeyword(String rawTranscript) {
    final norm = normalizeArabicSpoken(rawTranscript);
    if (norm.isEmpty) return false;
    final words = norm.split(' ').where((w) => w.isNotEmpty).toList();
    return _extractNoteFromWords(words) != '-';
  }

  /// Tail-focused candidate scoring: rewards the latest complete 3-letter plate
  /// and clean unparsed tail so long-session historical edits never corrupt new speech.
  static int _scoreCandidate(List<ParsedPlateData> plates, String unparsedTail) {
    if (plates.isEmpty) return 0;
    int score = plates.length * 40;
    final latest = plates.last;
    final lCount = latest.letters.replaceAll(' ', '').length;
    final dCount = latest.digits.length;
    if (latest.isComplete) score += 100;
    if (lCount == 3) score += 50;
    if (dCount == 4) {
      score += 30;
    } else if (dCount == 3) {
      score += 15;
    }
    if (latest.detectedBrand != '-') score += 5;
    if (latest.detectedNote != '-') score += 5;
    if (!RegExp(r'\d{2,}').hasMatch(unparsedTail)) {
      score += 15;
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
        primaryPlates.last.letters.replaceAll(' ', '').length == 3 &&
        primaryPlates.last.digits.length == 4 &&
        !RegExp(r'\d{2,}').hasMatch(primaryTail)) {
      return (rawTranscript: primaryRaw, normalized: primaryNorm, plates: primaryPlates);
    }

    var bestRaw = primaryRaw;
    var bestNorm = primaryNorm;
    var bestPlates = primaryPlates;
    var bestScore = _scoreCandidate(primaryPlates, primaryTail);

    for (final altRaw in candidates.skip(1).take(4)) {
      final altNorm = normalizeArabicSpoken(altRaw);
      final altPlates = extractPlatesFromNormalized(altNorm);
      final altTail = extractUnparsedTail(altNorm);
      final altScore = _scoreCandidate(altPlates, altTail);
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
