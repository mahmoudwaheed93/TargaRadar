import 'package:flutter/foundation.dart';

abstract class SpeechPlatformService {
  bool get isListening;

  /// Increases every time the recogniser (re)starts, so callers can tell
  /// which utterance a transcript belongs to.
  int get session;
  Future<bool> initSpeech();
  Future<void> startListening({
    required Function(String transcript) onResult,
    required VoidCallback onDone,
  });
  Future<void> stopListening();
}

SpeechPlatformService getSpeechPlatformService() =>
    throw UnsupportedError('Cannot create SpeechPlatformService');
