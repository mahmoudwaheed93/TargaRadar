import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/sound_alert_service.dart';
import '../../core/widgets/live_speech_ticker.dart';
import '../providers/car_record_provider.dart';
import '../providers/inspection_provider.dart';

class InspectionScreen extends StatefulWidget {
  const InspectionScreen({super.key});

  @override
  State<InspectionScreen> createState() => _InspectionScreenState();
}

class _InspectionScreenState extends State<InspectionScreen> {
  bool _detailsOpen = false;
  final TextEditingController _textPlatesController = TextEditingController();
  bool _useTextInput = false;

  @override
  void dispose() {
    _textPlatesController.dispose();
    super.dispose();
  }

  void _snack(String msg, {Color color = AppColors.info}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  bool _isLocationUrl(String val) {
    final v = val.toLowerCase().trim();
    return v.startsWith('http://') ||
        v.startsWith('https://') ||
        v.contains('maps.google.com') ||
        v.contains('google.com/maps') ||
        v.contains('maps.app.goo.gl');
  }

  Future<void> _openMapUrl(String url) async {
    try {
      final uri = Uri.parse(url.trim());
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Error launching map url: $e');
    }
  }

  Future<void> _pickReference(InspectionProvider insp) async {
    final ok = await insp.pickReferenceFile();
    if (!mounted) return;
    if (ok) {
      _snack('تم تحميل ${insp.refCount} صف من "${insp.refFileName}"', color: AppColors.success);
    } else if (insp.error != null) {
      _snack(insp.error!, color: AppColors.error);
    }
  }

  Future<void> _toggleMic(InspectionProvider insp) async {
    if (insp.isListening) {
      await insp.stopListening();
      return;
    }
    // Only one microphone session at a time.
    final records = context.read<CarRecordProvider>();
    if (records.isListening) await records.stopVoiceListening();
    await insp.startListening(onMatch: (entry) {
      SoundAlertService.instance.playMatchAlarm(durationSeconds: 3);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🎯 سيارة مطابقة بالشيت: ${entry.plate}'),
            backgroundColor: AppColors.success,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    });
  }

  Future<void> _export(InspectionProvider insp) async {
    final name = context.read<CarRecordProvider>().recorderName;
    final path = await insp.exportSession(name);
    if (path == null) {
      _snack('مفيش لوحات متسجلة للتصدير', color: AppColors.warning);
    } else {
      _snack('تم تصدير شيت الفحص إلى:\n$path', color: AppColors.success);
    }
  }

  /// Full data of a plate found in the reference sheet, with the cancel action.
  Future<void> _showDetails(String entryId) async {
    if (_detailsOpen) return;
    _detailsOpen = true;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.cardDark,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        return Consumer<InspectionProvider>(
          builder: (ctx, insp, _) {
            final idx = insp.entries.indexWhere((e) => e.id == entryId);
            if (idx == -1) return const SizedBox.shrink();
            final e = insp.entries[idx];
            return SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            e.cancelled ? Icons.cancel_rounded : Icons.check_circle_rounded,
                            color: e.cancelled ? AppColors.error : AppColors.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              e.plate,
                              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                            ),
                          ),
                          Text(e.time, style: const TextStyle(color: AppColors.textMutedDark, fontSize: 12)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        e.cancelled ? 'تم إلغاء الفرزة' : 'اللوحة موجودة في الشيت — بياناتها كاملة:',
                        style: TextStyle(
                          color: e.cancelled ? AppColors.error : AppColors.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (e.note.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text('ملاحظة: ${e.note}', style: const TextStyle(color: AppColors.warning, fontSize: 12)),
                      ],
                      const SizedBox(height: 10),
                      Flexible(
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.surfaceDark,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.borderDark),
                          ),
                          child: ListView(
                            shrinkWrap: true,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            children: e.rowData.entries
                                .where((kv) => kv.value.isNotEmpty)
                                .map(
                                  (kv) {
                                    final isLoc = _isLocationUrl(kv.value) ||
                                        kv.key.contains('موقع') ||
                                        kv.key.contains('خريطة') ||
                                        kv.key.contains('خرائط') ||
                                        kv.key.toLowerCase().contains('gps');
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 5),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          SizedBox(
                                            width: 110,
                                            child: Text(kv.key,
                                                style: const TextStyle(color: AppColors.textMutedDark, fontSize: 12)),
                                          ),
                                          Expanded(
                                            child: isLoc
                                                ? InkWell(
                                                    onTap: () {
                                                      if (_isLocationUrl(kv.value)) {
                                                        _openMapUrl(kv.value);
                                                      } else {
                                                        _openMapUrl('https://maps.google.com/?q=${Uri.encodeComponent(kv.value)}');
                                                      }
                                                    },
                                                    child: Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        const Icon(Icons.location_on, color: AppColors.primary, size: 16),
                                                        const SizedBox(width: 4),
                                                        Flexible(
                                                          child: Text(
                                                            kv.value.startsWith('http') ? 'فتح الموقع في الخريطة ↗' : kv.value,
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
                                                    kv.value,
                                                    style: const TextStyle(
                                                        color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                                                  ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                )
                                .toList(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(ctx),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: const BorderSide(color: AppColors.borderDark),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                              child: const Text('إغلاق'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                insp.setCancelled(e.id, !e.cancelled);
                                Navigator.pop(ctx);
                              },
                              icon: Icon(e.cancelled ? Icons.undo_rounded : Icons.cancel_outlined, size: 18),
                              label: Text(e.cancelled ? 'استرجاع الفرزة' : 'إلغاء الفرزة'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: e.cancelled ? AppColors.primary : AppColors.error,
                                foregroundColor: e.cancelled ? Colors.black : Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    _detailsOpen = false;
  }

  @override
  Widget build(BuildContext context) {
    final insp = context.read<InspectionProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFF10141D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF131B2A),
        elevation: 0,
        title: const Text(
          'الفحص والتدقيق',
          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_rounded, color: AppColors.primary, size: 22),
            tooltip: 'تصدير الفحص إلى Excel جديد',
            onPressed: () => _export(insp),
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined, color: AppColors.error, size: 22),
            tooltip: 'تصفير الجلسة',
            onPressed: insp.clearSession,
          ),
        ],
      ),
      body: Selector<InspectionProvider, (int, bool)>(
        selector: (_, p) => (p.entriesVersion, _useTextInput),
        builder: (context, _, __) => CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              children: [
                // Reference sheet strip
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: const BoxDecoration(
                    color: Color(0xFF101726),
                    border: Border(bottom: BorderSide(color: Color(0xFF232F46))),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.table_chart_rounded, color: AppColors.primary, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Selector<InspectionProvider, (bool, String, int)>(
                          selector: (_, p) => (p.hasReference, p.refFileName, p.refCount),
                          builder: (_, ref, __) => Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                ref.$1 ? ref.$2 : 'لم يتم رفع شيت الفحص بعد',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: AppColors.textSecondaryDark, fontSize: 12),
                              ),
                              Text(
                                ref.$1 ? '${ref.$3} صف بالشيت' : 'ارفع الشيت الكبير اللي فيه بيانات اللوحات',
                                style: const TextStyle(color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Selector<InspectionProvider, (bool, bool)>(
                        selector: (_, p) => (p.loadingFile, p.hasReference),
                        builder: (_, st, __) => ElevatedButton.icon(
                        onPressed: st.$1 ? null : () => _pickReference(insp),
                        icon: st.$1
                            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.upload_file_rounded, size: 14),
                        label: Text(
                          st.$1 ? 'جاري القراءة...' : (st.$2 ? 'تغيير الشيت' : 'رفع شيت'),
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          minimumSize: Size.zero,
                          backgroundColor: const Color(0xFF1E293B),
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Color(0xFF334155)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Stats
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  color: const Color(0xFF141E30),
                  child: Row(
                    children: [
                      _stat('الإجمالي', '${insp.totalCount}', Colors.white),
                      const SizedBox(width: 6),
                      _stat('بالشيت', '${insp.foundCount}', AppColors.primary),
                      const SizedBox(width: 6),
                      _stat('غير موجودة', '${insp.notFoundCount}', AppColors.warning),
                      const SizedBox(width: 6),
                      _stat('ملغاة', '${insp.cancelledCount}', AppColors.error),
                    ],
                  ),
                ),

                // Mic + live slots (isolated Selectors + RepaintBoundary)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  color: const Color(0xFF131B2A),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: RepaintBoundary(
                          child: Selector<InspectionProvider, Map<String, String>>(
                            selector: (_, p) => p.slots,
                            builder: (_, slots, __) => SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  for (final k in ['d4', 'd3', 'd2', 'd1']) ...[
                                    _slot(slots[k] ?? '-', digit: true),
                                    const SizedBox(width: 4),
                                  ],
                                  const SizedBox(width: 4),
                                  for (final k in ['l3', 'l2', 'l1']) ...[
                                    _slot(slots[k] ?? '-'),
                                    const SizedBox(width: 4),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SpeechSpeedModeChip(),
                          const SizedBox(width: 6),
                          Selector<InspectionProvider, (bool, int)>(
                            selector: (_, p) => (p.isListening, p.listeningSeconds),
                            builder: (_, st, __) => ElevatedButton.icon(
                              onPressed: () => _toggleMic(insp),
                              icon: Icon(st.$1 ? Icons.stop_rounded : Icons.mic_rounded, size: 16),
                              label: Text(
                                st.$1 ? 'إيقاف (${st.$2}s)' : 'مباشر • يستمع',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                              style: ElevatedButton.styleFrom(
                                minimumSize: Size.zero,
                                backgroundColor: (st.$1 ? AppColors.error : AppColors.primary).withValues(alpha: 0.2),
                                foregroundColor: st.$1 ? AppColors.error : AppColors.primary,
                                side: BorderSide(color: st.$1 ? AppColors.error : AppColors.primary),
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
                Selector<InspectionProvider, (bool, String)>(
                  selector: (_, p) => (p.isListening, p.currentTranscript),
                  builder: (_, st, __) {
                    if (!st.$1 && st.$2.isEmpty) return const SizedBox.shrink();
                    return LiveSpeechTicker(
                      isListening: st.$1,
                      transcript: st.$2,
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                    );
                  },
                ),

                // Toggle Mode (صوت مباشر / إدخال نصي)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
                                  'فحص صوتي مباشر',
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
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
                              'إدخال لوحات كنص للفحص والتدقيق',
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
                            hintText: 'مثال:\n1234 أ ب ج\n5678 د ر س',
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

                              final matchedCount = insp.processTextPlates(
                                lines,
                                onMatch: (entry) {
                                  SoundAlertService.instance.playMatchAlarm(durationSeconds: 3);
                                  if (mounted) _showDetails(entry.id);
                                },
                              );

                              _textPlatesController.clear();
                              _snack(
                                'تم فحص ${lines.length} لوحة بنجاح ($matchedCount مطابقة بالشيت)',
                                color: matchedCount > 0 ? AppColors.success : AppColors.cardDark,
                              );
                            },
                            icon: const Icon(Icons.playlist_add_check_rounded, size: 16),
                            label: const Text('فحص ومقارنة اللوحات', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
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
              ],
            ),
          ),

          if (insp.entries.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'ارفع الشيت، اضغط "مباشر" وقول أرقام اللوحات.\nبعد رقم اللوحة ممكن تقول "ملحوظة" وبعدها كلامك وهيتسجل مع اللوحة.\nأي لوحة موجودة في الشيت هتظهر بياناتها كاملة.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textMutedDark, fontSize: 13),
                  ),
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (ctx, i) => _entryTile(insp, insp.entries[i], insp.entries.length - i),
                childCount: insp.entries.length,
              ),
            ),
        ],
        ),
      ),
    );
  }

  Widget _entryTile(InspectionProvider insp, InspectionEntry e, int seq) {
    final color = e.cancelled ? AppColors.error : (e.inSheet ? AppColors.primary : AppColors.warning);
    final label = e.cancelled ? 'ملغاة' : (e.inSheet ? 'بالشيت ✓' : '');
    return InkWell(
      onTap: e.inSheet ? () => _showDetails(e.id) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: const BoxDecoration(
          color: Color(0xFF121927),
          border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
        ),
        child: Row(
          children: [
            Text('#$seq', style: const TextStyle(color: AppColors.textMutedDark, fontSize: 11, fontFamily: 'monospace')),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          e.plate,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: e.cancelled ? AppColors.textMutedDark : Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            decoration: e.cancelled ? TextDecoration.lineThrough : null,
                          ),
                        ),
                      ),
                      if (label.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: color.withValues(alpha: 0.4)),
                          ),
                          child: Text(label, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${e.time}${e.note.isNotEmpty ? ' • ${e.note}' : ''}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textSecondaryDark, fontSize: 11),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: AppColors.textMutedDark, size: 18),
              onPressed: () => insp.removeEntry(e.id),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String title, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF0F1624),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF24334C)),
        ),
        child: Column(
          children: [
            Text(value, style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.bold)),
            Text(title, style: const TextStyle(color: AppColors.textMutedDark, fontSize: 9)),
          ],
        ),
      ),
    );
  }

  Widget _slot(String ch, {bool digit = false}) {
    return Container(
      width: 26,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFF0F1624),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: digit ? const Color(0xFF2A374F) : AppColors.primary.withValues(alpha: 0.5)),
      ),
      child: Text(
        ch,
        style: TextStyle(color: digit ? Colors.white : AppColors.primary, fontSize: 13, fontWeight: FontWeight.bold),
      ),
    );
  }
}
