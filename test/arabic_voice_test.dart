import 'package:car_logix/core/services/arabic_voice_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ArabicVoiceNormalizer Tests', () {
    test('Plate with Brand First: كامري د ب ن 2816', () {
      final res = ArabicVoiceNormalizer.extractPlatesFromTranscript('كامري د ب ن 2816');
      expect(res.length, equals(1));
      expect(res.first.fullPlate, equals('د ب ن 2816'));
      expect(res.first.detectedBrand, equals('كامري'));
      expect(res.first.detectedNote, equals('-'));
    });

    test('Note + Brand + Plate: مركونة كامري د ب ن 2816', () {
      final res = ArabicVoiceNormalizer.extractPlatesFromTranscript('مركونة كامري د ب ن 2816');
      expect(res.length, equals(1));
      expect(res.first.fullPlate, equals('د ب ن 2816'));
      expect(res.first.detectedBrand, equals('كامري'));
      expect(res.first.detectedNote, equals('مركونة'));
    });

    test('Digits First with Brand: كامري 2816 د ب ن', () {
      final res = ArabicVoiceNormalizer.extractPlatesFromTranscript('كامري 2816 د ب ن');
      expect(res.length, equals(1));
      expect(res.first.fullPlate, equals('د ب ن 2816'));
      expect(res.first.detectedBrand, equals('كامري'));
      expect(res.first.detectedNote, equals('-'));
    });

    test('Digits First without Brand: 2816 د ب ن', () {
      final res = ArabicVoiceNormalizer.extractPlatesFromTranscript('2816 د ب ن');
      expect(res.length, equals(1));
      expect(res.first.fullPlate, equals('د ب ن 2816'));
      expect(res.first.detectedBrand, equals('-'));
      expect(res.first.detectedNote, equals('-'));
    });

    test('Plate + Brand + Note: د ب ن 2816 كامري مركونة', () {
      final res = ArabicVoiceNormalizer.extractPlatesFromTranscript('د ب ن 2816 كامري مركونة');
      expect(res.length, equals(1));
      expect(res.first.fullPlate, equals('د ب ن 2816'));
      expect(res.first.detectedBrand, equals('كامري'));
      expect(res.first.detectedNote, equals('مركونة'));
    });

    test('Multi-word Brand: لاند كروزر د ب ق 9999', () {
      final res = ArabicVoiceNormalizer.extractPlatesFromTranscript('لاند كروزر د ب ق 9999');
      expect(res.length, equals(1));
      expect(res.first.fullPlate, equals('د ب ق 9999'));
      expect(res.first.detectedBrand, equals('لاند كروزر'));
      expect(res.first.detectedNote, equals('-'));
    });

    test('Multi-word Note: نوعها تويوتا كامري د ب ن 2816 واقفة صف ثاني', () {
      final res = ArabicVoiceNormalizer.extractPlatesFromTranscript('نوعها تويوتا كامري د ب ن 2816 واقفة صف ثاني');
      expect(res.length, equals(1));
      expect(res.first.fullPlate, equals('د ب ن 2816'));
      expect(res.first.detectedBrand, equals('تويوتا كامري'));
      expect(res.first.detectedNote, equals('واقفة صف ثاني'));
    });

    test('Explicit Trigger Note: د ب ن 2816 ملحوظة الباب مفتوح والكاوتش نايم', () {
      final res = ArabicVoiceNormalizer.extractPlatesFromTranscript('د ب ن 2816 ملحوظة الباب مفتوح والكاوتش نايم');
      expect(res.length, equals(1));
      expect(res.first.fullPlate, equals('د ب ن 2816'));
      expect(res.first.detectedNote, equals('الباب مفتوح والكاوتش نايم'));
    });

    test('Continuous Multi-Plate Dictation', () {
      final res = ArabicVoiceNormalizer.extractPlatesFromTranscript('كامري د ب ن 2816 مركونة النترا س ص ع 5555 ماشية');
      expect(res.length, equals(2));
      expect(res[0].fullPlate, equals('د ب ن 2816'));
      expect(res[0].detectedBrand, equals('كامري'));
      expect(res[0].detectedNote, equals('مركونة'));

      expect(res[1].fullPlate, equals('س ص ع 5555'));
      expect(res[1].detectedBrand, equals('النترا'));
      expect(res[1].detectedNote, equals('ماشية'));
    });

    test('Orphan Brand and Note', () {
      final o1 = ArabicVoiceNormalizer.extractOrphanBrandAndNote(
        ArabicVoiceNormalizer.normalizeArabicSpoken('كامري'),
      );
      expect(o1.brand, equals('كامري'));
      expect(o1.note, isNull);

      final o2 = ArabicVoiceNormalizer.extractOrphanBrandAndNote(
        ArabicVoiceNormalizer.normalizeArabicSpoken('مركونة'),
      );
      expect(o2.brand, isNull);
      expect(o2.note, equals('مركونة'));

      final o3 = ArabicVoiceNormalizer.extractOrphanBrandAndNote(
        ArabicVoiceNormalizer.normalizeArabicSpoken('نوعها سوناتا واقفة صف تاني'),
      );
      expect(o3.brand, equals('سوناتا'));
      expect(o3.note, equals('واقفة صف تاني'));
    });

    test('Plate with Trailing Letter Noise: د ب ن 2816 س', () {
      final res = ArabicVoiceNormalizer.extractPlatesFromTranscript('د ب ن 2816 س');
      expect(res.length, equals(1));
      expect(res.first.fullPlate, equals('د ب ن 2816'));
      expect(res.first.detectedBrand, equals('-'));
      expect(res.first.detectedNote, equals('-'));
    });

    test('Speech of pure letters never creates orphan note', () {
      final o = ArabicVoiceNormalizer.extractOrphanBrandAndNote(
        ArabicVoiceNormalizer.normalizeArabicSpoken('د ب ن'),
      );
      expect(o.brand, isNull);
      expect(o.note, isNull);
    });

    test('Strictly 3 letters ONLY: rejects 2-letter and 4-letter plates while visualizing live slots', () {
      // 2 letters alone must NOT commit a plate
      expect(ArabicVoiceNormalizer.extractPlatesFromTranscript('3253 ب ن'), isEmpty);
      expect(ArabicVoiceNormalizer.extractPlatesFromTranscript('د ب 2816'), isEmpty);

      // 4 letters must NOT commit or slice into 3 letters
      expect(ArabicVoiceNormalizer.extractPlatesFromTranscript('د ب ن ق 2816'), isEmpty);
      expect(ArabicVoiceNormalizer.extractPlatesFromTranscript('2816 د ب ن ق'), isEmpty);

      // Exactly 3 letters commits immediately
      final complete = ArabicVoiceNormalizer.extractPlatesFromTranscript('3253 ب ن ق');
      expect(complete.length, equals(1));
      expect(complete.first.fullPlate, equals('ب ن ق 3253'));
      expect(complete.first.isComplete, isTrue);

      // Live character-by-character slot visualization BEFORE 3rd letter finishes
      final liveLetters = ArabicVoiceNormalizer.extractLiveSlots(
        ArabicVoiceNormalizer.normalizeArabicSpoken('د ب'),
        const [],
      );
      expect(liveLetters['l1'], equals('د'));
      expect(liveLetters['l2'], equals('ب'));
      expect(liveLetters['l3'], equals('-'));
    });

    test('3 letters + 3 digits appends trailing 0 (123 -> 1230) and closes cleanly', () {
      final pending = ArabicVoiceNormalizer.extractPlatesFromTranscript('د ب ن 123');
      expect(pending.length, equals(1));
      expect(pending.first.digits, equals('123'));
      expect(pending.first.isComplete, isFalse);

      final closed = ArabicVoiceNormalizer.finalizeThreeDigitPlate(pending.first);
      expect(closed.fullPlate, equals('د ب ن 1230'));
      expect(closed.digits, equals('1230'));
      expect(closed.isComplete, isTrue);

      // When immediately followed by another plate, 3-digit Plate 1 pads '0' at 0ms
      final two = ArabicVoiceNormalizer.extractPlatesFromTranscript('د ب ن 123 س ص ع 4567');
      expect(two.length, equals(2));
      expect(two[0].fullPlate, equals('د ب ن 1230'));
      expect(two[0].isComplete, isTrue);
      expect(two[1].fullPlate, equals('س ص ع 4567'));
      expect(two[1].isComplete, isTrue);
    });

    test('Colloquial words (لا، ده، يا، ما) never synthesize fake letters, and Alf=1000 works', () {
      expect(ArabicVoiceNormalizer.extractPlatesFromTranscript('لا ده 2816'), isEmpty);
      expect(ArabicVoiceNormalizer.extractPlatesFromTranscript('يا ما 2816'), isEmpty);

      final alfSolo = ArabicVoiceNormalizer.extractPlatesFromTranscript('د ب ن الف');
      expect(alfSolo.length, equals(1));
      expect(alfSolo.first.fullPlate, equals('د ب ن 1000'));

      final alfTens = ArabicVoiceNormalizer.extractPlatesFromTranscript('د ب ن الف وخمسين');
      expect(alfTens.length, equals(1));
      expect(alfTens.first.fullPlate, equals('د ب ن 1050'));
    });

    test('Arabic conjunction و between plates is skipped while letter و inside a plate is kept', () {
      final conj = ArabicVoiceNormalizer.extractPlatesFromTranscript('د ب ن 1234 و س ص ع 5678');
      expect(conj.length, equals(2));
      expect(conj[0].fullPlate, equals('د ب ن 1234'));
      expect(conj[1].fullPlate, equals('س ص ع 5678'));

      final wawLetter = ArabicVoiceNormalizer.extractPlatesFromTranscript('واو ب ن 2816');
      expect(wawLetter.length, equals(1));
      expect(wawLetter.first.fullPlate, equals('و ب ن 2816'));
    });

    test('Brands list includes جيب and explicit trigger drops pure digit notes', () {
      final jeep = ArabicVoiceNormalizer.extractPlatesFromTranscript('جيب د ب ن 2816');
      expect(jeep.length, equals(1));
      expect(jeep.first.detectedBrand, equals('جيب'));

      final noDigitNote = ArabicVoiceNormalizer.extractPlatesFromTranscript('د ب ن 2816 سجل 9999');
      expect(noDigitNote.length, equals(1));
      expect(noDigitNote.first.detectedNote, equals('-'));
    });

    test('Mixed glued and single letter combinations capture 3 letters cleanly', () {
      expect(ArabicVoiceNormalizer.extractPlatesFromTranscript('3253 بن ق').first.fullPlate, equals('ب ن ق 3253'));
      expect(ArabicVoiceNormalizer.extractPlatesFromTranscript('3253 ب نق').first.fullPlate, equals('ب ن ق 3253'));
      expect(ArabicVoiceNormalizer.extractPlatesFromTranscript('بن ق 3253').first.fullPlate, equals('ب ن ق 3253'));
      expect(ArabicVoiceNormalizer.extractPlatesFromTranscript('ب نق 3253').first.fullPlate, equals('ب ن ق 3253'));
    });

    test('Multi-word brand before digits-first plate is not treated as letters', () {
      final res = ArabicVoiceNormalizer.extractPlatesFromTranscript('بي ام 2816 د ب ن');
      expect(res.length, equals(1));
      expect(res.first.fullPlate, equals('د ب ن 2816'));
      expect(res.first.detectedBrand, equals('بي ام'));
    });

    test('Arabic diacritics on spoken letters are stripped properly', () {
      final res = ArabicVoiceNormalizer.extractPlatesFromTranscript('٣٢٥٣ بَ نْ قٌ');
      expect(res.length, equals(1));
      expect(res.first.fullPlate, equals('ب ن ق 3253'));
    });

    test('isPlateUpgrade detects trailing digit extensions only within same 3 letters', () {
      expect(ArabicVoiceNormalizer.isPlateUpgrade('د ب ق 285', 'د ب ق 2852'), isTrue);
      expect(ArabicVoiceNormalizer.isPlateUpgrade('د ب ق 285', 'د ب ق 9999'), isFalse);
      expect(ArabicVoiceNormalizer.isPlateUpgrade('ب ن ق 3253', 'د س ص 3253'), isFalse);
    });

    test('Egyptian compound thousands & hundreds parse cleanly', () {
      final r1 = ArabicVoiceNormalizer.extractPlatesFromTranscript('الف متين تلاته وخمسين ب ن ق');
      expect(r1.first.fullPlate, equals('ب ن ق 1253'));

      final r2 = ArabicVoiceNormalizer.extractPlatesFromTranscript('تلات تلاف متين تلاته وخمسين ب ن ق');
      expect(r2.first.fullPlate, equals('ب ن ق 3253'));

      final r3 = ArabicVoiceNormalizer.extractPlatesFromTranscript('اربع تلاف وخمسميه د ب ن');
      expect(r3.first.fullPlate, equals('د ب ن 4500'));
    });

    test('Mixed-order consecutive fast speech splits 3+3 cleanly', () {
      final r1 = ArabicVoiceNormalizer.extractPlatesFromTranscript('3253 ب ن ق د ب ن 2816');
      expect(r1.length, equals(2));
      expect(r1[0].fullPlate, equals('ب ن ق 3253'));
      expect(r1[1].fullPlate, equals('د ب ن 2816'));
    });

    test('N-best selectBestCandidate recovers valid 3-letter plate over 2-letter/noise hypothesis', () {
      final best = ArabicVoiceNormalizer.selectBestCandidate(['3253 ب ن', '3253 ب ن ق']);
      expect(best.plates.length, equals(1));
      expect(best.plates.first.fullPlate, equals('ب ن ق 3253'));

      final bestNoise = ArabicVoiceNormalizer.selectBestCandidate(['كلام غير واضح', 'د ب ن 2816']);
      expect(bestNoise.plates.length, equals(1));
      expect(bestNoise.plates.first.fullPlate, equals('د ب ن 2816'));
    });

    test('Canonical plateKey matches Excel formats regardless of order or punctuation', () {
      expect(
        ArabicVoiceNormalizer.plateKey('2816 د ب ن'),
        equals(ArabicVoiceNormalizer.plateKey('د ب ن - 2816')),
      );
      expect(ArabicVoiceNormalizer.plateKey('د.ب.ن/2816'), equals('دبن2816'));
    });

    test('extractUnparsedTail and hasValidNoteTriggerOrKeyword work cleanly', () {
      final normStr = ArabicVoiceNormalizer.normalizeArabicSpoken('د ب ن 2816 تلاته اتنين 53');
      expect(ArabicVoiceNormalizer.extractUnparsedTail(normStr), equals('3253'));
      expect(ArabicVoiceNormalizer.hasValidNoteTriggerOrKeyword('د ب ن 2816 س'), isFalse);
      expect(ArabicVoiceNormalizer.hasValidNoteTriggerOrKeyword('د ب ن 2816 مركونة'), isTrue);
    });

    test('Back-to-back plates with adjacent digits do not merge across plate boundaries', () {
      final res = ArabicVoiceNormalizer.extractPlatesFromTranscript('د ب ن 2816 تلاته اتنين خمسه تلاته ب ن ق');
      expect(res.length, equals(2));
      expect(res[0].fullPlate, equals('د ب ن 2816'));
      expect(res[1].fullPlate, equals('ب ن ق 3253'));
    });

    test('extractActiveTickerText clears completed 4-digit and final 3-digit plates', () {
      expect(
        ArabicVoiceNormalizer.extractActiveTickerText(
          ArabicVoiceNormalizer.normalizeArabicSpoken('د ب ن 2816'),
        ),
        equals(''),
      );
      expect(
        ArabicVoiceNormalizer.extractActiveTickerText(
          ArabicVoiceNormalizer.normalizeArabicSpoken('د ب ن 2816 د س'),
        ),
        equals('د س'),
      );
      expect(
        ArabicVoiceNormalizer.extractActiveTickerText(
          ArabicVoiceNormalizer.normalizeArabicSpoken('د ب ن 2816 د س ص 320'),
        ),
        equals('د س ص 320'),
      );
      expect(
        ArabicVoiceNormalizer.extractActiveTickerText(
          ArabicVoiceNormalizer.normalizeArabicSpoken('د ب ن 2816 د س ص 320'),
          isFinal: true,
        ),
        equals(''),
      );
    });

    test('Fused ultra-fast speech words (رانونيا، رانو نيا، سينصادعين) decode to 3 letters at 0ms', () {
      final f1 = ArabicVoiceNormalizer.extractPlatesFromTranscript('رانونيا 2816');
      expect(f1.length, equals(1));
      expect(f1.first.fullPlate, equals('ر ن ي 2816'));
      expect(f1.first.isComplete, isTrue);

      final f2 = ArabicVoiceNormalizer.extractPlatesFromTranscript('2816 رانونيا');
      expect(f2.length, equals(1));
      expect(f2.first.fullPlate, equals('ر ن ي 2816'));

      final f3 = ArabicVoiceNormalizer.extractPlatesFromTranscript('رانو نيا 2816');
      expect(f3.length, equals(1));
      expect(f3.first.fullPlate, equals('ر ن ي 2816'));

      final f3b = ArabicVoiceNormalizer.extractPlatesFromTranscript('2816 رانو نيا');
      expect(f3b.length, equals(1));
      expect(f3b.first.fullPlate, equals('ر ن ي 2816'));

      final f4 = ArabicVoiceNormalizer.extractPlatesFromTranscript('سينصادعين 3253');
      expect(f4.length, equals(1));
      expect(f4.first.fullPlate, equals('س ص ع 3253'));

      // Known brands must never split into fake letters
      expect(ArabicVoiceNormalizer.extractPlatesFromTranscript('تويوتا 2816'), isEmpty);
    });

    test('Digit-Pivot Phonetic Rescue fixes 1 lisped/slurred letter using unique sheet candidate', () {
      final sheetPlates = ['د ب ن 2816', 'س ص ع 9999'];
      final rescued = ArabicVoiceNormalizer.findPhoneticSheetMatchIndex(
        'ذ ب ن 2816',
        const [0],
        (i) => sheetPlates[i],
      );
      expect(rescued, equals(0));

      // Ambiguous tie across two candidates must not guess
      final tiedSheet = ['د ب ن 2816', 'ز ب ن 2816'];
      final tied = ArabicVoiceNormalizer.findPhoneticSheetMatchIndex(
        'ذ ب ن 2816',
        const [0, 1],
        (i) => tiedSheet[i],
      );
      expect(tied, isNull);
    });

    test('isPlateUpgrade supports both digit growth and zero-padded 3-digit upgrade', () {
      expect(ArabicVoiceNormalizer.isPlateUpgrade('د ب ق 281', 'د ب ق 2816'), isTrue);
      expect(ArabicVoiceNormalizer.isPlateUpgrade('د ب ق 2810', 'د ب ق 2816'), isTrue);
      expect(ArabicVoiceNormalizer.isPlateUpgrade('د ب ق 2810', 'د ب ق 9999'), isFalse);
      expect(ArabicVoiceNormalizer.isPlateUpgrade('د ب ق 2810', 'د ب ق 2810'), isFalse);
    });

    test('راعين / اراعين decode to ا ر ع at 0ms (both with digits and live slots)', () {
      expect(ArabicVoiceNormalizer.extractPlatesFromTranscript('راعين 2816').first.fullPlate, equals('ا ر ع 2816'));
      expect(ArabicVoiceNormalizer.extractPlatesFromTranscript('2816 راعين').first.fullPlate, equals('ا ر ع 2816'));
      expect(ArabicVoiceNormalizer.extractPlatesFromTranscript('اراعين 2816').first.fullPlate, equals('ا ر ع 2816'));

      final slots = ArabicVoiceNormalizer.extractLiveSlots(
        ArabicVoiceNormalizer.normalizeArabicSpoken('راعين'),
        const [],
      );
      expect(slots['l1'], equals('ا'));
      expect(slots['l2'], equals('ر'));
      expect(slots['l3'], equals('ع'));

      final fusedSlots = ArabicVoiceNormalizer.extractLiveSlots(
        ArabicVoiceNormalizer.normalizeArabicSpoken('رانونيا'),
        const [],
      );
      expect(fusedSlots['l1'], equals('ر'));
      expect(fusedSlots['l2'], equals('ن'));
      expect(fusedSlots['l3'], equals('ي'));
    });

    test('Digit-Pivot Rescue supports unique 3-letter permutation swap', () {
      final sheetPlates = ['ر ا ع 2816'];
      final rescued = ArabicVoiceNormalizer.findPhoneticSheetMatchIndex(
        'ا ر ع 2816',
        const [0],
        (i) => sheetPlates[i],
      );
      expect(rescued, equals(0));

      final tied = ArabicVoiceNormalizer.findPhoneticSheetMatchIndex(
        'ا ر ع 2816',
        const [0, 1],
        (i) => const ['ر ا ع 2816', 'ع ر ا 2816'][i],
      );
      expect(tied, isNull);
    });

    test('Universal 3-letter word-merge decoding (انوي، هاني، كلام، سالم، حامد، رامي) at 0ms while rejecting دبنق', () {
      expect(ArabicVoiceNormalizer.extractPlatesFromTranscript('انوي 2816').first.fullPlate, equals('ا ن ي 2816'));
      expect(ArabicVoiceNormalizer.extractPlatesFromTranscript('2816 انوي').first.fullPlate, equals('ا ن ي 2816'));
      expect(ArabicVoiceNormalizer.extractPlatesFromTranscript('هاني 2816').first.fullPlate, equals('ه ن ي 2816'));
      expect(ArabicVoiceNormalizer.extractPlatesFromTranscript('كلام 2816').first.fullPlate, equals('ك ل م 2816'));
      expect(ArabicVoiceNormalizer.extractPlatesFromTranscript('سالم 2816').first.fullPlate, equals('س ل م 2816'));
      expect(ArabicVoiceNormalizer.extractPlatesFromTranscript('حامد 2816').first.fullPlate, equals('ح م د 2816'));
      expect(ArabicVoiceNormalizer.extractPlatesFromTranscript('رامي 2816').first.fullPlate, equals('ر م ي 2816'));

      final liveAnwi = ArabicVoiceNormalizer.extractLiveSlots(
        ArabicVoiceNormalizer.normalizeArabicSpoken('انوي'),
        const [],
      );
      expect(liveAnwi['l1'], equals('ا'));
      expect(liveAnwi['l2'], equals('ن'));
      expect(liveAnwi['l3'], equals('ي'));

      // Invalid 4-consonant plate with no vowelized letter-name syllable remains rejected
      expect(ArabicVoiceNormalizer.extractPlatesFromTranscript('دبنق 2816'), isEmpty);
    });

    test('rescueUnparsedTailAgainstSheet rescues vowel-injected words cleanly against Excel without slicing 4-consonant plates', () {
      final sheet = ['س ع د 2816', 'ح م د 5555', 'د ب ن 2816'];
      final res1 = ArabicVoiceNormalizer.rescueUnparsedTailAgainstSheet(
        'سعود 2816',
        (d) => d == '2816' ? const [0, 2] : const [],
        (i) => sheet[i],
      );
      expect(res1?.fullPlate, equals('س ع د 2816'));

      final res2 = ArabicVoiceNormalizer.rescueUnparsedTailAgainstSheet(
        '5555 احمد',
        (d) => d == '5555' ? const [1] : const [],
        (i) => sheet[i],
      );
      expect(res2?.fullPlate, equals('ح م د 5555'));

      // 4th consonant 'ق' in 'دبنق' must not falsely slice to 'د ب ن 2816'
      final resBad = ArabicVoiceNormalizer.rescueUnparsedTailAgainstSheet(
        'دبنق 2816',
        (d) => d == '2816' ? const [0, 2] : const [],
        (i) => sheet[i],
      );
      expect(resBad, isNull);
    });

    test('Filler bridge (رقم/لوحة) and PlateUtteranceStitcher link letters & digits across pauses', () {
      expect(ArabicVoiceNormalizer.extractPlatesFromTranscript('د ب ن رقم 2816').first.fullPlate, equals('د ب ن 2816'));
      expect(ArabicVoiceNormalizer.extractPlatesFromTranscript('2816 لوحة د ب ن').first.fullPlate, equals('د ب ن 2816'));

      final stitcher = PlateUtteranceStitcher();
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);

      // Utterance 1: user says letters only, SpeechRecognizer restarts before digits
      final u1Norm = ArabicVoiceNormalizer.normalizeArabicSpoken('ا ر ع');
      stitcher.process(
        rawTranscript: 'ا ر ع',
        normalizedTranscript: u1Norm,
        rawPlates: const [],
        rawSlots: ArabicVoiceNormalizer.extractLiveSlots(u1Norm, const []),
        isFinal: true,
        now: t0,
      );

      // Utterance 2 (1.5s later): partial "28" preserves letters + shows digits live
      final partial = stitcher.process(
        rawTranscript: '28',
        normalizedTranscript: '28',
        rawPlates: const [],
        rawSlots: ArabicVoiceNormalizer.extractLiveSlots('28', const []),
        isFinal: false,
        now: t0.add(const Duration(milliseconds: 1500)),
      );
      expect(partial.slots['l1'], equals('ا'));
      expect(partial.slots['l2'], equals('ر'));
      expect(partial.slots['l3'], equals('ع'));
      expect(partial.slots['d1'], equals('2'));
      expect(partial.slots['d2'], equals('8'));

      // Utterance 2 completes "2816" -> commits full plate 'ا ر ع 2816'
      final done = stitcher.process(
        rawTranscript: '2816',
        normalizedTranscript: '2816',
        rawPlates: const [],
        rawSlots: ArabicVoiceNormalizer.extractLiveSlots('2816', const []),
        isFinal: false,
        now: t0.add(const Duration(milliseconds: 2000)),
      );
      expect(done.plates.length, equals(1));
      expect(done.plates.first.fullPlate, equals('ا ر ع 2816'));

      // Stale fragment (>6s later) must NOT leak into next utterance
      stitcher.process(
        rawTranscript: 'انوي',
        normalizedTranscript: ArabicVoiceNormalizer.normalizeArabicSpoken('انوي'),
        rawPlates: const [],
        rawSlots: ArabicVoiceNormalizer.extractLiveSlots('ا ن ي', const []),
        isFinal: true,
        now: t0.add(const Duration(seconds: 4)),
      );
      final stale = stitcher.process(
        rawTranscript: '9999',
        normalizedTranscript: '9999',
        rawPlates: const [],
        rawSlots: ArabicVoiceNormalizer.extractLiveSlots('9999', const []),
        isFinal: true,
        now: t0.add(const Duration(seconds: 11)),
      );
      expect(stale.plates, isEmpty);
    });

    test('Late 4th digit arriving within 5s triggers safe in-place upgrade over zero-padded 3-digit plate', () {
      final padded = ArabicVoiceNormalizer.finalizeThreeDigitPlate(
        ArabicVoiceNormalizer.extractPlatesFromTranscript('د ب ن 123').first,
      );
      expect(padded.fullPlate, equals('د ب ن 1230'));
      final lateFourth = ArabicVoiceNormalizer.extractPlatesFromTranscript('د ب ن 1234').first;
      expect(ArabicVoiceNormalizer.isPlateUpgrade(padded.fullPlate, lateFourth.fullPlate), isTrue);
      // Same letters different prefix must never overwrite
      expect(ArabicVoiceNormalizer.isPlateUpgrade(padded.fullPlate, 'د ب ن 5678'), isFalse);
      // Wait past 5s simulated at UI level does not falsely merge unrelated 3-digit plates
      expect(ArabicVoiceNormalizer.isPlateUpgrade(padded.fullPlate, 'س ص ع 1234'), isFalse);
    });
  });
}
