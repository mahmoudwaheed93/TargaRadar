import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/models/excel_vehicle_model.dart';
import '../config/secrets.dart';
import 'arabic_voice_normalizer.dart';

/// Multi-Model Ultra-Fast AI Plate Refiner powered by Groq LPU:
/// Primary: llama-3.1-8b-instant (~80ms LPU inference)
/// Secondary: llama-3.3-70b-versatile / allam-2-7b
/// Fallback: HuggingFace Qwen2.5-Coder-32B-Instruct
class AiPlateRefiner {
  AiPlateRefiner._();
  static final AiPlateRefiner instance = AiPlateRefiner._();

  static const String prefKeyGroqToken = 'aims_groq_api_key';
  static const Duration timeout = Duration(milliseconds: 1400);

  static const String _groqEndpoint = 'https://api.groq.com/openai/v1/chat/completions';
  static const String _groqFastModel = 'llama-3.1-8b-instant';
  static const String _groqArabicModel = 'allam-2-7b';

  static const String _hfEndpoint =
      'https://router.huggingface.co/hf-inference/models/Qwen/Qwen2.5-Coder-32B-Instruct/v1/chat/completions';
  static const String _hfModel = 'Qwen/Qwen2.5-Coder-32B-Instruct';

  String _userGroqToken = '';
  bool _prefsLoaded = false;

  final Map<String, List<ParsedPlateData>> _cache = {};
  final Map<String, Future<List<ParsedPlateData>>> _inFlight = {};

  String get effectiveGroqToken =>
      _userGroqToken.isNotEmpty ? _userGroqToken : kGroqToken.trim();

  bool get isEnabled =>
      effectiveGroqToken.isNotEmpty || kHuggingFaceToken.trim().isNotEmpty;

  bool get usesGroq => effectiveGroqToken.isNotEmpty;

  String get endpoint => usesGroq ? _groqEndpoint : _hfEndpoint;
  String get model => usesGroq ? _groqFastModel : _hfModel;
  String get token => usesGroq ? effectiveGroqToken : kHuggingFaceToken.trim();

  Future<String> getGroqToken() async {
    if (!_prefsLoaded) {
      try {
        final prefs = await SharedPreferences.getInstance();
        _userGroqToken = (prefs.getString(prefKeyGroqToken) ?? '').trim();
        _prefsLoaded = true;
      } catch (_) {}
    }
    return effectiveGroqToken;
  }

  Future<void> setGroqToken(String token) async {
    _userGroqToken = token.trim();
    _prefsLoaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefKeyGroqToken, _userGroqToken);
    } catch (_) {}
  }

  Future<List<ParsedPlateData>> refine(String rawTranscript) async {
    final clean = rawTranscript.trim();
    if (clean.isEmpty || !isEnabled) return const [];

    final cached = _cache[clean];
    if (cached != null) return cached;

    final active = _inFlight[clean];
    if (active != null) return active;

    final fut = _runRefinement(clean);
    _inFlight[clean] = fut;
    try {
      final res = await fut;
      if (_cache.length > 250) _cache.clear();
      _cache[clean] = res;
      return res;
    } finally {
      _inFlight.remove(clean);
    }
  }

  Future<List<ParsedPlateData>> _runRefinement(String rawTranscript) async {
    await getGroqToken();

    if (usesGroq) {
      // 1. Try Ultra-Fast llama-3.1-8b-instant (~80ms on Groq LPU)
      final fastRes = await _callChatCompletions(
        url: _groqEndpoint,
        apiKey: effectiveGroqToken,
        modelName: _groqFastModel,
        transcript: rawTranscript,
      );
      if (fastRes.isNotEmpty) return fastRes;

      // 2. Fallback to Arabic-specialized allam-2-7b
      final arRes = await _callChatCompletions(
        url: _groqEndpoint,
        apiKey: effectiveGroqToken,
        modelName: _groqArabicModel,
        transcript: rawTranscript,
      );
      if (arRes.isNotEmpty) return arRes;
    }

    if (kHuggingFaceToken.trim().isNotEmpty) {
      final hfRes = await _callChatCompletions(
        url: _hfEndpoint,
        apiKey: kHuggingFaceToken.trim(),
        modelName: _hfModel,
        transcript: rawTranscript,
      );
      if (hfRes.isNotEmpty) return hfRes;
    }

    return const [];
  }

  Future<List<ParsedPlateData>> _callChatCompletions({
    required String url,
    required String apiKey,
    required String modelName,
    required String transcript,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $apiKey',
            },
            body: jsonEncode({
              'model': modelName,
              'temperature': 0.0,
              'max_tokens': 90,
              'messages': [
                {
                  'role': 'system',
                  'content':
                      'Extract Saudi/Egyptian Arabic license plates from spoken transcript. Convert spoken letter names (دل/دال->د, به/باء->ب, ره/را->ر, عن/عين->ع, طا->ط, يه->ي, حه->ح, الف->أ) and spoken numbers (زيرو->0, اتنين->2, تلاته->3, تمانيه->8) into standard plates of 2-3 space-separated Arabic letters followed by 2-4 digits. Output ONLY one plate per line as: ح ر ف 1234'
                },
                {'role': 'user', 'content': transcript},
              ],
            }),
          )
          .timeout(timeout);

      if (response.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        final content =
            decoded['choices']?[0]?['message']?['content']?.toString() ?? '';
        if (content.trim().isNotEmpty) {
          return ArabicVoiceNormalizer.extractPlatesFromTranscript(content);
        }
      }
    } catch (e) {
      debugPrint('AiPlateRefiner ($modelName) error: $e');
    }
    return const [];
  }

  Future<({bool success, String message, int latencyMs})> testConnection({
    String? customToken,
  }) async {
    final sw = Stopwatch()..start();
    final keyToTest = (customToken != null && customToken.trim().isNotEmpty)
        ? customToken.trim()
        : await getGroqToken();

    if (keyToTest.isEmpty && kHuggingFaceToken.trim().isEmpty) {
      return (
        success: false,
        message: 'لا يوجد مفتاح API مفعل حالياً',
        latencyMs: 0,
      );
    }

    final useGroqKey = keyToTest.isNotEmpty;
    final res = await _callChatCompletions(
      url: useGroqKey ? _groqEndpoint : _hfEndpoint,
      apiKey: useGroqKey ? keyToTest : kHuggingFaceToken.trim(),
      modelName: useGroqKey ? _groqFastModel : _hfModel,
      transcript: 'دال به نون اتنين تمانيه واحد سته',
    );
    sw.stop();

    if (res.isNotEmpty) {
      return (
        success: true,
        message: 'متصل بنجاح (${res.first.fullPlate}) - ${sw.elapsedMilliseconds}ms',
        latencyMs: sw.elapsedMilliseconds,
      );
    }
    return (
      success: false,
      message: 'تعذر الاتصال بالموديل أو انتهت المهلة',
      latencyMs: sw.elapsedMilliseconds,
    );
  }
}
