import 'package:flutter/material.dart';

/// Central color definitions for CarLogix app.
class AppColors {
  AppColors._();

  // Primary & Accent Colors
  static const Color primary = Color(0xFF00C853); // Emerald Green
  static const Color primaryDark = Color(0xFF009624);
  static const Color primaryLight = Color(0xFF5EFA82);

  // Background Colors
  static const Color backgroundDark = Color(0xFF0E1726); // Dark Navy
  static const Color backgroundLight = Color(0xFFF8FAFC); // Light Off-White

  // Surface & Card Colors
  static const Color cardDark = Color(0xFF1E293B); // Deep Navy Slate
  static const Color cardLight = Color(0xFFFFFFFF); // Pure White
  static const Color surfaceDark = Color(0xFF131D31);

  // Border & Divider Colors
  static const Color borderDark = Color(0xFF334155);
  static const Color borderLight = Color(0xFFE2E8F0);

  // Text Colors
  static const Color textPrimaryDark = Color(0xFFF8FAFC);
  static const Color textSecondaryDark = Color(0xFF94A3B8);
  static const Color textMutedDark = Color(0xFF64748B);

  static const Color textPrimaryLight = Color(0xFF0F172A);
  static const Color textSecondaryLight = Color(0xFF475569);
  static const Color textMutedLight = Color(0xFF94A3B8);

  // Status & Feedback Colors
  static const Color success = Color(0xFF00C853);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);
  static const Color info = Color(0xFF3B82F6);

  // Input & Interactive States
  static const Color inputFillDark = Color(0xFF162235);
  static const Color inputFillLight = Color(0xFFF1F5F9);
  static const Color disabled = Color(0xFF475569);
}
