import 'package:flutter/foundation.dart';
import 'speech_to_text_service_interface.dart';

class WebSpeechPlatformService implements SpeechPlatformService {
  bool _isListening = false;

  @override
  bool get isListening => _isListening;

  @override
  int get session => 0;

  @override
  Future<bool> initSpeech() async => true;

  @override
  Future<void> startListening({
    required Function(List<String> candidates, bool isFinal) onResult,
    required VoidCallback onDone,
    bool preferOnDevice = false,
    VoidCallback? onFallbackToCloud,
  }) async {
    _isListening = true;
  }

  @override
  Future<void> stopListening() async {
    _isListening = false;
  }
}

SpeechPlatformService getSpeechPlatformService() => WebSpeechPlatformService();
