import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/app_colors.dart';
import '../services/user_storage.dart';
import '../../presentation/providers/auth_provider.dart';
import '../../presentation/providers/car_record_provider.dart';
import '../../presentation/providers/excel_sort_audit_provider.dart';
import '../../presentation/providers/inspection_provider.dart';
import '../../presentation/screens/account_blocked_screen.dart';
import '../../presentation/screens/login_screen.dart';
import '../../presentation/screens/main_navigation_shell.dart';
import '../../presentation/screens/user_management_screen.dart';

/// Root router driven by the persistent Firebase Auth session.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    switch (auth.status) {
      case AuthStatus.unknown:
        return _SplashScreen(
          error: auth.error?.message,
          onRetry: auth.retry,
        );
      case AuthStatus.unauthenticated:
        return const _UnauthenticatedScopeCleanup(child: LoginScreen());
      case AuthStatus.blocked:
        final user = auth.currentUser;
        if (user == null) return const _UnauthenticatedScopeCleanup(child: LoginScreen());
        return _UnauthenticatedScopeCleanup(child: AccountBlockedScreen(user: user));
      case AuthStatus.authenticated:
        final user = auth.currentUser;
        final isAdmin = user != null && user.isAdmin;
        return _AuthenticatedHome(uid: user?.uid ?? '', isAdmin: isAdmin);
    }
  }
}

class _UnauthenticatedScopeCleanup extends StatefulWidget {
  const _UnauthenticatedScopeCleanup({required this.child});
  final Widget child;

  @override
  State<_UnauthenticatedScopeCleanup> createState() => _UnauthenticatedScopeCleanupState();
}

class _UnauthenticatedScopeCleanupState extends State<_UnauthenticatedScopeCleanup> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final carProv = context.read<CarRecordProvider>();
      final inspProv = context.read<InspectionProvider>();
      if (carProv.isListening) await carProv.stopVoiceListening();
      if (inspProv.isListening) await inspProv.stopListening();
      await inspProv.resetSession();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _AuthenticatedHome extends StatefulWidget {
  const _AuthenticatedHome({required this.uid, required this.isAdmin});
  final String uid;
  final bool isAdmin;

  @override
  State<_AuthenticatedHome> createState() => _AuthenticatedHomeState();
}

class _AuthenticatedHomeState extends State<_AuthenticatedHome> {
  String _scopedUid = '';

  @override
  void initState() {
    super.initState();
    _syncScope();
  }

  @override
  void didUpdateWidget(covariant _AuthenticatedHome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid) {
      _syncScope();
    }
  }

  void _syncScope() {
    final uid = widget.uid;
    if (uid.isEmpty || uid == _scopedUid) return;
    _scopedUid = uid;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final carProv = context.read<CarRecordProvider>();
      final auditProv = context.read<ExcelSortAuditProvider>();
      final inspProv = context.read<InspectionProvider>();
      await carProv.setCurrentUserId(uid);
      await auditProv.setCurrentUserId(uid);
      await inspProv.setCurrentUserId(uid);
      await UserStorage.migrateLegacyFilesIfPresent(uid);
    });
  }

  @override
  Widget build(BuildContext context) =>
      widget.isAdmin ? const UserManagementScreen() : const MainNavigationShell();
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen({this.error, this.onRetry});

  final String? error;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    final hasError = error != null && error!.isNotEmpty;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.backgroundDark,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.35),
                      width: 1.5,
                    ),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.directions_car_rounded,
                      size: 48,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Saqr Al Mamlaka',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'نظام فحص وتسجيل المركبات',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondaryDark,
                  ),
                ),
                const SizedBox(height: 36),
                if (hasError) ...[
                  Text(
                    error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.error,
                    ),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('إعادة المحاولة'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ] else ...[
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(AppColors.primary),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
