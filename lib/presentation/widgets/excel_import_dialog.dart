import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/excel_table_service.dart';
import '../providers/excel_sort_audit_provider.dart';

/// Lets the user browse the phone for an Excel (.xlsx) file and loads it as the
/// live-matching sheet. Replaces the old "type the file path" box.
Future<void> showExcelImportDialog(
  BuildContext context,
  ExcelSortAuditProvider auditProvider, {
  String title = 'شيت إكسيل المطابقة الفورية',
}) {
  return showDialog(
    context: context,
    builder: (ctx) => _ExcelImportDialog(
      title: title,
      auditProvider: auditProvider,
      parentContext: context,
    ),
  );
}

class _ExcelImportDialog extends StatefulWidget {
  final String title;
  final ExcelSortAuditProvider auditProvider;
  final BuildContext parentContext;
  const _ExcelImportDialog({
    required this.title,
    required this.auditProvider,
    required this.parentContext,
  });

  @override
  State<_ExcelImportDialog> createState() => _ExcelImportDialogState();
}

class _ExcelImportDialogState extends State<_ExcelImportDialog> {
  bool _busy = false;
  String? _error;

  Future<void> _pickAndImport() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final picked = await ExcelTableService.instance.pickExcelFile();
      if (picked == null) {
        if (mounted) setState(() => _busy = false);
        return;
      }

      // The worker isolate reads the file from disk and picks the data sheet
      // (works for heavy files and workbooks with several sheets).
      final table = await ExcelTableService.instance.parse(picked);
      final ok = await widget.auditProvider.importTable(table, picked.name);
      if (!mounted) return;
      if (ok) {
        final count = widget.auditProvider.sheetItems.length;
        final messenger = ScaffoldMessenger.of(widget.parentContext);
        Navigator.pop(context);
        messenger.showSnackBar(
          SnackBar(
            content: Text('تم استيراد $count سيارة من "${picked.name}"'),
            backgroundColor: AppColors.success,
          ),
        );
      } else {
        setState(() {
          _busy = false;
          _error = 'الملف فارغ أو غير متوافق (لازم يكون .xlsx وفيه عمود لرقم اللوحة)';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'خطأ أثناء قراءة الملف: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.cardDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          const Icon(Icons.table_chart_rounded, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.title,
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'اختار ملف الإكسيل (.xlsx) من الموبايل عشان يتفعّل المطابقة الفورية أثناء التسجيل.',
              style: TextStyle(color: AppColors.textSecondaryDark, fontSize: 13),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _busy ? null : _pickAndImport,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                      )
                    : const Icon(Icons.folder_open_rounded, size: 18),
                label: Text(
                  _busy ? 'جاري قراءة الملف...' : 'اختيار ملف من الموبايل',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 12)),
            ],

          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('إلغاء', style: TextStyle(color: AppColors.textSecondaryDark)),
        ),
      ],
    );
  }
}
