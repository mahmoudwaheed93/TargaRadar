import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

enum BadgeType {
  success,
  warning,
  error,
  info,
  custom,
}

/// A compact status tag / pill badge widget for visual categorization and status indicators.
class StatusBadge extends StatelessWidget {
  final String label;
  final BadgeType type;
  final Color? customColor;
  final IconData? icon;
  final bool isOutlined;

  const StatusBadge({
    super.key,
    required this.label,
    this.type = BadgeType.info,
    this.customColor,
    this.icon,
    this.isOutlined = false,
  });

  Color _resolveColor() {
    if (customColor != null) return customColor!;
    switch (type) {
      case BadgeType.success:
        return AppColors.success;
      case BadgeType.warning:
        return AppColors.warning;
      case BadgeType.error:
        return AppColors.error;
      case BadgeType.info:
        return AppColors.info;
      case BadgeType.custom:
        return AppColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _resolveColor();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isOutlined ? color.withValues(alpha: 0.1) : color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: color.withValues(alpha: isOutlined ? 0.8 : 0.4),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
