import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/name_utils.dart';
import '../../core/widgets/custom_text_field.dart';
import '../../core/widgets/status_badge.dart';
import '../../data/models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/user_management_provider.dart';
import '../widgets/create_user_sheet.dart';
import '../widgets/renew_subscription_sheet.dart';
import 'profile_screen.dart';

/// Admin Control Panel → User Management screen (إدارة المستخدمين).
///
/// Renders the real-time `users` roster held by [UserManagementProvider] with
/// local search + status filtering. The provider's Firestore listener is tied
/// to this screen's lifecycle (started in [initState], cancelled in [dispose]),
/// so the subscription only lives while an admin has the panel open. The
/// provider itself lives at the app root, so the create-user modal sheet (shown
/// on the root navigator) can reach the same instance.
class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  late final UserManagementProvider _management;

  @override
  void initState() {
    super.initState();
    _management = context.read<UserManagementProvider>();
    _management.startUsersStream();
  }

  @override
  void dispose() {
    _management.stopUsersStream();
    super.dispose();
  }

  Future<void> _onCreatePressed() async {
    final created = await showCreateUserSheet(context);
    if (created == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم إنشاء الحساب بنجاح'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild on search/filter changes and on every roster update.
    final management = context.watch<UserManagementProvider>();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.backgroundDark,
        appBar: AppBar(
          title: const Text('إدارة المستخدمين'),
          actions: [
            IconButton(
              icon: const Icon(Icons.person_outline_rounded),
              tooltip: 'حسابي',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.logout_rounded),
              tooltip: 'تسجيل الخروج',
              onPressed: () => context.read<AuthProvider>().logout(),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: _onCreatePressed,
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.black,
          child: const Icon(Icons.add_rounded, size: 28),
        ),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header subtitle with dynamic user count
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: Text(
                  'مسؤول النظام - ${management.totalCount} مستخدمين',
                  style: const TextStyle(
                    fontSize: 13.5,
                    color: AppColors.textSecondaryDark,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Search bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: CustomTextField(
                  hintText: 'ابحث باسم المستخدم',
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: AppColors.textSecondaryDark,
                  ),
                  onChanged: management.setSearchQuery,
                ),
              ),
              const SizedBox(height: 16),

              // Filter chips
              _FilterChips(
                selected: management.filter,
                onSelected: management.setFilter,
              ),
              const SizedBox(height: 8),

              // User list
              Expanded(child: _buildBody(management)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(UserManagementProvider management) {
    if (management.isLoadingUsers) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (management.usersError != null) {
      return _MessageView(
        icon: Icons.cloud_off_rounded,
        message: 'تعذر تحميل المستخدمين',
        details: management.usersError,
      );
    }

    final visible = management.visibleUsers;
    if (visible.isEmpty) {
      return const _MessageView(
        icon: Icons.people_outline_rounded,
        message: 'لا توجد نتائج مطابقة',
        details: 'جرّب تعديل البحث أو الفلاتر',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
      itemCount: visible.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) => _UserCard(user: visible[index]),
    );
  }
}

/// Horizontal toggle group: الكل / نشط / غير نشط.
class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.selected, required this.onSelected});

  final UserFilter selected;
  final ValueChanged<UserFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          _FilterChip(
            label: 'الكل',
            selected: selected == UserFilter.all,
            onTap: () => onSelected(UserFilter.all),
          ),
          const SizedBox(width: 10),
          _FilterChip(
            label: 'نشط',
            selected: selected == UserFilter.active,
            onTap: () => onSelected(UserFilter.active),
          ),
          const SizedBox(width: 10),
          _FilterChip(
            label: 'غير نشط',
            selected: selected == UserFilter.inactive,
            onTap: () => onSelected(UserFilter.inactive),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.cardDark,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.borderDark,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.bold,
            color: selected ? Colors.black : AppColors.textSecondaryDark,
          ),
        ),
      ),
    );
  }
}

/// A single user row: initials avatar, username + expiry, and a status pill.
class _UserCard extends StatelessWidget {
  const _UserCard({required this.user});

  final UserModel user;

  String get _expiryLabel {
    if (user.isAdmin) return 'اشتراك غير محدود';
    final d = user.endDate;
    if (d == null) return 'تاريخ الانتهاء غير محدد';
    return 'ينتهي في ${d.year}/${d.month}/${d.day}';
  }

  Future<void> _onTap(BuildContext context) async {
    if (user.isSubscriptionValid) return;
    final renewed = await showRenewSubscriptionSheet(context, user);
    if (renewed == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم تجديد الاشتراك بنجاح'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isActive = user.isSubscriptionValid;

    return GestureDetector(
      onTap: () => _onTap(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.cardDark,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive
                ? AppColors.borderDark
                : AppColors.warning.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          children: [
          // Avatar
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.surfaceDark,
              border: Border.all(color: AppColors.borderDark),
            ),
            alignment: Alignment.center,
            child: Text(
              NameUtils.initials(user.username),
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 14),

          // Name + expiry
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.username,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimaryDark,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _expiryLabel,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSecondaryDark,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Status badge + renewal icon for inactive
          if (!isActive) ...[
            const SizedBox(width: 4),
            const Icon(
              Icons.autorenew_rounded,
              size: 18,
              color: AppColors.warning,
            ),
          ],
          const SizedBox(width: 4),
          StatusBadge(
            label: isActive ? 'نشط' : 'غير نشط',
            type: isActive ? BadgeType.success : BadgeType.warning,
          ),
        ],
        ),
      ),
    );
  }
}

/// Friendly empty / error placeholder.
class _MessageView extends StatelessWidget {
  const _MessageView({
    required this.icon,
    required this.message,
    this.details,
  });

  final IconData icon;
  final String message;
  final String? details;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 52, color: AppColors.textMutedDark),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondaryDark,
              ),
            ),
            if (details != null) ...[
              const SizedBox(height: 6),
              Text(
                details!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textMutedDark,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
