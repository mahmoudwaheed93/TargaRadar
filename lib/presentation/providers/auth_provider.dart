import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/session_store.dart';
import '../../core/services/user_storage.dart';
import '../../data/datasources/database_helper.dart';
import '../../data/models/user_model.dart';
import '../../data/repositories/auth_repository.dart';

/// Outcome of a login attempt, consumed by the LoginScreen to decide navigation.
enum LoginResult {
  /// Credentials valid AND subscription is active → go to MainNavigationShell.
  success,

  /// Credentials valid BUT subscription expired/inactive → go to AccountBlockedScreen.
  blocked,

  /// Invalid credentials or a connectivity failure → stay and show [AuthError.message].
  error,
}

/// Carries a user-facing Arabic error message for [LoginResult.error].
class AuthError {
  final String message;
  const AuthError(this.message);
}

/// Coarse session state that drives the [AuthGate] router.
enum AuthStatus {
  /// Still resolving the session on cold start (or a transient failure with a
  /// persisted session — the router stays on splash rather than bouncing out).
  unknown,

  /// Signed in with a valid subscription → main app.
  authenticated,

  /// Signed in but the subscription is expired/inactive → blocked screen.
  blocked,

  /// No session → login screen.
  unauthenticated,
}

/// Presentation-layer state management for authentication, subscription
/// gating, and persistent session routing.
///
/// Session model (this is what fixes the login↔home bounce):
///   * Credentials are verified against the Firestore `users` collection.
///   * On success the exact Firestore doc id is persisted locally via
///     [SessionStore] and [status] becomes [AuthStatus.authenticated]
///     **immediately** — routing never waits on a Firebase round-trip.
///   * A Firebase Auth "mirror" account (see [AuthService]) is then signed in
///     best-effort for cross-restart persistence. If that fails (e.g. the Email
///     provider is disabled) the user stays logged in on the local session.
///   * On cold start [_resolveSession] restores the profile from the persisted
///     doc id (falling back to the Firebase email only if local state is gone).
///
/// A transient Firestore failure or a Firebase `null` auth event never demotes
/// an established session to [AuthStatus.unauthenticated]; only an explicit
/// [logout] or a deleted account does.
class AuthProvider extends ChangeNotifier {
  AuthProvider({
    AuthRepository? authRepository,
    AuthService? authService,
    SessionStore? sessionStore,
  })  : _authRepository = authRepository ?? AuthRepository(),
        _authService = authService ?? AuthService.instance,
        _sessionStore = sessionStore ?? SessionStore.instance {
    _authSub = _authService.authStateChanges().listen((_) => _resolveSession());
    // Resolve now rather than waiting for the first Firebase event, which may
    // never arrive if the bridge sign-in previously failed.
    _resolveSession();
  }

  final AuthRepository _authRepository;
  final AuthService _authService;
  final SessionStore _sessionStore;
  late final StreamSubscription<User?> _authSub;

  bool _isLoading = false;
  bool _resolving = false;
  UserModel? _currentUser;
  AuthError? _error;
  AuthStatus _status = AuthStatus.unknown;
  String? _userDocId;
  String? _firebaseUid;

  bool get isLoading => _isLoading;
  UserModel? get currentUser => _currentUser;
  AuthError? get error => _error;
  AuthStatus get status => _status;

  /// Firestore `users/{docId}` id of the signed-in account — the key for
  /// user-scoped cloud data. Null when signed out.
  String? get userDocId => _userDocId;

  /// Firebase Auth uid of the mirror account. Null when unavailable.
  String? get firebaseUid => _firebaseUid;

  /// Re-runs session resolution (e.g. from a splash retry button).
  Future<void> retry() => _resolveSession();

  /// Resolves the current session into [status] + [currentUser].
  ///
  /// Prefers the locally-persisted doc id (exact, case-correct); only falls
  /// back to the Firebase mirror email when there is no local session.
  Future<void> _resolveSession() async {
    if (_resolving) return;
    _resolving = true;
    try {
      String? docId = await _sessionStore.readDocId();
      docId ??= _authService.currentUserDocId; // cold-start fallback (email)

      if (docId == null || docId.isEmpty) {
        _resetSession();
        _status = AuthStatus.unauthenticated;
        notifyListeners();
        return;
      }

      try {
        final user = await _authRepository.fetchUserByUid(docId);
        if (user == null) {
          // Account was deleted (e.g. by an admin) → end the session everywhere.
          await _clearSessionAndSignOut();
          return;
        }
        _currentUser = user;
        _userDocId = docId;
        _firebaseUid = _authService.currentUser?.uid;
        _status = user.isSubscriptionValid
            ? AuthStatus.authenticated
            : AuthStatus.blocked;
        _error = null;
        debugPrint('[AuthProvider] Session resolved for "${user.username}": role="${user.role}", isAdmin=${user.isAdmin}');
        // Persist in case the id came from the email fallback.
        await _sessionStore.saveDocId(docId);
        notifyListeners();
      } on AuthException catch (e) {
        // Transient failure (e.g. offline). NEVER drop a persisted session:
        // keep the last known profile if we have one, otherwise stay on splash
        // so the user can retry instead of being bounced to login.
        _error = AuthError(e.message);
        _status = _currentUser != null
            ? (_currentUser!.isSubscriptionValid
                ? AuthStatus.authenticated
                : AuthStatus.blocked)
            : AuthStatus.unknown;
        notifyListeners();
      }
    } finally {
      _resolving = false;
    }
  }

  /// Attempts to log in with [username] and [password].
  ///
  /// Returns a [LoginResult] that the UI uses to navigate:
  /// - [LoginResult.success] when the subscription is valid (a local session is
  ///   persisted and [AuthGate] routes to the app),
  /// - [LoginResult.blocked] when the account is expired/inactive,
  /// - [LoginResult.error] for bad credentials or connectivity issues.
  Future<LoginResult> login({
    required String username,
    required String password,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final user = await _authRepository.login(
        username: username,
        password: password,
      );
      debugPrint('[AuthProvider] Login successful for "${user.username}": role="${user.role}", isAdmin=${user.isAdmin}');

      if (!user.isSubscriptionValid) {
        _currentUser = user;
        return LoginResult.blocked;
      }

      // Establish OUR persisted session first so routing never depends on the
      // Firebase round-trip (the source of the login↔home bounce).
      _currentUser = user;
      _userDocId = user.uid;
      _firebaseUid = null;
      _status = AuthStatus.authenticated;
      _error = null;
      await _sessionStore.saveDocId(user.uid);
      notifyListeners();

      // Best-effort Firebase mirror sign-in for cross-restart persistence. A
      // failure here must NOT log the user out — the local session is
      // authoritative and the auth-stream event it triggers is idempotent.
      try {
        final fbUser = await _authService.bridgeSignIn(
          userDocId: user.uid,
          password: password,
        );
        _firebaseUid = fbUser.uid;
      } catch (e) {
        debugPrint('Firebase bridge sign-in failed; staying on local session: $e');
      }

      return LoginResult.success;
    } on AuthException catch (e) {
      _resetSession();
      _status = AuthStatus.unauthenticated;
      _error = AuthError(e.message);
      return LoginResult.error;
    } catch (e) {
      _resetSession();
      _status = AuthStatus.unauthenticated;
      _error = AuthError('حدث خطأ غير متوقع، حاول مجدداً ($e)');
      return LoginResult.error;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Clears the transient error banner (e.g. when the user edits a field).
  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  /// Ends the session: clears the persisted local session, signs out of
  /// Firebase, and resets in-memory state. [AuthGate] then routes to login.
  Future<void> logout() async {
    await _clearSessionAndSignOut();
  }

  Future<void> _clearSessionAndSignOut() async {
    final leavingUid = _userDocId ?? _authService.currentUser?.uid;

    try {
      await _sessionStore.clear();
    } catch (e) {
      debugPrint('SessionStore clear failed: $e');
    }

    // إذا كانت خيارات التطبيق تنص على حذف بيانات المستخدم محلياً عند الخروج:
    if (UserStorage.deleteLocalDataOnLogout && leavingUid != null && leavingUid.isNotEmpty) {
      try {
        await DatabaseHelper.instance.deleteAllRecordsForUser(leavingUid);
        await UserStorage.deleteUserData(leavingUid);
      } catch (e) {
        debugPrint('[AuthProvider] Error deleting local user data on logout: $e');
      }
    }

    try {
      await _authService.signOut();
    } catch (e) {
      debugPrint('Firebase signOut failed: $e');
    }

    // تنظيف كاش فايرستور دون كسر التطبيق
    try {
      await FirebaseFirestore.instance.terminate();
      await FirebaseFirestore.instance.clearPersistence();
    } catch (e) {
      debugPrint('[AuthProvider] Firestore cache clear skipped/failed: $e');
    }

    _resetSession();
    _status = AuthStatus.unauthenticated;
    notifyListeners();
  }

  void _resetSession() {
    _currentUser = null;
    _userDocId = null;
    _firebaseUid = null;
    _error = null;
  }

  @override
  void dispose() {
    _authSub.cancel();
    super.dispose();
  }
}
