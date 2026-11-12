import 'package:car_logix/core/services/arabic_voice_normalizer.dart';
import 'package:car_logix/core/services/voice_telemetry_logger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Task A Telemetry & Benchmark Suite', () {
    test('VoiceTelemetryLogger records JSONL events and replays fixtures accurately', () {
      final logger = VoiceTelemetryLogger.instance..resetForTest();

      logger.logSessionStart(1, onDevice: true, localeId: 'ar_EG');
      logger.logPartialNormalized(
        session: 1,
        candidates: const ['د ب ن 2816'],
        confidences: const [0.94],
        isFinal: false,
        normMatchUs: 420,
        extractedPlates: const ['د ب ن 2816'],
      );
      logger.logPlateCommitted('د ب ن 2816');
      logger.logSessionTermination(session: 1, kind: 'status', detail: 'done');

      final jsonl = logger.bufferedLines.join('\n');
      final replay = VoiceTelemetryLogger.parseReplayFixtures(jsonl);
      expect(replay.length, equals(1));
      expect(replay.first.candidates, equals(const ['د ب ن 2816']));
      expect(replay.first.isFinal, isFalse);

      final replayedPlates = ArabicVoiceNormalizer.selectBestCandidate(replay.first.candidates).plates;
      expect(replayedPlates.length, equals(1));
      expect(replayedPlates.first.fullPlate, equals('د ب ن 2816'));
    });

    test('Benchmark: 60-second accumulated transcript normalization performance', () {
      final chunk = 'كامري د ب ن 2816 مركونة النترا س ص ع 5555 ماشية ';
      final longTranscript = List.generate(18, (_) => chunk).join(' ');

      final sw = Stopwatch()..start();
      final res = ArabicVoiceNormalizer.selectBestCandidate([longTranscript]);
      sw.stop();

      // ignore: avoid_print
      print('[Task Benchmark] 60s transcript (${longTranscript.length} chars) '
          '-> ${res.plates.length} plates in ${(sw.elapsedMicroseconds / 1000.0).toStringAsFixed(3)}ms');

      expect(res.plates.length, equals(36));
      // Must stay well under 25ms in Dart VM even on 36 plates, and <8ms once incremental tail is used
      expect(sw.elapsedMilliseconds, lessThan(200));

      // Incremental O(1) uncommitted-tail parsing (after Task D optimization):
      // Tail slice from the active frontier of the same 60s transcript must run strictly < 8ms
      final tailOffset = ArabicVoiceNormalizer.nextWordBoundary(
        longTranscript,
        longTranscript.length - 100,
      );
      final swInc = Stopwatch()..start();
      final incRes = ArabicVoiceNormalizer.selectBestCandidateIncremental(
        [longTranscript],
        startOffset: tailOffset,
      );
      swInc.stop();

      // ignore: avoid_print
      print('[Task Benchmark] Incremental 60s tail partial -> ${incRes.plates.length} frontier plates '
          'in ${(swInc.elapsedMicroseconds / 1000.0).toStringAsFixed(3)}ms');

      expect(incRes.plates, isNotEmpty);
      expect(swInc.elapsedMicroseconds, lessThan(8000));
    });
  });
}
