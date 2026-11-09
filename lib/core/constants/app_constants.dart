/// Global app constants shared across layers.
class AppConstants {
  AppConstants._();

  /// Support WhatsApp number for admin contact and subscription renewal.
  /// Egyptian international format without '+' or leading zero: 201101356388
  static const String supportWhatsAppNumber = '201101356388';

  /// Default greeting message when contacting the supervisor from the profile screen.
  static const String supportWhatsAppMessage = 'مرحباً، أحتاج مساعدة بخصوص التطبيق';

  /// Builds the pre-filled renewal request message sent via WhatsApp.
  static String renewalWhatsAppMessage(String username) =>
      'مرحباً، أود تجديد اشتراكي في تطبيق Saqr Al Mamlaka (اسم المستخدم: $username)';

  /// Synthetic email domain for the Firebase Auth "bridge" account that mirrors
  /// each Firestore user. The mirror account's email local-part is the user's
  /// `users/{docId}` id, so the docId is recoverable from a persisted Firebase
  /// session on cold start. Firebase Auth is used purely as the session /
  /// persistence vehicle (`authStateChanges`); the real credential check still
  /// runs against the Firestore `users` collection.
  static const String bridgeAuthDomain = 'carlogix.app';
}
