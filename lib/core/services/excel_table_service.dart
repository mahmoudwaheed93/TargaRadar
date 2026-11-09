import 'dart:io';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'arabic_voice_normalizer.dart';
import 'xlsx_fast_reader.dart';

/// An Excel file picked from the phone storage.
class PickedExcel {
  final String name;
  final String? path; // mobile/desktop: read inside the worker isolate
  final Uint8List? bytes; // web only
  const PickedExcel(this.name, {this.path, this.bytes});

  XlsxSource get source => XlsxSource(path: path, bytes: bytes);
}

/// A generic table read from an Excel sheet (first sheet).
class ExcelTable {
  final List<String> headers;
  final List<List<String>> rows;
  final int plateCol;
  const ExcelTable({required this.headers, required this.rows, required this.plateCol});
}

/// Result of matching a small sheet against a big one.
class TwoFileMatchResult {
  final List<String> headers;
  final List<List<String>> matchedRows; // rows of the BIG file
  final List<String> notFoundPlates; // plates in the small file but not in the big one
  final int smallCount;
  final int bigCount; // data rows read from the big file
  final String bigSheetName;
  const TwoFileMatchResult({
    required this.headers,
    required this.matchedRows,
    required this.notFoundPlates,
    required this.smallCount,
    this.bigCount = 0,
    this.bigSheetName = '',
  });
}

class ExcelTableService {
  ExcelTableService._();
  static final ExcelTableService instance = ExcelTableService._();

  /// Opens the phone's file chooser so the user can browse to an Excel file.
  /// Big files are NOT loaded into memory here: only their path is kept and the
  /// worker isolate reads them, so the screen never freezes.
  /// NOTE: only .xlsx is supported (not the old .xls format).
  Future<PickedExcel?> pickExcelFile() async {
    // file_picker v13: static method, returns List<PlatformFile> (empty = cancelled).
    // PlatformFile no longer has a .bytes field; use .path or .readAsBytes().
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
    );
    if (files.isEmpty) return null;
    final f = files.single;

    // On web there is no local path — read bytes directly.
    if (kIsWeb) {
      final bytes = await f.readAsBytes();
      return PickedExcel(f.name, bytes: bytes);
    }

    // On mobile/desktop prefer the local path (keeps memory low for big files).
    if (f.path != null) return PickedExcel(f.name, path: f.path);

    // Fallback: load into memory (e.g. sandboxed platform with no path access).
    final bytes = await f.readAsBytes();
    return PickedExcel(f.name, bytes: bytes);
  }

  Future<T> _keepAwake<T>(Future<T> Function() job) async {
    try {
      await WakelockPlus.enable();
    } catch (_) {}
    try {
      return await job();
    } finally {
      try {
        await WakelockPlus.disable();
      } catch (_) {}
    }
  }

  /// Parses a (possibly huge) workbook off the UI thread.
  /// Throws a readable error if the file cannot be used.
  Future<ExcelTable> parse(PickedExcel file) {
    return _keepAwake(() async {
      final map = await compute(_parseTableIsolate, file.source.toMap());
      return _tableFromMap(map);
    });
  }

  /// Keeps every plate of [small] that also exists in [big] and returns the
  /// complete BIG-file rows for those plates.
  Future<TwoFileMatchResult> matchTwoFiles({
    required PickedExcel big,
    required PickedExcel small,
  }) {
    return _keepAwake(() async {
      final map = await compute(_matchIsolate, <String, dynamic>{
        'big': big.source.toMap(),
        'small': small.source.toMap(),
      });
      return TwoFileMatchResult(
        headers: List<String>.from(map['headers'] as List),
        matchedRows: (map['matched'] as List).map((r) => List<String>.from(r as List)).toList(),
        notFoundPlates: List<String>.from(map['notFound'] as List),
        smallCount: map['smallCount'] as int,
        bigCount: map['bigCount'] as int,
        bigSheetName: map['bigSheet'] as String,
      );
    });
  }

  /// Matches a list of plate strings directly against [big].
  Future<TwoFileMatchResult> matchPlatesWithBig({
    required PickedExcel big,
    required List<String> plates,
  }) {
    return _keepAwake(() async {
      final map = await compute(_matchTextIsolate, <String, dynamic>{
        'big': big.source.toMap(),
        'plates': plates,
      });
      return TwoFileMatchResult(
        headers: List<String>.from(map['headers'] as List),
        matchedRows: (map['matched'] as List).map((r) => List<String>.from(r as List)).toList(),
        notFoundPlates: List<String>.from(map['notFound'] as List),
        smallCount: map['smallCount'] as int,
        bigCount: map['bigCount'] as int,
        bigSheetName: map['bigSheet'] as String,
      );
    });
  }

  /// Writes an .xlsx into the Downloads folder and returns its path.
  Future<String?> saveWorkbook(Excel excel, String prefix) async {
    try {
      final fileBytes = excel.save();
      if (fileBytes == null) return null;
      Directory directory;
      if (!kIsWeb && Platform.isAndroid) {
        directory = Directory('/storage/emulated/0/Download');
        if (!await directory.exists()) {
          directory = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
        }
      } else {
        directory = await getApplicationDocumentsDirectory();
      }
      final path = p.join(directory.path, '${prefix}_${DateTime.now().millisecondsSinceEpoch}.xlsx');
      await File(path).writeAsBytes(fileBytes, flush: true);
      return path;
    } catch (e) {
      debugPrint('saveWorkbook error: $e');
      return null;
    }
  }

  Future<String?> exportMatchResult(TwoFileMatchResult r) async {
    final excel = Excel.createExcel();
    const name = 'اللوحات_المشتركة';
    final def = excel.getDefaultSheet();
    if (def != null) excel.rename(def, name);
    final ws = excel[name];
    ws.appendRow(r.headers.map((h) => TextCellValue(h)).toList());
    for (final row in r.matchedRows) {
      ws.appendRow(row.map((c) => TextCellValue(c)).toList());
    }
    if (r.notFoundPlates.isNotEmpty) {
      final ws2 = excel['غير_موجودة_بالداتا'];
      ws2.appendRow([TextCellValue('اللوحة')]);
      for (final pl in r.notFoundPlates) {
        ws2.appendRow([TextCellValue(pl)]);
      }
    }
    return saveWorkbook(excel, 'Saqr_Al_Mamlaka_المشتركة');
  }
}

// ───────────────────────── isolate helpers (top-level) ─────────────────────────

Map<String, dynamic> _tableToMap(ExcelTable t) => {
      'headers': t.headers,
      'rows': t.rows,
      'plateCol': t.plateCol,
    };

ExcelTable _tableFromMap(Map<String, dynamic> m) => ExcelTable(
      headers: List<String>.from(m['headers'] as List),
      rows: (m['rows'] as List).map((r) => List<String>.from(r as List)).toList(),
      plateCol: m['plateCol'] as int,
    );

final RegExp _plateLike = RegExp(r'[ء-ي]');

bool _isPlateHeader(String h) {
  final l = h.toLowerCase();
  return l.contains('لوح') || l.contains('plate');
}

/// Builds a table from raw rows: finds the header row (the first of the top
/// rows that has a "plate" column title, skipping banners/titles above it),
/// trims empty columns and locates the plate column.
ExcelTable? _tableFromRaw(List<List<String>> raw, {required bool requireHeader}) {
  if (raw.isEmpty) return null;

  int headerIdx = -1;
  final limit = raw.length < 15 ? raw.length : 15;
  for (int r = 0; r < limit; r++) {
    if (raw[r].any(_isPlateHeader)) {
      headerIdx = r;
      break;
    }
  }
  if (headerIdx == -1 && requireHeader) return null;
  if (headerIdx == -1) headerIdx = 0;

  final headerRow = raw[headerIdx];
  var width = 0;
  for (int c = headerRow.length - 1; c >= 0; c--) {
    if (headerRow[c].isNotEmpty) {
      width = c + 1;
      break;
    }
  }
  for (int r = headerIdx + 1; r < raw.length; r++) {
    if (raw[r].length > width) {
      for (int c = raw[r].length - 1; c >= width; c--) {
        if (raw[r][c].isNotEmpty) {
          width = c + 1;
          break;
        }
      }
    }
  }
  if (width == 0) return null;

  final headers = List<String>.generate(width, (c) => c < headerRow.length ? headerRow[c] : '');
  final rows = <List<String>>[];
  for (int r = headerIdx + 1; r < raw.length; r++) {
    final src = raw[r];
    final row = List<String>.generate(width, (c) => c < src.length ? src[c] : '');
    if (row.every((c) => c.isEmpty)) continue;
    rows.add(row);
  }

  int plateCol = -1;
  for (int i = 0; i < headers.length; i++) {
    if (_isPlateHeader(headers[i])) {
      plateCol = i;
      break;
    }
  }
  if (plateCol == -1) {
    int best = 0;
    var bestScore = -1;
    final sample = rows.length > 60 ? rows.sublist(0, 60) : rows;
    for (int c = 0; c < width; c++) {
      var score = 0;
      for (final row in sample) {
        final v = row[c];
        if (_plateLike.hasMatch(v) && RegExp(r'\d{3,4}').hasMatch(v)) score++;
      }
      if (score > bestScore) {
        bestScore = score;
        best = c;
      }
    }
    plateCol = best;
  }
  return ExcelTable(headers: headers, rows: rows, plateCol: plateCol);
}

class _SheetPick {
  final String name;
  final ExcelTable table;
  const _SheetPick(this.name, this.table);
}

/// Reads the workbook and returns the sheet that really holds the data:
/// the one with a plate column title and the MOST rows (a workbook may also
/// contain a small lookup/formula sheet first, like "تشييك" next to "بيانات").
_SheetPick _readBestTable(XlsxSource src) {
  final bytes = src.bytesSync();
  final sheets = XlsxFastReader.readAllSheets(bytes);

  _SheetPick? best;
  for (final s in sheets) {
    final t = _tableFromRaw(s.rows, requireHeader: true);
    if (t == null || t.rows.isEmpty) continue;
    if (best == null || t.rows.length > best.table.rows.length) best = _SheetPick(s.partName, t);
  }
  if (best != null) return best;

  // No sheet has a plate title: fall back to the biggest sheet and guess.
  for (final s in sheets) {
    final t = _tableFromRaw(s.rows, requireHeader: false);
    if (t == null || t.rows.isEmpty) continue;
    if (best == null || t.rows.length > best.table.rows.length) best = _SheetPick(s.partName, t);
  }
  if (best == null) throw StateError('الملف فارغ أو مفيهوش بيانات');
  return best;
}

Map<String, dynamic> _parseTableIsolate(Map<String, dynamic> src) {
  final pick = _readBestTable(XlsxSource.fromMap(src));
  return _tableToMap(pick.table);
}

Map<String, dynamic> _matchTextIsolate(Map<String, dynamic> args) {
  final bigPick = _readBestTable(XlsxSource.fromMap(Map<String, dynamic>.from(args['big'] as Map)));
  final big = bigPick.table;
  final plates = List<String>.from(args['plates'] as List);

  final bigIndex = <String, List<int>>{};
  for (int i = 0; i < big.rows.length; i++) {
    final key = ArabicVoiceNormalizer.plateKey(big.rows[i][big.plateCol]);
    if (key.isEmpty) continue;
    bigIndex.putIfAbsent(key, () => <int>[]).add(i);
  }

  final matched = <List<String>>[];
  final notFound = <String>[];
  final seen = <String>{};
  var smallCount = 0;
  for (final raw in plates) {
    final key = ArabicVoiceNormalizer.plateKey(raw);
    if (key.isEmpty || !seen.add(key)) continue;
    smallCount++;
    final hits = bigIndex[key];
    if (hits == null) {
      notFound.add(raw);
    } else {
      for (final i in hits) {
        matched.add(big.rows[i]);
      }
    }
  }
  return {
    'headers': big.headers,
    'matched': matched,
    'notFound': notFound,
    'smallCount': smallCount,
    'bigCount': big.rows.length,
    'bigSheet': bigPick.name,
  };
}

Map<String, dynamic> _matchIsolate(Map<String, dynamic> args) {
  final bigPick = _readBestTable(XlsxSource.fromMap(Map<String, dynamic>.from(args['big'] as Map)));
  final big = bigPick.table;
  final small = _readBestTable(XlsxSource.fromMap(Map<String, dynamic>.from(args['small'] as Map))).table;

  final bigIndex = <String, List<int>>{};
  for (int i = 0; i < big.rows.length; i++) {
    final key = ArabicVoiceNormalizer.plateKey(big.rows[i][big.plateCol]);
    if (key.isEmpty) continue;
    bigIndex.putIfAbsent(key, () => <int>[]).add(i);
  }

  final matched = <List<String>>[];
  final notFound = <String>[];
  final seen = <String>{};
  var smallCount = 0;
  for (final row in small.rows) {
    final raw = row[small.plateCol];
    final key = ArabicVoiceNormalizer.plateKey(raw);
    if (key.isEmpty || !seen.add(key)) continue;
    smallCount++;
    final hits = bigIndex[key];
    if (hits == null) {
      notFound.add(raw);
    } else {
      for (final i in hits) {
        matched.add(big.rows[i]);
      }
    }
  }
  return {
    'headers': big.headers,
    'matched': matched,
    'notFound': notFound,
    'smallCount': smallCount,
    'bigCount': big.rows.length,
    'bigSheet': bigPick.name,
  };
}
