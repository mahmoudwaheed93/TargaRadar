/// Small name-formatting helpers shared across the presentation layer.
class NameUtils {
  NameUtils._();

  /// Builds up to two initials from a display name for avatar placeholders.
  ///
  /// - "إسراء أحمد"  → "إأ"
  /// - "محمد"        → "م"
  /// - ""            → "؟"
  static String initials(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '؟';
    if (parts.length == 1) return parts.first.substring(0, 1);
    return parts[0].substring(0, 1) + parts[1].substring(0, 1);
  }
}
