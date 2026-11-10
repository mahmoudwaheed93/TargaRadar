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
  List<CarRecord> _recentRecords = [];
  bool _isLoading = false;
  bool _isSaving = false;
  bool _isExporting = false;
  bool _isListening = false;
  String _currentTranscript = '';
  LocationDetails? _lastKnownLocation;

  // Real-time HUD states matching web app
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

  // Set of recorded plates in current session to avoid duplicate row inserts
  final Set<String> _recordedPlates = {};
  // plate key -> db row id / latest spoken note (a note is usually spoken
  // AFTER the plate, so the saved row must be updated when it arrives)
  final Map<String, int> _recordIds = {};
  final Map<String, String> _latestNote = {};
  String? _lastKey; // last plate recorded (target of a note said after a pause)
  int _orphanSession = -1;
  String? _orphanTarget;

  // Location is refreshed in the background: a row must NEVER wait for GPS.
  bool _locRefreshing = false;
  DateTime? _locAt;

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

  /// A note spoken alone ("ملحوظة ...") goes to the plate recorded just before.
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

  // Recorder (user) name: editable, persisted, and written to every exported row
  static const String _recorderKeyBase = 'carlogix_recorder_name';
  String _recorderName = '';
  bool _recorderLoaded = false;
  String get recorderName => _recorderName;

  /// The uid of the current user — set this after login so the recorder name
  /// and DB records are scoped per account.
  String _currentUserId = '';

  /// Must be called after login to scope records and preferences per user.
  Future<void> setCurrentUserId(String uid) async {
    _currentUserId = uid;
    _dbHelper.currentUserId = uid;
    _recordedPlates.clear();
    _recordIds.clear();
    _latestNote.clear();
    _recorderLoaded = false;
    await _loadRecorderName();
    await loadRecords();
  }

  String get _recorderKey => '${_recorderKeyBase}_$_currentUserId';

  List<CarRecord> get records => _records;
  List<CarRecord> get recentRecords => _recentRecords;
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
    _loadRecorderName();
  }

  Future<void> _loadRecorderName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _recorderName = prefs.getString(_recorderKey) ?? '';
    } catch (e) {
      debugPrint('Error loading recorder name: $e');
    } finally {
      _recorderLoaded = true;
      notifyListeners();
    }
  }

  /// Uses [fallback] (the logged-in username) only while nothing was saved yet.
  Future<void> ensureRecorderName(String? fallback) async {
    while (!_recorderLoaded) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
    if (_recorderName.trim().isEmpty && fallback != null && fallback.trim().isNotEmpty) {
      await setRecorderName(fallback.trim());
    }
  }

  Future<void> setRecorderName(String name) async {
    _recorderName = name;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_recorderKey, name);
    } catch (e) {
      debugPrint('Error saving recorder name: $e');
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
    _stickyNote = note;
    notifyListeners();
  }

  Future<void> loadRecords() async {
    _isLoading = true;
    notifyListeners();

    try {
      _records = await _dbHelper.getAllCarRecords();
      _recentRecords = await _dbHelper.getRecentCarRecords(limit: 10);
      for (final r in _records) {
        final key = ArabicVoiceNormalizer.normalizePlateForMatch(r.plateNumber);
        _recordedPlates.add(key);
        if (r.id != null) {
          _recordIds[key] = r.id!;
          _latestNote.putIfAbsent(key, () => r.notes);
        }
      }
    } catch (e) {
      debugPrint('Error loading car records: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Toggle continuous live voice dictation
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
    _isListening = true;
    _currentTranscript = '';
    _listeningTimer = 0;
    _orphanSession = -1;
    unawaited(_refreshLocation()); // warm up GPS while the user starts talking
    _startTimer();
    notifyListeners();

    await _speechService.startListening(
      onOrphanNote: _handleOrphanNote,
      onResult: (rawTranscript, extractedPlates, slots, normalized) {
        _currentTranscript = rawTranscript;
        _currentSlots = slots;

        // Process special mode sticky notes (O(1) checks without re-normalizing)
        if (normalized.contains('بدايه جراج يمين') || normalized.contains('جراج يمين')) {
          _stickyNote = 'جراج يمين';
        } else if (normalized.contains('بدايه برحه يسار') || normalized.contains('برحه يسار')) {
          _stickyNote = 'برحة يسار';
        }
        if (normalized.contains('انتهي') || normalized.contains('انتهت')) {
          _stickyNote = null;
        }

        // 1. Process all completed plates immediately (zero wait)
        final completePlates = extractedPlates.where((p) => p.isComplete).toList();
        for (final plateData in completePlates) {
          _ingestPlate(plateData, sortAuditProvider, onPlateAdded);
        }

        // 2. Debounce trailing incomplete plate (e.g. 2 or 3 digits at the end of speech)
        // If the speaker pauses for 450ms without speaking a 4th digit, commit it cleanly!
        _incompletePlateTimer?.cancel();
        if (extractedPlates.isNotEmpty && !extractedPlates.last.isComplete) {
          final pending = extractedPlates.last;
          _incompletePlateTimer = Timer(const Duration(milliseconds: 450), () {
            if (!_isListening) return;
            _ingestPlate(pending, sortAuditProvider, onPlateAdded);
            notifyListeners();
          });
        }

        // AI fallback (background, never blocks the local engine): only when the
        // local parser found nothing but the transcript has plate-like digits.
        _scheduleAiFallback(rawTranscript, normalized, extractedPlates.isEmpty, sortAuditProvider, onPlateAdded);

        notifyListeners();
      },
      onDone: () {
        _isListening = false;
        _stopTimer();
        notifyListeners();
      },
    );
  }

  /// Records one plate (shared by the local engine and the AI fallback).
  void _ingestPlate(
    ParsedPlateData plateData,
    ExcelSortAuditProvider sortAuditProvider,
    Function(String plate, bool isMatched, String carModel) onPlateAdded,
  ) {
    final norm = ArabicVoiceNormalizer.normalizePlateForMatch(plateData.fullPlate);
    final spokenNote = plateData.detectedNote != '-' ? plateData.detectedNote : null;

    if (_recordedPlates.contains(norm)) {
      // Plate already saved: a note spoken after it goes to NOTES only.
      if (spokenNote != null && spokenNote != _stickyNote && _latestNote[norm] != spokenNote) {
        _latestNote[norm] = spokenNote;
        _applyNoteUpdate(norm);
      }
      return;
    }

    // In-place upgrade defense: if the previous card was inserted within 4 seconds
    // and is a prefix of the new plate (e.g. "د ب ق 28" upgraded to "د ب ق 2852"):
    if (_records.isNotEmpty) {
      final prev = _records.first;
      final prevNorm = ArabicVoiceNormalizer.normalizePlateForMatch(prev.plateNumber);
      if (norm.length > prevNorm.length &&
          norm.startsWith(prevNorm.substring(0, prevNorm.length.clamp(0, norm.length - 1))) &&
          DateTime.now().difference(prev.registrationDate).inSeconds <= 4) {
        _recordedPlates.remove(prevNorm);
        _recordedPlates.add(norm);
        _lastKey = norm;
        _latestNote[norm] = spokenNote ?? prev.notes;

        final auditLog = sortAuditProvider.processAuditPlate(
          plateData.fullPlate,
          detectedBrand: plateData.detectedBrand,
          detectedNote: spokenNote ?? _stickyNote,
        );
        _lastReadPlate = plateData.fullPlate;
        _lastReadIsWanted = auditLog.isMatched;
        _lastMatchResult = auditLog;

        final updated = CarRecord(
          id: prev.id,
          plateNumber: plateData.fullPlate,
          carType: plateData.detectedBrand != '-' ? plateData.detectedBrand : (auditLog.carType.isNotEmpty && auditLog.carType != '-' ? auditLog.carType : prev.carType),
          gpsUrl: prev.gpsUrl,
          district: prev.district,
          street: prev.street,
          registrationDate: prev.registrationDate,
          recorderName: prev.recorderName,
          notes: spokenNote ?? prev.notes,
          isMatched: auditLog.isMatched,
          color: auditLog.color,
          owner: auditLog.owner,
        );
        _records[0] = updated;
        _recentRecords = _records.take(10).toList();
        notifyListeners();

        if (prev.id != null) {
          unawaited(_dbHelper.updateCarRecord(updated));
        }
        onPlateAdded(plateData.fullPlate, auditLog.isMatched, auditLog.carType);
        return;
      }
    }

    _recordedPlates.add(norm);
    _lastKey = norm;
    _latestNote[norm] = spokenNote ?? _stickyNote ?? '-';

    // Audit & Match against Excel Sheet
    final auditLog = sortAuditProvider.processAuditPlate(
      plateData.fullPlate,
      detectedBrand: plateData.detectedBrand,
      detectedNote: spokenNote ?? _stickyNote,
    );

    _lastReadPlate = plateData.fullPlate;
    _lastReadIsWanted = auditLog.isMatched;
    _lastMatchResult = auditLog;

    // Reflect into full 7-slot visualizer
    final lClean = plateData.letters.replaceAll(RegExp(r'\s+'), '');
    final lSlots = lClean.length > 3 ? lClean.substring(lClean.length - 3) : lClean;
    final lList = lSlots.split('');
    final dList = plateData.digits.split('');

    _currentSlots = {
      'l1': lList.isNotEmpty ? lList[0] : '-',
      'l2': lList.length > 1 ? lList[1] : '-',
      'l3': lList.length > 2 ? lList[2] : '-',
      'd1': dList.isNotEmpty ? dList[0] : '-',
      'd2': dList.length > 1 ? dList[1] : '-',
      'd3': dList.length > 2 ? dList[2] : '-',
      'd4': dList.length > 3 ? dList[3] : '-',
    };

    // Instant O(1) in-memory session update - zero latency, zero frame drops!
    final location = _lastKnownLocation;
    final record = CarRecord(
      plateNumber: plateData.fullPlate,
      carType: plateData.detectedBrand != '-' ? plateData.detectedBrand : (auditLog.carType.isNotEmpty && auditLog.carType != '-' ? auditLog.carType : 'غير محدد'),
      gpsUrl: location?.gpsUrl ?? CarRecord.buildGpsUrl(24.7136, 46.6753),
      district: _currentDistrict.trim().isNotEmpty ? _currentDistrict.trim() : (location?.district ?? 'غير محدد'),
      street: _currentStreet,
      registrationDate: DateTime.now(),
      recorderName: _recorderName.trim().isEmpty ? '-' : _recorderName.trim(),
      notes: spokenNote ?? _stickyNote ?? '-',
      isMatched: auditLog.isMatched,
      color: auditLog.color,
      owner: auditLog.owner,
    );

    _records.insert(0, record);
    _recentRecords = _records.take(10).toList();
    notifyListeners();

    // Persist to local database in background without interrupting audio stream
    unawaited(() async {
      try {
        final newId = await _dbHelper.insertCarRecord(record);
        _recordIds[norm] = newId;
        final latest = _latestNote[norm];
        if (latest != null && latest != '-' && latest != record.notes) {
          await _dbHelper.updateCarRecordNotes(newId, latest);
        }
      } catch (e) {
        debugPrint('Async DB insert error: $e');
      }
    }());

    onPlateAdded(plateData.fullPlate, auditLog.isMatched, auditLog.carType);
  }

  Timer? _incompletePlateTimer;
  Timer? _aiTimer;
  static const Duration _aiDebounce = Duration(milliseconds: 750);

  void _scheduleAiFallback(
    String rawTranscript,
    String normalized,
    bool localFoundNothing,
    ExcelSortAuditProvider sortAuditProvider,
    Function(String plate, bool isMatched, String carModel) onPlateAdded,
  ) {
    _aiTimer?.cancel();
    if (!localFoundNothing || !AiPlateRefiner.instance.isEnabled) return;
    final digitCount = RegExp(r'\d').allMatches(normalized).length;
    if (digitCount < 3) return;
    // Wait until the speaker pauses, so we send one request per utterance.
    _aiTimer = Timer(_aiDebounce, () async {
      final plates = await AiPlateRefiner.instance.refine(rawTranscript);
      if (!_isListening) return;
      for (final p in plates) {
        _ingestPlate(p, sortAuditProvider, onPlateAdded);
      }
      if (plates.isNotEmpty) notifyListeners();
    });
  }

  /// Process text input containing plate numbers
  Future<int> processTextPlates({
    required List<String> plates,
    required ExcelSortAuditProvider sortAuditProvider,
    required Function(String plate, bool isMatched, String carModel) onPlateAdded,
  }) async {
    int matchedCount = 0;
    for (final raw in plates) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) continue;
      final norm = ArabicVoiceNormalizer.normalizePlateForMatch(trimmed);
      if (norm.isEmpty || _recordedPlates.contains(norm)) continue;

      _recordedPlates.add(norm);
      _lastKey = norm;
      _latestNote[norm] = _stickyNote ?? '-';

      // Audit & Match against Excel Sheet
      final auditLog = sortAuditProvider.processAuditPlate(
        trimmed,
        detectedNote: _stickyNote,
      );

      _lastReadPlate = trimmed;
      _lastReadIsWanted = auditLog.isMatched;
      _lastMatchResult = auditLog;

      if (auditLog.isMatched) {
        matchedCount++;
      }

      await saveCarRecord(
        plateNumber: trimmed,
        carModel: auditLog.carType.isNotEmpty && auditLog.carType != '-' ? auditLog.carType : 'غير محدد',
        notes: _stickyNote ?? '-',
        isMatched: auditLog.isMatched,
        color: auditLog.color,
        owner: auditLog.owner,
        plateKey: norm,
      );

      onPlateAdded(trimmed, auditLog.isMatched, auditLog.carType);
    }
    notifyListeners();
    return matchedCount;
  }

  Future<void> stopVoiceListening() async {
    _incompletePlateTimer?.cancel();
    _aiTimer?.cancel();
    await _speechService.stopListening();
    _isListening = false;
    _stopTimer();
    notifyListeners();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      _listeningTimer++;
      notifyListeners();
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
    _listeningTimer = 0;
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
    if (plateNumber.trim().isEmpty) return false;

    _isSaving = true;
    notifyListeners();

    try {
      // Instant: use the cached position, refresh it in the background.
      final location = _lastKnownLocation;
      unawaited(_refreshLocation());

      final record = CarRecord(
        plateNumber: plateNumber.trim(),
        carType: carModel.trim().isEmpty ? 'غير محدد' : carModel.trim(),
        gpsUrl: location?.gpsUrl ?? CarRecord.buildGpsUrl(24.7136, 46.6753),
        district: _currentDistrict.trim().isNotEmpty ? _currentDistrict.trim() : (location?.district ?? 'غير محدد'),
        street: _currentStreet,
        registrationDate: DateTime.now(),
        recorderName: (recorderName ?? _recorderName).trim().isEmpty ? '-' : (recorderName ?? _recorderName).trim(),
        notes: notes.trim().isEmpty ? (_stickyNote ?? '-') : notes.trim(),
        isMatched: isMatched,
        color: color,
        owner: owner,
      );

      final newId = await _dbHelper.insertCarRecord(record);
      if (plateKey != null) {
        _recordIds[plateKey] = newId;
        // A note may have been spoken while the location was being resolved.
        final latest = _latestNote[plateKey];
        if (latest != null && latest != '-' && latest != record.notes) {
          await _dbHelper.updateCarRecordNotes(newId, latest);
        }
      }
      final recordWithId = CarRecord(
        id: newId,
        plateNumber: record.plateNumber,
        carType: record.carType,
        gpsUrl: record.gpsUrl,
        district: record.district,
        street: record.street,
        registrationDate: record.registrationDate,
        recorderName: record.recorderName,
        notes: (plateKey != null ? _latestNote[plateKey] : null) ?? record.notes,
        isMatched: record.isMatched,
        color: record.color,
        owner: record.owner,
      );
      _records.removeWhere((r) => r.plateNumber == record.plateNumber && r.id == null);
      _records.insert(0, recordWithId);
      _recentRecords = _records.take(10).toList();
      return true;
    } catch (e) {
      debugPrint('Error saving record: $e');
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<String?> exportRecordsToExcel() async {
    if (_records.isEmpty) {
      await loadRecords();
      if (_records.isEmpty) return null;
    }

    _isExporting = true;
    notifyListeners();

    try {
      final filePath = await _excelService.exportCarRecordsToExcel(_records);
      return filePath;
    } catch (e) {
      debugPrint('Export error: $e');
      return null;
    } finally {
      _isExporting = false;
      notifyListeners();
    }
  }

  Future<void> _applyNoteUpdate(String key) async {
    final id = _recordIds[key];
    final note = _latestNote[key];
    if (id == null || note == null) return; // applied right after the insert
    try {
      await _dbHelper.updateCarRecordNotes(id, note);
      final idx = _records.indexWhere((r) => r.id == id);
      if (idx != -1) {
        _records[idx] = _records[idx].copyWith(notes: note);
        _recentRecords = _records.take(10).toList();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error updating note: $e');
    }
  }

  Future<void> deleteRecord(int id) async {
    final keys = _recordIds.entries.where((e) => e.value == id).map((e) => e.key).toList();
    for (final k in keys) {
      _recordIds.remove(k);
      _recordedPlates.remove(k);
      _latestNote.remove(k);
    }
    await _dbHelper.deleteCarRecord(id);
    await loadRecords();
  }

  Future<void> clearAllRecords() async {
    await _dbHelper.clearAllRecords();
    _records.clear();
    _recentRecords.clear();
    _recordedPlates.clear();
    _recordIds.clear();
    _latestNote.clear();
    notifyListeners();
  }
}
