import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Service to play alert/alarm sounds when a matching plate is detected.
class SoundAlertService {
  SoundAlertService._();
  static final SoundAlertService instance = SoundAlertService._();

  AudioPlayer? _player;
  bool _warmedUp = false;
  DateTime? _lastAlertTime;
  Timer? _stopTimer;

  /// Pre-configures AudioContext and pre-loads the alert sound so the first
  /// matched plate fires at 0ms without disk-decode lag or AudioFocus interruption.
  Future<void> warmUp() async {
    if (_warmedUp) return;
    try {
      _player ??= AudioPlayer();
      await _player!.setAudioContext(
        AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers).build(),
      );
      await _player!.setSource(AssetSource('sounds/alarm.wav'));
      _warmedUp = true;
    } catch (_) {}
  }

  /// Plays the alarm sound for a few seconds without stealing microphone AudioFocus.
  Future<void> playMatchAlarm({int durationSeconds = 3}) async {
    try {
      final now = DateTime.now();
      if (_lastAlertTime != null &&
          now.difference(_lastAlertTime!).inMilliseconds < 1500) {
        return; // debounce
      }
      _lastAlertTime = now;

      _stopTimer?.cancel();
      _player ??= AudioPlayer();
      final player = _player;
      if (player == null) return;

      unawaited(() async {
        try {
          if (!_warmedUp) {
            await warmUp();
          }
          await player.stop();
          await player.setVolume(1.0);
          await player.play(AssetSource('sounds/alarm.wav'));
        } catch (_) {}
      }());

      _stopTimer = Timer(Duration(seconds: durationSeconds), () {
        _player?.stop().catchError((_) {});
      });
    } catch (e) {
      debugPrint('[SoundAlertService] Error playing alert: $e');
    }
  }

  Future<void> stop() async {
    _stopTimer?.cancel();
    _stopTimer = null;
    try {
      await _player?.stop();
    } catch (_) {}
  }

  void dispose() {
    _stopTimer?.cancel();
    _stopTimer = null;
    _player?.dispose();
    _player = null;
    _warmedUp = false;
  }
}
