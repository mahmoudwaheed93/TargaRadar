import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/date_formatter.dart';
import '../../core/widgets/custom_button.dart';
import '../../data/models/subscription_duration.dart';
import '../../data/models/user_model.dart';
import '../providers/user_management_provider.dart';

/// Opens the «تجديد الاشتراك» bottom sheet for [user].
///
/// Returns `true` when the renewal was saved successfully, otherwise `null`.
Future<bool?> showRenewSubscriptionSheet(BuildContext context, UserModel user) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _RenewSubscriptionSheet(user: user),
  );
}

class _RenewSubscriptionSheet extends StatefulWidget {
  const _RenewSubscriptionSheet({required this.user});

  final UserModel user;

  @override
  State<_RenewSubscriptionSheet> createState() =>
      _RenewSubscriptionSheetState();
}

class _RenewSubscriptionSheetState extends State<_RenewSubscriptionSheet> {
  DurationMode _mode = DurationMode.days;
  int _days = 30;
  DateTime? _specificDate;

  static const int _minDays = 1;
  static const int _maxDays = 3650;

  void _onModeChanged(DurationMode mode) {
    setState(() {
      _mode = mode;
      if (mode == DurationMode.specificDate && _specificDate == null) {
        _specificDate = DateTime.now().add(const Duration(days: 30));
      }
    });
  }

  Future<void> _pickSpecificDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _specificDate ?? now.add(const Duration(days: 30)),
      firstDate: now,
      lastDate: DateTime(now.year + 10, 12, 31),
      helpText: 'اختر تاريخ الانتهاء',
    );
    if (picked != null) {
      setState(() => _specificDate = picked);
    }
  }

  void _changeDays(int delta) {
    setState(() {
      _days = (_days + delta).clamp(_minDays, _maxDays);
    });
  }

  Future<void> _submit() async {
    final provider = context.read<UserManagementProvider>();
    provider.clearRenewError();

    final ok = await provider.renewSubscription(
      user: widget.user,
      mode: _mode,
      days: _days,
      specificDate: _specificDate,
    );

    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<UserManagementProvider>();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          decoration: const BoxDecoration(
            color: AppColors.cardDark,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(
              top: BorderSide(color: AppColors.borderDark, width: 1),
            ),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 18),
                    decoration: BoxDecoration(
                      color: AppColors.borderDark,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),

                // Title + user avatar row
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.surfaceDark,
                        border: Border.all(color: AppColors.borderDark),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        widget.user.username.isNotEmpty
                            ? widget.user.username[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'تجديد الاشتراك',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimaryDark,
                            ),
                          ),
                          Text(
                            widget.user.username,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondaryDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Subscription duration label
                const Text(
                  'مدة الاشتراك الجديدة',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondaryDark,
                  ),
                ),
                const SizedBox(height: 10),

                // Mode toggle
                _ModeToggle(mode: _mode, onChanged: _onModeChanged),
                const SizedBox(height: 16),

                // Days stepper or date picker
                if (_mode == DurationMode.days)
                  _DaysStepper(
                    days: _days,
                    onDecrement:
                        _days > _minDays ? () => _changeDays(-1) : null,
                    onIncrement:
                        _days < _maxDays ? () => _changeDays(1) : null,
                  )
                else
                  _DateField(
                    text: _specificDate == null
                        ? 'اختر تاريخاً'
                        : AppDateFormatter.arabicLong(_specificDate!),
                    onTap: _pickSpecificDate,
                  ),
                const SizedBox(height: 12),

                // Error banner
                if (provider.renewError != null) ...[
                  const SizedBox(height: 8),
                  _ErrorText(message: provider.renewError!),
                ],
                const SizedBox(height: 20),

                CustomButton(
                  text: 'تجديد الاشتراك',
                  icon: Icons.autorenew_rounded,
                  isLoading: provider.isRenewing,
                  onPressed: provider.isRenewing ? null : _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Reused UI widgets (same style as create_user_sheet) ─────────────────────

class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.mode, required this.onChanged});

  final DurationMode mode;
  final ValueChanged<DurationMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.inputFillDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderDark),
      ),
      child: Row(
        children: [
          _ModeOption(
            label: 'عدد الأيام',
            selected: mode == DurationMode.days,
            onTap: () => onChanged(DurationMode.days),
          ),
          _ModeOption(
            label: 'تاريخ محدد',
            selected: mode == DurationMode.specificDate,
            onTap: () => onChanged(DurationMode.specificDate),
          ),
        ],
      ),
    );
  }
}

class _ModeOption extends StatelessWidget {
  const _ModeOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.bold,
              color: selected ? Colors.black : AppColors.textSecondaryDark,
            ),
          ),
        ),
      ),
    );
  }
}

class _DaysStepper extends StatelessWidget {
  const _DaysStepper({
    required this.days,
    required this.onDecrement,
    required this.onIncrement,
  });

  final int days;
  final VoidCallback? onDecrement;
  final VoidCallback? onIncrement;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.inputFillDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderDark),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _StepButton(icon: Icons.remove_rounded, onTap: onDecrement),
          Text(
            '$days يوماً',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimaryDark,
            ),
          ),
          _StepButton(icon: Icons.add_rounded, onTap: onIncrement),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: enabled
              ? AppColors.primary.withValues(alpha: 0.12)
              : AppColors.disabled.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          color: enabled ? AppColors.primary : AppColors.disabled,
          size: 22,
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.inputFillDark,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.borderDark),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.calendar_today_rounded,
              size: 18,
              color: AppColors.textSecondaryDark,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 15,
                  color: AppColors.textPrimaryDark,
                ),
              ),
            ),
            const Icon(
              Icons.arrow_drop_down_rounded,
              color: AppColors.textSecondaryDark,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: AppColors.error,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.error,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
