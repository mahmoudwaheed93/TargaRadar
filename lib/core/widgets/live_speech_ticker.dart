import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../services/speech_service.dart';

/// Single-line auto-scrolling live speech-to-text ribbon.
/// Never expands vertically, truncates with ellipsis, or freezes the screen
/// regardless of how long continuous dictation runs.
class LiveSpeechTicker extends StatefulWidget {
  final String transcript;
  final bool isListening;
  final EdgeInsetsGeometry margin;

  const LiveSpeechTicker({
    super.key,
    required this.transcript,
    required this.isListening,
    this.margin = EdgeInsets.zero,
  });

  @override
  State<LiveSpeechTicker> createState() => _LiveSpeechTickerState();
}

class _LiveSpeechTickerState extends State<LiveSpeechTicker> {
  final ScrollController _scrollController = ScrollController();

  @override
  void didUpdateWidget(covariant LiveSpeechTicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.transcript != oldWidget.transcript && widget.transcript.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        final max = _scrollController.position.maxScrollExtent;
        if (max > 0) {
          _scrollController.jumpTo(max);
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasText = widget.transcript.isNotEmpty;
    return RepaintBoundary(
      child: Container(
        height: 36,
        width: double.infinity,
        margin: widget.margin,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF0F1624),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: widget.isListening
                ? AppColors.primary.withValues(alpha: 0.45)
                : const Color(0xFF232F46),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.graphic_eq_rounded,
              size: 16,
              color: widget.isListening ? AppColors.primary : AppColors.textMutedDark,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: hasText
                  ? SingleChildScrollView(
                      controller: _scrollController,
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          widget.transcript,
                          maxLines: 1,
                          softWrap: false,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    )
                  : const Text(
                      'تحدث الآن... الكلام يتحول لشريط كتابة فوري متحرك',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppColors.textMutedDark, fontSize: 11),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact speed mode pill allowing users with the Arabic offline pack installed
/// to switch between On-Device (~50-100ms) and Cloud STT (automatic fallback).
class SpeechSpeedModeChip extends StatelessWidget {
  const SpeechSpeedModeChip({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: SpeechService.instance.preferOnDeviceNotifier,
      builder: (context, preferOnDevice, _) {
        return Tooltip(
          message: preferOnDevice
              ? 'وضع السرعة القصوى (معالج الموبايل أوفلاين + رجوع تلقائي للسحابة)'
              : 'وضع البث السحابي (Google Streaming)',
          child: InkWell(
            onTap: () => SpeechService.instance.setPreferOnDevice(!preferOnDevice),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: preferOnDevice
                    ? AppColors.success.withValues(alpha: 0.16)
                    : const Color(0xFF1A2333),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: preferOnDevice
                      ? AppColors.success.withValues(alpha: 0.5)
                      : const Color(0xFF2A374F),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    preferOnDevice ? Icons.bolt_rounded : Icons.cloud_done_rounded,
                    size: 13,
                    color: preferOnDevice ? AppColors.success : AppColors.textSecondaryDark,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    preferOnDevice ? 'أوفلاين سريع' : 'سحابي Cloud',
                    style: TextStyle(
                      color: preferOnDevice ? AppColors.success : AppColors.textSecondaryDark,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
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
}
