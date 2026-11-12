import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/services/ai_plate_refiner.dart';
import '../../core/services/arabic_voice_normalizer.dart';
import '../../core/services/excel_export_service.dart';
import '../../core/services/location_service.dart';
import '../../core/services/sound_alert_service.dart';
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

  // Real-time HUD states
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

  // All plate maps use canonical ArabicVoiceNormalizer.plateKey uniformly
  final Set<String> _recordedPlates = {};
  final Map<String, int> _recordIds = {};
  final Map<String, String> _latestNote = {};
  final Map<String, CarRecord> _pendingUpdates = {};
  final Map<String, String> _upgradedKeyRedirects = {};
  final Map<String, CarRecord> _recordByKey = {};
  String _lastProcessedTranscript = '';
  String? _lastKey;
  int _orphanSession = -1;
  String? _orphanTarget;

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

  void _handleOrphanNote(String? note, int session) {
    if (note == null) return;
    _handleOrphanData(OrphanVoiceData(note: note), session);
  }

  void _handleOrphanData(OrphanVoiceData data, int session) {
    if (!data.hasData || _records.isEmpty) return;

    if (session != _orphanSession) {
      _orphanSession = session;
      _orphanTarget = _lastKey;
    }
    final key = _orphanTarget ?? _lastKey;
    if (key == null) return;

    final idx = _records.indexWhere((r) => ArabicVoiceNormalizer.plateKey(r.plateNumber) == key);
    if (idx == -1) return;

    final existing = _records[idx];
    bool changed = false;
    String curBrand = existing.carType;
    String curNote = existing.notes;

    if (data.brand != null && data.brand != '-' && (curBrand == 'غير محدد' || curBrand == '-' || curBrand != data.brand)) {
      curBrand = data.brand!;
      changed = true;
    }

    if (data.note != null && data.note != '-' && curNote != data.note) {
      curNote = data.note!;
      _latestNote[key] = curNote;
      changed = true;
    }

    if (changed) {
      final updated = existing.copyWith(carType: curBrand, notes: curNote);
      _records[idx] = updated;
      _recordByKey[key] = updated;
      _recordsVersion++;
      _recentRecords = _records.take(10).toList();
      notifyListeners();
      _persistRecordUpdate(key, updated);
    }
  }

  static const String _recorderKeyBase = 'carlogix_recorder_name';
  String _recorderName = '';
  Completer<void> _recorderLoadCompleter = Completer<void>();
  String get recorderName => _recorderName;

  String _currentUserId = '';

  Future<void> setCurrentUserId(String uid) async {
    _currentUserId = uid;
    _dbHelper.currentUserId = uid;
    _recordedPlates.clear();
    _recordIds.clear();
    _latestNote.clear();
    _recordByKey.clear();
    _pendingUpdates.clear();
    _upgradedKeyRedirects.clear();
    _currentTranscript = '';
    _lastProcessedTranscript = '';
    _lastKey = null;
    _lastReadPlate = '';
    _lastReadIsWanted = false;
    _lastMatchResult = null;
    if (_recorderLoadCompleter.isCompleted) {
      _recorderLoadCompleter = Completer<void>();
    }
    await _loadRecorderName();
    await loadRecords();
  }

  String get _recorderKey => '${_recorderKeyBase}_$_currentUserId';

  int _recordsVersion = 0;
  int get recordsVersion => _recordsVersion;
  int get matchedCount => _records.where((r) => r.isMatched).length;
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
      if (!_recorderLoadCompleter.isCompleted) {
        _recorderLoadCompleter.complete();
      }
      notifyListeners();
    }
  }

  Future<void> ensureRecorderName(String? fallback) async {
    await _recorderLoadCompleter.future;
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
      final loaded = await _dbHelper.getAllCarRecords();
      _records = loaded;
      _recordedPlates.clear();
      _recordByKey.clear();
      _recordIds.clear();
      _latestNote.clear();
      _recordsVersion++;
      _recentRecords = _records.take(10).toList();
      for (final r in _records) {
        final key = ArabicVoiceNormalizer.plateKey(r.plateNumber);
        if (key.isEmpty) continue;
        _recordedPlates.add(key);
        _recordByKey[key] = r;
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
    _lastProcessedTranscript = '';
    _listeningTimer = 0;
    _orphanSession = -1;
    unawaited(_refreshLocation());
    unawaited(SoundAlertService.instance.warmUp());
    _startTimer();
    notifyListeners();

    await _speechService.startListening(
      onOrphanNote: _handleOrphanNote,
      onOrphanData: _handleOrphanData,
      onResult: (rawTranscript, extractedPlates, slots, normalized, isFinal) {
        if (rawTranscript.length < _lastProcessedTranscript.length) {
          _lastProcessedTranscript = '';
        }
        if (rawTranscript == _lastProcessedTranscript && !isFinal) return;
        _lastProcessedTranscript = isFinal ? '' : rawTranscript;
        _currentTranscript = ArabicVoiceNormalizer.extractActiveTickerText(normalized, isFinal: isFinal);
        if (slots.isNotEmpty) {
          _currentSlots = slots;
        }

        if (normalized.contains('بدايه جراج يمين') || normalized.contains('جراج يمين')) {
          _stickyNote = 'جراج يمين';
        } else if (normalized.contains('بدايه برحه يسار') || normalized.contains('برحه يسار')) {
          _stickyNote = 'برحة يسار';
        }
        if (normalized.contains('انتهي') || normalized.contains('انتهت')) {
          _stickyNote = null;
        }

        // 1. Commit all completed 4-digit plates at 0ms
        final completePlates = extractedPlates.where((p) => p.isComplete).toList();
        for (int i = 0; i < completePlates.length; i++) {
          _ingestPlate(
            completePlates[i],
            sortAuditProvider,
            onPlateAdded,
            isLatestInUtterance: i == completePlates.length - 1,
          );
        }

        // 2. Trailing 3-digit plate: wait 350ms for optional 4th digit; else pad '0' & close
        _incompletePlateTimer?.cancel();
        _pendingIncompletePlate = null;
        if (extractedPlates.isNotEmpty && !extractedPlates.last.isComplete) {
          final pending = extractedPlates.last;
          void commitThreeDigit() {
            final closed = ArabicVoiceNormalizer.finalizeThreeDigitPlate(pending);
            _ingestPlate(closed, sortAuditProvider, onPlateAdded);
            _applySlotsFromPlate(closed);
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

        // 3. AI fallback strictly on the unparsed speech tail
        final unparsedTail = ArabicVoiceNormalizer.extractUnparsedTail(normalized);
        _scheduleAiFallback(rawTranscript, unparsedTail, sortAuditProvider, onPlateAdded);

        notifyListeners();
      },
      onDone: () {
        _flushPendingIncompletePlate();
        _isListening = false;
        _stopTimer();
        notifyListeners();
      },
    );
  }

  /// Records one plate (shared by local engine and AI fallback).
  void _ingestPlate(
    ParsedPlateData plateData,
    ExcelSortAuditProvider sortAuditProvider,
    Function(String plate, bool isMatched, String carModel) onPlateAdded, {
    bool isLatestInUtterance = true,
  }) {
    final norm = ArabicVoiceNormalizer.plateKey(plateData.fullPlate);
    if (norm.isEmpty) return;
    final spokenNote = plateData.detectedNote != '-' ? plateData.detectedNote : null;

    if (_recordedPlates.contains(norm)) {
      final spokenBrand = plateData.detectedBrand != '-' ? plateData.detectedBrand : null;
      final cached = _recordByKey[norm];
      if (isLatestInUtterance && norm != _lastKey) {
        _lastKey = norm;
        _lastReadPlate = plateData.fullPlate;
        _lastReadIsWanted = cached?.isMatched ?? false;
        _recordsVersion++;
        notifyListeners();
      }
      if (cached != null) {
        final brandSame = spokenBrand == null || cached.carType == spokenBrand;
        final noteSame = spokenNote == null || spokenNote == _stickyNote || cached.notes == spokenNote;
        if (brandSame && noteSame) return;
      }

      final idx = _records.indexWhere((r) => ArabicVoiceNormalizer.plateKey(r.plateNumber) == norm);
      if (idx != -1) {
        final existing = _records[idx];
        bool changed = false;
        String curBrand = existing.carType;
        String curNote = existing.notes;

        if (spokenBrand != null && (curBrand == 'غير محدد' || curBrand == '-' || curBrand != spokenBrand)) {
          curBrand = spokenBrand;
          changed = true;
        }

        if (spokenNote != null && spokenNote != _stickyNote && curNote != spokenNote) {
          curNote = spokenNote;
          _latestNote[norm] = spokenNote;
          changed = true;
        }

        if (changed) {
          final updated = existing.copyWith(carType: curBrand, notes: curNote);
          _records[idx] = updated;
          _recordByKey[norm] = updated;
          _recordsVersion++;
          _recentRecords = _records.take(10).toList();
          notifyListeners();
          _persistRecordUpdate(norm, updated);
        }
      }
      return;
    }

    // In-place upgrade defense within 5 seconds
    if (_records.isNotEmpty) {
      final prev = _records.first;
      final prevNorm = ArabicVoiceNormalizer.plateKey(prev.plateNumber);
      if (DateTime.now().difference(prev.registrationDate).inSeconds <= 5 &&
          ArabicVoiceNormalizer.isPlateUpgrade(prev.plateNumber, plateData.fullPlate)) {
        _recordedPlates.remove(prevNorm);
        _recordByKey.remove(prevNorm);
        _pendingUpdates.remove(prevNorm);
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
        _applySlotsFromPlate(plateData);

        final existingId = prev.id ?? _recordIds.remove(prevNorm);
        final updated = CarRecord(
          id: existingId,
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
        _recordByKey[norm] = updated;
        _recordsVersion++;
        _recentRecords = _records.take(10).toList();
        notifyListeners();

        if (existingId != null) {
          _recordIds[norm] = existingId;
          unawaited(_dbHelper.updateCarRecord(updated));
        } else {
          for (final entry in _upgradedKeyRedirects.entries.toList()) {
            if (entry.value == prevNorm) {
              _upgradedKeyRedirects[entry.key] = norm;
            }
          }
          _upgradedKeyRedirects[prevNorm] = norm;
          _pendingUpdates[norm] = updated;
        }
        if (auditLog.isMatched && !prev.isMatched) {
          onPlateAdded(plateData.fullPlate, auditLog.isMatched, auditLog.carType);
        }
        return;
      }
    }

    _recordedPlates.add(norm);
    _lastKey = norm;
    _latestNote[norm] = spokenNote ?? _stickyNote ?? '-';

    final auditLog = sortAuditProvider.processAuditPlate(
      plateData.fullPlate,
      detectedBrand: plateData.detectedBrand,
      detectedNote: spokenNote ?? _stickyNote,
    );

    _lastReadPlate = plateData.fullPlate;
    _lastReadIsWanted = auditLog.isMatched;
    _lastMatchResult = auditLog;

    _applySlotsFromPlate(plateData);

    final location = _lastKnownLocation;
    final record = CarRecord(
      plateNumber: plateData.fullPlate,
      carType: plateData.detectedBrand != '-' ? plateData.detectedBrand : (auditLog.carType.isNotEmpty && auditLog.carType != '-' ? auditLog.carType : 'غير محدد'),
      gpsUrl: location?.gpsUrl ?? '-',
      district: _currentDistrict.trim().isNotEmpty ? _currentDistrict.trim() : (location?.district ?? 'غير متاح'),
      street: _currentStreet,
      registrationDate: DateTime.now(),
      recorderName: _recorderName.trim().isEmpty ? '-' : _recorderName.trim(),
      notes: spokenNote ?? _stickyNote ?? '-',
      isMatched: auditLog.isMatched,
      color: auditLog.color,
      owner: auditLog.owner,
    );

    _records.insert(0, record);
    _recordByKey[norm] = record;
    _recordsVersion++;
    _recentRecords = _records.take(10).toList();
    notifyListeners();

    // Persist to local database in background without interrupting audio stream
    unawaited(() async {
      try {
        final newId = await _dbHelper.insertCarRecord(record);
        final finalNorm = _upgradedKeyRedirects.remove(norm) ?? norm;
        _upgradedKeyRedirects.removeWhere((_, v) => v == finalNorm);
        // If the user already deleted the card while SQLite insert was in flight, delete the orphaned DB row
        if (!_recordedPlates.contains(finalNorm)) {
          await _dbHelper.deleteCarRecord(newId);
          return;
        }
        _recordIds[finalNorm] = newId;
        final idx = _records.indexWhere(
          (r) => ArabicVoiceNormalizer.plateKey(r.plateNumber) == finalNorm && r.id == null,
        );
        if (idx != -1) {
          _records[idx] = _records[idx].copyWith(id: newId);
          _recordByKey[finalNorm] = _records[idx];
          _recordsVersion++;
          _recentRecords = _records.take(10).toList();
          notifyListeners();
        }
        final pending = _pendingUpdates.remove(finalNorm) ?? _pendingUpdates.remove(norm);
        if (pending != null) {
          await _dbHelper.updateCarRecord(pending.copyWith(id: newId));
        } else {
          final latest = _latestNote[finalNorm];
          if (latest != null && latest != '-' && latest != record.notes) {
            await _dbHelper.updateCarRecordNotes(newId, latest);
          }
        }
      } catch (e) {
        debugPrint('Async DB insert error: $e');
      }
    }());

    onPlateAdded(plateData.fullPlate, auditLog.isMatched, auditLog.carType);
  }

  Timer? _incompletePlateTimer;
  static const Duration _threeDigitCloseDebounce = Duration(milliseconds: 350);
  VoidCallback? _pendingIncompletePlate;

  void _flushPendingIncompletePlate() {
    _incompletePlateTimer?.cancel();
    final flush = _pendingIncompletePlate;
    _pendingIncompletePlate = null;
    if (flush != null) flush();
  }

  void _applySlotsFromPlate(ParsedPlateData plateData) {
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
  }

  Timer? _aiTimer;
  static const Duration _aiDebounce = Duration(milliseconds: 250);

  void _scheduleAiFallback(
    String rawTranscript,
    String unparsedTail,
    ExcelSortAuditProvider sortAuditProvider,
    Function(String plate, bool isMatched, String carModel) onPlateAdded,
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
        _ingestPlate(p, sortAuditProvider, onPlateAdded);
      }
      if (plates.isNotEmpty) notifyListeners();
    });
  }

  Future<int> processTextPlates({
    required List<String> plates,
    required ExcelSortAuditProvider sortAuditProvider,
    required Function(String plate, bool isMatched, String carModel) onPlateAdded,
  }) async {
    int matchedCount = 0;
    for (final raw in plates) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) continue;

      final parsed = ArabicVoiceNormalizer.extractPlatesFromTranscript(trimmed, stickyNote: _stickyNote);
      if (parsed.isNotEmpty) {
        for (final p in parsed) {
          final closed = p.digits.length == 3
              ? ArabicVoiceNormalizer.finalizeThreeDigitPlate(p)
              : p;
          final norm = ArabicVoiceNormalizer.plateKey(closed.fullPlate);
          final alreadySeen = _recordedPlates.contains(norm);
          _ingestPlate(closed, sortAuditProvider, (plate, isMatched, model) {
            if (isMatched && !alreadySeen) matchedCount++;
            onPlateAdded(plate, isMatched, model);
          });
        }
        continue;
      }

      final norm = ArabicVoiceNormalizer.plateKey(trimmed);
      if (norm.isEmpty || _recordedPlates.contains(norm)) continue;

      _recordedPlates.add(norm);
      _lastKey = norm;
      _latestNote[norm] = _stickyNote ?? '-';

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
    _flushPendingIncompletePlate();
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
      final location = _lastKnownLocation;
      unawaited(_refreshLocation());

      final record = CarRecord(
        plateNumber: plateNumber.trim(),
        carType: carModel.trim().isEmpty ? 'غير محدد' : carModel.trim(),
        gpsUrl: location?.gpsUrl ?? '-',
        district: _currentDistrict.trim().isNotEmpty ? _currentDistrict.trim() : (location?.district ?? 'غير متاح'),
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
        final latest = _latestNote[plateKey];
        if (latest != null && latest != '-' && latest != record.notes) {
          await _dbHelper.updateCarRecordNotes(newId, latest);
        }
      }
      final recordWithId = record.copyWith(
        id: newId,
        notes: (plateKey != null ? _latestNote[plateKey] : null) ?? record.notes,
      );
      if (plateKey != null) _recordByKey[plateKey] = recordWithId;
      _records.removeWhere((r) => r.plateNumber == record.plateNumber && r.id == null);
      _records.insert(0, recordWithId);
      _recordsVersion++;
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
      return await _excelService.exportCarRecordsToExcel(_records);
    } catch (e) {
      debugPrint('Export error: $e');
      return null;
    } finally {
      _isExporting = false;
      notifyListeners();
    }
  }

  void _persistRecordUpdate(String norm, CarRecord updated) {
    final id = _recordIds[norm] ?? updated.id;
    if (id != null) {
      unawaited(_dbHelper.updateCarRecord(updated.copyWith(id: id)));
    } else {
      _pendingUpdates[norm] = updated;
    }
  }

  /// Deletes a record immediately even if its SQLite background insert is still pending (`id == null`).
  Future<void> deleteByRecord(CarRecord rec) async {
    final key = ArabicVoiceNormalizer.plateKey(rec.plateNumber);
    final resolvedId = rec.id ?? _recordIds[key];

    _recordIds.remove(key);
    _recordedPlates.remove(key);
    _latestNote.remove(key);
    _recordByKey.remove(key);
    _pendingUpdates.remove(key);
    if (_lastKey == key) _lastKey = null;

    _records.removeWhere((r) =>
        (resolvedId != null && r.id == resolvedId) ||
        ArabicVoiceNormalizer.plateKey(r.plateNumber) == key);
    _recordsVersion++;
    _recentRecords = _records.take(10).toList();
    notifyListeners();

    if (resolvedId != null) {
      await _dbHelper.deleteCarRecord(resolvedId);
    }
  }

  Future<void> deleteRecord(int id) async {
    final keys = _recordIds.entries.where((e) => e.value == id).map((e) => e.key).toList();
    for (final k in keys) {
      _recordIds.remove(k);
      _recordedPlates.remove(k);
      _latestNote.remove(k);
      _recordByKey.remove(k);
      _pendingUpdates.remove(k);
      if (_lastKey == k) _lastKey = null;
    }
    await _dbHelper.deleteCarRecord(id);
    await loadRecords();
  }

  Future<void> clearAllRecords() async {
    await _dbHelper.clearAllRecords();
    _records.clear();
    _recordsVersion++;
    _recentRecords.clear();
    _recordedPlates.clear();
    _recordIds.clear();
    _latestNote.clear();
    _recordByKey.clear();
    _pendingUpdates.clear();
    _upgradedKeyRedirects.clear();
    _lastKey = null;
    _lastReadPlate = '';
    _lastReadIsWanted = false;
    _lastMatchResult = null;
    _currentTranscript = '';
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _incompletePlateTimer?.cancel();
    _aiTimer?.cancel();
    _speechService.stopListening();
    super.dispose();
  }
}
