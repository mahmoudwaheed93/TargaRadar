import 'package:car_logix/presentation/providers/car_record_provider.dart';
import 'package:car_logix/presentation/providers/inspection_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:car_logix/core/services/arabic_voice_normalizer.dart';
import 'package:car_logix/data/models/excel_vehicle_model.dart';

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

    test('Digits-first with 2 letters waits before committing (isComplete=false), 3 letters commits immediately', () {
      final partial = ArabicVoiceNormalizer.extractPlatesFromTranscript('3253 ب ن');
      expect(partial.length, equals(1));
      expect(partial.first.fullPlate, equals('ب ن 3253'));
      expect(partial.first.isComplete, isFalse);

      final complete = ArabicVoiceNormalizer.extractPlatesFromTranscript('3253 ب ن ق');
      expect(complete.length, equals(1));
      expect(complete.first.fullPlate, equals('ب ن ق 3253'));
      expect(complete.first.isComplete, isTrue);

      final withBrand = ArabicVoiceNormalizer.extractPlatesFromTranscript('3253 ب ن كامري');
      expect(withBrand.length, equals(1));
      expect(withBrand.first.fullPlate, equals('ب ن 3253'));
      expect(withBrand.first.detectedBrand, equals('كامري'));
      expect(withBrand.first.isComplete, isTrue);
    });

    test('Mixed glued and single letter combinations capture last letter cleanly', () {
      expect(
        ArabicVoiceNormalizer.extractPlatesFromTranscript('3253 بن ق').first.fullPlate,
        equals('ب ن ق 3253'),
      );
      expect(
        ArabicVoiceNormalizer.extractPlatesFromTranscript('3253 ب نق').first.fullPlate,
        equals('ب ن ق 3253'),
      );
      expect(
        ArabicVoiceNormalizer.extractPlatesFromTranscript('بن ق 3253').first.fullPlate,
        equals('ب ن ق 3253'),
      );
      expect(
        ArabicVoiceNormalizer.extractPlatesFromTranscript('ب نق 3253').first.fullPlate,
        equals('ب ن ق 3253'),
      );
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

    test('isPlateUpgrade detects both digit extensions and trailing letter extensions', () {
      expect(ArabicVoiceNormalizer.isPlateUpgrade('ب ن 3253', 'ب ن ق 3253'), isTrue);
      expect(ArabicVoiceNormalizer.isPlateUpgrade('م ن ه 1013', 'م ن ه م 1013'), isTrue);
      expect(ArabicVoiceNormalizer.isPlateUpgrade('د ب ق 28', 'د ب ق 2852'), isTrue);
      expect(ArabicVoiceNormalizer.isPlateUpgrade('ب ن 3253', 'ب ن ق 9999'), isFalse);
      expect(ArabicVoiceNormalizer.isPlateUpgrade('ب ن 3253', 'د س ص 3253'), isFalse);
    });

    test('Egyptian compound thousands & hundreds (الف، متين، تلات تلاف) parse cleanly', () {
      final r1 = ArabicVoiceNormalizer.extractPlatesFromTranscript('الف متين تلاته وخمسين ب ن ق');
      expect(r1.length, equals(1));
      expect(r1.first.fullPlate, equals('ب ن ق 1253'));

      final r2 = ArabicVoiceNormalizer.extractPlatesFromTranscript('تلات تلاف متين تلاته وخمسين ب ن ق');
      expect(r2.length, equals(1));
      expect(r2.first.fullPlate, equals('ب ن ق 3253'));

      final r3 = ArabicVoiceNormalizer.extractPlatesFromTranscript('اربع تلاف وخمسميه د ب ن');
      expect(r3.length, equals(1));
      expect(r3.first.fullPlate, equals('د ب ن 4500'));
    });

    test('Mixed-order consecutive fast speech does not steal first letter of next plate', () {
      final r1 = ArabicVoiceNormalizer.extractPlatesFromTranscript('3253 ب ن ق د ب ن 2816');
      expect(r1.length, equals(2));
      expect(r1[0].fullPlate, equals('ب ن ق 3253'));
      expect(r1[1].fullPlate, equals('د ب ن 2816'));

      final r2 = ArabicVoiceNormalizer.extractPlatesFromTranscript('3253 ب ن ق د ب 2816');
      expect(r2.length, equals(2));
      expect(r2[0].fullPlate, equals('ب ن ق 3253'));
      expect(r2[1].fullPlate, equals('د ب 2816'));
    });

    test('N-best selectBestCandidate recovers missing last letter from alternate hypothesis', () {
      final best = ArabicVoiceNormalizer.selectBestCandidate(['3253 ب ن', '3253 ب ن ق']);
      expect(best.plates.length, equals(1));
      expect(best.plates.first.fullPlate, equals('ب ن ق 3253'));
      expect(best.plates.first.isComplete, isTrue);

      final bestNoise = ArabicVoiceNormalizer.selectBestCandidate(['كلام غير واضح', 'د ب ن 2816']);
      expect(bestNoise.plates.length, equals(1));
      expect(bestNoise.plates.first.fullPlate, equals('د ب ن 2816'));
    });

    test('Canonical plateKey matches Excel formats regardless of order or punctuation', () {
      expect(
        ArabicVoiceNormalizer.plateKey('2816 د ب ن'),
        equals(ArabicVoiceNormalizer.plateKey('د ب ن - 2816')),
      );
      expect(
        ArabicVoiceNormalizer.plateKey('د.ب.ن/2816'),
        equals('دبن2816'),
      );
    });

    test('extractUnparsedTail and hasValidNoteTriggerOrKeyword guard continuous AI fallback', () {
      final normStr = ArabicVoiceNormalizer.normalizeArabicSpoken('د ب ن 2816 تلاته اتنين 53');
      final tail = ArabicVoiceNormalizer.extractUnparsedTail(normStr);
      expect(tail, equals('3253'));

      expect(ArabicVoiceNormalizer.hasValidNoteTriggerOrKeyword('د ب ن 2816 س'), isFalse);
      expect(ArabicVoiceNormalizer.hasValidNoteTriggerOrKeyword('د ب ن 2816 مركونة'), isTrue);
    });

    test('Back-to-back plates with adjacent digits do not merge across plate boundaries', () {
      final res = ArabicVoiceNormalizer.extractPlatesFromTranscript('د ب ن 2816 تلاته اتنين خمسه تلاته ب ن ق');
      expect(res.length, equals(2));
      expect(res[0].fullPlate, equals('د ب ن 2816'));
      expect(res[1].fullPlate, equals('ب ن ق 3253'));
    });
  });
}

