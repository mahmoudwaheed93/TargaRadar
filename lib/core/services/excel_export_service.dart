import 'dart:io';
import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../data/models/car_record_model.dart';
import '../../data/models/excel_vehicle_model.dart';

class ExcelExportService {
  static final ExcelExportService instance = ExcelExportService._init();
  ExcelExportService._init();

  /// Returns the Downloads directory on Android, falling back to app documents.
  Future<Directory> _getDownloadDir() async {
    if (!kIsWeb && Platform.isAndroid) {
      final dir = Directory('/storage/emulated/0/Download');
      if (await dir.exists()) return dir;
    }
    return await getApplicationDocumentsDirectory();
  }

  /// Export list of CarRecords to an Excel (.xlsx) file
  Future<String?> exportCarRecordsToExcel(List<CarRecord> records) async {
    try {
      final excel = Excel.createExcel();
      const sheetName = 'سجل_السيارات';

      final defaultSheet = excel.getDefaultSheet();
      if (defaultSheet != null) {
        excel.rename(defaultSheet, sheetName);
      }

      final sheet = excel[sheetName];
      sheet.appendRow(CarRecord.excelHeaders);

      for (int i = 0; i < records.length; i++) {
        sheet.appendRow(records[i].toExcelRow(rowIndex: i + 1));
      }

      final fileBytes = excel.save();
      if (fileBytes == null) return null;

      final directory = await _getDownloadDir();

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'Saqr_Al_Mamlaka_Records_$timestamp.xlsx';
      final filePath = p.join(directory.path, fileName);

      final file = File(filePath);
      await file.writeAsBytes(fileBytes, flush: true);

      return filePath;
    } catch (e) {
      debugPrint('Error generating Excel file: $e');
      return null;
    }
  }

  /// Export full triage & audit report with 2 sheets:
  /// Sheet 1: Matched vehicles report
  /// Sheet 2: Unlisted vehicles report
  Future<String?> exportAuditReport({
    required List<ExcelVehicleItem> sheetItems,
    required List<AuditedLogItem> auditedLog,
  }) async {
    try {
      final excel = Excel.createExcel();

      // Sheet 1: Matched sheet items
      const sheet1Name = 'تقرير_مطابقة_الشيت';
      final def = excel.getDefaultSheet();
      if (def != null) {
        excel.rename(def, sheet1Name);
      }
      final ws1 = excel[sheet1Name];
      ws1.appendRow([
        TextCellValue('م'),
        TextCellValue('رقم اللوحة'),
        TextCellValue('حالة الرصد'),
        TextCellValue('وقت الرصد'),
        TextCellValue('نوع السيارة'),
        TextCellValue('الملاحظات'),
      ]);

      for (int i = 0; i < sheetItems.length; i++) {
        final it = sheetItems[i];
        ws1.appendRow([
          TextCellValue('${i + 1}'),
          TextCellValue(it.rawPlate),
          TextCellValue(it.isAudited ? 'تم رصدها ✓' : 'لم يتم رصدها بعد'),
          TextCellValue(it.auditedAt ?? '-'),
          TextCellValue(it.carType),
          TextCellValue(it.notes),
        ]);
      }

      // Sheet 2: Unlisted vehicles
      final unlisted = auditedLog.where((l) => !l.isMatched).toList();
      if (unlisted.isNotEmpty) {
        const sheet2Name = 'سيارات_غير_مسجلة_بالشيت';
        final ws2 = excel[sheet2Name];
        ws2.appendRow([
          TextCellValue('م'),
          TextCellValue('اللوحة المرصودة'),
          TextCellValue('نوع السيارة'),
          TextCellValue('الملاحظات'),
          TextCellValue('وقت التسجيل'),
          TextCellValue('الحالة'),
        ]);

        for (int i = 0; i < unlisted.length; i++) {
          final u = unlisted[i];
          ws2.appendRow([
            TextCellValue('${i + 1}'),
            TextCellValue(u.plateNumber),
            TextCellValue(u.carType),
            TextCellValue(u.notes),
            TextCellValue(u.timestamp),
            TextCellValue('⚠️ سيارة غير مسجلة بالشيت الأصلي'),
          ]);
        }
      }

      final fileBytes = excel.save();
      if (fileBytes == null) return null;

      final directory = await _getDownloadDir();

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'Saqr_Al_Mamlaka_الفرز_$timestamp.xlsx';
      final filePath = p.join(directory.path, fileName);

      final file = File(filePath);
      await file.writeAsBytes(fileBytes, flush: true);

      return filePath;
    } catch (e) {
      debugPrint('Error exporting audit report: $e');
      return null;
    }
  }
}
