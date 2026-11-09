import '../../core/utils/date_formatter.dart';
import 'dart:async';
import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
import '../../core/services/arabic_voice_normalizer.dart';
import '../../core/services/excel_table_service.dart';
import '../../core/services/speech_service.dart';
import '../../data/models/excel_vehicle_model.dart';

class InspectionEntry {
  final String id;
  final String plate;
  final String key;
  final String time;
  final bool inSheet;
  final Map<String, String> rowData;
  final String note;
  final bool cancelled;

  const InspectionEntry({
    required this.id,
    required this.plate,
    required this.key,
    required this.time,
    required this.inSheet,
    required this.rowData,
    required this.note,
    this.cancelled = false,
  });

  InspectionEntry copyWith({
    String? plate,
    String? key,
    bool? inSheet,
    Map<String, String>? rowData,
    String? note,
    bool? cancelled,
  }) =>
      InspectionEntry(
        id: id,
        plate: plate ?? this.plate,
        key: key ?? this.key,
        time: time,
        inSheet: inSheet ?? this.inSheet,
        rowData: rowData ?? this.rowData,
        note: note ?? this.note,
        cancelled: cancelled ?? this.cancelled,
      );
}

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
  Timer? _tailSettleTimer;
  ParsedPlateData? _pendingTailPlate;

  String? _lastKey;
  String? _lastLettersKey;
  String? _lastDigits;
  int _orphanSession = -1;
  String? _orphanTarget;
  Map<String, String> _slots = {
    'l1': '-', 'l2': '-', 'l3': '-',
    'd1': '-', 'd2': '-', 'd3': '-', 'd4': '-',
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

  Future<bool> pickReferenceFile() async {
    _loadingFile = true;
    _error = null;
    notifyListeners();
    try {
      final picked = await _tables.pickExcelFile();
      if (picked == null) return false;
      final table = await _tables.parse(picked);
      if (table.rows.isEmpty) {
        _error = 'الملف فارغ أو غير متوافق (لازم يكون .xlsx وليه عمود لرقم اللوحة)';
        return false;
      }
      _table = table;
      _refFileName = picked.name;
      _index.clear();
      for (int i = 0; i < table.rows.length; i++) {
        final k = ArabicVoiceNormalizer.plateKey(table.rows[i][table.plateCol]);
        if (k.isNotEmpty) _index.putIfAbsent(k, () => i);
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
        );
      }
      return true;
    } catch (e) {
      _error = 'فشل فتح/قراءة الملف: $e';
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

  void _handleOrphanNote(String? note, int session) {
    if (note == null) return;
    if (session != _orphanSession) {
      _orphanSession = session;
      _orphanTarget = _lastKey;
    }
    final key = _orphanTarget;
    if (key == null) return;
    final i = _entries.indexWhere((e) => e.key == key);
    if (i == -1 || _entries[i].note == note) return;
    _entries[i] = _entries[i].copyWith(note: note);
    notifyListeners();
  }

  void _commitInspectionPlate(
    ParsedPlateData p,
    void Function(InspectionEntry entry) onMatch,
  ) {
    final key = ArabicVoiceNormalizer.plateKey(p.fullPlate);
    if (key.isEmpty) return;
    final lettersKey = ArabicVoiceNormalizer.plateKey(p.letters);
    final note = p.detectedNote != '-' ? p.detectedNote : '';

    if (_seen.contains(key)) {
      final i = _entries.indexWhere((e) => e.key == key);
      if (i != -1 && note.isNotEmpty && _entries[i].note != note) {
        _entries[i] = _entries[i].copyWith(note: note);
        notifyListeners();
      }
      return;
    }

    // In-place prefix upgrade if user paused mid-plate
    if (_lastKey != null &&
        _lastLettersKey == lettersKey &&
        _lastDigits != null &&
        _lastDigits!.length < p.digits.length &&
        p.digits.startsWith(_lastDigits!) &&
        _entries.isNotEmpty) {
      final oldKey = _lastKey!;
      _seen.remove(oldKey);
      _seen.add(key);
      _lastKey = key;
      _lastDigits = p.digits;

      final row = _rowFor(key);
      final upgraded = _entries.first.copyWith(
        plate: p.fullPlate,
        key: key,
        inSheet: row != null,
        rowData: row ?? const {},
        note: note.isNotEmpty ? note : _entries.first.note,
      );
      _entries[0] = upgraded;
      if (upgraded.inSheet) onMatch(upgraded);
      notifyListeners();
      return;
    }

    _seen.add(key);
    _lastKey = key;
    _lastLettersKey = lettersKey;
    _lastDigits = p.digits;

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
    );
    _entries.insert(0, entry);
    if (entry.inSheet) onMatch(entry);
    notifyListeners();
  }

  Future<void> startListening({
    required void Function(InspectionEntry entry) onMatch,
  }) async {
    if (_isListening) return;
    _orphanSession = -1;
    _isListening = true;
    _timer = 0;
    _pendingTailPlate = null;
    _tailSettleTimer?.cancel();
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      _timer++;
    });
    notifyListeners();

    await _speech.startListening(
      onOrphanNote: _handleOrphanNote,
      onResult: (raw, plates, slots, normalized) {
        _slots = slots;
        // 0ms Ultra-Fast Instant Ingestion on Mic 2 (Inspection Mic):
        // Every plate commits in 0ms and upgrades in-place as digits complete (28 -> 281 -> 2816).
        for (int i = 0; i < plates.length; i++) {
          _commitInspectionPlate(plates[i], onMatch);
        }
        notifyListeners();
      },
      onDone: () {
        final tail = _pendingTailPlate;
        _tailSettleTimer?.cancel();
        if (tail != null) {
          _pendingTailPlate = null;
          _commitInspectionPlate(tail, onMatch);
        }
        _isListening = false;
        _ticker?.cancel();
        notifyListeners();
      },
    );
  }

  int processTextPlates(
    List<String> plates, {
    required void Function(InspectionEntry entry) onMatch,
  }) {
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
    _tailSettleTimer?.cancel();
    _pendingTailPlate = null;
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
    _lastKey = null;
    _lastLettersKey = null;
    _lastDigits = null;
    notifyListeners();
  }

  Future<String?> exportSession({String recorderName = ''}) async {
    final active = _entries.where((e) => !e.cancelled).toList();
    if (active.isEmpty) return null;

    final excel = Excel.createExcel();
    final sheetName = excel.sheets.keys.first;
    final ws = excel[sheetName];

    final extraHeaders = _table?.headers ?? const [];
    final headers = <String>[
      'م',
      'رقم اللوحة',
      'الحالة',
      'ملحوظات',
      'الوقت',
      'اسم المسجل',
      ...extraHeaders,
    ];

    ws.appendRow(headers.map((h) => TextCellValue(h)).toList());

    for (int i = 0; i < active.length; i++) {
      final e = active[i];
      final row = <CellValue>[
        IntCellValue(i + 1),
        TextCellValue(e.plate),
        TextCellValue(e.inSheet ? 'موجود باللوحة المرجعية' : 'غير موجود باللوحة المرجعية'),
        TextCellValue(e.note),
        TextCellValue(e.time),
        TextCellValue(recorderName),
      ];
      for (final h in extraHeaders) {
        row.add(TextCellValue(e.rowData[h] ?? ''));
      }
      ws.appendRow(row);
    }

    final cancelled = _entries.where((e) => e.cancelled).toList();
    if (cancelled.isNotEmpty) {
      final ws2 = excel['الفحصات_الملغاة'];
      ws2.appendRow([
        TextCellValue('رقم اللوحة'),
        TextCellValue('الوقت'),
        TextCellValue('ملحوظات'),
      ]);
      for (final e in cancelled) {
        ws2.appendRow([
          TextCellValue(e.plate),
          TextCellValue(e.time),
          TextCellValue(e.note),
        ]);
      }
    }

    return _tables.saveWorkbook(excel, 'Saqr_Al_Mamlaka_الفحص');
  }
}
