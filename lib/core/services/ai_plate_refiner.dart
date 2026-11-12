import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/models/excel_vehicle_model.dart';
import '../config/secrets.dart';
import 'arabic_voice_normalizer.dart';

/// Fallback plate extractor powered by ultra-fast Groq LPU (qwen/qwen3.8-27b)
/// with automatic Hugging Face Router fallback if Groq fails or rate-limits.
class AiPlateRefiner {
  AiPlateRefiner._();
  static final AiPlateRefiner instance = AiPlateRefiner._();

  static const String prefKeyGroqToken = 'groq_api_key';

  // Primary High-Accuracy Ultra-Fast Engine: Groq LPU (Qwen 3.8 27B, reasoning disabled)
  static const String _groqEndpoint = 'https://api.groq.com/openai/v1/chat/completions';
  static const String _groqModel = 'qwen/qwen3.8-27b';

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

  static const Duration _timeout = Duration(milliseconds: 2200);
  static const int _maxCache = 200;

  static const String _systemPrompt =
      'Extract Arabic vehicle license plates from fast, slurred, or noisy Egyptian & Saudi speech-recognition text. '
      'Handle both Letters-First ("د ب ن 2816") and Digits-First ("2816 د ب ن") speech. '
      'EVERY plate MUST have EXACTLY 3 Arabic letters (never 2 or 4) and 3 or 4 digits. '
      'If only 3 digits are spoken after 3 letters (e.g. "د ب ن 123"), append a trailing 0 ("1230"). '
      'CRITICAL: Google Arabic STT often merges 3 spoken letters into real-looking Arabic words with extra vowels (ا/و/ي) near numbers — decode them back to 3 single letters! '
      'Examples: "انوي 2816" -> letters:"ا ن ي", digits:"2816"; "راعين 2816" -> letters:"ا ر ع", digits:"2816"; "سعود 2816" -> letters:"س ع د", digits:"2816"; "حامد 2816" -> letters:"ح م د", digits:"2816"; "رانونيا 2816" -> letters:"ر ن ي", digits:"2816"; "سينصادعين 4512" -> letters:"س ص ع", digits:"4512". '
      'Convert spoken numbers to digits (e.g. "تلات تلاف متين تلاته وخمسين" -> "3253", "الفين تمانية مية واحد وستين" -> "2861", "زيرو" -> "0"). '
      'Convert spoken letter names to 3 space-separated single Arabic letters (e.g. "به نون قاف" -> "ب ن ق", "سين" -> "س", "دال" -> "د"). '
      'Only set "note" if explicit remark trigger (ملحوظة/ملاحظة/نوت/اكتب/سجل) or car condition (مركونة/واقفة غلط/عطلانة/مصدومة/مخالفة/ماشية) is spoken; otherwise note MUST be "". '
      'Reply with ONLY a valid JSON array, strictly without prose or markdown: '
      '[{"letters":"ب ن ق","digits":"3253","brand":"","note":""}]. '
      'If no valid 3-letter plate is detected, reply with []. Never invent digits or letters.';

  final http.Client _client = http.Client();
  final Map<String, List<ParsedPlateData>> _cache = {};
  final Set<String> _inFlight = {};

  /// Bounds prompt size to the latest ~14 words so accumulated noise cannot
  /// trigger AI hallucinations on long voice sessions.
  static String _trimToRecentTail(String text) {
    final words = text.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.length <= 14) return text.trim();
    return words.sublist(words.length - 14).join(' ');
  }

  Future<List<ParsedPlateData>?> _queryProvider({
    required String url,
    required String apiKey,
    required String modelName,
    required String input,
    required bool isGroq,
  }) async {
    final started = DateTime.now();
    try {
      final payload = <String, dynamic>{
        'model': modelName,
        'temperature': 0,
        'max_tokens': 90,
        if (isGroq) 'reasoning_effort': 'none',
        'messages': [
          {'role': 'system', 'content': _systemPrompt},
          {'role': 'user', 'content': input},
        ],
      };

      final res = await _client
          .post(
            Uri.parse(url),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(payload),
          )
          .timeout(_timeout);

      if (res.statusCode != 200) {
        debugPrint('AI refine HTTP ${res.statusCode} (${isGroq ? "Groq" : "HF"})');
        return null;
      }

      final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final content = body['choices'][0]['message']['content'] as String? ?? '';
      final allowNote = ArabicVoiceNormalizer.hasValidNoteTriggerOrKeyword(input);
      final plates = _parse(content, allowNote: allowNote);
      debugPrint('AI refine [${isGroq ? "Groq" : "HF"}] ${DateTime.now().difference(started).inMilliseconds}ms '
          '-> ${plates.map((p) => p.fullPlate).toList()}');
      return plates;
    } on TimeoutException {
      debugPrint('AI refine timeout (${isGroq ? "Groq" : "HF"})');
      return null;
    } catch (e) {
      debugPrint('AI refine error (${isGroq ? "Groq" : "HF"}): $e');
      return null;
    }
  }

  Future<List<ParsedPlateData>> refine(String rawTranscript) async {
    await _ensureInit();
    if (!isEnabled) return const [];
    final bounded = _trimToRecentTail(rawTranscript);
    final key = ArabicVoiceNormalizer.normalizeArabicSpoken(bounded);
    if (key.isEmpty) return const [];

    final cached = _cache[key];
    if (cached != null) return cached;
    if (!_inFlight.add(key)) return const [];

    try {
      List<ParsedPlateData>? plates;
      if (usesGroq) {
        plates = await _queryProvider(
          url: _groqEndpoint,
          apiKey: effectiveGroqToken,
          modelName: _groqModel,
          input: bounded,
          isGroq: true,
        );
      }

      // Automatic fallback to Hugging Face Router if Groq failed/timed out or is unconfigured
      if (plates == null && kHuggingFaceToken.isNotEmpty) {
        plates = await _queryProvider(
          url: _hfEndpoint,
          apiKey: kHuggingFaceToken,
          modelName: _hfModel,
          input: bounded,
          isGroq: false,
        );
      }

      final finalPlates = plates ?? const <ParsedPlateData>[];
      if (plates != null) {
        if (_cache.length >= _maxCache) _cache.remove(_cache.keys.first);
        _cache[key] = finalPlates;
      }
      return finalPlates;
    } finally {
      _inFlight.remove(key);
    }
  }

  /// Strictly enforces EXACTLY 3 Arabic letters + 3-4 digits (padding 3 digits with trailing '0').
  List<ParsedPlateData> _parse(String content, {bool allowNote = true}) {
    List<dynamic> raw = const [];
    final arrStart = content.indexOf('[');
    final arrEnd = content.lastIndexOf(']');
    if (arrStart != -1 && arrEnd > arrStart) {
      try {
        raw = jsonDecode(content.substring(arrStart, arrEnd + 1)) as List<dynamic>;
      } catch (_) {}
    } else {
      final objStart = content.indexOf('{');
      final objEnd = content.lastIndexOf('}');
      if (objStart != -1 && objEnd > objStart) {
        try {
          final obj = jsonDecode(content.substring(objStart, objEnd + 1));
          if (obj is Map) raw = [obj];
        } catch (_) {}
      }
    }
    if (raw.isEmpty) return const [];

    final out = <ParsedPlateData>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final lettersRaw = ArabicVoiceNormalizer.normalizePlateForMatch('${item['letters'] ?? ''}');
      final digitsRaw = ArabicVoiceNormalizer.normalizePlateForMatch('${item['digits'] ?? ''}');
      // Strictly 3 Arabic letters only (never 2, never 4)
      if (!RegExp(r'^[ا-ي]{3}$').hasMatch(lettersRaw)) continue;
      if (!RegExp(r'^\d{3,4}$').hasMatch(digitsRaw)) continue;

      final finalDigits = digitsRaw.length == 3 ? '${digitsRaw}0' : digitsRaw;
      final letters = lettersRaw.split('').join(' ');
      final brand = '${item['brand'] ?? ''}'.trim();
      final rawNote = allowNote ? '${item['note'] ?? ''}'.trim() : '';
      final isOnlyLetters = RegExp(r'^[ا-ي](?:\s+[ا-ي])*$').hasMatch(rawNote);
      final note = (rawNote.isEmpty || isOnlyLetters) ? '' : rawNote;

      out.add(ParsedPlateData(
        fullPlate: '$letters $finalDigits',
        letters: letters,
        digits: finalDigits,
        detectedBrand: brand.isEmpty ? '-' : brand,
        detectedNote: note.isEmpty ? '-' : note,
        isComplete: true,
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
          if (candidate.isNotEmpty) 'reasoning_effort': 'none',
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
          message: 'الاتصال ناجح ومحرك Groq LPU ($md) جاهز للعمل!',
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
