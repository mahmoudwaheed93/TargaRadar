import 'package:url_launcher/url_launcher.dart';
import '../../core/services/sound_alert_service.dart';
import '../../core/widgets/live_speech_ticker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/ai_plate_refiner.dart';
import '../../core/services/arabic_voice_normalizer.dart';
import '../../data/models/car_record_model.dart';
import '../../data/models/excel_vehicle_model.dart';
import '../providers/auth_provider.dart';
import '../providers/car_record_provider.dart';
import '../providers/inspection_provider.dart';
import '../providers/excel_sort_audit_provider.dart';
import '../widgets/excel_import_dialog.dart';

class VoiceRegistrationScreen extends StatefulWidget {
  const VoiceRegistrationScreen({super.key});

  @override
  State<VoiceRegistrationScreen> createState() => _VoiceRegistrationScreenState();
}

class _VoiceRegistrationScreenState extends State<VoiceRegistrationScreen> {
  final TextEditingController _districtController = TextEditingController();
  final TextEditingController _streetController = TextEditingController();
  final TextEditingController _recorderController = TextEditingController();
  final FocusNode _recorderFocus = FocusNode();
  final TextEditingController _textPlatesController = TextEditingController();
  bool _useTextInput = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final auth = context.read<AuthProvider>();
      final records = context.read<CarRecordProvider>();
      await records.ensureRecorderName(auth.currentUser?.username);
      if (!mounted) return;
      if (_recorderController.text.isEmpty) {
        _recorderController.text = records.recorderName;
      }
    });
  }

  @override
  void dispose() {
    _districtController.dispose();
    _streetController.dispose();
    _recorderController.dispose();
    _recorderFocus.dispose();
    _textPlatesController.dispose();
    super.dispose();
  }

  void _showFileImportDialog(BuildContext context, ExcelSortAuditProvider auditProvider) {
    showExcelImportDialog(context, auditProvider);
  }

  void _showAiSettingsDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        final tokenController = TextEditingController();
        bool isObscured = true;
        bool isTesting = false;
        String? testResult;
        bool? testSuccess;

        return StatefulBuilder(
          builder: (ctx, setState) {
            if (tokenController.text.isEmpty) {
              AiPlateRefiner.instance.getGroqToken().then((tok) {
                if (tok.isNotEmpty && tokenController.text.isEmpty && ctx.mounted) {
                  setState(() => tokenController.text = tok);
                }
              });
            }

            final hasToken = tokenController.text.trim().isNotEmpty;

            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                backgroundColor: const Color(0xFF131B2A),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: const BorderSide(color: Color(0xFF1F2B42), width: 1),
                ),
                title: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.auto_awesome, color: Colors.amber, size: 22),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'محرك الذكاء الاصطناعي (Groq LPU)',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A2333),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF2A374F)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  hasToken ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                                  color: hasToken ? AppColors.success : Colors.amber,
                                  size: 16,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    hasToken
                                        ? 'Groq LPU نشط (14,400 طلب مجاني يومياً)'
                                        : 'المعالج المحلي (0ms) نشط | Groq غير مفعّل',
                                    style: TextStyle(
                                      color: hasToken ? AppColors.success : Colors.amber,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              '• التعرف الصوتي الأساسي يعمل محلياً بالكامل على الجهاز في 0 ثانية وبدون إنترنت.\n'
                              '• محرك Groq المجاني يعمل كاحتياطي فائق السرعة (~120ms) لمعالجة اللهجات المشوشة.',
                              style: TextStyle(color: AppColors.textMutedDark, fontSize: 11, height: 1.4),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'مفتاح Groq API Key (مجاني):',
                        style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: tokenController,
                        obscureText: isObscured,
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'monospace'),
                        decoration: InputDecoration(
                          hintText: 'gsk_...',
                          hintStyle: const TextStyle(color: AppColors.textMutedDark, fontSize: 12),
                          filled: true,
                          fillColor: const Color(0xFF10141D),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Color(0xFF2A374F)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Color(0xFF2A374F)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: AppColors.primary),
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(
                              isObscured ? Icons.visibility_off : Icons.visibility,
                              color: AppColors.textMutedDark,
                              size: 18,
                            ),
                            onPressed: () => setState(() => isObscured = !isObscured),
                          ),
                        ),
                        onChanged: (_) => setState(() {
                          testResult = null;
                          testSuccess = null;
                        }),
                      ),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: () async {
                          final uri = Uri.parse('https://console.groq.com/keys');
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri, mode: LaunchMode.externalApplication);
                          }
                        },
                        child: const Row(
                          children: [
                            Icon(Icons.open_in_new, color: AppColors.primary, size: 14),
                            SizedBox(width: 4),
                            Text(
                              'اضغط هنا لإنشاء مفتاح مجاني في 30 ثانية',
                              style: TextStyle(
                                color: AppColors.primary,
                                fontSize: 11,
                                decoration: TextDecoration.underline,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (testResult != null) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: testSuccess == true
                                ? AppColors.success.withValues(alpha: 0.15)
                                : AppColors.error.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: testSuccess == true ? AppColors.success : AppColors.error,
                              width: 0.5,
                            ),
                          ),
                          child: Text(
                            testResult!,
                            style: TextStyle(
                              color: testSuccess == true ? AppColors.success : AppColors.error,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogCtx).pop(),
                    child: const Text('إلغاء', style: TextStyle(color: AppColors.textMutedDark)),
                  ),
                  TextButton(
                    onPressed: isTesting
                        ? null
                        : () async {
                            final input = tokenController.text.trim();
                            if (input.isEmpty) {
                              setState(() {
                                testResult = 'يرجى إدخال المفتاح أولاً لاختباره';
                                testSuccess = false;
                              });
                              return;
                            }
                            setState(() {
                              isTesting = true;
                              testResult = null;
                            });
                            final res = await AiPlateRefiner.instance.testConnection(customToken: input);
                            if (dialogCtx.mounted) {
                              setState(() {
                                isTesting = false;
                                testSuccess = res.success;
                                testResult = '${res.message} (${res.latencyMs}ms)';
                              });
                            }
                          },
                    child: isTesting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amber),
                          )
                        : const Text('اختبار المفتاح', style: TextStyle(color: Colors.amber)),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () async {
                      await AiPlateRefiner.instance.setGroqToken(tokenController.text.trim());
                      if (dialogCtx.mounted) {
                        Navigator.of(dialogCtx).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('تم حفظ إعدادات Groq بنجاح'),
                            backgroundColor: AppColors.success,
                          ),
                        );
                      }
                    },
                    child: const Text('حفظ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// Shows a bottom sheet with the full matched plate details (like the inspection screen).
  void _showMatchedPlateDetails(BuildContext context, AuditedLogItem result) {
    if (!result.isMatched) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.cardDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
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
                          result.plateNumber,
                          style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                      ),
                      Text(result.timestamp, style: const TextStyle(color: AppColors.textMutedDark, fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'اللوحة موجودة في الشيت — بياناتها كاملة:',
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
                      child: ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        children: [
                          _detailRow('نوع السيارة', result.carType),
                          _detailRow('اللون', result.color),
                          _detailRow('المالك', result.owner),
                          _detailRow('الملاحظات', result.notes),
                          ...result.otherFields.entries
                              .where((kv) => kv.value.isNotEmpty && kv.value != '-')
                              .map((kv) => _detailRow(kv.key, kv.value)),
                        ],
                      ),
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
  }

  bool _isLocationUrl(String val) {
    final v = val.toLowerCase().trim();
    return v.startsWith('http://') || v.startsWith('https://') || v.contains('maps.google.com') || v.contains('google.com/maps') || v.contains('maps.app.goo.gl');
  }

  Future<void> _openMapUrl(String url) async {
    try {
      final uri = Uri.parse(url.trim());
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Error launching maps url: $e');
    }
  }

  Widget _detailRow(String label, String value) {
    final isUrl = _isLocationUrl(value) || label.contains('موقع') || label.contains('خريطة') || label.contains('خرائط');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: const TextStyle(color: AppColors.textMutedDark, fontSize: 12)),
          ),
          Expanded(
            child: isUrl && (value.startsWith('http') || value.contains('google.com'))
                ? InkWell(
                    onTap: () => _openMapUrl(value),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.location_on, color: AppColors.primary, size: 16),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            'فتح الموقع في الخريطة',
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
                : Text(value, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final recordProvider = context.read<CarRecordProvider>();
    final auditProvider = context.read<ExcelSortAuditProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFF10141D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF131B2A),
        elevation: 0,
        title: Row(
          children: [
            const Text(
              'تسجيل الجلسة',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 8),
            Selector<CarRecordProvider, int>(
              selector: (_, p) => p.recordsVersion,
              builder: (_, __, ___) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${recordProvider.records.length} لوحة',
                  style: const TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
        actions: [

          // Export session Excel
          IconButton(
            icon: const Icon(Icons.download_rounded, color: AppColors.primary, size: 22),
            tooltip: 'تصدير الجلسة إلى Excel',
            onPressed: () async {
              final path = await recordProvider.exportRecordsToExcel();
              if (!context.mounted) return;
              if (path != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('تم تصدير سجل الجلسة بنجاح إلى:\n$path'),
                    backgroundColor: AppColors.success,
                  ),
                );
              }
            },
          ),
          // Clear all records
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined, color: AppColors.error, size: 22),
            tooltip: 'تصفير الجلسة',
            onPressed: () async {
              await recordProvider.clearAllRecords();
            },
          ),
        ],
      ),
      body: Selector<CarRecordProvider, (int, bool)>(
        selector: (_, p) => (p.recordsVersion, _useTextInput),
        builder: (context, _, __) => CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Column(
        children: [
                    // District Input Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFF162032),
              border: Border(bottom: BorderSide(color: Color(0xFF1F2B42), width: 0.5)),
            ),
            child: Row(
              children: [
                const Icon(Icons.location_city_rounded, color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _districtController,
                    onChanged: (val) => recordProvider.setCurrentDistrict(val),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: const InputDecoration(
                      hintText: 'الحي الحالي للسيارات (اختياري)',
                      hintStyle: TextStyle(color: AppColors.textMutedDark, fontSize: 12),
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Street Input Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: const Color(0xFF162032),
            child: Row(
              children: [
                const Icon(Icons.location_on_rounded, color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _streetController,
                    onChanged: (val) => recordProvider.setCurrentStreet(val),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: const InputDecoration(
                      hintText: 'الشارع الحالي للسيارات القادمة',
                      hintStyle: TextStyle(color: AppColors.textMutedDark, fontSize: 12),
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                    ),
                  ),
                ),
                Selector<CarRecordProvider, String?>(
                  selector: (_, p) => p.stickyNote,
                  builder: (_, sticky, __) => sticky == null
                      ? const SizedBox.shrink()
                      : Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.warning.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
                          ),
                          child: Text(
                            sticky,
                            style: const TextStyle(color: AppColors.warning, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                ),
              ],
            ),
          ),

          // Recorder (user) name — editable, persisted, written into the exported Excel
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            color: const Color(0xFF162032),
            child: Row(
              children: [
                const Icon(Icons.person_rounded, color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _recorderController,
                    focusNode: _recorderFocus,
                    onChanged: (val) => recordProvider.setRecorderName(val),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: const InputDecoration(
                      hintText: 'اسم المستخدم (يظهر في شيت الإكسيل)',
                      hintStyle: TextStyle(color: AppColors.textMutedDark, fontSize: 12),
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                    ),
                  ),
                ),
                const Icon(Icons.edit_rounded, color: AppColors.textMutedDark, size: 14),
              ],
            ),
          ),

          // Excel Matching Strip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFF101726),
              border: Border(bottom: BorderSide(color: Color(0xFF232F46))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                        ),
                        child: const Icon(Icons.table_chart_rounded, color: AppColors.primary, size: 16),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Selector<ExcelSortAuditProvider, (String, int)>(
                          selector: (_, a) => (a.sheetFileName, a.totalSheetCount),
                          builder: (_, data, __) => Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                data.$1.isEmpty ? 'لم يتم رفع شيت بعد' : data.$1,
                                style: const TextStyle(color: AppColors.textSecondaryDark, fontSize: 11, fontFamily: 'monospace'),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                data.$2 == 0
                                    ? 'ارفع شيت إكسيل للمطابقة الفورية'
                                    : '${data.$2} سيارة بالشيت (مطابقة فورية)',
                                style: const TextStyle(color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () => _showFileImportDialog(context, auditProvider),
                  icon: const Icon(Icons.upload_file_rounded, size: 14),
                  label: const Text('تغيير الشيت', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    minimumSize: Size.zero,
                    backgroundColor: const Color(0xFF1E293B),
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFF334155)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                ),
              ],
            ),
          ),

          // Competitor Real-Time HUD (Header Badge + Live Button)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: const Color(0xFF131B2A),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                      ),
                      child: const Text(
                        'جارية',
                        style: TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F1624),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF24334C)),
                      ),
                      child: Row(
                        children: [
                          Text('${recordProvider.records.length}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                          const SizedBox(width: 4),
                          const Text('لوحات', style: TextStyle(color: AppColors.textMutedDark, fontSize: 11)),
                          const SizedBox(width: 6),
                          const Text('|', style: TextStyle(color: Color(0xFF334155))),
                          const SizedBox(width: 6),
                          Text('${recordProvider.matchedCount}', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 12)),
                          const SizedBox(width: 4),
                          const Text('مطابقة', style: TextStyle(color: AppColors.primary, fontSize: 11)),
                        ],
                      ),
                    ),
                  ],
                ),

                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SpeechSpeedModeChip(),
                    const SizedBox(width: 6),
                    Selector<CarRecordProvider, (bool, int)>(
                      selector: (_, p) => (p.isListening, p.listeningTimer),
                      builder: (_, st, __) => ElevatedButton.icon(
                        onPressed: () async {
                          final insp = context.read<InspectionProvider>();
                          if (insp.isListening) await insp.stopListening();
                          await recordProvider.toggleVoiceListening(
                            sortAuditProvider: auditProvider,
                            onPlateAdded: (plate, isMatched, model) {
                              if (isMatched) {
                                SoundAlertService.instance.playMatchAlarm(durationSeconds: 3);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('🎯 لوحة مطابقة بالشيت: $plate ($model)'),
                                      backgroundColor: AppColors.success,
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                                }
                              }
                            },
                          );
                        },
                        icon: Icon(
                          st.$1 ? Icons.stop_rounded : Icons.mic_rounded,
                          size: 16,
                        ),
                        label: Text(
                          st.$1 ? 'إيقاف (${st.$2}s)' : 'مباشر • يستمع',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          minimumSize: Size.zero,
                          backgroundColor: st.$1
                              ? AppColors.error.withValues(alpha: 0.2)
                              : AppColors.primary.withValues(alpha: 0.2),
                          foregroundColor: st.$1 ? AppColors.error : AppColors.primary,
                          side: BorderSide(
                            color: st.$1 ? AppColors.error : AppColors.primary,
                          ),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Toggle Mode (صوت مباشر / إدخال نصي)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFF131B2A),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF232F46)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _useTextInput = false),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: !_useTextInput ? AppColors.primary : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.mic, size: 16, color: !_useTextInput ? Colors.black : Colors.white70),
                          const SizedBox(width: 6),
                          Text(
                            'تسجيل صوتي مباشر',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: !_useTextInput ? Colors.black : Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _useTextInput = true),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: _useTextInput ? AppColors.primary : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.text_fields, size: 16, color: _useTextInput ? Colors.black : Colors.white70),
                          const SizedBox(width: 6),
                          Text(
                            'إدخال نصي (لوحات)',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: _useTextInput ? Colors.black : Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (_useTextInput)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF1A2333),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF2A374F)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.keyboard_alt_outlined, color: AppColors.primary, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'إدخال لوحات كنص للمقارنة والتسجيل',
                        style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'اكتب أو الصق أرقام اللوحات هنا (كل لوحة في سطر):',
                    style: TextStyle(color: AppColors.textMutedDark, fontSize: 11),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _textPlatesController,
                    maxLines: 4,
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'monospace'),
                    decoration: InputDecoration(
                      hintText: 'مثال:\n1234 أ ب ج\n5678 د ر س\n9012 ص ع ط',
                      hintStyle: const TextStyle(color: AppColors.textMutedDark, fontSize: 11),
                      filled: true,
                      fillColor: const Color(0xFF10141D),
                      contentPadding: const EdgeInsets.all(12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF24334C))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF24334C))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.primary)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final raw = _textPlatesController.text.trim();
                        if (raw.isEmpty) return;
                        final lines = raw.split(RegExp(r'[\r\n]+')).map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
                        if (lines.isEmpty) return;

                        final matchedCount = await recordProvider.processTextPlates(
                          plates: lines,
                          sortAuditProvider: auditProvider,
                          onPlateAdded: (plate, isMatched, model) {
                            if (isMatched) {
                              SoundAlertService.instance.playMatchAlarm(durationSeconds: 3);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('🎯 لوحة مطابقة بالشيت: $plate ($model)'),
                                  backgroundColor: AppColors.success,
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                              if (recordProvider.lastMatchResult != null && recordProvider.lastMatchResult!.isMatched) {
                                _showMatchedPlateDetails(context, recordProvider.lastMatchResult!);
                              }
                            }
                          },
                        );

                        if (!context.mounted) return;
                        _textPlatesController.clear();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('تمت معالجة ${lines.length} لوحة بنجاح ($matchedCount مطابقة)'),
                            backgroundColor: matchedCount > 0 ? AppColors.success : AppColors.cardDark,
                          ),
                        );
                      },
                      icon: const Icon(Icons.playlist_add_check_rounded, size: 16),
                      label: const Text('تسجيل ومقارنة اللوحات', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Card 1: Last Read Plate & 7-Slots
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF1A2333),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF2A374F)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('آخر قراءة مكتملة', style: TextStyle(color: AppColors.textMutedDark, fontSize: 11)),
                    Selector<CarRecordProvider, int>(
                      selector: (_, p) => p.listeningTimer,
                      builder: (_, sec, __) => Text(
                        '${(sec ~/ 60).toString().padLeft(2, '0')}:${(sec % 60).toString().padLeft(2, '0')}',
                        style: const TextStyle(color: AppColors.primary, fontSize: 11, fontFamily: 'monospace', fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  recordProvider.lastReadPlate.isEmpty ? '- - -' : recordProvider.lastReadPlate,
                  style: TextStyle(
                    color: recordProvider.lastReadIsWanted ? AppColors.primary : Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
                Text(
                  recordProvider.lastReadPlate.isEmpty
                      ? 'في انتظار قراءة أول لوحة...'
                      : (recordProvider.lastReadIsWanted ? '🎯 سيارة مسجلة ومطابقة للشيت' : ''),
                  style: TextStyle(
                    color: recordProvider.lastReadIsWanted ? AppColors.primary : AppColors.textSecondaryDark,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),

                const SizedBox(height: 10),
                const Divider(color: Color(0xFF232F46), height: 1),
                const SizedBox(height: 8),

                const Text('اللوحة الحالية • جاري الالتقاط بالصوت', style: TextStyle(color: AppColors.textMutedDark, fontSize: 11)),
                const SizedBox(height: 6),

                // 7-Slots Interactive Visualizer (isolated RepaintBoundary + Selector)
                RepaintBoundary(
                  child: Selector<CarRecordProvider, Map<String, String>>(
                    selector: (_, p) => p.currentSlots,
                    builder: (_, slots, __) => Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildBigSlot(slots['d4'] ?? '-', isDigit: true),
                        const SizedBox(width: 4),
                        _buildBigSlot(slots['d3'] ?? '-', isDigit: true),
                        const SizedBox(width: 4),
                        _buildBigSlot(slots['d2'] ?? '-', isDigit: true),
                        const SizedBox(width: 4),
                        _buildBigSlot(slots['d1'] ?? '-', isDigit: true),
                        const SizedBox(width: 8),
                        Container(width: 4, height: 4, decoration: const BoxDecoration(color: Color(0xFF64748B), shape: BoxShape.circle)),
                        const SizedBox(width: 8),
                        _buildBigSlot(slots['l3'] ?? '-'),
                        const SizedBox(width: 4),
                        _buildBigSlot(slots['l2'] ?? '-'),
                        const SizedBox(width: 4),
                        _buildBigSlot(slots['l1'] ?? '-'),
                      ],
                    ),
                  ),
                ),
                Selector<CarRecordProvider, (bool, String)>(
                  selector: (_, p) => (p.isListening, p.currentTranscript),
                  builder: (_, st, __) {
                    if (!st.$1 && st.$2.isEmpty) return const SizedBox.shrink();
                    return LiveSpeechTicker(
                      isListening: st.$1,
                      transcript: st.$2,
                      margin: const EdgeInsets.only(top: 8),
                    );
                  },
                ),
              ],
            ),
          ),

          // Card 2: Dedicated Matched Result Card (Identical to Web/Sort View)
          if (recordProvider.lastMatchResult != null && recordProvider.lastMatchResult!.isMatched)
            _buildMatchedResultCard(recordProvider.lastMatchResult!),

        ],
            ),
          ),

          // Real-time table
          if (recordProvider.records.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'لا توجد سيارات مسجلة بعد.\nاضغط على زر "مباشر" وتحدث بالصوت!',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textMutedDark, fontSize: 13),
                  ),
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (ctx, idx) {
                  final rec = recordProvider.records[idx];
                  final seq = recordProvider.records.length - idx;
                  return _buildRecordRow(recordProvider, rec, seq);
                },
                childCount: recordProvider.records.length,
              ),
            ),
        ],
        ),
      ),
    );
  }

  Widget _buildRecordRow(CarRecordProvider recordProvider, CarRecord rec, int seq) {
    return InkWell(
      onTap: rec.isMatched
          ? () {
              final audit = context.read<ExcelSortAuditProvider>();
              final key = ArabicVoiceNormalizer.plateKey(rec.plateNumber);
              final item = audit.sheetItems.where((i) => ArabicVoiceNormalizer.plateKey(i.rawPlate) == key).firstOrNull;
              _showMatchedPlateDetails(
                context,
                AuditedLogItem(
                  id: 'rec-${rec.id}',
                  seqNumber: seq,
                  plateNumber: rec.plateNumber,
                  normalizedPlate: key,
                  isMatched: true,
                  carType: rec.carType,
                  color: rec.color,
                  owner: rec.owner,
                  notes: rec.notes,
                  timestamp: '${rec.registrationDate.hour.toString().padLeft(2, '0')}:${rec.registrationDate.minute.toString().padLeft(2, '0')}',
                  otherFields: item?.otherFields ?? const {},
                ),
              );
            }
          : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: const BoxDecoration(
          color: Color(0xFF121927),
          border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
        ),
        child: Row(
          children: [
            Text(
              '#$seq',
              style: const TextStyle(color: AppColors.textMutedDark, fontSize: 11, fontFamily: 'monospace'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        rec.plateNumber,
                        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                      if (rec.isMatched) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                          ),
                          child: const Text('شيت ✓', style: TextStyle(color: AppColors.primary, fontSize: 9, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${rec.carType} • ${rec.notes} • ${rec.street}',
                    style: const TextStyle(color: AppColors.textSecondaryDark, fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: AppColors.textMutedDark, size: 18),
              onPressed: () {
                if (rec.id != null) recordProvider.deleteRecord(rec.id!);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBigSlot(String char, {bool isDigit = false}) {
    return Container(
      width: 32,
      height: 38,
      decoration: BoxDecoration(
        color: const Color(0xFF0F1624),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDigit ? const Color(0xFF2A374F) : AppColors.primary.withValues(alpha: 0.5),
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        char,
        style: TextStyle(
          color: isDigit ? Colors.white : AppColors.primary,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildMatchedResultCard(AuditedLogItem result) {
    final isMatched = result.isMatched;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isMatched
              ? [const Color(0xFF0F291E), const Color(0xFF14232C)]
              : [const Color(0xFF2D1A12), const Color(0xFF1E1724)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isMatched ? AppColors.primary : AppColors.warning,
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    isMatched ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
                    color: isMatched ? AppColors.primary : AppColors.warning,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isMatched ? 'سيارة مسجلة ومطابقة للشيت!' : '⚠️ غير مسجلة بالشيت (تم حفظها بالجلسة)',
                    style: TextStyle(
                      color: isMatched ? AppColors.primary : AppColors.warning,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Text(
                result.timestamp,
                style: const TextStyle(color: AppColors.textMutedDark, fontSize: 10, fontFamily: 'monospace'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                result.plateNumber,
                style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
              ),
              if (isMatched)
                Text(
                  result.carType,
                  style: const TextStyle(color: AppColors.info, fontSize: 12, fontWeight: FontWeight.bold),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
                  ),
                  child: const Text('سيارة جديدة', style: TextStyle(color: AppColors.warning, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
          if (isMatched) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(6)),
                    child: Text('اللون: ${result.color}', style: const TextStyle(color: Colors.white, fontSize: 10)),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(6)),
                    child: Text('المالك: ${result.owner}', style: const TextStyle(color: Colors.white, fontSize: 10), overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
