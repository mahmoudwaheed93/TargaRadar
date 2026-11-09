import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../data/models/user_model.dart';
import '../../presentation/screens/account_blocked_screen.dart';
import '../../presentation/screens/login_screen.dart';
import '../../presentation/screens/main_navigation_shell.dart';
import '../../presentation/screens/profile_screen.dart';
import '../../presentation/screens/user_management_screen.dart';

/// Centralized route names. Use these constants everywhere instead of raw
/// strings so a typo is a compile-time error rather than a runtime one.
class AppRoutes {
  AppRoutes._();

  static const String login = '/login';
  static const String accountBlocked = '/account-blocked';
  static const String profile = '/profile';
  static const String adminPanel = '/admin-panel';
  static const String mainNavigation = '/main';
}

/// Centralized route generator.
///
/// Wire [onGenerateRoute] into `MaterialApp` and set `initialRoute` to one of
/// the [AppRoutes] values to pick the app's first screen.
///
/// [onGenerateInitialRoutes] is overridden on purpose: Flutter's default
/// behavior would also push a stray `/` route beneath any non-`/` initial
/// route (and split `/admin-panel` into `/` + `/admin` + `/admin-panel`), which
/// would leave unreachable screens on the back stack. Emitting exactly one
/// route keeps the one-line start-screen switch clean.
class AppRouter {
  AppRouter._();

  static List<Route<dynamic>> onGenerateInitialRoutes(String initialRoute) {
    return <Route<dynamic>>[
      onGenerateRoute(RouteSettings(name: initialRoute)),
    ];
  }

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case AppRoutes.login:
        return _page(const LoginScreen(), settings);

      case AppRoutes.mainNavigation:
        return _page(const MainNavigationShell(), settings);

      case AppRoutes.profile:
        return _page(const ProfileScreen(), settings);

      case AppRoutes.adminPanel:
        return _page(const UserManagementScreen(), settings);

      case AppRoutes.accountBlocked:
        // This screen requires a [UserModel]. In normal flow it is reached via
        // a push that carries the logged-in user in `settings.arguments`. When
        // it is used as the initial route there is no session yet, so in debug
        // builds we fall back to a throwaway preview user; in release we send
        // the user back to login rather than rendering meaningless data.
        final args = settings.arguments;
        if (args is UserModel) {
          return _page(AccountBlockedScreen(user: args), settings);
        }
        if (kDebugMode) {
          return _page(
            AccountBlockedScreen(user: _previewBlockedUser),
            settings,
          );
        }
        return _page(const LoginScreen(), settings);

      default:
        return _page(_UnknownRouteScreen(name: settings.name), settings);
    }
  }

  static Route<dynamic> _page(Widget child, RouteSettings settings) {
    return MaterialPageRoute<dynamic>(builder: (_) => child, settings: settings);
  }

  static UserModel get _previewBlockedUser {
    final start = DateTime.now().subtract(const Duration(days: 40));
    final end = DateTime.now().subtract(const Duration(days: 10));
    return UserModel(
      uid: 'preview-blocked',
      username: 'مستخدم تجريبي',
      role: 'user',
      isActive: false,
      startDate: start,
      endDate: end,
      createdAt: start,
      lastActiveAt: end,
    );
  }
}

/// Fallback for an unrecognized route name. Kept intentionally plain so a
/// misconfiguration is obvious during development.
class _UnknownRouteScreen extends StatelessWidget {
  const _UnknownRouteScreen({this.name});

  final String? name;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.backgroundDark,
        appBar: AppBar(title: const Text('مسار غير معروف')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.explore_off_rounded,
                  size: 56,
                  color: AppColors.textMutedDark,
                ),
                const SizedBox(height: 16),
                Text(
                  'لم يتم العثور على المسار: ${name ?? '—'}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondaryDark,
                  ),
                ),
                const SizedBox(height: 24),
                TextButton(
                  onPressed: () =>
                      Navigator.of(context).pushReplacementNamed(AppRoutes.login),
                  child: const Text('العودة إلى تسجيل الدخول'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
