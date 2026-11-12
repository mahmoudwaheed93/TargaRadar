/// How the subscription end date is chosen when creating a user.
enum DurationMode {
  /// A number of days starting from now (e.g. 30 يوماً).
  days,

  /// An explicit calendar date picked by the admin.
  specificDate,
}

/// Immutable value object encapsulating the "مدة الاشتراك" selection and the
/// business rule that turns it into a concrete end date.
class SubscriptionDuration {
  const SubscriptionDuration.days(this.days)
      : mode = DurationMode.days,
        specificEndDate = null;

  const SubscriptionDuration.untilDate(this.specificEndDate)
      : mode = DurationMode.specificDate,
        days = 0;

  final DurationMode mode;
  final int days;
  final DateTime? specificEndDate;

  /// Resolves the subscription end date relative to [startDate], normalized to
  /// 23:59:59 of the final day for both modes so partial-day registrations remain consistent.
  DateTime resolveEndDate(DateTime startDate) {
    final DateTime target;
    switch (mode) {
      case DurationMode.days:
        target = startDate.add(Duration(days: days));
      case DurationMode.specificDate:
        target = specificEndDate ?? startDate.add(Duration(days: days));
    }
    return DateTime(target.year, target.month, target.day, 23, 59, 59);
  }
}
