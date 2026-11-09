import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/date_formatter.dart';
import '../../core/utils/name_utils.dart';
import '../../core/widgets/custom_button.dart';
import '../../data/models/user_model.dart';
import '../providers/auth_provider.dart';
import 'login_screen.dart';
import 'user_management_screen.dart';

/// User Profile Screen (شاشة حسابي).
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.backgroundDark,
        appBar: AppBar(title: const Text('حسابي')),
        body: user == null ? const _NoSessionView() : _ProfileBody(user: user),
      ),
    );
  }
}

/// Scrollable profile content shown when a user session exists.
class _ProfileBody extends StatelessWidget {
  const _ProfileBody({required this.user});

  final UserModel user;

  Future<void> _openWhatsApp(BuildContext context) async {
    final uri = Uri.parse(
      'https://wa.me/${AppConstants.supportWhatsAppNumber}'
      '?text=${Uri.encodeComponent(AppConstants.supportWhatsAppMessage)}',
    );

    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تعذر فتح تطبيق واتساب، يرجى المحاولة لاحقاً'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تعذر فتح تطبيق واتساب، يرجى المحاولة لاحقاً'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _logout(BuildContext context) async {
    final navigator = Navigator.of(context);
    await context.read<AuthProvider>().logout();
    navigator.popUntil((route) => route.isFirst);
  }

  void _openUserManagement(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const UserManagementScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ProfileHeader(user: user),
            const SizedBox(height: 28),
            _SubscriptionCard(user: user),
            const SizedBox(height: 32),
            const Text(
              'إجراءات سريعة',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimaryDark,
              ),
            ),
            const SizedBox(height: 14),
            _ActionTile(
              leading: const FaIcon(
                FontAwesomeIcons.whatsapp,
                size: 22,
                color: AppColors.success,
              ),
              iconBackground: AppColors.success.withValues(alpha: 0.12),
              title: 'تواصل مع المشرف عبر واتساب',
              onTap: () => _openWhatsApp(context),
            ),
            if (user.role == 'admin') ...[
              const SizedBox(height: 12),
              _ActionTile(
                leading: const Icon(
                  Icons.manage_accounts_rounded,
                  size: 22,
                  color: AppColors.info,
                ),
                iconBackground: AppColors.info.withValues(alpha: 0.12),
                title: 'إدارة المستخدمين',
                onTap: () => _openUserManagement(context),
              ),
            ],
            const SizedBox(height: 12),
            _ActionTile(
              leading: const Icon(
                Icons.logout_rounded,
                size: 22,
                color: AppColors.error,
              ),
              iconBackground: AppColors.error.withValues(alpha: 0.12),
              title: 'تسجيل الخروج',
              onTap: () => _logout(context),
            ),
          ],
        ),
      ),
    );
  }
}

/// Centered avatar with initials, dynamic username, and role pill.
class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.user});

  final UserModel user;

  @override
  Widget build(BuildContext context) {
    final isAdmin = user.role == 'admin';
    final roleLabel = isAdmin ? 'حساب مشرف' : 'حساب مستخدم';

    return Column(
      children: [
        Container(
          width: 92,
          height: 92,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.cardDark,
            border: Border.all(color: AppColors.borderDark, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Center(
            child: Text(
              NameUtils.initials(user.username),
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          user.username,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimaryDark,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: BoxDecoration(
            color: isAdmin
                ? AppColors.primary.withValues(alpha: 0.15)
                : AppColors.surfaceDark,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isAdmin
                  ? AppColors.primary.withValues(alpha: 0.4)
                  : AppColors.borderDark,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isAdmin
                    ? Icons.admin_panel_settings_rounded
                    : Icons.person_rounded,
                size: 15,
                color: isAdmin ? AppColors.primary : AppColors.textSecondaryDark,
              ),
              const SizedBox(width: 6),
              Text(
                roleLabel,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color:
                      isAdmin ? AppColors.primary : AppColors.textSecondaryDark,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Subscription summary card (dates, progress bar, days left).
class _SubscriptionCard extends StatelessWidget {
  const _SubscriptionCard({required this.user});

  final UserModel user;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderDark),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.card_membership_rounded,
                    color: AppColors.primary,
                    size: 22,
                  ),
                  SizedBox(width: 10),
                  Text(
                    'تفاصيل الاشتراك',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimaryDark,
                    ),
                  ),
                ],
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: user.isSubscriptionValid
                      ? AppColors.success.withValues(alpha: 0.15)
                      : AppColors.error.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: user.isSubscriptionValid
                        ? AppColors.success.withValues(alpha: 0.4)
                        : AppColors.error.withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  user.isSubscriptionValid ? 'نشط' : 'غير نشط',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: user.isSubscriptionValid
                        ? AppColors.success
                        : AppColors.error,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _DateColumn(
                  label: 'تاريخ البداية',
                  value: user.startDate != null
                      ? AppDateFormatter.arabicLong(user.startDate!)
                      : 'غير محدد',
                ),
              ),
              Container(width: 1, height: 42, color: AppColors.borderDark),
              Expanded(
                child: _DateColumn(
                  label: 'تاريخ الانتهاء',
                  value: user.endDate != null
                      ? AppDateFormatter.arabicLong(user.endDate!)
                      : 'غير محدد',
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: user.subscriptionProgress,
              minHeight: 10,
              backgroundColor: AppColors.borderDark,
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              user.remainingDays < 0
                  ? 'اشتراك غير محدود'
                  : 'باقي ${user.remainingDays} يوم',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DateColumn extends StatelessWidget {
  const _DateColumn({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12.5,
            color: AppColors.textSecondaryDark,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimaryDark,
          ),
        ),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.leading,
    required this.iconBackground,
    required this.title,
    required this.onTap,
  });

  final Widget leading;
  final Color iconBackground;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.cardDark,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.borderDark),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconBackground,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(child: leading),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimaryDark,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_left_rounded,
                color: AppColors.textMutedDark,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoSessionView extends StatelessWidget {
  const _NoSessionView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.person_off_rounded,
              size: 56,
              color: AppColors.textMutedDark,
            ),
            const SizedBox(height: 16),
            const Text(
              'لم يتم تحميل بيانات الحساب',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondaryDark,
              ),
            ),
            const SizedBox(height: 24),
            CustomButton(
              text: 'تسجيل الدخول',
              icon: Icons.login_rounded,
              width: 220,
              onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
