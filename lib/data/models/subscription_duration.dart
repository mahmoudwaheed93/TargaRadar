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

  /// Resolves the subscription end date relative to [startDate].
  ///
  /// - [DurationMode.days]: `startDate + days`.
  /// - [DurationMode.specificDate]: the picked date at the end of that day
  ///   (23:59:59), so the whole selected day remains valid.
  DateTime resolveEndDate(DateTime startDate) {
    switch (mode) {
      case DurationMode.days:
        return startDate.add(Duration(days: days));
      case DurationMode.specificDate:
        final picked = specificEndDate ?? startDate.add(Duration(days: days));
        return DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
    }
  }
}
