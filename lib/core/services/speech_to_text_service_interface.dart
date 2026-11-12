import 'package:flutter/foundation.dart';

abstract class SpeechPlatformService {
  bool get isListening;

  /// Increases every time the recogniser (re)starts, so callers can tell
  /// which utterance a transcript belongs to.
  int get session;

  Future<bool> initSpeech();
  Future<void> startListening({
    required Function(List<String> candidates, bool isFinal) onResult,
    required VoidCallback onDone,
    bool preferOnDevice = false,
    VoidCallback? onFallbackToCloud,
  });
  void updatePreferOnDevice(bool preferOnDevice);
  Future<void> stopListening();
}

SpeechPlatformService getSpeechPlatformService() =>
    throw UnsupportedError('Cannot create SpeechPlatformService');
