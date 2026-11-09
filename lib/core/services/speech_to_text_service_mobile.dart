import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'speech_to_text_service_interface.dart';

const bool kPreferOnDeviceSpeech = false;

class MobileSpeechPlatformService implements SpeechPlatformService {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isInitialized = false;
  bool _wantListening = false;
  bool _isStarting = false;
  bool _useOnDevice = kPreferOnDeviceSpeech;
  Function(String transcript)? _onResult;
  VoidCallback? _onDone;
  String? _localeId;
  Timer? _restartTimer;
  String _lastDispatchedTranscript = '';

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
              _useOnDevice = false;
            }
            // Recover automatically from Android transient speech timeouts / no_match
            final msg = val.errorMsg.toLowerCase();
            final isRecoverable = !val.permanent ||
                msg.contains('no_match') ||
                msg.contains('speech_timeout') ||
                msg.contains('busy') ||
                msg.contains('client');
            if (isRecoverable) {
              _restartSoon();
            } else {
              _wantListening = false;
              _onDone?.call();
            }
          }
        },
        onStatus: (val) {
          if (_wantListening && (val == 'done' || val == 'notListening')) {
            _restartSoon();
          }
        },
      );
      if (_isInitialized) {
        final locales = await _speech.locales();
        final ar = locales
            .where((l) => l.localeId.toLowerCase().startsWith('ar'))
            .toList();
        // Prioritize Saudi & Egyptian Arabic locales for plate dictation
        for (final pref in ['ar_sa', 'ar-sa', 'ar_eg', 'ar-eg']) {
          final m = ar.where((l) => l.localeId.toLowerCase() == pref);
          if (m.isNotEmpty) {
            _localeId = m.first.localeId;
            break;
          }
        }
        _localeId ??= ar.isNotEmpty ? ar.first.localeId : 'ar_SA';
      }
      return _isInitialized;
    } catch (e) {
      debugPrint('Error initializing speech: $e');
      return false;
    }
  }

  void _restartSoon() {
    if (!_wantListening || _isStarting) return;
    _restartTimer?.cancel();
    // Ultra-fast 40ms hardware handoff for seamless continuous listening
    _restartTimer = Timer(const Duration(milliseconds: 40), () {
      if (_wantListening && !_speech.isListening && !_isStarting) {
        _listen();
      }
    });
  }

  Future<void> _listen() async {
    if (_isStarting || !_wantListening) return;
    _isStarting = true;
    _session++;
    _lastDispatchedTranscript = '';
    bool needFallback = false;
    try {
      await _speech.listen(
        listenOptions: stt.SpeechListenOptions(
          localeId: _localeId ?? 'ar_SA',
          listenMode: stt.ListenMode.dictation,
          partialResults: true,
          cancelOnError: false,
          autoPunctuation: false,
          enableHapticFeedback: false,
          onDevice: _useOnDevice,
        ),
        listenFor: const Duration(hours: 1),
        pauseFor: const Duration(seconds: 15),
        onResult: (result) {
          final words = result.recognizedWords;
          if (words.isNotEmpty && words != _lastDispatchedTranscript) {
            _lastDispatchedTranscript = words;
            _onResult?.call(words);
          }
        },
      );
    } catch (e) {
      debugPrint('Error during speech listen: $e');
      if (_useOnDevice) {
        _useOnDevice = false;
        needFallback = true;
      } else {
        _restartSoon();
      }
    } finally {
      _isStarting = false;
    }

    if (needFallback && _wantListening) {
      _listen();
    }
  }

  @override
  Future<void> startListening({
    required Function(String transcript) onResult,
    required VoidCallback onDone,
  }) async {
    _wantListening = true;
    _onResult = onResult;
    _onDone = onDone;
    _useOnDevice = kPreferOnDeviceSpeech;

    final initialized = await initSpeech();
    if (!initialized) {
      _wantListening = false;
      _onDone?.call();
      return;
    }

    if (!_speech.isListening && !_isStarting) {
      await _listen();
    }
  }

  @override
  Future<void> stopListening() async {
    _wantListening = false;
    _restartTimer?.cancel();
    _onResult = null;
    _onDone = null;
    await _speech.stop();
  }
}

SpeechPlatformService getSpeechPlatformService() => MobileSpeechPlatformService();
