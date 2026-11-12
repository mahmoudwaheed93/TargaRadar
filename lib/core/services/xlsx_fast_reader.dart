import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';

/// Where a workbook comes from: a file on disk (mobile/desktop, preferred for
/// big files so the bytes never go through the UI isolate) or in-memory bytes
/// (web).
class XlsxSource {
  final String? path;
  final Uint8List? bytes;
  const XlsxSource({this.path, this.bytes});

  Map<String, dynamic> toMap() => {'path': path, 'bytes': bytes};

  static XlsxSource fromMap(Map<String, dynamic> m) =>
      XlsxSource(path: m['path'] as String?, bytes: m['bytes'] as Uint8List?);

  /// Used inside the worker isolate, so a synchronous read is fine.
  Uint8List bytesSync() {
    if (bytes != null) return bytes!;
    if (path != null) return File(path!).readAsBytesSync();
    throw StateError('الملف غير متاح للقراءة');
  }
}

/// One worksheet read as plain text rows.
class RawSheet {
  final String partName;
  final List<List<String>> rows;
  const RawSheet(this.partName, this.rows);
}

/// Reads .xlsx workbooks WITHOUT building the full object model of the `excel`
/// package (which is what made 60k-row workbooks hang forever). It only pulls
/// the shared strings and the cell text of each worksheet with plain scanning.
class XlsxFastReader {
  XlsxFastReader._();

  static final RegExp _si = RegExp(r'<si\b[^>]*?(?:/>|>(.*?)</si>)', dotAll: true);
  static final RegExp _rPh = RegExp(r'<rPh\b[^>]*?(?:/>|>(.*?)</rPh>)', dotAll: true);
  static final RegExp _t = RegExp(r'<t\b[^>]*?(?:/>|>(.*?)</t>)', dotAll: true);
  static final RegExp _row = RegExp(r'<row\b[^>]*?(?:/>|>(.*?)</row>)', dotAll: true);
  static final RegExp _cell = RegExp(r'<c\b([^>]*?)(?:/>|>(.*?)</c>)', dotAll: true);
  static final RegExp _v = RegExp(r'<v\b[^>]*?(?:/>|>(.*?)</v>)', dotAll: true);
  static final RegExp _refAttr = RegExp(r'\br="([A-Za-z]+)(\d*)"');
  static final RegExp _typeAttr = RegExp(r'\bt="([^"]*)"');
  static final RegExp _entity = RegExp(r'&(#x[0-9a-fA-F]+|#[0-9]+|amp|lt|gt|quot|apos);');
  static final RegExp _excelHex = RegExp(r'_x([0-9a-fA-F]{4})_');

  /// Reads every worksheet of the workbook (largest part first).
  static List<RawSheet> readAllSheets(Uint8List bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const FormatException('الملف غير صالح أو تالف أو بصيغة .xls قديمة — يجب اختيار ملف .xlsx سليم');
    }

    ArchiveFile? sharedFile;
    final sheetFiles = <ArchiveFile>[];
    for (final f in archive.files) {
      if (!f.isFile) continue;
      final n = f.name.replaceAll('\\', '/').toLowerCase();
      if (n == 'xl/sharedstrings.xml') {
        sharedFile = f;
      } else if (n.startsWith('xl/worksheets/') && n.endsWith('.xml') && !n.contains('/_rels/')) {
        sheetFiles.add(f);
      }
    }
    if (sheetFiles.isEmpty) throw StateError('الملف لا يحتوي على أي شيت');

    final shared = sharedFile == null ? const <String>[] : _readSharedStrings(_decode(sharedFile));

    sheetFiles.sort((a, b) => b.size.compareTo(a.size));
    final sheets = <RawSheet>[];
    for (final f in sheetFiles) {
      sheets.add(RawSheet(f.name.replaceAll('\\', '/'), _readSheet(_decode(f), shared)));
    }
    return sheets;
  }

  static String _decode(ArchiveFile f) {
    final content = f.content as List<int>;
    return utf8.decode(content, allowMalformed: true);
  }

  static List<String> _readSharedStrings(String xml) {
    final out = <String>[];
    for (final m in _si.allMatches(xml)) {
      var body = m.group(1);
      if (body == null || body.isEmpty) {
        out.add('');
        continue;
      }
      if (body.contains('<rPh')) {
        body = body.replaceAll(_rPh, '');
      }
      final sb = StringBuffer();
      for (final t in _t.allMatches(body)) {
        final s = t.group(1);
        if (s != null) sb.write(_unescape(s));
      }
      out.add(sb.toString());
    }
    return out;
  }

  static List<List<String>> _readSheet(String xml, List<String> shared) {
    final rows = <List<String>>[];
    for (final rm in _row.allMatches(xml)) {
      final body = rm.group(1);
      if (body == null || body.isEmpty) continue;

      final cells = <int, String>{};
      var maxCol = -1;
      var seq = 0;
      for (final cm in _cell.allMatches(body)) {
        final attrs = cm.group(1) ?? '';
        final inner = cm.group(2);

        int col;
        final ref = _refAttr.firstMatch(attrs);
        if (ref != null) {
          col = _colIndex(ref.group(1)!);
        } else {
          col = seq;
        }
        seq = col + 1;

        if (inner == null || inner.isEmpty) continue;
        final type = _typeAttr.firstMatch(attrs)?.group(1) ?? 'n';

        String text = '';
        if (type == 'inlineStr') {
          final sb = StringBuffer();
          for (final t in _t.allMatches(inner)) {
            final s = t.group(1);
            if (s != null) sb.write(_unescape(s));
          }
          text = sb.toString();
        } else {
          final vm = _v.firstMatch(inner);
          final raw = vm?.group(1);
          if (raw == null || raw.isEmpty) continue;
          if (type == 's') {
            final idx = int.tryParse(raw.trim());
            if (idx != null && idx >= 0 && idx < shared.length) text = shared[idx];
          } else if (type == 'str' || type == 'e') {
            text = _unescape(raw);
          } else if (type == 'b') {
            text = raw.trim() == '1' ? 'TRUE' : 'FALSE';
          } else {
            text = raw.trim();
            if (text.endsWith('.0')) text = text.substring(0, text.length - 2);
          }
        }
        text = text.trim();
        if (text.isEmpty) continue;
        cells[col] = text;
        if (col > maxCol) maxCol = col;
      }

      if (maxCol < 0) continue; // fully empty row
      final row = List<String>.filled(maxCol + 1, '');
      cells.forEach((c, v) => row[c] = v);
      rows.add(row);
    }
    return rows;
  }

  static int _colIndex(String letters) {
    var n = 0;
    for (final u in letters.toUpperCase().codeUnits) {
      n = n * 26 + (u - 64);
    }
    return n - 1;
  }

  static String _unescape(String s) {
    var out = s;
    if (out.contains('_x')) {
      out = out.replaceAllMapped(_excelHex, (m) {
        try {
          return String.fromCharCode(int.parse(m.group(1)!, radix: 16));
        } catch (_) {
          return m.group(0)!;
        }
      });
    }
    if (!out.contains('&')) return out;
    return out.replaceAllMapped(_entity, (m) {
      final g = m.group(1)!;
      switch (g) {
        case 'amp':
          return '&';
        case 'lt':
          return '<';
        case 'gt':
          return '>';
        case 'quot':
          return '"';
        case 'apos':
          return "'";
      }
      try {
        final code = g.startsWith('#x') ? int.parse(g.substring(2), radix: 16) : int.parse(g.substring(1));
        return String.fromCharCode(code);
      } catch (_) {
        return m.group(0)!;
      }
    });
  }
}
