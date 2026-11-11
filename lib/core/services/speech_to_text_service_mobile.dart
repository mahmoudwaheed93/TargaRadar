import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'speech_to_text_service_interface.dart';

/// Set to true ONLY if the Arabic offline speech pack is explicitly installed on the phone.
/// Setting to false ensures instant, reliable recognition via Google speech streaming on all devices.
const bool kPreferOnDeviceSpeech = false;

class MobileSpeechPlatformService implements SpeechPlatformService {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isInitialized = false;
  bool _wantListening = false;
  bool _isStarting = false;
  bool _useOnDevice = kPreferOnDeviceSpeech;
  Function(List<String> candidates, bool isFinal)? _onResult;
  VoidCallback? _onDone;
  String? _localeId;
  Timer? _restartTimer;

  int _session = 0;

  @override
  int get session => _session;

  @override
  bool get isListening => _wantListening;

  @override
  Future<bool> initSpeech() async {
    if (_isInitialized) return true;
    try {
      _isInitialized = await _speech.initialize(
        onError: (val) {
          debugPrint('Speech error: ${val.errorMsg} permanent=${val.permanent}');
          if (_wantListening) {
            if (_useOnDevice) {
              debugPrint('On-device speech error, falling back to Google Cloud recognition.');
              _useOnDevice = false;
            }
            if (!val.permanent) {
              _restartSoon();
            } else {
              _wantListening = false;
              _onDone?.call();
            }
          }
        },
        onStatus: (val) {
          debugPrint('Speech status: $val');
          if (_wantListening && (val == 'done' || val == 'notListening')) {
            _restartSoon();
          }
        },
      );
      if (_isInitialized) {
        final locales = await _speech.locales();
        final ar = locales.where((l) => l.localeId.toLowerCase().startsWith('ar')).toList();
        // Prefer Egyptian Arabic, then Saudi, then any Arabic; else device default.
        for (final pref in ['ar_eg', 'ar-eg', 'ar_sa', 'ar-sa']) {
          final m = ar.where((l) => l.localeId.toLowerCase() == pref);
          if (m.isNotEmpty) {
            _localeId = m.first.localeId;
            break;
          }
        }
        _localeId ??= ar.isNotEmpty ? ar.first.localeId : null;
        debugPrint('Speech locale used: $_localeId (onDevice: $_useOnDevice)');
      }
      return _isInitialized;
    } catch (e) {
      debugPrint('Error initializing speech: $e');
      return false;
    }
  }

  void _restartSoon({int delayMs = 25}) {
    if (!_wantListening || _isStarting) return;
    _restartTimer?.cancel();
    _restartTimer = Timer(Duration(milliseconds: delayMs), () {
      if (!_wantListening || _isStarting) return;
      if (!_speech.isListening) {
        _listen();
      } else {
        // Native AudioRecord still winding down — retry once shortly so the mic never dies silently
        _restartSoon(delayMs: 60);
      }
    });
  }

  Future<void> _listen() async {
    if (_isStarting || !_wantListening) return;
    _isStarting = true;
    _session++;
    bool needFallback = false;
    try {
      await _speech.listen(
        listenOptions: stt.SpeechListenOptions(
          localeId: _localeId ?? 'ar_SA',
          // dictation mode keeps listening continuously without killing the session after single words
          listenMode: stt.ListenMode.dictation,
          partialResults: true,
          cancelOnError: false,
          autoPunctuation: false,
          enableHapticFeedback: false,
          onDevice: _useOnDevice,
        ),
        listenFor: const Duration(hours: 1),
        pauseFor: const Duration(seconds: 10),
        onResult: (result) {
          final candidates = <String>[];
          final seen = <String>{};
          if (result.recognizedWords.isNotEmpty) {
            candidates.add(result.recognizedWords);
            seen.add(result.recognizedWords);
          }
          for (final alt in result.alternates) {
            final w = alt.recognizedWords;
            if (w.isNotEmpty && seen.add(w)) {
              candidates.add(w);
            }
          }
          if (candidates.isNotEmpty) {
            _onResult?.call(candidates, result.finalResult);
          }
        },
      );
    } catch (e) {
      debugPrint('Error during speech listen: $e');
      if (_useOnDevice) {
        _useOnDevice = false;
        needFallback = true;
      } else {
        _wantListening = false;
        _onDone?.call();
      }
    } finally {
      _isStarting = false;
    }

    if (needFallback && _wantListening) {
      _restartSoon();
    }
  }

  @override
  Future<void> startListening({
    required Function(List<String> candidates, bool isFinal) onResult,
    required VoidCallback onDone,
  }) async {
    final available = await initSpeech();
    if (!available) {
      onDone();
      return;
    }
    _onResult = onResult;
    _onDone = onDone;
    _wantListening = true;
    _useOnDevice = kPreferOnDeviceSpeech;
    await _listen();
  }

  @override
  Future<void> stopListening() async {
    _wantListening = false;
    _isStarting = false;
    _restartTimer?.cancel();
    if (_speech.isListening) {
      await _speech.stop();
    }
  }
}

SpeechPlatformService getSpeechPlatformService() => MobileSpeechPlatformService();
