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
    ) onResult,
    required VoidCallback onDone,
    void Function(String? note, int session)? onOrphanNote,
  }) async {
    await _platformService.startListening(
      onResult: (transcript) {
        // Single-pass O(1) normalization + live tail slot extraction
        final normalized = ArabicVoiceNormalizer.normalizeArabicSpoken(transcript);
        if (onOrphanNote != null) {
          onOrphanNote(
            ArabicVoiceNormalizer.orphanNoteFromNormalized(normalized),
            _platformService.session,
          );
        }
        final plates = ArabicVoiceNormalizer.extractPlatesFromNormalized(normalized);
        final slots = ArabicVoiceNormalizer.extractSlotsFromPlates(
          plates,
          normalizedTail: normalized,
        );
        onResult(transcript, plates, slots, normalized);
      },
      onDone: onDone,
    );
  }

  Future<void> stopListening() => _platformService.stopListening();
}
