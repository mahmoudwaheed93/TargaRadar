import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Service to play alert/alarm sounds when a matching plate is detected.
class SoundAlertService {
  SoundAlertService._();
  static final SoundAlertService instance = SoundAlertService._();

  AudioPlayer? _player;
  bool _audioContextConfigured = false;
  DateTime? _lastAlertTime;

  /// Plays the alarm sound for a few seconds without stealing microphone AudioFocus.
  Future<void> playMatchAlarm({int durationSeconds = 3}) async {
    try {
      final now = DateTime.now();
      if (_lastAlertTime != null &&
          now.difference(_lastAlertTime!).inMilliseconds < 1500) {
        return; // debounce
      }
      _lastAlertTime = now;

      _player ??= AudioPlayer();
      final player = _player;
      if (player == null) return;

      unawaited(() async {
        try {
          if (!_audioContextConfigured) {
            _audioContextConfigured = true;
            await player.setAudioContext(
              AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers).build(),
            );
          }
          await player.stop();
          await player.setVolume(1.0);
          await player.play(AssetSource('sounds/alarm.wav'));
        } catch (_) {}
      }());

      Timer(Duration(seconds: durationSeconds), () {
        player.stop().catchError((_) {});
      });
    } catch (e) {
      debugPrint('[SoundAlertService] Error playing alert: $e');
    }
  }

  Future<void> stop() async {
    try {
      await _player?.stop();
    } catch (_) {}
  }

  void dispose() {
    _player?.dispose();
    _player = null;
    _audioContextConfigured = false;
  }
}
