import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'speech_to_text_service_interface.dart';

/// Web browser speech service powered by speech_to_text's Web Speech API plugin
/// (SpeechRecognition / webkitSpeechRecognition with ar-EG / ar-SA & interim results).
class WebSpeechPlatformService implements SpeechPlatformService {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isInitialized = false;
  bool _wantListening = false;
  int _session = 0;
  String? _localeId;

  Function(List<String> candidates, bool isFinal)? _onResult;
  VoidCallback? _onDone;
  void Function(String msg, bool permanent)? _onErrorDelegate;
  void Function(String status)? _onStatusDelegate;

  @override
  SpeechEngineType get activeEngine => SpeechEngineType.platformRecognizer;

  @override
  bool get isListening => _wantListening;

  @override
  int get session => _session;

  @override
  Future<bool> initSpeech() async {
    if (_isInitialized) return true;
    try {
      _isInitialized = await _speech.initialize(
        onError: (val) {
          final msg = val.errorMsg;
          final lower = msg.toLowerCase();
          final isTimeout = lower.contains('no-speech') ||
              lower.contains('no_match') ||
              lower.contains('speech_timeout');
          if (!_wantListening) return;
          if (!isTimeout && (val.permanent || lower.contains('not-allowed') || lower.contains('permission'))) {
            _wantListening = false;
            _onErrorDelegate?.call(msg, true);
            _onDone?.call();
          }
        },
        onStatus: (status) {
          _onStatusDelegate?.call(status);
          if (_wantListening && (status == 'done' || status == 'notListening')) {
            Timer.run(() {
              if (_wantListening && !_speech.isListening) {
                unawaited(_listen());
              }
            });
          }
        },
      );
      if (_isInitialized) {
        final locales = await _speech.locales();
        final ar = locales.where((l) => l.localeId.toLowerCase().startsWith('ar')).toList();
        for (final pref in ['ar_eg', 'ar-eg', 'ar_sa', 'ar-sa']) {
          final match = ar.where((l) => l.localeId.toLowerCase() == pref);
          if (match.isNotEmpty) {
            _localeId = match.first.localeId;
            break;
          }
        }
        _localeId ??= ar.isNotEmpty ? ar.first.localeId : 'ar-EG';
      }
      return _isInitialized;
    } catch (e) {
      debugPrint('Web Speech init error: $e');
      return false;
    }
  }

  Future<void> _listen() async {
    if (!_wantListening) return;
    _session++;
    try {
      await _speech.listen(
        listenOptions: stt.SpeechListenOptions(
          localeId: _localeId ?? 'ar-EG',
          listenMode: stt.ListenMode.dictation,
          partialResults: true,
          cancelOnError: false,
          listenFor: const Duration(minutes: 10),
          pauseFor: const Duration(seconds: 5),
        ),
        onResult: (result) {
          if (!_wantListening) return;
          final candidates = <String>[
            if (result.recognizedWords.isNotEmpty) result.recognizedWords,
            for (final alt in result.alternates)
              if (alt.recognizedWords.isNotEmpty) alt.recognizedWords,
          ];
          if (candidates.isNotEmpty) {
            _onResult?.call(candidates, result.finalResult);
          }
        },
      );
    } catch (e) {
      _wantListening = false;
      _onErrorDelegate?.call(e.toString(), true);
      _onDone?.call();
    }
  }

  @override
  Future<void> startListening({
    required Function(List<String> candidates, bool isFinal) onResult,
    required VoidCallback onDone,
    bool preferOnDevice = false,
    VoidCallback? onFallbackToCloud,
    void Function(String msg, bool permanent)? onError,
    void Function(String status)? onStatus,
  }) async {
    _onResult = onResult;
    _onDone = onDone;
    _onErrorDelegate = onError;
    _onStatusDelegate = onStatus;
    final ok = await initSpeech();
    if (!ok) {
      _onErrorDelegate?.call('المتصفح لا يدعم التعرف الصوتي أو تم رفض إذن الميكروفون', true);
      onDone();
      return;
    }
    _wantListening = true;
    await _listen();
  }

  @override
  void updatePreferOnDevice(bool preferOnDevice) {}

  @override
  Future<void> stopListening() async {
    _wantListening = false;
    _session++;
    if (_speech.isListening) {
      await _speech.stop();
    }
  }
}

SpeechPlatformService getSpeechPlatformService() => WebSpeechPlatformService();
