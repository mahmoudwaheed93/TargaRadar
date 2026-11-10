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
  });
}
