import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/models/excel_vehicle_model.dart';
import '../config/secrets.dart';
import 'arabic_voice_normalizer.dart';

/// Fallback plate extractor powered by ultra-fast Groq LPU (llama-3.1-8b-instant ~120ms)
/// or Hugging Face Inference Providers (Qwen2.5-1.5B ~300ms).
///
/// SPEED RULES (so the app keeps the same feel as the local engine):
///  * It is NEVER on the hot path. The local [ArabicVoiceNormalizer] runs first
///    on every partial result; this class is only called, in the background,
///    when the local parser found no plate in a transcript that clearly
///    contains plate-like digits.
///  * Hard timeout, tiny output (max_tokens: 120), temperature 0.
///  * In-memory cache + de-duplication of identical in-flight requests.
class AiPlateRefiner {
  AiPlateRefiner._();
  static final AiPlateRefiner instance = AiPlateRefiner._();

  static const String prefKeyGroqToken = 'groq_api_key';

  // Primary Ultra-Fast Engine: Groq LPU (Arabic-specialized ALLAM 2 7B / LPU)
  static const String _groqEndpoint = 'https://api.groq.com/openai/v1/chat/completions';
  static const String _groqModel = 'allam-2-7b';

  // Fallback Engine: Hugging Face Router
  static const String _hfEndpoint = 'https://router.huggingface.co/v1/chat/completions';
  static const String _hfModel = 'Qwen/Qwen2.5-1.5B-Instruct';

  String _runtimeGroqToken = '';
  bool _initialized = false;

  Future<void> _ensureInit() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _runtimeGroqToken = prefs.getString(prefKeyGroqToken) ?? '';
    } catch (_) {}
    _initialized = true;
  }

  Future<String> getGroqToken() async {
    await _ensureInit();
    return _runtimeGroqToken.isNotEmpty ? _runtimeGroqToken : kGroqToken;
  }

  Future<void> setGroqToken(String token) async {
    _runtimeGroqToken = token.trim();
    _initialized = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_runtimeGroqToken.isEmpty) {
        await prefs.remove(prefKeyGroqToken);
      } else {
        await prefs.setString(prefKeyGroqToken, _runtimeGroqToken);
      }
    } catch (_) {}
  }

  String get effectiveGroqToken =>
      _runtimeGroqToken.isNotEmpty ? _runtimeGroqToken : kGroqToken;

  /// Whether AI fallback is configured with at least one provider.
  bool get isEnabled => effectiveGroqToken.isNotEmpty || kHuggingFaceToken.isNotEmpty;

  /// True when Groq is used as the primary engine.
  bool get usesGroq => effectiveGroqToken.isNotEmpty;

  String get endpoint => usesGroq ? _groqEndpoint : _hfEndpoint;
  String get model => usesGroq ? _groqModel : _hfModel;
  String get token => usesGroq ? effectiveGroqToken : kHuggingFaceToken;

  static const Duration _timeout = Duration(milliseconds: 2000);
  static const int _maxCache = 200;

  static const String _systemPrompt =
      'You extract vehicle license plates from noisy Arabic speech-recognition text (Egyptian and Saudi dialects). '
      'A plate consists of 2 to 4 Arabic letters followed by 2 to 4 digits. '
      'Spoken numbers must be converted to numeric digits (e.g. "الفين تمانية مية واحد وستين" -> 2861, "تلاتة تسعة اتنين ستة" -> 3926, "زيرو" -> 0). '
      'Spoken letter names and colloquial variations must become letters (e.g. "سين" -> س, "به" -> ب, "يه" -> ي, "طه" -> ط, "عين" -> ع, "نون" -> ن, "دال" -> د). '
      'Optional car brand or remarks spoken before, after, or anywhere around the plate go to "brand" and "note". '
      'Reply with ONLY a valid JSON array, strictly without any prose, markdown explanation or thinking: '
      '[{"letters":"د ب ن","digits":"2816","brand":"","note":""}]. '
      'If no valid plate is detected, reply with []. Never invent digits or letters.';

  final http.Client _client = http.Client();
  final Map<String, List<ParsedPlateData>> _cache = {};
  final Set<String> _inFlight = {};

  Future<List<ParsedPlateData>> refine(String rawTranscript) async {
    await _ensureInit();
    if (!isEnabled) return const [];
    final key = ArabicVoiceNormalizer.normalizeArabicSpoken(rawTranscript);
    if (key.isEmpty) return const [];

    final cached = _cache[key];
    if (cached != null) return cached;
    if (!_inFlight.add(key)) return const [];

    final started = DateTime.now();
    try {
      final res = await _client
          .post(
            Uri.parse(endpoint),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': model,
              'temperature': 0,
              'max_tokens': 120,
              'messages': [
                {'role': 'system', 'content': _systemPrompt},
                {'role': 'user', 'content': rawTranscript},
              ],
            }),
          )
          .timeout(_timeout);

      if (res.statusCode != 200) {
        debugPrint('AI refine HTTP ${res.statusCode} (${usesGroq ? "Groq" : "HF"})');
        return const [];
      }
      final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final content = body['choices'][0]['message']['content'] as String? ?? '';
      final plates = _parse(content);

      if (_cache.length >= _maxCache) _cache.remove(_cache.keys.first);
      _cache[key] = plates;
      debugPrint('AI refine [${usesGroq ? "Groq" : "HF"}] ${DateTime.now().difference(started).inMilliseconds}ms '
          '-> ${plates.map((p) => p.fullPlate).toList()}');
      return plates;
    } on TimeoutException {
      debugPrint('AI refine timeout');
      return const [];
    } catch (e) {
      debugPrint('AI refine error: $e');
      return const [];
    } finally {
      _inFlight.remove(key);
    }
  }

  /// Strictly validates the model output: anything that is not
  /// 2-4 Arabic letters + exactly 4 digits is dropped.
  List<ParsedPlateData> _parse(String content) {
    final start = content.indexOf('[');
    final end = content.lastIndexOf(']');
    if (start == -1 || end <= start) return const [];
    final List<dynamic> raw;
    try {
      raw = jsonDecode(content.substring(start, end + 1)) as List<dynamic>;
    } catch (_) {
      return const [];
    }

    final out = <ParsedPlateData>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final lettersRaw = ArabicVoiceNormalizer.normalizePlateForMatch('${item['letters'] ?? ''}');
      final digitsRaw = ArabicVoiceNormalizer.normalizePlateForMatch('${item['digits'] ?? ''}');
      if (!RegExp(r'^[ا-ي]{2,4}$').hasMatch(lettersRaw)) continue;
      if (!RegExp(r'^\d{2,4}$').hasMatch(digitsRaw)) continue;

      final letters = lettersRaw.split('').join(' ');
      final brand = '${item['brand'] ?? ''}'.trim();
      final note = '${item['note'] ?? ''}'.trim();
      out.add(ParsedPlateData(
        fullPlate: '$letters $digitsRaw',
        letters: letters,
        digits: digitsRaw,
        detectedBrand: brand.isEmpty ? '-' : brand,
        detectedNote: note.isEmpty ? '-' : note,
      ));
    }
    return out;
  }

  /// Utility to test API connectivity and return latency
  Future<({bool success, String message, int latencyMs})> testConnection({String? customToken}) async {
    await _ensureInit();
    final candidate = (customToken != null && customToken.trim().isNotEmpty)
        ? customToken.trim()
        : effectiveGroqToken;
    final t = candidate.isNotEmpty ? candidate : kHuggingFaceToken;
    final ep = candidate.isNotEmpty ? _groqEndpoint : _hfEndpoint;
    final md = candidate.isNotEmpty ? _groqModel : _hfModel;

    if (t.isEmpty) {
      return (success: false, message: 'لم يتم إدخال مفتاح API', latencyMs: 0);
    }

    final sw = Stopwatch()..start();
    try {
      final res = await _client.post(
        Uri.parse(ep),
        headers: {
          'Authorization': 'Bearer $t',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': md,
          'temperature': 0,
          'max_tokens': 60,
          'messages': [
            {'role': 'system', 'content': _systemPrompt},
            {'role': 'user', 'content': 'د ب ن 2816'},
          ],
        }),
      ).timeout(const Duration(milliseconds: 4000));

      sw.stop();
      if (res.statusCode == 200) {
        return (
          success: true,
          message: 'الاتصال ناجح ومحرك Groq LPU جاهز للعمل!',
          latencyMs: sw.elapsedMilliseconds,
        );
      } else {
        return (
          success: false,
          message: 'خطأ من الخادم (رمز ${res.statusCode}): تأكد من صحة المفتاح',
          latencyMs: sw.elapsedMilliseconds,
        );
      }
    } catch (e) {
      sw.stop();
      return (
        success: false,
        message: 'تعذر الاتصال بالخادم: $e',
        latencyMs: sw.elapsedMilliseconds,
      );
    }
  }
}
