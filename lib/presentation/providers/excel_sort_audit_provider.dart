import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/services/arabic_voice_normalizer.dart';
import '../../core/services/excel_table_service.dart';
import '../../core/utils/date_formatter.dart';
import '../../data/models/excel_vehicle_model.dart';

class ExcelSortAuditProvider extends ChangeNotifier {
  static const String _sheetKeyBase = 'carlogix_sort_sheet';
  static const String _filenameKeyBase = 'carlogix_sort_filename';
  static const String _feedKeyBase = 'carlogix_sort_feed';

  String _currentUserId = '';
  int _logSeq = 0;

  String get _sheetKey => '${_sheetKeyBase}_$_currentUserId';
  String get _filenameKey => '${_filenameKeyBase}_$_currentUserId';
  String get _feedKey => '${_feedKeyBase}_$_currentUserId';

  List<ExcelVehicleItem> _sheetItems = [];
  String _sheetFileName = '';
  List<AuditedLogItem> _liveAuditFeed = [];
  AuditedLogItem? _lastAuditResult;
  bool _isLoading = false;

  List<ExcelVehicleItem> get sheetItems => _sheetItems;
  String get sheetFileName => _sheetFileName;
  List<AuditedLogItem> get liveAuditFeed => _liveAuditFeed;
  AuditedLogItem? get lastAuditResult => _lastAuditResult;
  bool get isLoading => _isLoading;

  int get totalSheetCount => _sheetItems.length;
  int get auditedCount => _sheetItems.where((i) => i.isAudited).length;
  int get unlistedCount => _liveAuditFeed.where((i) => !i.isMatched).length;
  int get pendingCount => totalSheetCount - auditedCount;

  static final List<ExcelVehicleItem> sampleExcelData = [
    ExcelVehicleItem(
      id: 'sample-1',
      rawPlate: 'أ ب ج 1234',
      normalizedPlate: ArabicVoiceNormalizer.normalizePlateForMatch('أ ب ج 1234'),
      carType: 'تويوتا كورولا',
      color: 'أبيض',
      owner: 'شركة الأفق للنقل',
      notes: 'سارية - فحص دوري',
      otherFields: {'رقم الشاسيه': '984210'},
    ),
    ExcelVehicleItem(
      id: 'sample-2',
      rawPlate: 'ر س ر 9332',
      normalizedPlate: ArabicVoiceNormalizer.normalizePlateForMatch('ر س ر 9332'),
      carType: 'هيونداي النترا',
      color: 'رمادي',
      owner: 'مؤسسة الرياض',
      notes: 'سارية',
      otherFields: {'رقم الشاسيه': '551294'},
    ),
    ExcelVehicleItem(
      id: 'sample-3',
      rawPlate: 'ن س ك 5566',
      normalizedPlate: ArabicVoiceNormalizer.normalizePlateForMatch('ن س ك 5566'),
      carType: 'كيا سبورتاج',
      color: 'أسود',
      owner: 'أحمد عبد الله',
      notes: 'مطلوب تجديد',
      otherFields: {'رقم الشاسيه': '319401'},
    ),
    ExcelVehicleItem(
      id: 'sample-4',
      rawPlate: 'ق ح 2669',
      normalizedPlate: ArabicVoiceNormalizer.normalizePlateForMatch('ق ح 2669'),
      carType: 'نيسان صني',
      color: 'فضي',
      owner: 'سالم محمود',
      notes: 'سارية',
      otherFields: {'المحافظة': 'الجيزة'},
    ),
    ExcelVehicleItem(
      id: 'sample-5',
      rawPlate: 'ك ب 4321',
      normalizedPlate: ArabicVoiceNormalizer.normalizePlateForMatch('ك ب 4321'),
      carType: 'فورد تورس',
      color: 'كحلي',
      owner: 'مجموعة الفهد',
      notes: 'سارية',
      otherFields: {'المحافظة': 'الجيزة'},
    ),
  ];

  ExcelSortAuditProvider();

  Future<File?> _largeSheetCacheFile() async {
    if (kIsWeb) return null;
    try {
      final base = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(base.path, 'sheet_cache'));
      if (!await dir.exists()) await dir.create(recursive: true);
      final safeUid = _currentUserId.isEmpty ? 'default' : _currentUserId;
      return File(p.join(dir.path, 'sort_sheet_$safeUid.json'));
    } catch (_) {
      return null;
    }
  }

  Future<void> setCurrentUserId(String uid) async {
    if (_currentUserId == uid) return;
    _currentUserId = uid;
    await loadPersistedData();
  }

  Future<void> loadPersistedData() async {
    _isLoading = true;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      _sheetFileName = prefs.getString(_filenameKey) ?? '';

      String? rawSheet = prefs.getString(_sheetKey);
      if (rawSheet == null || rawSheet.isEmpty) {
        final cacheFile = await _largeSheetCacheFile();
        if (cacheFile != null && await cacheFile.exists()) {
          rawSheet = await cacheFile.readAsString();
        }
      }

      if (rawSheet != null && rawSheet.isNotEmpty) {
        final decoded = jsonDecode(rawSheet) as List;
        _sheetItems = decoded
            .map((e) => ExcelVehicleItem.fromJson(e as Map<String, dynamic>))
            .toList();
      } else {
        _sheetItems = [];
      }

      final savedFeed = prefs.getString(_feedKey);
      if (savedFeed != null && savedFeed.isNotEmpty) {
        final decodedFeed = jsonDecode(savedFeed) as List;
        _liveAuditFeed = decodedFeed
            .map((e) => AuditedLogItem.fromJson(e as Map<String, dynamic>))
            .toList();
      } else {
        _liveAuditFeed = [];
      }
      _lastAuditResult = null;
    } catch (e) {
      debugPrint('Error loading persisted sort audit data: $e');
      _sheetItems = [];
    } finally {
      _rebuildIndex();
      _isLoading = false;
      notifyListeners();
    }
  }

  Timer? _persistTimer;

  void _schedulePersist() {
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(seconds: 2), () {
      _persistData();
    });
  }

  Future<void> _persistData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_filenameKey, _sheetFileName);

      final encodedSheet = jsonEncode(_sheetItems.map((e) => e.toJson()).toList());
      if (_sheetItems.length <= 3000) {
        await prefs.setString(_sheetKey, encodedSheet);
        final cacheFile = await _largeSheetCacheFile();
        if (cacheFile != null && await cacheFile.exists()) {
          await cacheFile.delete();
        }
      } else {
        // Persist large >3000-row sheets on disk so restarts never lose the table
        await prefs.remove(_sheetKey);
        final cacheFile = await _largeSheetCacheFile();
        if (cacheFile != null) {
          await cacheFile.writeAsString(encodedSheet, flush: true);
        }
      }

      // Cap persisted live audit log to 500 recent items to keep SharedPreferences fast
      final feedToSave = _liveAuditFeed.length > 500
          ? _liveAuditFeed.take(500).toList()
          : _liveAuditFeed;
      await prefs.setString(_feedKey, jsonEncode(feedToSave.map((e) => e.toJson()).toList()));
    } catch (e) {
      debugPrint('Error saving sort audit data: $e');
    }
  }

  // plate key -> index in _sheetItems (O(1) matching even for 60k+ rows)
  final Map<String, int> _index = {};

  void _rebuildIndex() {
    _index.clear();
    for (int i = 0; i < _sheetItems.length; i++) {
      final k = ArabicVoiceNormalizer.plateKey(_sheetItems[i].rawPlate);
      if (k.isNotEmpty) _index.putIfAbsent(k, () => i);
    }
  }

  /// Instant O(1) lookup by plate string using the pre-built hash index.
  ExcelVehicleItem? findItemByPlate(String plate) {
    final idx = _index[ArabicVoiceNormalizer.plateKey(plate)];
    if (idx == null || idx < 0 || idx >= _sheetItems.length) return null;
    return _sheetItems[idx];
  }

  Future<bool> importTable(ExcelTable table, String fileName) async {
    _isLoading = true;
    notifyListeners();

    try {
      if (table.rows.isEmpty) return false;
      final headers = table.headers.map((h) => h.trim().toLowerCase()).toList();
      final plateCol = table.plateCol;

      int typeCol = -1, colorCol = -1, ownerCol = -1, notesCol = -1;
      for (int i = 0; i < headers.length; i++) {
        if (i == plateCol) continue;
        final h = headers[i];
        if (typeCol == -1 && (h.contains('نوع') || h.contains('مارك') || h.contains('طراز') || h.contains('model') || h.contains('type'))) {
          typeCol = i;
        } else if (colorCol == -1 && (h.contains('لون') || h.contains('color'))) {
          colorCol = i;
        } else if (ownerCol == -1 && (h.contains('مالك') || h.contains('اسم') || h.contains('عميل') || h.contains('بنك') || h.contains('owner'))) {
          ownerCol = i;
        } else if (notesCol == -1 && (h.contains('ملاحظ') || h.contains('حالة') || h.contains('note') || h.contains('status'))) {
          notesCol = i;
        }
      }

      String cell(List<String> row, int c) => (c != -1 && c < row.length && row[c].isNotEmpty) ? row[c] : '-';

      final stamp = DateTime.now().millisecondsSinceEpoch;
      final parsed = <ExcelVehicleItem>[];
      for (int r = 0; r < table.rows.length; r++) {
        final row = table.rows[r];
        final rawPlate = plateCol < row.length ? row[plateCol].trim() : '';
        if (rawPlate.isEmpty) continue;

        final other = <String, String>{};
        for (int c = 0; c < row.length; c++) {
          if (c == plateCol || c == typeCol || c == colorCol || c == ownerCol || c == notesCol) continue;
          if (row[c].isEmpty) continue;
          final h = c < table.headers.length && table.headers[c].isNotEmpty ? table.headers[c] : 'حقل_$c';
          other[h] = row[c];
        }

        parsed.add(ExcelVehicleItem(
          id: 'item-$stamp-$r',
          rawPlate: rawPlate,
          normalizedPlate: ArabicVoiceNormalizer.plateKey(rawPlate),
          carType: cell(row, typeCol),
          color: cell(row, colorCol),
          owner: cell(row, ownerCol),
          notes: cell(row, notesCol),
          otherFields: other,
        ));
      }

      if (parsed.isEmpty) return false;
      _sheetItems = parsed;
      _sheetFileName = fileName;
      _liveAuditFeed.clear();
      _lastAuditResult = null;
      _rebuildIndex();
      await _persistData();
      return true;
    } catch (e) {
      debugPrint('Error importing table: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadSampleData() async {
    _sheetItems = List.from(sampleExcelData);
    _sheetFileName = 'شيت_بيانات_السيارات.xlsx';
    _liveAuditFeed.clear();
    _lastAuditResult = null;
    _rebuildIndex();
    await _persistData();
    notifyListeners();
  }

  Future<void> clearAuditFeed() async {
    _sheetItems = _sheetItems.map((e) => e.copyWith(isAudited: false)).toList();
    _liveAuditFeed.clear();
    _lastAuditResult = null;
    await _persistData();
    notifyListeners();
  }

  /// Match a spoken or manually entered plate against the sheet (O(1))
  AuditedLogItem processAuditPlate(String fullPlate, {String? detectedBrand, String? detectedNote}) {
    final normPlate = ArabicVoiceNormalizer.plateKey(fullPlate);

    final matchIndex = _index[normPlate] ?? -1;

    final isMatched = matchIndex != -1;
    final now = DateTime.now();
    final nowStr = AppDateFormatter.time12(now);

    final ExcelVehicleItem? matchedItem = isMatched ? _sheetItems[matchIndex] : null;

    if (isMatched) {
      _sheetItems[matchIndex] = _sheetItems[matchIndex].copyWith(
        isAudited: true,
        auditedAt: nowStr,
      );
    }

    final logItem = AuditedLogItem(
      id: 'log-${now.microsecondsSinceEpoch}-${_logSeq++}',
      seqNumber: _liveAuditFeed.length + 1,
      plateNumber: fullPlate,
      normalizedPlate: normPlate,
      isMatched: isMatched,
      carType: isMatched
          ? (matchedItem!.carType != '-' ? matchedItem.carType : (detectedBrand ?? '-'))
          : (detectedBrand ?? '-'),
      color: isMatched ? matchedItem!.color : '-',
      owner: isMatched ? matchedItem!.owner : '-',
      notes: isMatched
          ? (matchedItem!.notes != '-' ? matchedItem.notes : (detectedNote ?? '-'))
          : (detectedNote ?? '-'),
      timestamp: nowStr,
      otherFields: isMatched ? matchedItem!.otherFields : const {},
    );

    _liveAuditFeed.insert(0, logItem);
    _lastAuditResult = logItem;
    _schedulePersist();
    notifyListeners();

    return logItem;
  }

  @override
  void dispose() {
    _persistTimer?.cancel();
    super.dispose();
  }
}
