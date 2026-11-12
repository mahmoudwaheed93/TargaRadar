import 'dart:async';
import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
import '../../core/services/ai_plate_refiner.dart';
import '../../core/services/arabic_voice_normalizer.dart';
import '../../core/services/excel_table_service.dart';
import '../../core/services/location_service.dart';
import '../../core/services/sound_alert_service.dart';
import '../../core/services/speech_service.dart';
import '../../core/services/voice_telemetry_logger.dart';
import '../../core/utils/date_formatter.dart';

/// One plate heard during an inspection session.
class InspectionEntry {
  final String id;
  final String plate;
  final String key;
  final String time;
  final bool inSheet;
  final Map<String, String> rowData;
  final String note;
  final bool cancelled;
  final String gpsUrl;

  const InspectionEntry({
    required this.id,
    required this.plate,
    required this.key,
    required this.time,
    required this.inSheet,
    required this.rowData,
    required this.note,
    this.cancelled = false,
    this.gpsUrl = '',
  });

  InspectionEntry copyWith({String? note, bool? cancelled, String? gpsUrl}) => InspectionEntry(
        id: id,
        plate: plate,
        key: key,
        time: time,
        inSheet: inSheet,
        rowData: rowData,
        note: note ?? this.note,
        cancelled: cancelled ?? this.cancelled,
        gpsUrl: gpsUrl ?? this.gpsUrl,
      );
}

/// Inspection ("الفحص"): plates-only live lookup against a large reference sheet.
class InspectionProvider extends ChangeNotifier {
  final SpeechService _speech = SpeechService.instance;
  final ExcelTableService _tables = ExcelTableService.instance;

  String _currentUserId = '';
  ExcelTable? _table;
  final Map<String, int> _index = {};
  final Map<String, List<int>> _byDigits = {};
  String _refFileName = '';
  bool _loadingFile = false;
  String? _error;

  final List<InspectionEntry> _entries = [];
  final Set<String> _seen = {};
  bool _isListening = false;
  int _timer = 0;
  Timer? _ticker;
  LocationDetails? _lastKnownLocation;
  bool _locRefreshing = false;
  DateTime? _locAt;

  Timer? _incompletePlateTimer;
  Timer? _aiTimer;
  static const Duration _aiDebounce = Duration(milliseconds: 250);
  static const Duration _threeDigitCloseDebounce = Duration(milliseconds: 160);
  VoidCallback? _pendingIncompletePlate;
  DateTime? _lastIngestedAt;
  String _lastProcessedTranscript = '';
  final PlateUtteranceStitcher _stitcher = PlateUtteranceStitcher();
  String _currentTranscript = '';
  String get currentTranscript => _currentTranscript;
  int _entriesVersion = 0;
  int get entriesVersion => _entriesVersion;

  String? _lastKey;
  Map<String, String> _slots = {
    'l1': '-', 'l2': '-', 'l3': '-', 'd1': '-', 'd2': '-', 'd3': '-', 'd4': '-',
  };

  bool get hasReference => _table != null;
  String get refFileName => _refFileName;
  int get refCount => _table?.rows.length ?? 0;
  bool get loadingFile => _loadingFile;
  String? get error => _error;
  List<InspectionEntry> get entries => _entries;
  bool get isListening => _isListening;
  int get listeningSeconds => _timer;
  Map<String, String> get slots => _slots;

  int get totalCount => _entries.length;
  int get foundCount => _entries.where((e) => e.inSheet && !e.cancelled).length;
  int get notFoundCount => _entries.where((e) => !e.inSheet && !e.cancelled).length;
  int get cancelledCount => _entries.where((e) => e.cancelled).length;

  /// Scopes in-memory inspection session to the signed-in user so switching accounts
  /// never leaks the previous user's reference table or inspection records.
  Future<void> setCurrentUserId(String uid) async {
    if (_currentUserId == uid) return;
    _currentUserId = uid;
    await resetSession();
  }

  Future<void> resetSession() async {
    if (_isListening) await stopListening();
    _table = null;
    _index.clear();
    _byDigits.clear();
    _refFileName = '';
    _error = null;
    _entries.clear();
    _seen.clear();
    _lastKey = null;
    _lastIngestedAt = null;
    _lastProcessedTranscript = '';
    _stitcher.reset();
    _currentTranscript = '';
    _slots = {'l1': '-', 'l2': '-', 'l3': '-', 'd1': '-', 'd2': '-', 'd3': '-', 'd4': '-'};
    _entriesVersion++;
    notifyListeners();
  }

  Future<void> _refreshLocation() async {
    if (_locRefreshing) return;
    final at = _locAt;
    if (at != null && DateTime.now().difference(at).inSeconds < 60) return;
    _locRefreshing = true;
    try {
      final l = await LocationService.instance.getCurrentLocationDetails();
      if (l != null) {
        _lastKnownLocation = l;
        _locAt = DateTime.now();
      }
    } catch (e) {
      debugPrint('Location refresh error in inspection: $e');
    } finally {
      _locRefreshing = false;
    }
  }

  void _flushPendingIncompletePlate() {
    _incompletePlateTimer?.cancel();
    final flush = _pendingIncompletePlate;
    _pendingIncompletePlate = null;
    if (flush != null) flush();
  }

  Future<bool> pickReferenceFile() async {
    _loadingFile = true;
    _error = null;
    notifyListeners();
    try {
      final picked = await _tables.pickExcelFile();
      if (picked == null) return false;
      final table = await _tables.parse(picked);
      if (table.rows.isEmpty) {
        _error = 'الملف فارغ أو غير متوافق (لازم يكون .xlsx وفيه عمود لرقم اللوحة)';
        return false;
      }
      _table = table;
      _refFileName = picked.name;
      _index.clear();
      _byDigits.clear();
      for (int i = 0; i < table.rows.length; i++) {
        final k = ArabicVoiceNormalizer.plateKey(table.rows[i][table.plateCol]);
        if (k.isNotEmpty) {
          _index.putIfAbsent(k, () => i);
          final d = k.replaceAll(RegExp(r'[^\d]'), '');
          if (d.length >= 3) {
            _byDigits.putIfAbsent(d, () => <int>[]).add(i);
          }
        }
      }
      for (int i = 0; i < _entries.length; i++) {
        final e = _entries[i];
        final row = _rowFor(e.key);
        _entries[i] = InspectionEntry(
          id: e.id,
          plate: e.plate,
          key: e.key,
          time: e.time,
          inSheet: row != null,
          rowData: row ?? const {},
          note: e.note,
          cancelled: e.cancelled,
          gpsUrl: e.gpsUrl,
        );
      }
      _entriesVersion++;
      return true;
    } catch (e) {
      _error = 'خطأ أثناء قراءة الملف: $e';
      return false;
    } finally {
      _loadingFile = false;
      notifyListeners();
    }
  }

  Map<String, String>? _rowFor(String key) {
    final t = _table;
    if (t == null) return null;
    final idx = _index[key];
    if (idx == null) return null;
    final row = t.rows[idx];
    final data = <String, String>{};
    for (int c = 0; c < t.headers.length; c++) {
      var h = t.headers[c].isEmpty ? 'عمود ${c + 1}' : t.headers[c];
      if (data.containsKey(h)) h = '$h (${c + 1})';
      data[h] = row[c];
    }
    return data;
  }

  void _ingestInspectionPlate(ParsedPlateData p, void Function(InspectionEntry entry) onMatch) {
    var key = ArabicVoiceNormalizer.plateKey(p.fullPlate);
    var resolvedPlate = p.fullPlate;
    if (key.isEmpty) return;

    // Digit-pivot phonetic rescue against the reference sheet
    if (_table != null && _index[key] == null) {
      final digits = key.replaceAll(RegExp(r'[^\d]'), '');
      if (digits.length >= 3) {
        final rescuedIdx = ArabicVoiceNormalizer.findPhoneticSheetMatchIndex(
          p.fullPlate,
          _byDigits[digits] ?? const [],
          (idx) => _table!.rows[idx][_table!.plateCol],
        );
        if (rescuedIdx != null) {
          resolvedPlate = _table!.rows[rescuedIdx][_table!.plateCol];
          key = ArabicVoiceNormalizer.plateKey(resolvedPlate);
        }
      }
    }

    if (_seen.contains(key)) {
      _lastKey = key;
      _lastIngestedAt = DateTime.now();
      return;
    }

    if (_entries.isNotEmpty &&
        _lastIngestedAt != null &&
        DateTime.now().difference(_lastIngestedAt!).inSeconds <= 5) {
      final prev = _entries.first;
      if (ArabicVoiceNormalizer.isPlateUpgrade(prev.plate, resolvedPlate)) {
        _seen.remove(prev.key);
        _seen.add(key);
        _lastKey = key;
        _lastIngestedAt = DateTime.now();
        final row = _rowFor(key);
        final updated = InspectionEntry(
          id: prev.id,
          plate: resolvedPlate,
          key: key,
          time: prev.time,
          inSheet: row != null,
          rowData: row ?? const {},
          note: '',
          gpsUrl: prev.gpsUrl,
        );
        _entries[0] = updated;
        _entriesVersion++;
        if (updated.inSheet && !prev.inSheet) onMatch(updated);
        notifyListeners();
        return;
      }
    }

    _seen.add(key);
    _lastKey = key;
    _lastIngestedAt = DateTime.now();
    VoiceTelemetryLogger.instance.logPlateCommitted(resolvedPlate, source: 'inspection');

    final row = _rowFor(key);
    final now = DateTime.now();
    final entry = InspectionEntry(
      id: 'insp-${now.microsecondsSinceEpoch}-$key',
      plate: resolvedPlate,
      key: key,
      time: AppDateFormatter.time12(now),
      inSheet: row != null,
      rowData: row ?? const {},
      note: '',
      gpsUrl: _lastKnownLocation?.gpsUrl ?? '',
    );
    _entries.insert(0, entry);
    _entriesVersion++;
    if (entry.inSheet) onMatch(entry);
    notifyListeners();
  }

  Future<void> startListening({required void Function(InspectionEntry entry) onMatch}) async {
    unawaited(_refreshLocation());
    unawaited(SoundAlertService.instance.warmUp());
    if (_isListening) return;
    _isListening = true;
    _currentTranscript = '';
    _lastProcessedTranscript = '';
    _stitcher.reset();
    _timer = 0;
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      _timer++;
      notifyListeners();
    });
    notifyListeners();

    await _speech.startListening(
      // Inspection mode strictly tracks plates only (never voice notes)
      onResult: (raw, plates, slots, normalized, isFinal) {
        if (raw.length < _lastProcessedTranscript.length) {
          _lastProcessedTranscript = '';
        }
        if (raw == _lastProcessedTranscript && !isFinal) return;
        _lastProcessedTranscript = isFinal ? '' : raw;

        final stitched = _stitcher.process(
          rawTranscript: raw,
          normalizedTranscript: normalized,
          rawPlates: plates,
          rawSlots: slots,
          isFinal: isFinal,
        );
        final effectiveNorm = stitched.normalized;
        final effectivePlates = stitched.plates;
        final effectiveSlots = stitched.slots;

        _currentTranscript = ArabicVoiceNormalizer.extractActiveTickerText(effectiveNorm, isFinal: isFinal);
        if (effectiveSlots.isNotEmpty) {
          _slots = effectiveSlots;
        }

        // 1. Immediate commit for finished 4-digit plates
        final completePlates = effectivePlates.where((p) => p.isComplete).toList();
        for (final p in completePlates) {
          _ingestInspectionPlate(p, onMatch);
        }

        // 2. Trailing 3-digit plate: wait 350ms for optional 4th digit; else pad '0' & close
        _incompletePlateTimer?.cancel();
        _pendingIncompletePlate = null;
        if (effectivePlates.isNotEmpty && !effectivePlates.last.isComplete) {
          final pending = effectivePlates.last;
          void commitThreeDigit() {
            final closed = ArabicVoiceNormalizer.finalizeThreeDigitPlate(pending);
            _ingestInspectionPlate(closed, onMatch);
            _slots = ArabicVoiceNormalizer.extractSlotsFromPlates([closed]);
            _stitcher.clearPending();
            _currentTranscript = '';
          }

          if (isFinal) {
            commitThreeDigit();
          } else {
            _pendingIncompletePlate = commitThreeDigit;
            _incompletePlateTimer = Timer(_threeDigitCloseDebounce, () {
              final flush = _pendingIncompletePlate;
              _pendingIncompletePlate = null;
              if (!_isListening || flush == null) return;
              flush();
              notifyListeners();
            });
          }
        }

        // 3. 0ms local Excel vowel-injected word rescue, else AI fallback on unparsed tail
        final unparsedTail = ArabicVoiceNormalizer.extractUnparsedTail(effectiveNorm);
        final rescuedFromSheet = (unparsedTail.isNotEmpty && _table != null)
            ? ArabicVoiceNormalizer.rescueUnparsedTailAgainstSheet(
                unparsedTail,
                (digits) => _byDigits[digits] ?? const [],
                (idx) => _table!.rows[idx][_table!.plateCol],
              )
            : null;
        if (rescuedFromSheet != null) {
          _aiTimer?.cancel();
          _ingestInspectionPlate(rescuedFromSheet, onMatch);
          _slots = ArabicVoiceNormalizer.extractSlotsFromPlates([rescuedFromSheet]);
          _stitcher.clearPending();
        } else {
          _scheduleAiFallback(raw, unparsedTail, onMatch);
        }

        notifyListeners();
      },
      onDone: () {
        _flushPendingIncompletePlate();
        _stitcher.reset();
        _isListening = false;
        _ticker?.cancel();
        notifyListeners();
      },
    );
  }

  /// Process text input containing plate numbers (supports 3-digit -> '0' padding)
  int processTextPlates(List<String> plates, {required void Function(InspectionEntry entry) onMatch}) {
    int matchedCount = 0;
    for (final raw in plates) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) continue;

      final parsed = ArabicVoiceNormalizer.extractPlatesFromTranscript(trimmed);
      if (parsed.isNotEmpty) {
        for (final p in parsed) {
          final closed = p.digits.length == 3
              ? ArabicVoiceNormalizer.finalizeThreeDigitPlate(p)
              : p;
          final k = ArabicVoiceNormalizer.plateKey(closed.fullPlate);
          final wasSeen = _seen.contains(k);
          _ingestInspectionPlate(closed, (entry) {
            if (!wasSeen) matchedCount++;
            onMatch(entry);
          });
        }
        continue;
      }

      final key = ArabicVoiceNormalizer.plateKey(trimmed);
      if (key.isEmpty || _seen.contains(key)) continue;

      _seen.add(key);
      _lastKey = key;
      _lastIngestedAt = DateTime.now();

      final row = _rowFor(key);
      final now = DateTime.now();
      final entry = InspectionEntry(
        id: 'insp-${now.microsecondsSinceEpoch}-$key',
        plate: trimmed,
        key: key,
        time: AppDateFormatter.time12(now),
        inSheet: row != null,
        rowData: row ?? const {},
        note: '',
        gpsUrl: _lastKnownLocation?.gpsUrl ?? '',
      );
      _entries.insert(0, entry);
      _entriesVersion++;
      if (entry.inSheet) {
        matchedCount++;
        onMatch(entry);
      }
    }
    notifyListeners();
    return matchedCount;
  }

  void _scheduleAiFallback(
    String rawTranscript,
    String unparsedTail,
    void Function(InspectionEntry entry) onMatch,
  ) {
    _aiTimer?.cancel();
    if (unparsedTail.isEmpty || !AiPlateRefiner.instance.isEnabled) return;
    final digitCount = RegExp(r'\d').allMatches(unparsedTail).length;
    if (digitCount < 3) return;
    final input = unparsedTail;
    _aiTimer = Timer(_aiDebounce, () async {
      final plates = await AiPlateRefiner.instance.refine(input);
      if (!_isListening) return;
      for (final p in plates) {
        _ingestInspectionPlate(p, onMatch);
      }
      if (plates.isNotEmpty) notifyListeners();
    });
  }

  Future<void> stopListening() async {
    _flushPendingIncompletePlate();
    _stitcher.reset();
    _aiTimer?.cancel();
    await _speech.stopListening();
    _isListening = false;
    _ticker?.cancel();
    _timer = 0;
    notifyListeners();
  }

  void setCancelled(String id, bool cancelled) {
    final i = _entries.indexWhere((e) => e.id == id);
    if (i == -1) return;
    _entries[i] = _entries[i].copyWith(cancelled: cancelled);
    _entriesVersion++;
    notifyListeners();
  }

  void removeEntry(String id) {
    final i = _entries.indexWhere((e) => e.id == id);
    if (i == -1) return;
    final removedKey = _entries[i].key;
    _seen.remove(removedKey);
    _entries.removeAt(i);
    if (_lastKey == removedKey) {
      _lastKey = _entries.isNotEmpty ? _entries.first.key : null;
      if (_entries.isEmpty) _lastIngestedAt = null;
    }
    _entriesVersion++;
    notifyListeners();
  }

  void clearSession() {
    _entries.clear();
    _seen.clear();
    _lastKey = null;
    _lastIngestedAt = null;
    _currentTranscript = '';
    _entriesVersion++;
    notifyListeners();
  }

  Future<String?> exportSession(String recorderName) async {
    final active = _entries.where((e) => !e.cancelled).toList().reversed.toList();
    if (_entries.isEmpty) return null;

    final excel = Excel.createExcel();
    const name = 'الفحص';
    final def = excel.getDefaultSheet();
    if (def != null) excel.rename(def, name);
    final ws = excel[name];

    final extraHeaders = _table?.headers ?? const [];
    final headers = <CellValue>[
      TextCellValue('م'),
      TextCellValue('رقم اللوحة'),
      TextCellValue('الحالة'),
      TextCellValue('ملاحظات'),
      TextCellValue('الوقت'),
      TextCellValue('اسم المسجّل'),
      TextCellValue('رابط الموقع (Google Maps)'),
      ...extraHeaders.map((h) => TextCellValue(h)),
    ];

    ws.appendRow(headers);

    for (int i = 0; i < active.length; i++) {
      final e = active[i];
      String locUrl = e.gpsUrl;
      if (locUrl.isEmpty) {
        for (final entry in e.rowData.entries) {
          final k = entry.key;
          final v = entry.value;
          if (k.contains('موقع') || k.contains('خريطة') || k.contains('خرائط') || k.toLowerCase().contains('gps') || v.contains('http') || v.contains('maps')) {
            if (v.isNotEmpty) {
              locUrl = v;
              break;
            }
          }
        }
      }
      if (locUrl.isEmpty) locUrl = '-';

      final row = <CellValue>[
        TextCellValue('${i + 1}'),
        TextCellValue(e.plate),
        TextCellValue(e.inSheet ? 'موجودة بالشيت' : 'غير موجودة بالشيت'),
        TextCellValue(e.note.isEmpty ? '-' : e.note),
        TextCellValue(e.time),
        TextCellValue(recorderName.isEmpty ? '-' : recorderName),
        TextCellValue(locUrl),
      ];

      for (final h in extraHeaders) {
        row.add(TextCellValue(e.rowData[h] ?? '-'));
      }
      ws.appendRow(row);
    }

    final cancelled = _entries.where((e) => e.cancelled).toList();
    if (cancelled.isNotEmpty) {
      final ws2 = excel['الفرزات_الملغاة'];
      ws2.appendRow([
        TextCellValue('رقم اللوحة'),
        TextCellValue('الوقت'),
        TextCellValue('رابط الموقع (Google Maps)'),
        TextCellValue('ملاحظات'),
      ]);
      for (final e in cancelled) {
        ws2.appendRow([
          TextCellValue(e.plate),
          TextCellValue(e.time),
          TextCellValue(e.gpsUrl.isNotEmpty ? e.gpsUrl : '-'),
          TextCellValue(e.note.isEmpty ? '-' : e.note),
        ]);
      }
    }

    return _tables.saveWorkbook(excel, 'Saqr_Al_Mamlaka_الفحص');
  }

  @override
  void dispose() {
    _isListening = false;
    _pendingIncompletePlate = null;
    _ticker?.cancel();
    _incompletePlateTimer?.cancel();
    _aiTimer?.cancel();
    _speech.stopListening();
    super.dispose();
  }
}
