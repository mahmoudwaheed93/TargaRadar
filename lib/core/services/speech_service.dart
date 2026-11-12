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

  // Incremental O(1) parsing & early duplicate filtering state
  String _lastRawPrimary = '';
  int _lastSessionId = -1;
  int _committedTailOffset = 0;

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
    _lastRawPrimary = '';
    _lastSessionId = -1;
    _committedTailOffset = 0;
    await _platformService.startListening(
      preferOnDevice: preferOnDeviceNotifier.value,
      onFallbackToCloud: () => setPreferOnDevice(false),
      onResult: (candidates, isFinal) {
        if (candidates.isEmpty) return;
        final currentSession = _platformService.session;
        final primaryRaw = candidates.first;

        // Reset incremental window when recognizer starts a fresh session/utterance
        if (currentSession != _lastSessionId || primaryRaw.length < _lastRawPrimary.length) {
          _lastSessionId = currentSession;
          _lastRawPrimary = '';
          _committedTailOffset = 0;
        }

        // Early duplicate-partial filter BEFORE running ArabicVoiceNormalizer
        if (!isFinal && primaryRaw == _lastRawPrimary) return;
        _lastRawPrimary = isFinal ? '' : primaryRaw;

        final sw = kDebugMode ? (Stopwatch()..start()) : null;
        final best = ArabicVoiceNormalizer.selectBestCandidateIncremental(
          candidates,
          startOffset: _committedTailOffset,
        );
        final slots = ArabicVoiceNormalizer.extractLiveSlots(best.normalized, best.plates);

        // Slide committed pointer forward once a completed plate accumulates >220 chars
        if (primaryRaw.length - _committedTailOffset > 220 &&
            best.plates.isNotEmpty &&
            best.plates.last.isComplete) {
          _committedTailOffset = ArabicVoiceNormalizer.nextWordBoundary(
            primaryRaw,
            primaryRaw.length - 100,
          );
        }

        if (sw != null) {
          sw.stop();
          VoiceTelemetryLogger.instance.logPartialNormalized(
            session: currentSession,
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
            onOrphanData?.call(orphan, currentSession);
            if (onOrphanNote != null && orphan.note != null) {
              onOrphanNote(orphan.note, currentSession);
            }
          }
        }

        onResult(primaryRaw, best.plates, slots, best.normalized, isFinal);
      },
      onDone: onDone,
    );
  }

  Future<void> stopListening() {
    _lastRawPrimary = '';
    _committedTailOffset = 0;
    return _platformService.stopListening();
  }
}
