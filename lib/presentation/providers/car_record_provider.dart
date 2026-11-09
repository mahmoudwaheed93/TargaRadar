import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/services/ai_plate_refiner.dart';
import '../../core/services/arabic_voice_normalizer.dart';
import '../../core/services/excel_export_service.dart';
import '../../core/services/location_service.dart';
import '../../core/services/speech_service.dart';
import '../../data/datasources/database_helper.dart';
import '../../data/models/car_record_model.dart';
import '../../data/models/excel_vehicle_model.dart';
import 'excel_sort_audit_provider.dart';

class CarRecordProvider extends ChangeNotifier {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final LocationService _locationService = LocationService.instance;
  final ExcelExportService _excelService = ExcelExportService.instance;
  final SpeechService _speechService = SpeechService.instance;

  List<CarRecord> _records = [];
  bool _isLoading = false;
  bool _isSaving = false;
  bool _isExporting = false;
  bool _isListening = false;
  String _currentTranscript = '';
  LocationDetails? _lastKnownLocation;

  String _lastReadPlate = '';
  bool _lastReadIsWanted = false;
  Map<String, String> _currentSlots = {
    'l1': '-', 'l2': '-', 'l3': '-',
    'd1': '-', 'd2': '-', 'd3': '-', 'd4': '-',
  };
  AuditedLogItem? _lastMatchResult;
  String _currentStreet = '';
  String _currentDistrict = '';
  String? _stickyNote;
  int _listeningTimer = 0;
  Timer? _timer;

  // Debounce timer for <4-digit tail plates & AI fallback
  Timer? _tailSettleTimer;
  ParsedPlateData? _pendingTailPlate;
  Timer? _aiTimer;
  static const Duration _aiDebounce = Duration(milliseconds: 300);
  static const Duration _tailSettleDelay = Duration(milliseconds: 260);

  final Set<String> _recordedPlates = {};
  final Map<String, int> _recordIds = {};
  final Map<String, String> _latestNote = {};

  /// O(1) reverse lookup: rowId → index in _records (avoids O(n) indexWhere)
  final Map<int, int> _rowIdToIndex = {};

  String? _lastKey;
  String? _lastLettersKey;
  String? _lastDigits;
  int _orphanSession = -1;
  String? _orphanTarget;

  bool _locRefreshing = false;
  DateTime? _locAt;

  static const String _recorderKeyBase = 'carlogix_recorder_name';
  String _recorderName = '';
  bool _recorderLoaded = false;
  String _currentUserId = '';

  // ── Digit-count regex reused across calls ────────────────────────────────
  static final RegExp _digitRx = RegExp(r'\d');

  String get recorderName => _recorderName;
  List<CarRecord> get records => _records;

  /// Computed getter — always fresh, no stale copies.
  List<CarRecord> get recentRecords => _records.take(10).toList();

  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  bool get isExporting => _isExporting;
  bool get isListening => _isListening;
  String get currentTranscript => _currentTranscript;
  LocationDetails? get lastKnownLocation => _lastKnownLocation;
  String get lastReadPlate => _lastReadPlate;
  bool get lastReadIsWanted => _lastReadIsWanted;
  Map<String, String> get currentSlots => _currentSlots;
  AuditedLogItem? get lastMatchResult => _lastMatchResult;
  String get currentStreet => _currentStreet;
  String get currentDistrict => _currentDistrict;
  String? get stickyNote => _stickyNote;
  int get listeningTimer => _listeningTimer;

  CarRecordProvider() {
    loadRecords();
  }

  String get _recorderKey => '${_recorderKeyBase}_$_currentUserId';

  Future<void> setCurrentUserId(String uid) async {
    _currentUserId = uid;
    _dbHelper.currentUserId = uid;
    _recordedPlates.clear();
    _recordIds.clear();
    _latestNote.clear();
    _rowIdToIndex.clear();
    _lastKey = null;
    _lastLettersKey = null;
    _lastDigits = null;
    _recorderLoaded = false;
    await _loadRecorderName();
    await loadRecords();
  }

  Future<void> ensureRecorderName(String? fallback) async {
    await _loadRecorderName();
    if (_recorderName.isEmpty && fallback != null && fallback.trim().isNotEmpty) {
      await setRecorderName(fallback.trim());
    }
  }

  Future<void> _loadRecorderName() async {
    if (_recorderLoaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final loaded = prefs.getString(_recorderKey) ?? '';
      _recorderLoaded = true;
      // Only notify when the value actually changed
      if (loaded != _recorderName) {
        _recorderName = loaded;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Failed to load recorder name: $e');
    }
  }

  Future<void> setRecorderName(String name) async {
    _recorderName = name.trim();
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_recorderKey, _recorderName);
    } catch (e) {
      debugPrint('Failed to save recorder name: $e');
    }
  }

  void setCurrentStreet(String street) {
    _currentStreet = street;
    notifyListeners();
  }

  void setCurrentDistrict(String district) {
    _currentDistrict = district;
    notifyListeners();
  }

  void setStickyNote(String? note) {
    _stickyNote = (note == null || note.trim().isEmpty) ? null : note.trim();
    notifyListeners();
  }

  Future<void> _refreshLocation() async {
    if (_locRefreshing) return;
    final at = _locAt;
    if (at != null && DateTime.now().difference(at).inSeconds < 60) return;
    _locRefreshing = true;
    try {
      final l = await _locationService.getCurrentLocationDetails();
      if (l != null) {
        _lastKnownLocation = l;
        _locAt = DateTime.now();
      }
    } catch (e) {
      debugPrint('Location refresh error: $e');
    } finally {
      _locRefreshing = false;
    }
  }

  void _handleOrphanNote(String? note, int session) {
    if (note == null) return;
    if (session != _orphanSession) {
      _orphanSession = session;
      _orphanTarget = _lastKey;
    }
    final key = _orphanTarget;
    if (key == null) return;
    if (_latestNote[key] == note) return;
    _latestNote[key] = note;
    _applyNoteUpdate(key);
  }

  Future<void> loadRecords() async {
    _isLoading = true;
    notifyListeners();
    try {
      _records = await _dbHelper.getAllCarRecords();
      // Rebuild O(1) reverse-index after full reload
      _rowIdToIndex.clear();
      for (int i = 0; i < _records.length; i++) {
        final id = _records[i].id;
        if (id != null) _rowIdToIndex[id] = i;
      }
    } catch (e) {
      debugPrint('Error loading records: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> toggleVoiceListening({
    required ExcelSortAuditProvider sortAuditProvider,
    required Function(String plate, bool isMatched, String carModel) onPlateAdded,
  }) async {
    if (_isListening) {
      await stopVoiceListening();
    } else {
      await startVoiceListening(
        sortAuditProvider: sortAuditProvider,
        onPlateAdded: onPlateAdded,
      );
    }
  }

  Future<void> startVoiceListening({
    required ExcelSortAuditProvider sortAuditProvider,
    required Function(String plate, bool isMatched, String carModel) onPlateAdded,
  }) async {
    if (_isListening) return;

    _isListening = true;
    _currentTranscript = '';
    _listeningTimer = 0;
    _orphanSession = -1;
    _pendingTailPlate = null;
    _tailSettleTimer?.cancel();
    notifyListeners();

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _listeningTimer++;
    });

    unawaited(_refreshLocation());

    await _speechService.startListening(
      onOrphanNote: _handleOrphanNote,
      onResult: (rawText, plates, slots, normalized) {
        bool uiChanged = false;
        if (_currentTranscript != rawText) {
          _currentTranscript = rawText;
          uiChanged = true;
        }
        if (_slotsDiffer(_currentSlots, slots)) {
          _currentSlots = slots;
          uiChanged = true;
        }

        if (normalized.contains('بدون لوحة') || normalized.contains('بدون لوحه')) {
          _stickyNote = 'بدون لوحة';
        }
        if (normalized.contains('انتهى') || normalized.contains('إنتهى')) {
          _stickyNote = null;
        }

        // 0ms Ultra-Fast Instant Ingestion on Mic 1:
        // Every plate is ingested immediately (0ms delay), and if the user continues
        // pronouncing the 3rd or 4th digit (e.g. 28 -> 281 -> 2816), _ingestPlate
        // upgrades the top row in-place in 0ms!
        for (int i = 0; i < plates.length; i++) {
          _ingestPlate(plates[i], sortAuditProvider, onPlateAdded);
        }

        if (plates.isEmpty) {
          _scheduleAiFallback(rawText, normalized, sortAuditProvider, onPlateAdded);
        } else {
          _aiTimer?.cancel();
        }

        if (uiChanged) {
          notifyListeners();
        }
      },
      onDone: () {
        final tail = _pendingTailPlate;
        _tailSettleTimer?.cancel();
        if (tail != null) {
          _pendingTailPlate = null;
          _ingestPlate(tail, sortAuditProvider, onPlateAdded);
        }
        _isListening = false;
        _timer?.cancel();
        notifyListeners();
      },
    );
  }

  bool _slotsDiffer(Map<String, String> a, Map<String, String> b) {
    for (final k in const ['l1', 'l2', 'l3', 'd1', 'd2', 'd3', 'd4']) {
      if (a[k] != b[k]) return true;
    }
    return false;
  }

  void _ingestPlate(
    ParsedPlateData plateData,
    ExcelSortAuditProvider sortAuditProvider,
    Function(String plate, bool isMatched, String carModel) onPlateAdded,
  ) {
    final norm = ArabicVoiceNormalizer.normalizePlateForMatch(plateData.fullPlate);
    if (norm.isEmpty) return;

    final lettersKey = ArabicVoiceNormalizer.normalizePlateForMatch(plateData.letters);
    final spokenNote = plateData.detectedNote != '-' ? plateData.detectedNote : null;

    if (_recordedPlates.contains(norm)) {
      if (spokenNote != null && spokenNote.isNotEmpty && _latestNote[norm] != spokenNote) {
        _latestNote[norm] = spokenNote;
        _applyNoteUpdate(norm);
      }
      return;
    }

    // In-place prefix upgrade: if the immediately preceding plate had the same letters
    // and shorter prefix digits (e.g. user paused between "281" and "6"), upgrade it!
    if (_lastKey != null &&
        _lastLettersKey == lettersKey &&
        _lastDigits != null &&
        _lastDigits!.length < plateData.digits.length &&
        plateData.digits.startsWith(_lastDigits!) &&
        _records.isNotEmpty) {
      final oldKey = _lastKey!;
      _recordedPlates.remove(oldKey);
      _recordedPlates.add(norm);
      _lastKey = norm;
      _lastDigits = plateData.digits;
      _lastReadPlate = plateData.fullPlate;

      final auditLog = sortAuditProvider.processAuditPlate(
        plateData.fullPlate,
        detectedBrand: plateData.detectedBrand,
        detectedNote: spokenNote ?? _stickyNote,
      );
      _lastMatchResult = auditLog;
      _lastReadIsWanted = auditLog.isMatched;

      final prev = _records.first;
      final upgraded = prev.copyWith(
        plateNumber: plateData.fullPlate,
        isMatched: auditLog.isMatched,
        carType: plateData.detectedBrand != '-'
            ? plateData.detectedBrand
            : (auditLog.carType.isNotEmpty && auditLog.carType != '-'
                ? auditLog.carType
                : prev.carType),
        color: auditLog.color,
        owner: auditLog.owner,
      );
      _records[0] = upgraded;
      // Rebuild rowIdToIndex entry for index 0 (prev id stays same until DB resolves)
      final prevId = prev.id;
      if (prevId != null) _rowIdToIndex[prevId] = 0;

      final oldRowId = _recordIds.remove(oldKey);
      // Chain delete → insert to avoid race condition
      if (oldRowId != null) {
        _rowIdToIndex.remove(oldRowId);
        unawaited(
          _dbHelper.deleteCarRecord(oldRowId).then((_) =>
            _dbHelper.insertCarRecord(upgraded).then((newId) {
              _recordIds[norm] = newId;
              // O(1) index lookup instead of O(n) indexOf
              final idx = _rowIdToIndex[prevId] ?? 0;
              _records[idx] = upgraded.copyWith(id: newId);
              _rowIdToIndex.remove(prevId);
              _rowIdToIndex[newId] = idx;
            }),
          ),
        );
      } else {
        unawaited(
          _dbHelper.insertCarRecord(upgraded).then((newId) {
            _recordIds[norm] = newId;
            _records[0] = upgraded.copyWith(id: newId);
            _rowIdToIndex[newId] = 0;
          }),
        );
      }

      if (auditLog.isMatched) {
        onPlateAdded(plateData.fullPlate, true, upgraded.carType);
      }
      notifyListeners();
      return;
    }

    _recordedPlates.add(norm);
    _lastKey = norm;
    _lastLettersKey = lettersKey;
    _lastDigits = plateData.digits;
    if (spokenNote != null && spokenNote.isNotEmpty) {
      _latestNote[norm] = spokenNote;
    }

    final auditLog = sortAuditProvider.processAuditPlate(
      plateData.fullPlate,
      detectedBrand: plateData.detectedBrand,
      detectedNote: spokenNote ?? _stickyNote,
    );

    _lastReadPlate = plateData.fullPlate;
    _lastReadIsWanted = auditLog.isMatched;
    _lastMatchResult = auditLog;

    final location = _lastKnownLocation;
    final resolvedCarType = plateData.detectedBrand != '-'
        ? plateData.detectedBrand
        : (auditLog.carType.isNotEmpty && auditLog.carType != '-'
            ? auditLog.carType
            : '-');

    final record = CarRecord(
      plateNumber: plateData.fullPlate,
      carType: resolvedCarType,
      gpsUrl: location?.gpsUrl ?? CarRecord.buildGpsUrl(24.7136, 46.6753),
      district: _currentDistrict.trim().isNotEmpty
          ? _currentDistrict.trim()
          : (location?.district ?? 'مدينة الرياض'),
      street: _currentStreet,
      registrationDate: DateTime.now(),
      recorderName: _recorderName.trim().isEmpty ? '-' : _recorderName.trim(),
      notes: spokenNote ?? _stickyNote ?? '-',
      isMatched: auditLog.isMatched,
      color: auditLog.color,
      owner: auditLog.owner,
    );

    _records.insert(0, record);
    // Shift all existing indices up by 1
    _rowIdToIndex.updateAll((id, idx) => idx + 1);

    onPlateAdded(plateData.fullPlate, auditLog.isMatched, resolvedCarType);
    notifyListeners();

    unawaited(
      _dbHelper.insertCarRecord(record).then((newId) {
        _recordIds[norm] = newId;
        // O(1) index via rowIdToIndex; new record is at index 0
        _records[0] = record.copyWith(id: newId);
        _rowIdToIndex[newId] = 0;
      }),
    );
  }

  void _scheduleAiFallback(
    String rawTranscript,
    String normalized,
    ExcelSortAuditProvider sortAuditProvider,
    Function(String plate, bool isMatched, String carModel) onPlateAdded,
  ) {
    if (!AiPlateRefiner.instance.isEnabled) return;
    // Use RegExp for clarity and speed — reuse compiled pattern
    final digitCount = _digitRx.allMatches(normalized).length;
    if (digitCount < 3) return;

    _aiTimer?.cancel();
    _aiTimer = Timer(_aiDebounce, () async {
      final aiPlates = await AiPlateRefiner.instance.refine(rawTranscript);
      for (final p in aiPlates) {
        _ingestPlate(p, sortAuditProvider, onPlateAdded);
      }
    });
  }

  Future<int> processTextPlates({
    required List<String> plates,
    required ExcelSortAuditProvider sortAuditProvider,
    required Function(String plate, bool isMatched, String carModel) onPlateAdded,
  }) async {
    int count = 0;
    unawaited(_refreshLocation());
    for (final line in plates) {
      final extracted = ArabicVoiceNormalizer.extractPlatesFromTranscript(
        line,
        stickyNote: _stickyNote,
      );
      for (final p in extracted) {
        final before = _recordedPlates.length;
        _ingestPlate(p, sortAuditProvider, onPlateAdded);
        // O(1) set-length comparison — detects if plate was truly new
        if (_recordedPlates.length > before) count++;
      }
    }
    return count;
  }

  Future<void> stopVoiceListening() async {
    _tailSettleTimer?.cancel();
    final tail = _pendingTailPlate;
    _pendingTailPlate = null;
    _aiTimer?.cancel();
    await _speechService.stopListening();
    _isListening = false;
    _timer?.cancel();
    if (tail != null) {
      // Committed on stop if needed
    }
    notifyListeners();
  }

  Future<bool> saveCarRecord({
    required String plateNumber,
    required String carModel,
    String notes = '',
    String? recorderName,
    bool isMatched = false,
    String color = '-',
    String owner = '-',
    String? plateKey,
  }) async {
    _isSaving = true;
    notifyListeners();
    try {
      await _refreshLocation();
      final location = _lastKnownLocation;
      final record = CarRecord(
        plateNumber: plateNumber,
        carType: carModel.isEmpty ? '-' : carModel,
        gpsUrl: location?.gpsUrl ?? CarRecord.buildGpsUrl(24.7136, 46.6753),
        district: _currentDistrict.trim().isNotEmpty
            ? _currentDistrict.trim()
            : (location?.district ?? 'مدينة الرياض'),
        street: _currentStreet,
        registrationDate: DateTime.now(),
        recorderName: (recorderName ?? _recorderName).trim().isEmpty
            ? '-'
            : (recorderName ?? _recorderName).trim(),
        notes: notes.isEmpty ? '-' : notes,
        isMatched: isMatched,
        color: color,
        owner: owner,
      );
      final id = await _dbHelper.insertCarRecord(record);
      final key = plateKey ?? ArabicVoiceNormalizer.normalizePlateForMatch(plateNumber);
      if (key.isNotEmpty) {
        _recordedPlates.add(key);
        _recordIds[key] = id;
      }
      final saved = record.copyWith(id: id);
      // Shift existing indices before inserting at 0
      _rowIdToIndex.updateAll((rid, idx) => idx + 1);
      _records.insert(0, saved);
      _rowIdToIndex[id] = 0;
      return true;
    } catch (e) {
      debugPrint('Error saving car record: $e');
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<void> _applyNoteUpdate(String key) async {
    final rowId = _recordIds[key];
    final note = _latestNote[key];
    if (rowId == null || note == null) return;
    try {
      await _dbHelper.updateCarRecordNotes(rowId, note);
      // O(1) lookup via reverse-index map — no linear scan
      final idx = _rowIdToIndex[rowId];
      if (idx != null && idx < _records.length) {
        _records[idx] = _records[idx].copyWith(notes: note);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Failed to update record note: $e');
    }
  }

  Future<String?> exportRecordsToExcel() async {
    if (_records.isEmpty) return null;
    _isExporting = true;
    notifyListeners();
    try {
      return await _excelService.exportCarRecordsToExcel(_records);
    } catch (e) {
      debugPrint('Error exporting to excel: $e');
      return null;
    } finally {
      _isExporting = false;
      notifyListeners();
    }
  }

  Future<void> deleteRecord(int id) async {
    try {
      await _dbHelper.deleteCarRecord(id);
      final idx = _rowIdToIndex.remove(id);
      if (idx != null && idx < _records.length) {
        _records.removeAt(idx);
        // Fix indices for all records after the deleted one
        for (final entry in _rowIdToIndex.entries.toList()) {
          if (entry.value > idx) {
            _rowIdToIndex[entry.key] = entry.value - 1;
          }
        }
      } else {
        _records.removeWhere((r) => r.id == id);
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Error deleting record: $e');
    }
  }

  Future<void> clearAllRecords() async {
    try {
      await _dbHelper.clearAllRecords();
      _records.clear();
      _rowIdToIndex.clear();
      _recordedPlates.clear();
      _recordIds.clear();
      _latestNote.clear();
      _lastKey = null;
      _lastLettersKey = null;
      _lastDigits = null;
      notifyListeners();
    } catch (e) {
      debugPrint('Error clearing records: $e');
    }
  }
}
