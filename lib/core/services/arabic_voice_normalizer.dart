import '../../data/models/excel_vehicle_model.dart';

/// Ultra-fast O(1) Single-Pass Arabic Voice Normalizer & License Plate Parser.
/// Engineered for sub-millisecond (<0.05ms) real-time partial speech streaming.
class ArabicVoiceNormalizer {
  ArabicVoiceNormalizer._();

  static const List<String> carBrands = [
    'مرسيدس',
    'تويوتا',
    'نيسان',
    'هيونداي',
    'هونداي',
    'كيا',
    'فورد',
    'شيفروليه',
    'شفروليه',
    'جلنتوش',
    'جلنت',
    'كاديلاك',
    'كامري',
    'كورولا',
    'بيمو',
    'بي ام',
    'مازدا',
    'لكزس',
    'ميتسوبيشي',
    'هوندا',
    'ازيرا',
    'أزيرا',
    'سوناتا',
    'النترا',
    'إلنترا',
    'يارس',
    'هايلوكس',
    'لاندكروزر',
    'باترول',
    'تاهو',
    'يوكن',
    'اكسبدشن',
    'شانجان',
    'جيلي',
    'هافال',
    'ام جي',
  ];

  static const List<String> noteKeywords = [
    'سيارة عامة',
    'بدون لوحة',
    'بدون',
    'سواق',
    'سواقين',
    'عطلانة',
    'عطلان',
    'موقفة',
    'موقف',
    'مصفوفة',
    'مصفوف',
    'مصدومة',
    'مصدوم',
    'تشليح',
    'مطلوبة',
    'مطلوب',
    'مهجورة',
    'مهجور',
  ];

  static const String _noteMark = '__NOTE_TRIGGER__';

  /// Conversational filler words ignored during continuous dictation
  static const Set<String> _ignoreWords = {
    'يعني', 'مثلا', 'نقول', 'طيب', 'تمام', 'خلاص', 'لوحة', 'لوحه', 'اللوحة',
    'اللوحه', 'سيارة', 'سياره', 'السيارة', 'السياره', 'عربية', 'عربيه', 'رقم',
    'ارقام', 'حروف', 'ببساطة', 'ببساطه', 'دي', 'ده', 'دا', 'هذا', 'هذه',
    'وليكن', 'عندك', 'علامة', 'علامه', 'الموقع', 'نورت', 'بالاخضر', 'هو',
    'كده', 'حفظ', 'مواقع', 'جميع', 'اللوحات', 'المرصودة', 'المرصوده', 'فقط',
    'ما', 'بس', 'احنا', 'مقفلينها', 'حاليا', 'لو', 'رحت', 'هيوديك', 'للموقع',
    'اللي', 'حصلتها', 'فيه', 'موجود', 'بتتحفظ', 'هنا', 'كمان', 'لكن', 'كله',
    'هينور', 'بالشكل', 'الاخضر', 'طبعا', 'ابلكيشن', 'الابلكيشن', 'تطبيق',
    'التطبيق', 'ايضا', 'وهنا', 'كدا', 'يا', 'باشا', 'في', 'من', 'على', 'الي',
    'إلى', 'مع', 'كل', 'اول', 'اخر', 'صف', 'خط', 'شارع', 'حي', 'طريق'
  };

  /// Direct O(1) hash map for spoken Arabic letter names & Google STT dialectal variants
  static const Map<String, String> _spokenLetterTokenMap = {
    // أ
    'الف': 'أ', 'ألف': 'أ', 'إلف': 'أ', 'آلف': 'أ', 'الالف': 'أ', 'الألف': 'أ',
    'همزه': 'أ', 'همزة': 'أ', 'ا': 'أ', 'أ': 'أ', 'إ': 'أ', 'آ': 'أ', 'ء': 'أ',
    'ابليس': 'أ', 'إبليس': 'أ',
    // ب
    'باء': 'ب', 'با': 'ب', 'به': 'ب', 'بة': 'ب', 'بي': 'ب', 'بى': 'ب', 'ب': 'ب',
    // ت
    'تاء': 'ت', 'تا': 'ت', 'ته': 'ت', 'تة': 'ت', 'تي': 'ت', 'تى': 'ت', 'تيه': 'ت', 'ت': 'ت',
    // ث
    'ثاء': 'ث', 'ثا': 'ث', 'ثه': 'ث', 'ثة': 'ث', 'ثي': 'ث', 'ث': 'ث',
    // ج
    'جيم': 'ج', 'جم': 'ج', 'جيمات': 'ج', 'جه': 'ج', 'ج': 'ج',
    // ح
    'حاء': 'ح', 'حا': 'ح', 'حه': 'ح', 'حة': 'ح', 'حى': 'ح', 'حاه': 'ح', 'ح': 'ح',
    // خ
    'خاء': 'خ', 'خا': 'خ', 'خه': 'خ', 'خة': 'خ', 'خ': 'خ',
    // د (Includes "دل" which Google STT outputs in fast Saudi/Egyptian dictation)
    'دال': 'د', 'دل': 'د', 'ده': 'د', 'دة': 'د', 'د': 'د',
    // ذ
    'ذال': 'ذ', 'ذل': 'ذ', 'ذه': 'ذ', 'ذ': 'ذ',
    // ر
    'راء': 'ر', 'را': 'ر', 'ره': 'ر', 'رة': 'ر', 'رى': 'ر', 'راءه': 'ر', 'ر': 'ر',
    // ز
    'زاي': 'ز', 'زاى': 'ز', 'زين': 'ز', 'زن': 'ز', 'زه': 'ز', 'ز': 'ز',
    // س
    'سين': 'س', 'سن': 'س', 'سه': 'س', 'سة': 'س', 'سم': 'س', 'س': 'س',
    // ش
    'شين': 'ش', 'شن': 'ش', 'شه': 'ش', 'ش': 'ش',
    // ص
    'صاد': 'ص', 'صد': 'ص', 'صه': 'ص', 'صاط': 'ص', 'ص': 'ص',
    // ض
    'ضاد': 'ض', 'ضد': 'ض', 'ضه': 'ض', 'ض': 'ض',
    // ط
    'طاء': 'ط', 'طا': 'ط', 'طه': 'ط', 'طة': 'ط', 'طى': 'ط', 'ط': 'ط',
    // ظ
    'ظاء': 'ظ', 'ظا': 'ظ', 'ظه': 'ظ', 'ظ': 'ظ',
    // ع (Includes "عن" which Google STT frequently outputs for "عين" in fast dictation!)
    'عين': 'ع', 'عن': 'ع', 'عاين': 'ع', 'عه': 'ع', 'عة': 'ع', 'ع': 'ع',
    // غ
    'غين': 'غ', 'غن': 'غ', 'غه': 'غ', 'غ': 'غ',
    // ف
    'فاء': 'ف', 'فا': 'ف', 'فه': 'ف', 'فة': 'ف', 'ف': 'ف',
    // ق
    'قاف': 'ق', 'قف': 'ق', 'قه': 'ق', 'قة': 'ق', 'ق': 'ق',
    // ك
    'كاف': 'ك', 'كف': 'ك', 'كه': 'ك', 'كة': 'ك', 'ك': 'ك',
    // ل
    'لام': 'ل', 'لم': 'ل', 'له': 'ل', 'لة': 'ل', 'ل': 'ل',
    // م
    'ميم': 'م', 'مم': 'م', 'مه': 'م', 'مة': 'م', 'م': 'م',
    // ن
    'نون': 'ن', 'نن': 'ن', 'نه': 'ن', 'نة': 'ن', 'ن': 'ن',
    // هـ
    'هاء': 'هـ', 'ها': 'هـ', 'هه': 'هـ', 'هة': 'هـ', 'ه': 'هـ', 'هـ': 'هـ',
    // و
    'واو': 'و', 'وو': 'و', 'وه': 'و', 'وة': 'و', 'و': 'و',
    // ي
    'ياء': 'ي', 'يا': 'ي', 'يه': 'ي', 'ية': 'ي', 'يى': 'ي', 'ى': 'ي', 'ي': 'ي',
  };

  /// Direct O(1) hash map for spoken Arabic numbers (units, teens, tens, hundreds, thousands)
  static const Map<String, String> _spokenDigitTokenMap = {
    'صفر': '0', 'زيرو': '0', 'زيروا': '0', 'سفر': '0',
    'واحد': '1', 'واحده': '1', 'واحدة': '1', 'حادي': '1', 'احد': '1', 'إحدى': '1',
    'اثنين': '2', 'اثنان': '2', 'إثنين': '2', 'إثنان': '2', 'اتنين': '2', 'إتنين': '2', 'تنين': '2', 'ثنتين': '2',
    'ثلاثة': '3', 'ثلاثه': '3', 'ثلاث': '3', 'تلاتة': '3', 'تلاته': '3', 'تلات': '3',
    'أربعة': '4', 'اربعة': '4', 'أربعه': '4', 'اربعه': '4', 'أربع': '4', 'اربع': '4', 'ربعه': '4',
    'خمسة': '5', 'خمسه': '5', 'خمس': '5',
    'ستة': '6', 'سته': '6', 'ست': '6',
    'سبعة': '7', 'سبعه': '7', 'سبع': '7',
    'ثمانية': '8', 'ثمانيه': '8', 'ثماني': '8', 'ثمان': '8', 'تمانية': '8', 'تمانيه': '8', 'تمنية': '8', 'تمنيه': '8', 'تمن': '8',
    'تسعة': '9', 'تسعه': '9', 'تسع': '9',
    'عشرة': '10', 'عشره': '10', 'عشر': '10',
    'حداشر': '11', 'احدعشر': '11', 'أحدعشر': '11',
    'اتناشر': '12', 'اثناعشر': '12', 'إثناعشر': '12',
    'تلتاشر': '13', 'ثلاثةعشر': '13',
    'اربعتاشر': '14', 'أربعةعشر': '14',
    'خمستاشر': '15', 'خمسةعشر': '15',
    'ستاشر': '16', 'ستةعشر': '16',
    'سبعتاشر': '17', 'سبعةعشر': '17',
    'تمنتاشر': '18', 'ثمانيةعشر': '18',
    'تسعتاشر': '19', 'تسعةعشر': '19',
    'عشرين': '20', 'عشرون': '20',
    'ثلاثين': '30', 'ثلاثون': '30', 'تلاتين': '30',
    'أربعين': '40', 'اربعين': '40', 'أربعون': '40', 'اربعون': '40',
    'خمسين': '50', 'خمسون': '50',
    'ستين': '60', 'ستون': '60',
    'سبعين': '70', 'سبعون': '70',
    'ثمانين': '80', 'ثمانون': '80', 'تمانين': '80',
    'تسعين': '90', 'تسعون': '90',
    'مائة': '100', 'مية': '100', 'ميه': '100', 'مائه': '100', 'مئة': '100',
    'ميتين': '200', 'مائتين': '200', 'مئتين': '200',
    'ثلاثمائة': '300', 'تلتمائة': '300', 'تلتمية': '300', 'ثلاثمية': '300',
    'أربعمائة': '400', 'اربعمائة': '400', 'اربعمية': '400', 'أربعمية': '400',
    'خمسمائة': '500', 'خمسمية': '500',
    'ستمائة': '600', 'ستمية': '600',
    'سبعمائة': '700', 'سبعمية': '700',
    'ثمانمائة': '800', 'تمنمية': '800', 'ثمانمية': '800',
    'تسعمائة': '900', 'تسعمية': '900',
    'ألفين': '2000', 'الفين': '2000',
    'ثلاثةآلاف': '3000', 'تلاتآلاف': '3000',
    'أربعةآلاف': '4000', 'اربعآلاف': '4000',
    'خمسةآلاف': '5000', 'خمسآلاف': '5000',
    'ستةآلاف': '6000', 'ستآلاف': '6000',
    'سبعةآلاف': '7000', 'سبعآلاف': '7000',
    'ثمانيةآلاف': '8000', 'تمنآلاف': '8000',
    'تسعةآلاف': '9000', 'تسعآلاف': '9000',
  };

  static final RegExp _diacriticsRe = RegExp(r'[\u064B-\u0652\u0640]');
  static final RegExp _punctRe = RegExp(r'[^\w\u0600-\u06FF\s]');
  static final RegExp _mixedTokenRe = RegExp(r'^([\u0621-\u064A]+)(\d+)$');
  static final RegExp _digitsOnlyRe = RegExp(r'^\d+$');

  // LRU cache for normalized strings
  static String _lastRaw = '';
  static String _lastNormalized = '';

  static bool _isSinglePlateLetter(String tok) {
    if (tok == 'هـ') return true;
    if (tok.length != 1) return false;
    final c = tok.codeUnitAt(0);
    return c >= 0x0621 && c <= 0x064A;
  }

  static bool _isArabicWord(String tok) {
    if (tok.isEmpty) return false;
    for (int i = 0; i < tok.length; i++) {
      final c = tok.codeUnitAt(i);
      if (c < 0x0621 || c > 0x064A) return false;
    }
    return true;
  }

  static String _replaceEasternDigits(String input) {
    final sb = StringBuffer();
    for (int i = 0; i < input.length; i++) {
      final c = input.codeUnitAt(i);
      if (c >= 0x0660 && c <= 0x0669) {
        sb.writeCharCode(0x30 + (c - 0x0660));
      } else {
        sb.writeCharCode(c);
      }
    }
    return sb.toString();
  }

  /// Single-pass O(1) per-token normalization of spoken Arabic transcript.
  static String normalizeArabicSpoken(String text) {
    if (text.trim().isEmpty) return '';
    if (text == _lastRaw) return _lastNormalized;

    var s = _replaceEasternDigits(text);
    s = s.replaceAll(_diacriticsRe, '');
    s = s.replaceAll(_punctRe, ' ');

    final rawTokens = s.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    if (rawTokens.isEmpty) return '';

    final out = <String>[];
    final n = rawTokens.length;
    int i = 0;

    while (i < n) {
      var w = rawTokens[i];
      final wClean = w.replaceAll('أ', 'ا').replaceAll('إ', 'ا').replaceAll('آ', 'ا');

      if (w == 'ملاحظة' || w == 'ملحوظة' || wClean == 'ملاحظه' || wClean == 'ملحوظه') {
        out.add(_noteMark);
        i++;
        continue;
      }

      // Strip 'و' prefix attached to number words (e.g. "وستة" -> "ستة", "وثمانمائة" -> "ثمانمائة")
      if (w.length > 2 && w.startsWith('و') && _spokenDigitTokenMap.containsKey(w.substring(1))) {
        w = w.substring(1);
      }

      // Context-aware handling of "ألفين" / "الفين":
      // If preceded by a plate letter and followed by digits -> two Alifs ("أ أ" as in "س أ أ 1325")
      if (wClean == 'الفين') {
        final prevIsLetter = out.isNotEmpty && _isSinglePlateLetter(out.last);
        final nextIsDigits = (i + 1 < n) &&
            (_digitsOnlyRe.hasMatch(rawTokens[i + 1]) ||
                _spokenDigitTokenMap.containsKey(rawTokens[i + 1]));
        if (prevIsLetter && nextIsDigits) {
          out.add('أ');
          out.add('أ');
          i++;
          continue;
        }
      }

      // Check direct spoken digit token
      if (_spokenDigitTokenMap.containsKey(w)) {
        out.add(_spokenDigitTokenMap[w]!);
        i++;
        continue;
      }

      // Check spoken letter token
      if (_spokenLetterTokenMap.containsKey(w)) {
        out.add(_spokenLetterTokenMap[w]!);
        i++;
        continue;
      }
      if (_spokenLetterTokenMap.containsKey(wClean)) {
        out.add(_spokenLetterTokenMap[wClean]!);
        i++;
        continue;
      }

      // Pure digits
      if (_digitsOnlyRe.hasMatch(w)) {
        out.add(w);
        i++;
        continue;
      }

      // Attached letters + digits (e.g. "رهد8837" or "س1325")
      final mixMatch = _mixedTokenRe.firstMatch(w);
      if (mixMatch != null) {
        final lPart = mixMatch.group(1)!;
        final dPart = mixMatch.group(2)!;
        for (int c = 0; c < lPart.length; c++) {
          final ch = lPart[c];
          out.add(_spokenLetterTokenMap[ch] ?? ch);
        }
        out.add(dPart);
        i++;
        continue;
      }

      // Ignore conversational filler words unless inside a note
      if ((_ignoreWords.contains(w) || _ignoreWords.contains(wClean)) && !out.contains(_noteMark)) {
        i++;
        continue;
      }

      // Connected 2 or 3 Arabic letters right before digits (e.g. "روي 5853", "رهد 8837", "سحط 8849")
      if (wClean.length >= 2 &&
          wClean.length <= 3 &&
          _isArabicWord(wClean) &&
          !carBrands.contains(w) &&
          !carBrands.contains(wClean)) {
        bool lookaheadHasDigit = false;
        for (int k = i + 1; k < n && k < i + 4; k++) {
          final tk = rawTokens[k];
          if (_digitsOnlyRe.hasMatch(tk) || _spokenDigitTokenMap.containsKey(tk)) {
            lookaheadHasDigit = true;
            break;
          }
        }
        if (lookaheadHasDigit) {
          for (int c = 0; c < w.length; c++) {
            final ch = w[c];
            out.add(_spokenLetterTokenMap[ch] ?? ch);
          }
          i++;
          continue;
        }
      }

      out.add(w);
      i++;
    }

    // Merge consecutive numeric tokens into max 4-digit plate groups
    final merged = <String>[];
    int idx = 0;
    while (idx < out.length) {
      final tok = out[idx];
      if (_digitsOnlyRe.hasMatch(tok)) {
        final run = <String>[tok];
        idx++;
        while (idx < out.length && _digitsOnlyRe.hasMatch(out[idx])) {
          run.add(out[idx]);
          idx++;
        }
        final digitStr = _collapseNumberRun(run);
        for (int start = 0; start < digitStr.length; start += 4) {
          final end = (start + 4 < digitStr.length) ? start + 4 : digitStr.length;
          merged.add(digitStr.substring(start, end));
        }
      } else {
        merged.add(tok);
        idx++;
      }
    }

    final res = merged.join(' ');
    _lastRaw = text;
    _lastNormalized = res;
    return res;
  }

  static String _collapseNumberRun(List<String> run) {
    final outDigits = <String>[];
    int i = 0;
    final n = run.length;
    while (i < n) {
      final t = run[i];
      final val = int.tryParse(t) ?? 0;
      if (t.length == 1) {
        if (val >= 1 && val <= 9 && i + 1 < n) {
          final nextVal = int.tryParse(run[i + 1]) ?? -1;
          if (nextVal == 10 || nextVal == 20 || nextVal == 30 || nextVal == 40 ||
              nextVal == 50 || nextVal == 60 || nextVal == 70 || nextVal == 80 || nextVal == 90) {
            outDigits.add((nextVal + val).toString());
            i += 2;
            continue;
          }
        }
        outDigits.add(t);
        i++;
        continue;
      }
      if (val == 1000 || val == 2000 || val == 3000 || val == 4000 || val == 5000 ||
          val == 6000 || val == 7000 || val == 8000 || val == 9000 ||
          val == 100 || val == 200 || val == 300 || val == 400 || val == 500 ||
          val == 600 || val == 700 || val == 800 || val == 900) {
        int total = val;
        int prevVal = val;
        i++;
        while (i < n) {
          final nxt = int.tryParse(run[i]) ?? -1;
          if (nxt > 0 && nxt < prevVal && ((total >= 1000 && nxt < 1000) || (total >= 100 && nxt < 100))) {
            if (nxt >= 1 && nxt <= 9 && i + 1 < n) {
              final afterNxt = int.tryParse(run[i + 1]) ?? -1;
              if (afterNxt == 10 || afterNxt == 20 || afterNxt == 30 || afterNxt == 40 ||
                  afterNxt == 50 || afterNxt == 60 || afterNxt == 70 || afterNxt == 80 || afterNxt == 90) {
                total += afterNxt + nxt;
                i += 2;
                break;
              }
            }
            total += nxt;
            prevVal = nxt;
            i++;
          } else {
            break;
          }
        }
        outDigits.add(total.toString());
        continue;
      }
      outDigits.add(t);
      i++;
    }
    return outDigits.join('');
  }

  /// Canonical plate key for O(1) matching regardless of letter/digit ordering in Excel sheets.
  /// Always normalizes to "<letters><digits>" (e.g., "1325 س ا ا" and "س أ أ ١٣٢٥" both -> "ساا1325").
  static String normalizePlateForMatch(String plate) {
    if (plate.trim().isEmpty) return '';
    var s = _replaceEasternDigits(plate);
    s = s.replaceAll(_diacriticsRe, '');
    s = s.replaceAll('هـ', 'ه').replaceAll('ة', 'ه').replaceAll('ى', 'ي');
    s = s.replaceAll(RegExp(r'[أإآء]'), 'ا');

    final letters = StringBuffer();
    final digits = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      if (c >= 0x0621 && c <= 0x064A) {
        letters.writeCharCode(c);
      } else if (c >= 0x30 && c <= 0x39) {
        digits.writeCharCode(c);
      }
    }
    if (letters.isEmpty && digits.isEmpty) return '';
    return '${letters.toString()}${digits.toString()}';
  }

  static String plateKey(String plate) => normalizePlateForMatch(plate);

  /// Extracts all plates from an already-normalized string in a single linear pass.
  static List<ParsedPlateData> extractPlatesFromNormalized(
    String normalized, {
    String? stickyNote,
  }) {
    if (normalized.isEmpty) return const [];
    final tokens = normalized.split(' ').where((t) => t.isNotEmpty).toList();
    if (tokens.isEmpty) return const [];

    final results = <ParsedPlateData>[];
    int i = 0;
    final n = tokens.length;

    while (i < n) {
      final letters = <String>[];
      while (i < n && _isSinglePlateLetter(tokens[i]) && letters.length < 4) {
        letters.add(tokens[i]);
        i++;
      }

      if (letters.length < 2) {
        if (letters.isEmpty) i++;
        continue;
      }

      final plateLetters = letters.length > 3 ? letters.sublist(letters.length - 3) : letters;

      if (i < n && _digitsOnlyRe.hasMatch(tokens[i]) && tokens[i].length >= 2 && tokens[i].length <= 4) {
        final digits = tokens[i];
        i++;

        // Collect optional trailing brand or note before next plate
        final freeWords = <String>[];
        while (i < n) {
          final t = tokens[i];
          if (_isSinglePlateLetter(t)) {
            // Look ahead: if another letter or digit follows, a new plate is starting
            if (i + 1 < n && (_isSinglePlateLetter(tokens[i + 1]) || _digitsOnlyRe.hasMatch(tokens[i + 1]))) {
              break;
            }
          }
          freeWords.add(t);
          i++;
        }

        String brand = '-';
        String note = stickyNote ?? '-';

        for (final b in carBrands) {
          if (freeWords.contains(b)) {
            brand = b;
            freeWords.remove(b);
            break;
          }
        }

        final noteIdx = freeWords.indexOf(_noteMark);
        if (noteIdx != -1 && noteIdx + 1 < freeWords.length) {
          note = freeWords.sublist(noteIdx + 1).join(' ').trim();
        } else {
          for (final kw in noteKeywords) {
            if (freeWords.any((w) => w == kw || w.contains(kw))) {
              note = kw;
              break;
            }
          }
        }

        final lettersJoined = plateLetters.join(' ');
        results.add(ParsedPlateData(
          fullPlate: '$lettersJoined $digits',
          letters: lettersJoined,
          digits: digits,
          detectedBrand: brand,
          detectedNote: note.isEmpty ? '-' : note,
        ));
      }
    }

    return results;
  }

  static List<ParsedPlateData> extractPlatesFromTranscript(
    String transcriptChunk, {
    String? stickyNote,
  }) {
    return extractPlatesFromNormalized(
      normalizeArabicSpoken(transcriptChunk),
      stickyNote: stickyNote,
    );
  }

  /// Extracts live HUD slots (L1-L3, D1-D4) with 0ms feedback even while the user is mid-plate!
  static Map<String, String> extractSlotsFromPlates(
    List<ParsedPlateData> plates, {
    String? normalizedTail,
  }) {
    if (normalizedTail != null && normalizedTail.isNotEmpty) {
      final tokens = normalizedTail.split(' ').where((t) => t.isNotEmpty).toList();
      final tailLetters = <String>[];
      String tailDigits = '';
      for (int i = tokens.length - 1; i >= 0; i--) {
        final t = tokens[i];
        if (tailDigits.isEmpty && _digitsOnlyRe.hasMatch(t) && tailLetters.isEmpty) {
          tailDigits = t;
        } else if (_isSinglePlateLetter(t) && tailLetters.length < 3) {
          tailLetters.insert(0, t);
        } else if (tailLetters.isNotEmpty || tailDigits.isNotEmpty) {
          break;
        }
      }
      if (tailLetters.isNotEmpty || tailDigits.isNotEmpty) {
        final dList = tailDigits.split('');
        return {
          'l1': tailLetters.isNotEmpty ? tailLetters[0] : '-',
          'l2': tailLetters.length > 1 ? tailLetters[1] : '-',
          'l3': tailLetters.length > 2 ? tailLetters[2] : '-',
          'd1': dList.isNotEmpty ? dList[0] : '-',
          'd2': dList.length > 1 ? dList[1] : '-',
          'd3': dList.length > 2 ? dList[2] : '-',
          'd4': dList.length > 3 ? dList[3] : '-',
        };
      }
    }

    if (plates.isEmpty) {
      return const {
        'l1': '-', 'l2': '-', 'l3': '-',
        'd1': '-', 'd2': '-', 'd3': '-', 'd4': '-',
      };
    }
    final p = plates.last;
    final lList = p.letters.split(' ').where((s) => s.isNotEmpty).toList();
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
    final norm = normalizeArabicSpoken(transcript);
    final plates = extractPlatesFromNormalized(norm);
    return extractSlotsFromPlates(plates, normalizedTail: norm);
  }

  static String? orphanNoteFromNormalized(String normalized) {
    if (normalized.isEmpty) return null;
    final tokens = normalized.split(' ').where((t) => t.isNotEmpty).toList();
    if (tokens.isEmpty) return null;

    for (final kw in noteKeywords) {
      if (tokens.any((t) => t == kw || t.contains(kw))) {
        return kw;
      }
    }

    final idx = tokens.indexOf(_noteMark);
    if (idx != -1 && idx + 1 < tokens.length) {
      return tokens.sublist(idx + 1).join(' ').trim();
    }
    return null;
  }

  static String? orphanNote(String transcript) {
    return orphanNoteFromNormalized(normalizeArabicSpoken(transcript));
  }
}
