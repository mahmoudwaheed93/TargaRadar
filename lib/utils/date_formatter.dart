/// Presentation-agnostic date formatting helpers for Arabic UI.
///
/// We format manually (instead of `DateFormat` with the `ar` locale) so the
/// output uses Western digits with Arabic month names — e.g. "1 سبتمبر 2026" —
/// which matches the CarLogix design spec and stays deterministic regardless of
/// the ambient [Intl] locale/numbering system.
class AppDateFormatter {
  AppDateFormatter._();

  static const List<String> _arabicMonths = [
    'يناير',
    'فبراير',
    'مارس',
    'أبريل',
    'مايو',
    'يونيو',
    'يوليو',
    'أغسطس',
    'سبتمبر',
    'أكتوبر',
    'نوفمبر',
    'ديسمبر',
  ];

  /// Formats [date] as "1 سبتمبر 2026" (day + Arabic month + year).
  static String arabicLong(DateTime date) {
    final monthName = _arabicMonths[date.month - 1];
    return '${date.day} $monthName ${date.year}';
  }


  /// Formats time in 12-hour format e.g. "03:45 ?"
  static String time12(DateTime dt) {
    final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final min = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour < 12 ? 'ص' : 'م';
    return '$hour12:$min $period';
  }

  /// Formats full date and time in 12-hour format: "2026-10-24 03:45 ?"
  static String formatDateTime12(DateTime dt) {
    final y = dt.year;
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d ${time12(dt)}';
  }
  /// Formats [dateTime] with a 12-hour clock: "1 سبتمبر 2026 - 3:45 م".
  ///
  /// Used for absolute timestamps in inspection history and the log workbook.
  static String arabicDateTime(DateTime dateTime) {
    final hour12 = dateTime.hour % 12 == 0 ? 12 : dateTime.hour % 12;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final period = dateTime.hour < 12 ? 'ص' : 'م';
    return '${arabicLong(dateTime)} - $hour12:$minute $period';
  }

  /// Relative Arabic time such as "منذ 3 دقائق" for recent-inspection rows.
  ///
  /// [now] is injectable so tests stay deterministic. Anything under a minute
  /// (or slightly in the future, e.g. from clock skew) collapses to "الآن".
  static String relativeArabic(DateTime dateTime, {DateTime? now}) {
    final elapsed = (now ?? DateTime.now()).difference(dateTime);
    if (elapsed.inSeconds < 60) return 'الآن';

    if (elapsed.inMinutes < 60) {
      return 'منذ ${_counted(elapsed.inMinutes, 'دقيقة', 'دقيقتين', 'دقائق')}';
    }
    if (elapsed.inHours < 24) {
      return 'منذ ${_counted(elapsed.inHours, 'ساعة', 'ساعتين', 'ساعات')}';
    }
    if (elapsed.inDays < 7) {
      return 'منذ ${_counted(elapsed.inDays, 'يوم', 'يومين', 'أيام')}';
    }
    if (elapsed.inDays < 30) {
      return 'منذ ${_counted(elapsed.inDays ~/ 7, 'أسبوع', 'أسبوعين', 'أسابيع')}';
    }
    if (elapsed.inDays < 365) {
      return 'منذ ${_counted(elapsed.inDays ~/ 30, 'شهر', 'شهرين', 'أشهر')}';
    }
    return 'منذ ${_counted(elapsed.inDays ~/ 365, 'سنة', 'سنتين', 'سنوات')}';
  }

  /// Arabic count agreement: 1 -> "دقيقة", 2 -> "دقيقتين", 3..10 -> "3 دقائق",
  /// 11+ -> "11 دقيقة".
  static String _counted(
    int count,
    String singular,
    String dual,
    String plural,
  ) {
    if (count <= 1) return singular;
    if (count == 2) return dual;
    if (count <= 10) return '$count $plural';
    return '$count $singular';
  }
}
