import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'speech_to_text_service_interface.dart';
import 'speech_to_text_service_mobile.dart';
import 'speech_to_text_service_web.dart';
import 'arabic_voice_normalizer.dart';
import 'voice_telemetry_logger.dart';

class SpeechService {
  static final SpeechService instance = SpeechService._init();
  SpeechService._init();

  static const String _prefOnDeviceKey = 'prefer_on_device_speech';

  late final SpeechPlatformService _platformService = kIsWeb
      ? WebSpeechPlatformService()
      : MobileSpeechPlatformService();

  final ValueNotifier<bool> preferOnDeviceNotifier = ValueNotifier<bool>(true);
  bool _prefLoaded = false;

  bool get preferOnDevice => preferOnDeviceNotifier.value;
  bool get isListening => _platformService.isListening;

  Future<void> _ensurePrefLoaded() async {
    if (_prefLoaded) return;
    _prefLoaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      preferOnDeviceNotifier.value = prefs.getBool(_prefOnDeviceKey) ?? true;
    } catch (_) {}
  }

  Future<void> setPreferOnDevice(bool value) async {
    preferOnDeviceNotifier.value = value;
    _prefLoaded = true;
    _platformService.updatePreferOnDevice(value);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefOnDeviceKey, value);
    } catch (_) {}
  }

  Future<bool> initSpeech() async {
    await _ensurePrefLoaded();
    return _platformService.initSpeech();
  }

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
    await _ensurePrefLoaded();
    await _platformService.startListening(
      preferOnDevice: preferOnDeviceNotifier.value,
      onFallbackToCloud: () => setPreferOnDevice(false),
      onResult: (candidates, isFinal) {
        final sw = kDebugMode ? (Stopwatch()..start()) : null;
        // High-performance single-pass pipeline with N-best alternate recovery:
        // Scores Google STT alternate hypotheses in <0.2ms so dropped letters
        // in noise or fast speech are recovered automatically on-device.
        final best = ArabicVoiceNormalizer.selectBestCandidate(candidates);
        final slots = ArabicVoiceNormalizer.extractLiveSlots(best.normalized, best.plates);
        if (sw != null) {
          sw.stop();
          VoiceTelemetryLogger.instance.logPartialNormalized(
            session: _platformService.session,
            candidates: candidates,
            confidences: const [],
            isFinal: isFinal,
            normMatchUs: sw.elapsedMicroseconds,
            extractedPlates: best.plates.map((p) => p.fullPlate).toList(),
            activeTailKey: ArabicVoiceNormalizer.extractUnparsedTail(best.normalized),
          );
        }

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
