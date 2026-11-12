import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Debug-only high-resolution voice recognition & parser telemetry logger.
/// Completely no-ops in release builds (`!kDebugMode`) to keep zero runtime overhead.
/// Writes replayable JSONL fixtures to `<appDocumentsDir>/voice_telemetry.jsonl`.
class VoiceTelemetryLogger {
  VoiceTelemetryLogger._();
  static final VoiceTelemetryLogger instance = VoiceTelemetryLogger._();

  static final RegExp _digitTailRegex = RegExp(r'\d{3,4}');

  final List<String> _buffer = [];
  int? _lastSessionStopUs;
  int? _lastDigitPartialAtUs;
  String? _pendingDigitPlateKey;
  IOSink? _sink;
  String? _logFilePath;
  bool _initializing = false;

  String? get logFilePath => _logFilePath;
  List<String> get bufferedLines => List.unmodifiable(_buffer);

  Future<void> _ensureSink() async {
    if (!kDebugMode || kIsWeb || _sink != null || _initializing) return;
    _initializing = true;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final path = p.join(dir.path, 'voice_telemetry.jsonl');
      _logFilePath = path;
      _sink = File(path).openWrite(mode: FileMode.append);
      if (_buffer.isNotEmpty) {
        for (final line in _buffer) {
          _sink!.writeln(line);
        }
      }
    } catch (_) {
      // Ignore file IO failures inside headless unit tests or restricted environments.
    } finally {
      _initializing = false;
    }
  }

  void _record(Map<String, dynamic> event) {
    if (!kDebugMode) return;
    event['tsUs'] = DateTime.now().microsecondsSinceEpoch;
    final line = jsonEncode(event);
    _buffer.add(line);
    if (_buffer.length > 500) {
      _buffer.removeAt(0);
    }
    if (_sink != null) {
      try {
        _sink!.writeln(line);
      } catch (_) {}
    } else {
      unawaited(_ensureSink());
    }
  }

  void logSessionStart(int session, {bool onDevice = false, String? localeId}) {
    if (!kDebugMode) return;
    final nowUs = DateTime.now().microsecondsSinceEpoch;
    final gapMs = _lastSessionStopUs != null
        ? ((nowUs - _lastSessionStopUs!) / 1000.0).toStringAsFixed(2)
        : null;
    _record({
      'type': 'session_start',
      'session': session,
      'onDevice': onDevice,
      if (localeId != null) 'locale': localeId,
      if (gapMs != null) 'gapMs': double.parse(gapMs),
    });
  }

  void logSessionTermination({
    required int session,
    required String kind, // 'status' or 'error'
    required String detail,
    bool? permanent,
  }) {
    if (!kDebugMode) return;
    _lastSessionStopUs = DateTime.now().microsecondsSinceEpoch;
    _record({
      'type': 'session_term',
      'session': session,
      'kind': kind,
      'detail': detail,
      if (permanent != null) 'permanent': permanent,
    });
  }

  void logPartialNormalized({
    required int session,
    required List<String> candidates,
    required List<double> confidences,
    required bool isFinal,
    required int normMatchUs,
    required List<String> extractedPlates,
    String? activeTailKey,
  }) {
    if (!kDebugMode) return;
    final nowUs = DateTime.now().microsecondsSinceEpoch;
    final hasNewDigitTail = extractedPlates.isNotEmpty ||
        (activeTailKey != null && _digitTailRegex.hasMatch(activeTailKey));
    if (hasNewDigitTail) {
      final candidateKey = extractedPlates.isNotEmpty
          ? extractedPlates.last
          : (activeTailKey ?? '');
      if (candidateKey != _pendingDigitPlateKey) {
        _pendingDigitPlateKey = candidateKey;
        _lastDigitPartialAtUs = nowUs;
      }
    }
    _record({
      'type': 'partial',
      'session': session,
      'isFinal': isFinal,
      'candidates': candidates,
      if (confidences.isNotEmpty) 'confidences': confidences,
      'normMatchMs': double.parse((normMatchUs / 1000.0).toStringAsFixed(3)),
      'plates': extractedPlates,
    });
  }

  void logPlateCommitted(String plate, {String source = 'local'}) {
    if (!kDebugMode) return;
    final nowUs = DateTime.now().microsecondsSinceEpoch;
    final latencyMs = _lastDigitPartialAtUs != null
        ? ((nowUs - _lastDigitPartialAtUs!) / 1000.0)
        : 0.0;
    _lastDigitPartialAtUs = null;
    _pendingDigitPlateKey = null;
    _record({
      'type': 'plate_commit',
      'plate': plate,
      'source': source,
      'commitLatencyMs': double.parse(latencyMs.toStringAsFixed(2)),
    });
  }

  /// Parses JSONL telemetry lines back into replayable `(candidates, isFinal)` fixtures.
  static List<({List<String> candidates, bool isFinal})> parseReplayFixtures(String jsonl) {
    final fixtures = <({List<String> candidates, bool isFinal})>[];
    for (final rawLine in const LineSplitter().convert(jsonl)) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final decoded = jsonDecode(line);
      if (decoded is Map<String, dynamic> && decoded['type'] == 'partial') {
        final cands = (decoded['candidates'] as List?)?.map((e) => e.toString()).toList() ?? const [];
        if (cands.isNotEmpty) {
          fixtures.add((candidates: cands, isFinal: decoded['isFinal'] == true));
        }
      }
    }
    return fixtures;
  }

  void resetForTest() {
    _buffer.clear();
    _lastSessionStopUs = null;
    _lastDigitPartialAtUs = null;
    _pendingDigitPlateKey = null;
  }
}
