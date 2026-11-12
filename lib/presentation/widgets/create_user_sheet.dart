import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/date_formatter.dart';
import '../../core/widgets/custom_button.dart';
import '../../core/widgets/custom_text_field.dart';
import '../../data/models/subscription_duration.dart';
import '../providers/user_management_provider.dart';

/// Opens the "إنشاء مستخدم جديد" bottom sheet.
///
/// Returns `true` when a user was created successfully, otherwise `null`.
Future<bool?> showCreateUserSheet(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _CreateUserSheet(),
  );
}

class _CreateUserSheet extends StatefulWidget {
  const _CreateUserSheet();

  @override
  State<_CreateUserSheet> createState() => _CreateUserSheetState();
}

class _CreateUserSheetState extends State<_CreateUserSheet> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _isActive = true;
  DurationMode _mode = DurationMode.days;
  int _days = 30;
  DateTime? _specificDate;

  static const int _minDays = 1;
  static const int _maxDays = 3650;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

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
    if (!_formKey.currentState!.validate()) return;

    final provider = context.read<UserManagementProvider>();
    provider.clearCreateError();

    final ok = await provider.createUser(
      username: _usernameController.text,
      password: _passwordController.text,
      isActive: _isActive,
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
        // Lift the sheet above the keyboard.
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.9,
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
            child: Form(
              key: _formKey,
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
                  const Text(
                    'إنشاء مستخدم جديد',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimaryDark,
                    ),
                  ),
                  const SizedBox(height: 22),

                  // Username
                  CustomTextField(
                    controller: _usernameController,
                    labelText: 'اسم المستخدم',
                    hintText: 'أدخل اسم المستخدم',
                    prefixIcon: const Icon(
                      Icons.person_outline_rounded,
                      color: AppColors.textSecondaryDark,
                    ),
                    textInputAction: TextInputAction.next,
                    onChanged: (_) => provider.clearCreateError(),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'يرجى إدخال اسم المستخدم' : null,
                  ),
                  const SizedBox(height: 16),

                  // Password
                  CustomTextField(
                    controller: _passwordController,
                    labelText: 'كلمة المرور',
                    hintText: 'أدخل كلمة المرور',
                    obscureText: _obscurePassword,
                    prefixIcon: const Icon(
                      Icons.lock_outline_rounded,
                      color: AppColors.textSecondaryDark,
                    ),
                    suffixIcon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: AppColors.textSecondaryDark,
                    ),
                    onSuffixTap: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                    textInputAction: TextInputAction.done,
                    onChanged: (_) => provider.clearCreateError(),
                    validator: (v) => (v == null || v.length < 6)
                        ? 'كلمة المرور يجب أن تكون ٦ أحرف على الأقل'
                        : null,
                  ),
                  const SizedBox(height: 22),

                  // Subscription duration
                  const _SectionLabel('مدة الاشتراك'),
                  const SizedBox(height: 10),
                  _ModeToggle(
                    mode: _mode,
                    onChanged: _onModeChanged,
                  ),
                  const SizedBox(height: 16),
                  if (_mode == DurationMode.days)
                    _DaysStepper(
                      days: _days,
                      onDecrement: _days > _minDays ? () => _changeDays(-1) : null,
                      onIncrement: _days < _maxDays ? () => _changeDays(1) : null,
                    )
                  else
                    _DateField(
                      text: _specificDate == null
                          ? 'اختر تاريخاً'
                          : AppDateFormatter.arabicLong(_specificDate!),
                      onTap: _pickSpecificDate,
                    ),
                  const SizedBox(height: 12),

                  // Activate immediately switch
                  _ActivateSwitch(
                    value: _isActive,
                    onChanged: (v) => setState(() => _isActive = v),
                  ),
                  const SizedBox(height: 8),

                  // Error banner
                  if (provider.createError != null) ...[
                    const SizedBox(height: 8),
                    _ErrorText(message: provider.createError!),
                  ],
                  const SizedBox(height: 20),

                  CustomButton(
                    text: 'إنشاء الحساب',
                    icon: Icons.person_add_alt_1_rounded,
                    isLoading: provider.isCreating,
                    onPressed: provider.isCreating ? null : _submit,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.textSecondaryDark,
      ),
    );
  }
}

/// Two-option segmented toggle: [عدد الأيام] / [تاريخ محدد].
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

/// -/+ stepper with the day count, labelled "يوماً".
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

/// Read-only field that opens the date picker on tap.
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

class _ActivateSwitch extends StatelessWidget {
  const _ActivateSwitch({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.inputFillDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderDark),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'تفعيل الحساب فوراً',
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimaryDark,
              ),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppColors.primary,
            activeTrackColor: AppColors.primary.withValues(alpha: 0.4),
          ),
        ],
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
          const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 20),
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
