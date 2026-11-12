import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'speech_to_text_service_interface.dart';
import 'voice_telemetry_logger.dart';

class MobileSpeechPlatformService implements SpeechPlatformService {
  static const MethodChannel _audioChannel = MethodChannel('com.example.car_logix/audio_control');

  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isInitialized = false;
  bool _wantListening = false;
  bool _isStarting = false;
  bool _useOnDevice = false;
  Function(List<String> candidates, bool isFinal)? _onResult;
  VoidCallback? _onDone;
  VoidCallback? _onFallbackToCloud;
  void Function(String msg, bool permanent)? _onErrorDelegate;
  void Function(String status)? _onStatusDelegate;
  String? _localeId;
  Timer? _restartTimer;
  Timer? _watchdogTimer;

  DateTime _lastSpeechActivityAt = DateTime.now();
  String _lastObservedWords = '';
  bool _hasSpokenInSession = false;
  int _session = 0;
  int _restartScheduledForSession = -1;
  int _consecutiveErrors = 0;

  // Auto-stop shortly after speaker goes silent so the mic never stays stuck open:
  // 6s after at least one utterance has been spoken, or 10s if completely idle.
  static const Duration _postSpeechSilence = Duration(seconds: 6);
  static const Duration _initialIdleSilence = Duration(seconds: 10);

  @override
  SpeechEngineType get activeEngine => SpeechEngineType.platformRecognizer;

  @override
  int get session => _session;

  @override
  bool get isListening => _wantListening;

  static bool _isFatalPermissionError(String errorMsg) {
    final e = errorMsg.toLowerCase();
    return e.contains('permission') ||
        e.contains('not_available') ||
        e.contains('permanently_denied');
  }

  static bool _isMissingOfflineModelError(String errorMsg) {
    final e = errorMsg.toLowerCase();
    return e.contains('not_supported') ||
        e.contains('not_available') ||
        e.contains('language') ||
        e.contains('offline') ||
        e.contains('download');
  }

  Future<void> _setBeepSuppressed(bool suppress) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _audioChannel.invokeMethod<void>('suppressBeep', {'suppress': suppress});
    } catch (_) {
      // Ignore on unsupported devices or headless tests.
    }
  }

  void _handleSpeechError(String msg, bool permanent) {
    debugPrint('Speech error: $msg permanent=$permanent');
    VoiceTelemetryLogger.instance.logSessionTermination(
      session: _session,
      kind: 'error',
      detail: msg,
      permanent: permanent,
    );
    if (!_wantListening) return;

    // Only fall back from offline mode if the offline model itself is missing/unsupported;
    // never downgrade on normal silence timeouts (speech_timeout / no_match).
    if (_useOnDevice && _isMissingOfflineModelError(msg)) {
      debugPrint('On-device speech pack unavailable, switching to Cloud streaming.');
      _useOnDevice = false;
      _onFallbackToCloud?.call();
      _scheduleRestart(isError: false, forcedDelayMs: 0);
      return;
    }

    final lower = msg.toLowerCase();
    final isTimeoutNoise = lower.contains('speech_timeout') || lower.contains('no_match');
    final isCloudLanguageUnavailable = !_useOnDevice && _isMissingOfflineModelError(msg);
    final isFatal = _isFatalPermissionError(msg) ||
        isCloudLanguageUnavailable ||
        (permanent && !isTimeoutNoise);

    if (isFatal) {
      _wantListening = false;
      _watchdogTimer?.cancel();
      _restartTimer?.cancel();
      unawaited(_setBeepSuppressed(false));
      _onErrorDelegate?.call(msg, true);
      _onDone?.call();
      return;
    }

    _scheduleRestart(isError: !isTimeoutNoise);
  }

  void _handleSpeechStatus(String val) {
    debugPrint('Speech status: $val');
    _onStatusDelegate?.call(val);
    if (val == 'done' || val == 'notListening') {
      VoiceTelemetryLogger.instance.logSessionTermination(
        session: _session,
        kind: 'status',
        detail: val,
      );
      if (_wantListening) {
        // Immediate 0ms restart on clean recognizer completion when continuous listening is active.
        _scheduleRestart(isError: false, forcedDelayMs: 0);
      }
    }
  }

  @override
  Future<bool> initSpeech() async {
    if (_isInitialized) return true;
    try {
      _isInitialized = await _speech.initialize(
        onError: (val) => _handleSpeechError(val.errorMsg, val.permanent),
        onStatus: _handleSpeechStatus,
      );
      if (_isInitialized) {
        final locales = await _speech.locales();
        final ar = locales.where((l) => l.localeId.toLowerCase().startsWith('ar')).toList();
        for (final pref in ['ar_eg', 'ar-eg', 'ar_sa', 'ar-sa', 'ar_ae', 'ar-ae']) {
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
    _watchdogTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_wantListening) {
        _watchdogTimer?.cancel();
        return;
      }
      final silenceLimit = _hasSpokenInSession ? _postSpeechSilence : _initialIdleSilence;
      if (DateTime.now().difference(_lastSpeechActivityAt) >= silenceLimit) {
        debugPrint('Speech watchdog: ${silenceLimit.inSeconds}s continuous silence -> auto-stopping mic.');
        unawaited(stopListening(notifyDone: true));
        return;
      }
      if (!_speech.isListening && !_isStarting && !(_restartTimer?.isActive ?? false)) {
        debugPrint('Speech watchdog reviving idle recognizer');
        _listen();
      }
    });
  }

  /// Unified deduplicated restart scheduler: guarantees at most ONE pending restart
  /// per session termination, restarting cleanly at 0ms unless backing off from errors.
  void _scheduleRestart({required bool isError, int? forcedDelayMs}) {
    if (!_wantListening || _isStarting) return;
    if (_restartScheduledForSession == _session && (_restartTimer?.isActive ?? false)) {
      return;
    }
    _restartScheduledForSession = _session;
    _restartTimer?.cancel();

    int delayMs;
    if (forcedDelayMs != null) {
      delayMs = forcedDelayMs;
      if (!isError) _consecutiveErrors = 0;
    } else if (!isError) {
      _consecutiveErrors = 0;
      delayMs = 0;
    } else {
      _consecutiveErrors++;
      const backoff = [40, 120, 300, 600, 1000, 1500];
      final idx = (_consecutiveErrors - 1).clamp(0, backoff.length - 1);
      delayMs = backoff[idx];
    }

    _restartTimer = Timer(Duration(milliseconds: delayMs), () {
      _restartScheduledForSession = -1;
      if (!_wantListening || _isStarting) return;
      if (!_speech.isListening) {
        _listen();
      } else {
        _scheduleRestart(isError: false, forcedDelayMs: 40);
      }
    });
  }

  Future<void> _listen() async {
    if (_isStarting || !_wantListening) return;
    _isStarting = true;
    final listenSession = ++_session;
    _lastObservedWords = '';
    VoiceTelemetryLogger.instance.logSessionStart(
      listenSession,
      onDevice: _useOnDevice,
      localeId: _localeId,
    );
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
          listenFor: const Duration(hours: 1),
          // Generous 5s endpointing window avoids clipping softer far-field speech mid-plate
          // while still keeping 0ms capture on partialResults and 6s watchdog auto-stop.
          pauseFor: const Duration(seconds: 5),
        ),
        onResult: (result) {
          if (!_wantListening) return;
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
            _consecutiveErrors = 0;
            final trimmed = result.recognizedWords.trim();
            if (trimmed.isNotEmpty && trimmed != _lastObservedWords) {
              _lastObservedWords = trimmed;
              _hasSpokenInSession = true;
              _lastSpeechActivityAt = DateTime.now();
            }
            _onResult?.call(candidates, result.finalResult);
          }
        },
      );
      // Race guard: if user pressed Stop while _speech.listen() was awaiting bind
      if (!_wantListening || _session != listenSession) {
        if (_speech.isListening) {
          await _speech.stop();
        }
      }
    } catch (e) {
      debugPrint('Error during speech listen: $e');
      if (_useOnDevice && _isMissingOfflineModelError(e.toString())) {
        _useOnDevice = false;
        _onFallbackToCloud?.call();
      }
      needFallback = true;
    } finally {
      _isStarting = false;
    }

    if (needFallback && _wantListening) {
      _scheduleRestart(isError: true);
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
    _onErrorDelegate = onError;
    _onStatusDelegate = onStatus;
    final available = await initSpeech();
    if (!available) {
      _onErrorDelegate?.call('speech_init_failed', true);
      onDone();
      return;
    }
    _onResult = onResult;
    _onDone = onDone;
    _onFallbackToCloud = onFallbackToCloud;
    _wantListening = true;
    _useOnDevice = preferOnDevice;
    _hasSpokenInSession = false;
    _consecutiveErrors = 0;
    _restartScheduledForSession = -1;
    _lastSpeechActivityAt = DateTime.now();
    unawaited(_setBeepSuppressed(true));
    _startWatchdog();
    await _listen();
  }

  @override
  void updatePreferOnDevice(bool preferOnDevice) {
    if (_useOnDevice == preferOnDevice) return;
    _useOnDevice = preferOnDevice;
    if (_wantListening) {
      _restartTimer?.cancel();
      if (_speech.isListening) {
        _speech.stop().then((_) {
          if (_wantListening) _scheduleRestart(isError: false, forcedDelayMs: 0);
        });
      } else {
        _scheduleRestart(isError: false, forcedDelayMs: 0);
      }
    }
  }

  @override
  Future<void> stopListening({bool notifyDone = false}) async {
    _wantListening = false;
    _isStarting = false;
    _session++;
    _restartScheduledForSession = -1;
    _restartTimer?.cancel();
    _watchdogTimer?.cancel();
    unawaited(_setBeepSuppressed(false));
    if (_speech.isListening) {
      await _speech.stop();
    }
    if (notifyDone) {
      _onDone?.call();
    }
  }
}
