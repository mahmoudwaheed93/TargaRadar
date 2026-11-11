import '../../core/services/location_service.dart';
import '../../data/models/excel_vehicle_model.dart';
import '../../core/utils/date_formatter.dart';
import 'dart:async';
import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
import '../../core/services/arabic_voice_normalizer.dart';
import '../../core/services/excel_table_service.dart';
import '../../core/services/speech_service.dart';

/// One plate heard during an inspection session.
class InspectionEntry {
  final String id;
  final String plate;
  final String key;
  final String time;
  final bool inSheet;
  final Map<String, String> rowData; // full row from the reference sheet
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

/// Inspection ("الفحص"): a big reference sheet is loaded once; every plate that
/// is spoken goes into a NEW session list (exported as a new Excel). If the
/// plate exists in the reference sheet its whole row is shown and the
/// inspection of that plate can be cancelled.
class InspectionProvider extends ChangeNotifier {
  final SpeechService _speech = SpeechService.instance;
  final ExcelTableService _tables = ExcelTableService.instance;

  ExcelTable? _table;
  final Map<String, int> _index = {};
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
  Timer? _incompletePlateTimer;
  VoidCallback? _pendingIncompletePlate;
  DateTime? _lastIngestedAt;

  void _flushPendingIncompletePlate() {
    _incompletePlateTimer?.cancel();
    final flush = _pendingIncompletePlate;
    _pendingIncompletePlate = null;
    if (flush != null) flush();
  }
  String? _lastKey;
  int _orphanSession = -1;
  String? _orphanTarget;
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

  /// Browse the phone for the big reference sheet and load it.
  Future<bool> pickReferenceFile() async {
    _loadingFile = true;
    _error = null;
    notifyListeners();
    try {
      final picked = await _tables.pickExcelFile();
      if (picked == null) return false;
      // Heavy files are read by a worker isolate straight from disk.
      final table = await _tables.parse(picked);
      if (table.rows.isEmpty) {
        _error = 'الملف فارغ أو غير متوافق (لازم يكون .xlsx وفيه عمود لرقم اللوحة)';
        return false;
      }
      _table = table;
      _refFileName = picked.name;
      _index.clear();
      for (int i = 0; i < table.rows.length; i++) {
        final k = ArabicVoiceNormalizer.plateKey(table.rows[i][table.plateCol]);
        if (k.isNotEmpty) _index.putIfAbsent(k, () => i);
      }
      // Re-check plates already heard against the newly loaded sheet.
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
      if (data.containsKey(h)) h = '$h (${c + 1})'; // keep one value per column
      data[h] = row[c];
    }
    return data;
  }

  /// A note spoken alone ("ملحوظة ...") goes to the plate heard just before.
  void _handleOrphanNote(String? note, int session) {
    if (note == null) return;
    _handleOrphanData(OrphanVoiceData(note: note), session);
  }

  void _handleOrphanData(OrphanVoiceData data, int session) {
    if (!data.hasData || _entries.isEmpty) return;
    final note = data.note;
    if (note != null && note != '-' && note.isNotEmpty) {
      if (session != _orphanSession) {
        _orphanSession = session;
        _orphanTarget = _lastKey;
      }
      final key = _orphanTarget ?? _lastKey;
      if (key == null) return;
      final i = _entries.indexWhere((e) => e.key == key);
      if (i != -1 && _entries[i].note != note) {
        _entries[i] = _entries[i].copyWith(note: note);
        notifyListeners();
      }
    }
  }

  
  void _ingestInspectionPlate(ParsedPlateData p, void Function(InspectionEntry entry) onMatch) {
    final key = ArabicVoiceNormalizer.plateKey(p.fullPlate);
    // In Inspection mode, inspectors only speak plate numbers. Never record voice notes.
    const note = '';

    if (_seen.contains(key)) {
      // The note is spoken after the plate -> goes to the note only.
      final i = _entries.indexWhere((e) => e.key == key);
      if (i != -1 && note.isNotEmpty && _entries[i].note != note) {
        _entries[i] = _entries[i].copyWith(note: note);
        notifyListeners();
      }
      return;
    }

    // In-place upgrade defense: handles both digit extensions and trailing letter extensions
    if (_entries.isNotEmpty &&
        _lastIngestedAt != null &&
        DateTime.now().difference(_lastIngestedAt!).inSeconds <= 5) {
      final prev = _entries.first;
      if (ArabicVoiceNormalizer.isPlateUpgrade(prev.plate, p.fullPlate)) {
        _seen.remove(prev.key);
        _seen.add(key);
        _lastKey = key;
        _lastIngestedAt = DateTime.now();
        final row = _rowFor(key);
        final updated = InspectionEntry(
          id: prev.id,
          plate: p.fullPlate,
          key: key,
          time: prev.time,
          inSheet: row != null,
          rowData: row ?? const {},
          note: note.isNotEmpty ? note : prev.note,
          gpsUrl: prev.gpsUrl,
        );
        _entries[0] = updated;
        if (updated.inSheet && !prev.inSheet) onMatch(updated);
        notifyListeners();
        return;
      }
    }

    _seen.add(key);
    _lastKey = key;
    _lastIngestedAt = DateTime.now();

    final row = _rowFor(key);
    final now = DateTime.now();
    final entry = InspectionEntry(
      id: 'insp-${now.microsecondsSinceEpoch}',
      plate: p.fullPlate,
      key: key,
      time: AppDateFormatter.time12(now),
      inSheet: row != null,
      rowData: row ?? const {},
      note: note,
      gpsUrl: _lastKnownLocation?.gpsUrl ?? '',
    );
    _entries.insert(0, entry);
    if (entry.inSheet) onMatch(entry);
    notifyListeners();
  }

  Future<void> startListening({required void Function(InspectionEntry entry) onMatch}) async {
    unawaited(_refreshLocation());
    if (_isListening) return;
    _orphanSession = -1;
    _isListening = true;
    _timer = 0;
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      _timer++;
      notifyListeners();
    });
    notifyListeners();

    await _speech.startListening(
      onOrphanNote: _handleOrphanNote,
      onOrphanData: _handleOrphanData,
      onResult: (raw, plates, slots, normalized) {
        if (slots.isNotEmpty) {
          _slots = slots;
        }

        // 1. Process all completed plates immediately (zero wait)
        final completePlates = plates.where((p) => p.isComplete).toList();
        for (final p in completePlates) {
          _ingestInspectionPlate(p, onMatch);
        }

        // 2. Debounce trailing incomplete plate (e.g. 2-letter digits-first or <4 digits)
        _incompletePlateTimer?.cancel();
        _pendingIncompletePlate = null;
        if (plates.isNotEmpty && !plates.last.isComplete) {
          final pending = plates.last;
          _pendingIncompletePlate = () => _ingestInspectionPlate(pending, onMatch);
          _incompletePlateTimer = Timer(const Duration(milliseconds: 650), () {
            final flush = _pendingIncompletePlate;
            _pendingIncompletePlate = null;
            if (!_isListening || flush == null) return;
            flush();
            notifyListeners();
          });
        }

        notifyListeners();
      },
      onDone: () {
        _flushPendingIncompletePlate();
        _isListening = false;
        _ticker?.cancel();
        notifyListeners();
      },
    );
  }

    /// Process text input containing plate numbers (e.g. from a text box)
  int processTextPlates(List<String> plates, {required void Function(InspectionEntry entry) onMatch}) {
    int matchedCount = 0;
    for (final raw in plates) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) continue;
      final key = ArabicVoiceNormalizer.plateKey(trimmed);
      if (key.isEmpty || _seen.contains(key)) continue;

      _seen.add(key);
      _lastKey = key;

      final row = _rowFor(key);
      final now = DateTime.now();
      final entry = InspectionEntry(
        id: 'insp-${DateTime.now().microsecondsSinceEpoch}-$key',
        plate: trimmed,
        key: key,
        time: AppDateFormatter.time12(now),
        inSheet: row != null,
        rowData: row ?? const {},
        note: '',
        gpsUrl: _lastKnownLocation?.gpsUrl ?? '',
      );
      _entries.insert(0, entry);
      if (entry.inSheet) {
        matchedCount++;
        onMatch(entry);
      }
    }
    notifyListeners();
    return matchedCount;
  }

  Future<void> stopListening() async {
    _flushPendingIncompletePlate();
    await _speech.stopListening();
    _isListening = false;
    _ticker?.cancel();
    _timer = 0;
    notifyListeners();
  }

  /// "كنسل الفرزة" — the plate stays visible but is excluded from the export.
  void setCancelled(String id, bool cancelled) {
    final i = _entries.indexWhere((e) => e.id == id);
    if (i == -1) return;
    _entries[i] = _entries[i].copyWith(cancelled: cancelled);
    notifyListeners();
  }

  void removeEntry(String id) {
    final i = _entries.indexWhere((e) => e.id == id);
    if (i == -1) return;
    _seen.remove(_entries[i].key);
    _entries.removeAt(i);
    notifyListeners();
  }

  void clearSession() {
    _entries.clear();
    _seen.clear();
    notifyListeners();
  }

  /// Writes the session into a NEW Excel file. Plates found in the reference
  /// sheet carry all of their original columns.
  Future<String?> exportSession(String recorderName) async {
    final active = _entries.where((e) => !e.cancelled).toList().reversed.toList();
    if (_entries.isEmpty) return null;

    final excel = Excel.createExcel();
    const name = 'الفحص';
    final def = excel.getDefaultSheet();
    if (def != null) excel.rename(def, name);
    final ws = excel[name];

    // Reference sheet headers + Location + Standard columns
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

      // Retrieve location URL: live GPS or from reference sheet rowData
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
    _ticker?.cancel();
    super.dispose();
  }
}
