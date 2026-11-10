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
    required Function(String rawTranscript, List<ParsedPlateData> plates, Map<String, String> slots, String normalizedTranscript) onResult,
    required VoidCallback onDone,
    void Function(String? note, int session)? onOrphanNote,
    void Function(OrphanVoiceData data, int session)? onOrphanData,
  }) async {
    await _platformService.startListening(
      onResult: (transcript) {
        // High-performance single-pass pipeline:
        // Normalize spoken Arabic once, then feed the normalized tokens
        // to plate extraction, slot calculation, and orphan semantic detection.
        final normalized = ArabicVoiceNormalizer.normalizeArabicSpoken(transcript);
        final plates = ArabicVoiceNormalizer.extractPlatesFromNormalized(normalized);
        final slots = ArabicVoiceNormalizer.extractSlotsFromPlates(plates);

        if (plates.isEmpty) {
          final orphan = ArabicVoiceNormalizer.extractOrphanBrandAndNote(normalized);
          if (orphan.hasData) {
            onOrphanData?.call(orphan, _platformService.session);
            if (onOrphanNote != null && orphan.note != null) {
              onOrphanNote(orphan.note, _platformService.session);
            }
          }
        }

        onResult(transcript, plates, slots, normalized);
      },
      onDone: onDone,
    );
  }

  Future<void> stopListening() => _platformService.stopListening();
}
