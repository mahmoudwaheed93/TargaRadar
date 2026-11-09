import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../core/widgets/custom_button.dart';
import '../../data/models/user_model.dart';
import '../providers/auth_provider.dart';
import 'login_screen.dart';

/// Account Blocked Screen (شاشة الحساب غير مفعل).
///
/// Shown when a user authenticates successfully but their subscription is
/// inactive or expired. Renders the subscription window from [UserModel] and
/// offers WhatsApp renewal plus a logout action back to the login screen.
class AccountBlockedScreen extends StatelessWidget {
  const AccountBlockedScreen({super.key, required this.user});

  final UserModel user;

  Future<void> _openWhatsApp(BuildContext context) async {
    final uri = Uri.parse(
      'https://wa.me/${AppConstants.supportWhatsAppNumber}'
      '?text=${Uri.encodeComponent(AppConstants.renewalWhatsAppMessage(user.username))}',
    );

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذر فتح تطبيق واتساب، يرجى المحاولة لاحقاً'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _logout(BuildContext context) {
    context.read<AuthProvider>().logout();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('yyyy/MM/dd');

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.backgroundDark,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _WarningGlowIcon(),
                    const SizedBox(height: 24),
                    const Text(
                      'الحساب غير مفعل حالياً',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimaryDark,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'انتهت صلاحية الاشتراك أو تم إيقافه، تواصل مع المسؤول للتفاصيل أو التجديد.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondaryDark,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 28),

                    _SubscriptionStatusCard(
                      endDate: user.endDate != null
                          ? dateFormat.format(user.endDate!)
                          : '—',
                      packageName: user.packageName,
                      lastActive: user.lastActiveAt != null
                          ? dateFormat.format(user.lastActiveAt!)
                          : '—',
                    ),
                    const SizedBox(height: 32),

                    // Primary action: WhatsApp renewal (Emerald Green)
                    CustomButton(
                      text: 'تواصل عبر واتساب للتجديد',
                      icon: FontAwesomeIcons.whatsapp.data,
                      backgroundColor: AppColors.primary,
                      onPressed: () => _openWhatsApp(context),
                    ),
                    const SizedBox(height: 8),

                    // Secondary action: logout
                    TextButton.icon(
                      onPressed: () => _logout(context),
                      icon: const Icon(Icons.logout_rounded, size: 18),
                      label: const Text(
                        'تسجيل الخروج',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.textSecondaryDark,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Centered '!' warning indicator inside a glowing orange/yellow circle.
class _WarningGlowIcon extends StatelessWidget {
  const _WarningGlowIcon();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.warning.withValues(alpha: 0.14),
          border: Border.all(
            color: AppColors.warning.withValues(alpha: 0.6),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.warning.withValues(alpha: 0.45),
              blurRadius: 32,
              spreadRadius: 3,
            ),
            BoxShadow(
              color: AppColors.warning.withValues(alpha: 0.2),
              blurRadius: 60,
              spreadRadius: 10,
            ),
          ],
        ),
        child: const Icon(
          Icons.priority_high_rounded,
          size: 52,
          color: AppColors.warning,
        ),
      ),
    );
  }
}

/// Yellow/gold bordered card summarizing the subscription status.
class _SubscriptionStatusCard extends StatelessWidget {
  const _SubscriptionStatusCard({
    required this.endDate,
    required this.packageName,
    required this.lastActive,
  });

  final String endDate;
  final String packageName;
  final String lastActive;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.45), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: AppColors.warning.withValues(alpha: 0.06),
            blurRadius: 24,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Align(
            alignment: AlignmentDirectional.centerStart,
            child: _InactiveBadge(),
          ),
          const SizedBox(height: 18),
          const _DetailRow(
            icon: Icons.info_outline_rounded,
            label: 'حالة الحساب',
            value: 'غير نشط',
            valueColor: AppColors.warning,
          ),
          const Divider(height: 28),
          _DetailRow(
            icon: Icons.event_busy_rounded,
            label: 'تاريخ الانتهاء',
            value: endDate,
          ),
          const Divider(height: 28),
          _DetailRow(
            icon: Icons.card_membership_rounded,
            label: 'الباقة',
            value: packageName,
          ),
          const Divider(height: 28),
          _DetailRow(
            icon: Icons.history_rounded,
            label: 'آخر تحميل',
            value: lastActive,
          ),
        ],
      ),
    );
  }
}

/// 'غير نشط' status pill with subtle amber styling.
class _InactiveBadge extends StatelessWidget {
  const _InactiveBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.warning,
            ),
          ),
          const SizedBox(width: 6),
          const Text(
            'غير نشط',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppColors.warning,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.textSecondaryDark),
        const SizedBox(width: 10),
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            color: AppColors.textSecondaryDark,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: valueColor ?? AppColors.textPrimaryDark,
          ),
        ),
      ],
    );
  }
}
