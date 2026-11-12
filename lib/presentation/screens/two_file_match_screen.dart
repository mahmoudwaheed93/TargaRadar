import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/excel_table_service.dart';
import '../../core/utils/external_actions.dart';

/// Screen for matching a BIG data sheet ("داتا") with an "الاحاله" (which can be
/// an uploaded sheet or directly typed/pasted plate numbers).
class TwoFileMatchScreen extends StatefulWidget {
  final bool embedded;
  const TwoFileMatchScreen({super.key, this.embedded = false});

  @override
  State<TwoFileMatchScreen> createState() => _TwoFileMatchScreenState();
}

class _TwoFileMatchScreenState extends State<TwoFileMatchScreen> {
  final _service = ExcelTableService.instance;

  PickedExcel? _big;
  PickedExcel? _small;
  final TextEditingController _textPlatesController = TextEditingController();
  bool _useTextInput = false; // toggle between file or text input for الاحاله

  TwoFileMatchResult? _result;
  bool _busy = false;
  bool _detailsOpen = false;
  String? _error;
  String? _exportedPath;

  bool _isLocationUrl(String val) {
    final v = val.toLowerCase().trim();
    return v.startsWith('http://') ||
        v.startsWith('https://') ||
        v.contains('maps.google.com') ||
        v.contains('google.com/maps') ||
        v.contains('maps.app.goo.gl');
  }

  @override
  void dispose() {
    _textPlatesController.dispose();
    super.dispose();
  }

  Future<void> _pick(bool big) async {
    try {
      final f = await _service.pickExcelFile();
      if (f == null || !mounted) return;
      setState(() {
        if (big) {
          _big = f;
        } else {
          _small = f;
        }
        _result = null;
        _exportedPath = null;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'تعذر فتح الملف: $e');
    }
  }

  List<String> _extractPlatesFromText(String text) {
    // Splits by lines, commas, or semicolons
    final lines = text.split(RegExp(r'[\r\n,;]+'));
    final plates = <String>[];
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) {
        plates.add(trimmed);
      }
    }
    return plates;
  }

  Future<void> _match() async {
    if (_big == null) return;
    if (!_useTextInput && _small == null) return;

    List<String> textPlates = [];
    if (_useTextInput) {
      textPlates = _extractPlatesFromText(_textPlatesController.text);
      if (textPlates.isEmpty) {
        setState(() => _error = 'يرجى إدخال أرقام اللوح في المربع النصي');
        return;
      }
    }

    setState(() {
      _busy = true;
      _error = null;
      _exportedPath = null;
    });

    TwoFileMatchResult? r;
    String? err;
    try {
      if (_useTextInput) {
        r = await _service.matchPlatesWithBig(big: _big!, plates: textPlates);
      } else {
        r = await _service.matchTwoFiles(big: _big!, small: _small!);
      }
    } catch (e) {
      err = 'تعذرت قراءة الملفات (لازم يكونوا .xlsx وفيهم عمود لرقم اللوحة): $e';
    }

    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = r;
      _error = err;
    });
  }

  Future<void> _export() async {
    final r = _result;
    if (r == null || r.matchedRows.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final path = await _service.exportMatchResult(r);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _exportedPath = path;
        if (path == null) _error = 'فشل حفظ ملف الإكسيل، تحقق من أذونات التخزين';
      });
      if (path != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم تصدير النتائج إلى:\n$path'),
            backgroundColor: AppColors.success,
            action: SnackBarAction(
              label: 'مشاركة',
              textColor: Colors.black,
              onPressed: () => ExternalActions.shareFile(path, text: 'نتائج المطابقة - صقر المملكة'),
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'تعذر حفظ ملف الإكسيل: $e';
      });
    }
  }

  Future<void> _showPlateDetailsModal(List<String> row, List<String> headers, int plateCol) async {
    if (_detailsOpen) return;
    _detailsOpen = true;
    final plateStr = plateCol < row.length ? row[plateCol] : '';
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.cardDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.75),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.check_circle_rounded, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          plateStr.isNotEmpty ? plateStr : 'بيانات اللوحة',
                          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded, color: AppColors.textMutedDark),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'البيانات الكاملة المسجلة في ملف الداتا:',
                    style: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Flexible(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F1624),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF232F46)),
                      ),
                      child: Builder(builder: (context) {
                        final visibleIndices = <int>[
                          for (int i = 0; i < row.length; i++)
                            if (row[i].isNotEmpty) i,
                        ];
                        return ListView.separated(
                          shrinkWrap: true,
                          itemCount: visibleIndices.length,
                          separatorBuilder: (_, __) => const Divider(color: Color(0xFF1E293B), height: 1),
                          itemBuilder: (context, pos) {
                            final i = visibleIndices[pos];
                            final h = i < headers.length && headers[i].isNotEmpty ? headers[i] : 'حقل ${i + 1}';
                            final val = row[i];
                            final isLoc = _isLocationUrl(val) ||
                                h.contains('موقع') ||
                                h.contains('خريطة') ||
                                h.contains('خرائط') ||
                                h.toLowerCase().contains('gps');
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: 120,
                                    child: Text(h, style: const TextStyle(color: AppColors.textMutedDark, fontSize: 12)),
                                  ),
                                  Expanded(
                                    child: isLoc
                                        ? InkWell(
                                            onTap: () => ExternalActions.openMapLocation(val),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(Icons.location_on, color: AppColors.primary, size: 16),
                                                const SizedBox(width: 4),
                                                Flexible(
                                                  child: Text(
                                                    val.startsWith('http') ? 'فتح الموقع في الخريطة ↗' : val,
                                                    style: const TextStyle(
                                                      color: AppColors.primary,
                                                      fontSize: 13,
                                                      fontWeight: FontWeight.bold,
                                                      decoration: TextDecoration.underline,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          )
                                        : Text(
                                            val,
                                            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                                          ),
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      }),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Color(0xFF232F46)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('إغلاق'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    _detailsOpen = false;
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    final canMatch = _big != null && (!_useTextInput ? _small != null : true) && !_busy;

    return Scaffold(
      backgroundColor: const Color(0xFF10141D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF131B2A),
        elevation: 0,
        automaticallyImplyLeading: !widget.embedded,
        title: const Text(
          'الفرز — مطابقة ملفين',
          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'اختار ملف الداتا وملف الاحاله (أو أدخل أرقام اللوح نصياً) وابدأ الفرز. أي لوحة في الاحاله موجودة كمان في الداتا ستظهر كاملة ويمكنك تصديرها لشيت إكسيل واحد، أو النقر على أي لوحة لعرض كامل بياناتها.',
                style: TextStyle(color: AppColors.textSecondaryDark, fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 16),
              _fileCard(title: 'داتا', file: _big, onPick: () => _pick(true)),
              const SizedBox(height: 12),

              // الاحاله section (Switch between File and Text)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.cardDark,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.borderDark),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'الاحاله',
                          style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                        // Toggle buttons
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F1624),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              GestureDetector(
                                onTap: () => setState(() => _useTextInput = false),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: !_useTextInput ? AppColors.primary : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'ملف إكسيل',
                                    style: TextStyle(
                                      color: !_useTextInput ? Colors.black : AppColors.textSecondaryDark,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: () => setState(() => _useTextInput = true),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: _useTextInput ? AppColors.primary : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'إدخال نصي',
                                    style: TextStyle(
                                      color: _useTextInput ? Colors.black : AppColors.textSecondaryDark,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (!_useTextInput) ...[
                      Row(
                        children: [
                          Icon(
                            _small == null ? Icons.insert_drive_file_outlined : Icons.table_chart_rounded,
                            color: _small == null ? AppColors.textMutedDark : AppColors.primary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _small?.name ?? 'لم يتم اختيار ملف الاحاله',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: AppColors.textSecondaryDark, fontSize: 12),
                            ),
                          ),
                          ElevatedButton(
                            onPressed: _busy ? null : () => _pick(false),
                            style: ElevatedButton.styleFrom(
                              minimumSize: Size.zero,
                              backgroundColor: const Color(0xFF1E293B),
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Color(0xFF334155)),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            child: Text(_small == null ? 'اختيار' : 'تغيير', style: const TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                    ] else ...[
                      TextField(
                        controller: _textPlatesController,
                        maxLines: 4,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'اكتب أو الصق أرقام اللوح هنا (كل لوحة في سطر)\nمثال:\nأ ب ج 1234\nر س ر 9332',
                          hintStyle: const TextStyle(color: AppColors.textMutedDark, fontSize: 12),
                          filled: true,
                          fillColor: const Color(0xFF0F1624),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Color(0xFF24334C)),
                          ),
                          contentPadding: const EdgeInsets.all(10),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: canMatch ? _match : null,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                      )
                    : const Icon(Icons.compare_arrows_rounded),
                label: Text(_busy ? 'جاري القراءة والمطابقة...' : 'ابدأ الفرز', style: const TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
              ],

              if (r != null) ...[
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A2333),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF2A374F)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _line('صفوف الداتا', '${r.bigCount}', AppColors.textSecondaryDark),
                      _line('لوحات الاحاله', '${r.smallCount}', Colors.white),
                      _line('المشتركة مع الداتا', '${r.matchedRows.length}', AppColors.primary),
                      _line('غير موجودة بالداتا', '${r.notFoundPlates.length}', AppColors.warning),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: (r.matchedRows.isNotEmpty && !_busy) ? _export : null,
                          icon: const Icon(Icons.download_rounded, size: 18),
                          label: const Text('تصدير المشتركة إلى Excel', style: TextStyle(fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      if (_exportedPath != null) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'تم الحفظ في:\n$_exportedPath',
                                style: const TextStyle(color: AppColors.success, fontSize: 12),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () => ExternalActions.shareFile(
                                _exportedPath!,
                                text: 'نتائج المطابقة - صقر المملكة',
                              ),
                              icon: const Icon(Icons.share_rounded, size: 16, color: AppColors.primary),
                              label: const Text('مشاركة', style: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 8),
                        Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 12)),
                      ],
                    ],
                  ),
                ),

                // List of matched plates with scroll and tap to open details
                if (r.matchedRows.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'اللوحات المشتركة (اضغط على أي لوحة لعرض البيانات):',
                        style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${r.matchedRows.length} لوحة',
                        style: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Identify plate column in headers
                  Builder(builder: (context) {
                    var plateCol = 0;
                    for (int c = 0; c < r.headers.length; c++) {
                      final h = r.headers[c].toLowerCase();
                      if (h.contains('لوح') || h.contains('plate')) {
                        plateCol = c;
                        break;
                      }
                    }

                    return SizedBox(
                      height: 360,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xFF141E30),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFF24334C)),
                        ),
                        child: ListView.separated(
                          itemCount: r.matchedRows.length,
                          separatorBuilder: (_, __) => const Divider(color: Color(0xFF1E293B), height: 1),
                        itemBuilder: (context, i) {
                          final row = r.matchedRows[i];
                          final plateVal = plateCol < row.length ? row[plateCol] : 'صف ${i + 1}';
                          // Secondary text: next 1 or 2 fields
                          final secondVal = row.where((c) => c.isNotEmpty && c != plateVal).take(2).join(' • ');

                          return ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                            leading: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.directions_car_rounded, color: AppColors.primary, size: 18),
                            ),
                            title: Text(
                              plateVal,
                              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                            subtitle: secondVal.isNotEmpty
                                ? Text(
                                    secondVal,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: AppColors.textSecondaryDark, fontSize: 11),
                                  )
                                : null,
                            trailing: const Icon(Icons.arrow_forward_ios_rounded, color: AppColors.textMutedDark, size: 14),
                            onTap: () => _showPlateDetailsModal(row, r.headers, plateCol),
                          );
                        },
                      ),
                    ),
                  );
                  }),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _line(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondaryDark, fontSize: 13)),
          Text(value, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _fileCard({required String title, required PickedExcel? file, required VoidCallback onPick}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: file == null ? AppColors.borderDark : AppColors.primary.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(file == null ? Icons.insert_drive_file_outlined : Icons.table_chart_rounded,
              color: file == null ? AppColors.textMutedDark : AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                Text(
                  file?.name ?? 'لم يتم اختيار ملف',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textSecondaryDark, fontSize: 11),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: _busy ? null : onPick,
            style: ElevatedButton.styleFrom(
              minimumSize: Size.zero,
              backgroundColor: const Color(0xFF1E293B),
              foregroundColor: Colors.white,
              side: const BorderSide(color: Color(0xFF334155)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(file == null ? 'اختيار' : 'تغيير', style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}