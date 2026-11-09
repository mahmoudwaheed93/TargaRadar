import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/widgets/custom_button.dart';
import '../../core/widgets/custom_text_field.dart';
import '../providers/auth_provider.dart';
import 'account_blocked_screen.dart';

/// Login & Subscription Gate Screen (تسجيل الدخول والتحقق من الاشتراك).
///
/// Verifies credentials against Firestore, then routes the user based on
/// subscription validity:
/// - valid  → [MainNavigationShell]
/// - blocked → [AccountBlockedScreen]
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameFocus = FocusNode();
  final _passwordFocus = FocusNode();

  bool _obscurePassword = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submitLogin() async {
    if (!_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();

    final authProvider = context.read<AuthProvider>();
    final result = await authProvider.login(
      username: _usernameController.text,
      password: _passwordController.text,
    );

    if (!mounted) return;

    switch (result) {
      case LoginResult.success:
        // AuthGate watches AuthProvider.status and swaps in MainNavigationShell
        // automatically once the Firebase session is established — no
        // imperative navigation here (it would double-push over the gate).
        break;
      case LoginResult.blocked:
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => AccountBlockedScreen(user: authProvider.currentUser!),
          ),
        );
        break;
      case LoginResult.error:
        // Error banner is rendered reactively via Consumer below.
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
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
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _GlowingLogo(),
                      const SizedBox(height: 28),
                      const Text(
                        'مرحباً بعودتك',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimaryDark,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'سجّل الدخول لمتابعة تسجيل بيانات السيارات',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondaryDark,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 36),

                      // Username
                      CustomTextField(
                        controller: _usernameController,
                        focusNode: _usernameFocus,
                        labelText: 'اسم المستخدم',
                        hintText: 'أدخل اسم المستخدم',
                        prefixIcon: const Icon(
                          Icons.person_outline_rounded,
                          color: AppColors.textSecondaryDark,
                        ),
                        keyboardType: TextInputType.text,
                        textInputAction: TextInputAction.next,
                        onChanged: (_) => context.read<AuthProvider>().clearError(),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'يرجى إدخال اسم المستخدم';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 18),

                      // Password
                      CustomTextField(
                        controller: _passwordController,
                        focusNode: _passwordFocus,
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
                        onFieldSubmitted: (_) => _submitLogin(),
                        onChanged: (_) => context.read<AuthProvider>().clearError(),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'يرجى إدخال كلمة المرور';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),

                      // Error banner
                      Consumer<AuthProvider>(
                        builder: (context, auth, _) {
                          if (auth.error == null) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: _ErrorBanner(message: auth.error!.message),
                          );
                        },
                      ),
                      const SizedBox(height: 16),

                      // Login button
                      Consumer<AuthProvider>(
                        builder: (context, auth, _) {
                          return CustomButton(
                            text: 'تسجيل الدخول',
                            icon: Icons.login_rounded,
                            isLoading: auth.isLoading,
                            onPressed: auth.isLoading ? null : _submitLogin,
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Centered app logo with an emerald glowing aura.
class _GlowingLogo extends StatelessWidget {
  const _GlowingLogo();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.primary, AppColors.primaryDark],
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.55),
              blurRadius: 32,
              spreadRadius: 4,
            ),
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.25),
              blurRadius: 60,
              spreadRadius: 12,
            ),
          ],
        ),
        child: ClipOval(
          child: Image.asset(
            'assets/images/app_logo.png',
            width: 96,
            height: 96,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => const Center(child: Icon(Icons.directions_car_rounded, size: 52, color: Colors.white)),
          ),
        ),
      ),
    );
  }
}

/// Inline red banner used to surface authentication errors.
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

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
          const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 22),
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
