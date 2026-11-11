import 'package:flutter/foundation.dart';
import 'speech_to_text_service_interface.dart';
import 'speech_to_text_service_mobile.dart';
import 'speech_to_text_service_web.dart';
import 'arabic_voice_normalizer.dart';
import '../../data/models/excel_vehicle_model.dart';

class SpeechService {
  static final SpeechService instance = SpeechService._init();
  SpeechService._init();

  late final SpeechPlatformService _platformService = kIsWeb
      ? WebSpeechPlatformService()
      : MobileSpeechPlatformService();

  bool get isListening => _platformService.isListening;

  Future<bool> initSpeech() => _platformService.initSpeech();

  Future<void> startListening({
    required Function(
      String rawTranscript,
      List<ParsedPlateData> plates,
      Map<String, String> slots,
      String normalizedTranscript,
      bool isFinal,
    ) onResult,
    required VoidCallback onDone,
    void Function(String? note, int session)? onOrphanNote,
    void Function(OrphanVoiceData data, int session)? onOrphanData,
  }) async {
    await _platformService.startListening(
      onResult: (candidates, isFinal) {
        // High-performance single-pass pipeline with N-best alternate recovery:
        // Scores Google STT alternate hypotheses in <0.2ms so dropped letters
        // in noise or fast speech are recovered automatically on-device.
        final best = ArabicVoiceNormalizer.selectBestCandidate(candidates);
        final slots = ArabicVoiceNormalizer.extractSlotsFromPlates(best.plates);

        if (best.plates.isEmpty) {
          final orphan = ArabicVoiceNormalizer.extractOrphanBrandAndNote(best.normalized);
          if (orphan.hasData) {
            onOrphanData?.call(orphan, _platformService.session);
            if (onOrphanNote != null && orphan.note != null) {
              onOrphanNote(orphan.note, _platformService.session);
            }
          }
        }

        onResult(best.rawTranscript, best.plates, slots, best.normalized, isFinal);
      },
      onDone: onDone,
    );
  }

  Future<void> stopListening() => _platformService.stopListening();
}
