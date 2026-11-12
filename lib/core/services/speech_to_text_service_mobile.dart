import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'speech_to_text_service_interface.dart';

class MobileSpeechPlatformService implements SpeechPlatformService {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isInitialized = false;
  bool _wantListening = false;
  bool _isStarting = false;
  bool _useOnDevice = false;
  Function(List<String> candidates, bool isFinal)? _onResult;
  VoidCallback? _onDone;
  VoidCallback? _onFallbackToCloud;
  String? _localeId;
  Timer? _restartTimer;
  Timer? _watchdogTimer;

  int _session = 0;

  @override
  int get session => _session;

  @override
  bool get isListening => _wantListening;

  static bool _isFatalHardwareOrPermissionError(String errorMsg) {
    final e = errorMsg.toLowerCase();
    return e.contains('permission') ||
        e.contains('not_available') ||
        e.contains('audio');
  }

  @override
  Future<bool> initSpeech() async {
    if (_isInitialized) return true;
    try {
      _isInitialized = await _speech.initialize(
        onError: (val) {
          final msg = val.errorMsg;
          debugPrint('Speech error: $msg permanent=${val.permanent}');
          if (!_wantListening) return;

          // Instant fallback from on-device to Google Cloud streaming if offline pack fails
          if (_useOnDevice) {
            debugPrint('On-device speech unavailable, switching seamlessly to Cloud streaming.');
            _useOnDevice = false;
            _onFallbackToCloud?.call();
            _restartSoon(delayMs: 80);
            return;
          }

          // Only stop on genuine fatal permission/hardware errors;
          // Android marks error_speech_timeout, error_no_match, error_busy & error_client
          // as permanent=true, yet all of them are recoverable during continuous dictation!
          if (_isFatalHardwareOrPermissionError(msg)) {
            _wantListening = false;
            _watchdogTimer?.cancel();
            _onDone?.call();
            return;
          }

          final lower = msg.toLowerCase();
          final isBusyOrClient = lower.contains('busy') || lower.contains('client');
          _restartSoon(delayMs: isBusyOrClient ? 180 : 60);
        },
        onStatus: (val) {
          debugPrint('Speech status: $val');
          if (_wantListening && (val == 'done' || val == 'notListening')) {
            _restartSoon(delayMs: 60);
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

  void _startWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!_wantListening) {
        _watchdogTimer?.cancel();
        return;
      }
      if (!_speech.isListening && !_isStarting && !(_restartTimer?.isActive ?? false)) {
        debugPrint('Speech watchdog reviving idle recognizer');
        _listen();
      }
    });
  }

  void _restartSoon({int delayMs = 60}) {
    if (!_wantListening || _isStarting) return;
    _restartTimer?.cancel();
    _restartTimer = Timer(Duration(milliseconds: delayMs), () {
      if (!_wantListening || _isStarting) return;
      if (!_speech.isListening) {
        _listen();
      } else {
        // Native AudioRecord still winding down — retry shortly so the mic never dies silently
        _restartSoon(delayMs: 100);
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
        _onFallbackToCloud?.call();
        needFallback = true;
      } else {
        // Recoverable listen error: let watchdog/restart recover instead of killing the mic
        needFallback = true;
      }
    } finally {
      _isStarting = false;
    }

    if (needFallback && _wantListening) {
      _restartSoon(delayMs: 150);
    }
  }

  @override
  Future<void> startListening({
    required Function(List<String> candidates, bool isFinal) onResult,
    required VoidCallback onDone,
    bool preferOnDevice = false,
    VoidCallback? onFallbackToCloud,
  }) async {
    final available = await initSpeech();
    if (!available) {
      onDone();
      return;
    }
    _onResult = onResult;
    _onDone = onDone;
    _onFallbackToCloud = onFallbackToCloud;
    _wantListening = true;
    _useOnDevice = preferOnDevice;
    _startWatchdog();
    await _listen();
  }

  @override
  Future<void> stopListening() async {
    _wantListening = false;
    _isStarting = false;
    _restartTimer?.cancel();
    _watchdogTimer?.cancel();
    if (_speech.isListening) {
      await _speech.stop();
    }
  }
}

SpeechPlatformService getSpeechPlatformService() => MobileSpeechPlatformService();
