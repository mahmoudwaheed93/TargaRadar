import 'package:shared_preferences/shared_preferences.dart';

/// Persists the minimal local session — the exact Firestore `users/{docId}` id —
/// so the app can restore the signed-in user on cold start.
///
/// This is the authoritative session source for routing. It deliberately does
/// **not** rely on the Firebase Auth mirror account's email, because Firebase
/// lowercases emails while Firestore auto-ids are mixed-case, making an
/// `email → docId` round-trip lossy (the cause of the login↔home bounce).
class SessionStore {
  SessionStore._();

  static final SessionStore instance = SessionStore._();

  static const String _kDocId = 'carlogix_session_doc_id';

  /// Persists the signed-in account's Firestore doc id.
  Future<void> saveDocId(String docId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDocId, docId);
  }

  /// The persisted doc id, or `null` when there is no local session.
  Future<String?> readDocId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kDocId);
  }

  /// Clears the local session (on logout).
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kDocId);
  }
}
