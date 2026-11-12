import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../constants/app_constants.dart';

/// Thin wrapper around Firebase Authentication that provides the persistent
/// session used to route the app on startup.
///
/// CarLogix authenticates against a Firestore `users` collection (username /
/// password + subscription). This service does **not** replace that check; it
/// adds a Firebase Auth "mirror" account per Firestore user so the app gets:
///   * a persisted session that survives app restarts ([authStateChanges]), and
///   * a stable, account-scoped identity to key user data by.
///
/// The mirror account's email is `<usersDocId>@carlogix.app`, so the Firestore
/// doc id is recoverable from any persisted session (see [docIdFromEmail]).
///
/// Security note: because there is no back-end, the Firestore credential check
/// remains the real gate and runs *before* [bridgeSignIn]. Data protection must
/// be enforced by Firestore security rules; a client-only bridge cannot fully
/// prevent a determined attacker who knows a doc id. Migrating sign-in to a
/// Cloud Function / custom token is the recommended hardening path.
class AuthService {
  AuthService._();

  static final AuthService instance = AuthService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Emits the current Firebase user (or `null`) now and on every change.
  Stream<User?> authStateChanges() => _auth.authStateChanges();

  /// The persisted Firebase user, or `null` when signed out.
  User? get currentUser => _auth.currentUser;

  /// The Firestore `users/{docId}` id of the signed-in mirror account, or
  /// `null` when signed out. Prefers exact case-sensitive [User.displayName].
  String? get currentUserDocId {
    final user = _auth.currentUser;
    if (user == null) return null;
    final exact = user.displayName?.trim();
    if (exact != null && exact.isNotEmpty) return exact;
    return docIdFromEmail(user.email);
  }

  /// Builds the mirror-account email for a Firestore user doc id.
  static String bridgeEmail(String userDocId) =>
      '$userDocId@${AppConstants.bridgeAuthDomain}';

  /// Recovers the Firestore doc id from a mirror-account email.
  static String? docIdFromEmail(String? email) {
    if (email == null || !email.contains('@')) return null;
    final local = email.split('@').first;
    return local.isEmpty ? null : local;
  }

  /// Signs into (creating on first use) the Firebase Auth mirror account for
  /// [userDocId], using [password] — the same secret already verified against
  /// Firestore — so the account stays protected by the user's own credential.
  ///
  /// Handles the real-world cases without a back-end:
  ///   * returning user → plain sign-in;
  ///   * first bridge login → create the mirror account;
  ///   * legacy password shorter than Firebase's 6-char minimum → create/sign-in
  ///     with a deterministic fallback derived from the doc id.
  ///
  /// Throws [FirebaseAuthException] on unrecoverable failures.
  Future<User> bridgeSignIn({
    required String userDocId,
    required String password,
  }) async {
    final email = bridgeEmail(userDocId);
    final fallback = 'CLX#$userDocId';

    // 1) Returning user: the mirror account already exists with this password.
    try {
      final cred = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      if (cred.user != null) {
        if (cred.user!.displayName != userDocId) {
          try {
            await cred.user!.updateDisplayName(userDocId);
          } catch (_) {}
        }
        return cred.user!;
      }
    } on FirebaseAuthException catch (e) {
      if (!_isCredentialError(e)) rethrow;
      debugPrint('[AuthService] sign-in miss (${e.code}); ensuring account');
    }

    // 2) First bridge login: create the mirror account.
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      if (cred.user != null) return cred.user!;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'weak-password') {
        // Legacy short password — fall back to a deterministic strong secret.
        try {
          final cred = await _auth.createUserWithEmailAndPassword(
            email: email,
            password: fallback,
          );
          if (cred.user != null) return cred.user!;
        } on FirebaseAuthException catch (e2) {
          if (e2.code != 'email-already-in-use') rethrow;
        }
      } else if (e.code != 'email-already-in-use') {
        rethrow;
      }
    }

    // 3) Account exists but the real password did not match → it was created
    //    earlier with the deterministic fallback (legacy short-password user).
    final cred = await _auth.signInWithEmailAndPassword(
      email: email,
      password: fallback,
    );
    return cred.user!;
  }

  /// Signs out of Firebase Auth; [authStateChanges] then emits `null`.
  Future<void> signOut() => _auth.signOut();

  static bool _isCredentialError(FirebaseAuthException e) =>
      e.code == 'invalid-credential' ||
      e.code == 'wrong-password' ||
      e.code == 'user-not-found';
}
