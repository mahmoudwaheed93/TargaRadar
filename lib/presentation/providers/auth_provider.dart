import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../core/services/auth_service.dart';
import '../../core/services/session_store.dart';
import '../../core/services/speech_service.dart';
import '../../core/services/user_storage.dart';
import '../../data/datasources/database_helper.dart';
import '../../data/models/user_model.dart';
import '../../data/repositories/auth_repository.dart';

enum LoginResult {
  success,
  blocked,
  error,
}

class AuthError {
  final String message;
  const AuthError(this.message);
}

enum AuthStatus {
  unknown,
  authenticated,
  blocked,
  unauthenticated,
}

/// Presentation-layer state management for authentication, real-time
/// subscription monitoring, and persistent session routing.
class AuthProvider extends ChangeNotifier {
  AuthProvider({
    AuthRepository? authRepository,
    AuthService? authService,
    SessionStore? sessionStore,
  })  : _authRepository = authRepository ?? AuthRepository(),
        _authService = authService ?? AuthService.instance,
        _sessionStore = sessionStore ?? SessionStore.instance {
    _authSub = _authService.authStateChanges().listen((_) => _resolveSession());
    _resolveSession();
  }

  final AuthRepository _authRepository;
  final AuthService _authService;
  final SessionStore _sessionStore;
  late final StreamSubscription<User?> _authSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userDocSub;

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
  String? get userDocId => _userDocId;
  String? get firebaseUid => _firebaseUid;

  Future<void> retry() => _resolveSession();

  /// Subscribes to live subscription/status changes on `users/{docId}` so admin
  /// renewals or suspensions take effect immediately without restarting the app.
  void _watchUserDoc(String docId) {
    _userDocSub?.cancel();
    _userDocSub = FirebaseFirestore.instance
        .collection('users')
        .doc(docId)
        .snapshots()
        .listen((snap) {
      if (!snap.exists) {
        unawaited(_clearSessionAndSignOut(deleteLocalData: false));
        return;
      }
      final updated = UserModel.fromMap(snap.data()!, snap.id);
      _currentUser = updated;
      _status = updated.isSubscriptionValid
          ? AuthStatus.authenticated
          : AuthStatus.blocked;
      notifyListeners();
    }, onError: (Object e) {
      debugPrint('[AuthProvider] User doc stream error (kept cached state): $e');
    });
  }

  Future<void> _resolveSession() async {
    if (_resolving) return;
    _resolving = true;
    try {
      final storedId = await _sessionStore.readDocId();
      final fromFallback = storedId == null || storedId.isEmpty;
      final docId = fromFallback ? _authService.currentUserDocId : storedId;

      if (docId == null || docId.isEmpty) {
        _resetSession();
        _status = AuthStatus.unauthenticated;
        notifyListeners();
        return;
      }

      try {
        final user = await _authRepository.fetchUserByUid(docId);
        if (user == null) {
          // Never wipe local SQLite files if the fallback email lookup missed due to case mismatch
          await _clearSessionAndSignOut(deleteLocalData: !fromFallback);
          return;
        }
        _currentUser = user;
        _userDocId = docId;
        _firebaseUid = _authService.currentUser?.uid;
        _status = user.isSubscriptionValid
            ? AuthStatus.authenticated
            : AuthStatus.blocked;
        _error = null;
        await _sessionStore.saveDocId(docId);
        _watchUserDoc(docId);
        notifyListeners();
      } on AuthException catch (e) {
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

      _currentUser = user;
      _userDocId = user.uid;
      _firebaseUid = null;
      _error = null;

      if (!user.isSubscriptionValid) {
        _status = AuthStatus.blocked;
        await _sessionStore.saveDocId(user.uid);
        _watchUserDoc(user.uid);
        notifyListeners();
        return LoginResult.blocked;
      }

      _status = AuthStatus.authenticated;
      await _sessionStore.saveDocId(user.uid);
      _watchUserDoc(user.uid);
      notifyListeners();

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

  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  Future<void> logout() async {
    await _clearSessionAndSignOut();
  }

  Future<void> _clearSessionAndSignOut({bool deleteLocalData = true}) async {
    final leavingUid = _userDocId ?? _authService.currentUser?.uid;

    // Ensure active mic stops immediately on logout
    try {
      await SpeechService.instance.stopListening();
    } catch (_) {}

    await _userDocSub?.cancel();
    _userDocSub = null;

    try {
      await _sessionStore.clear();
    } catch (e) {
      debugPrint('SessionStore clear failed: $e');
    }

    if (deleteLocalData &&
        UserStorage.deleteLocalDataOnLogout &&
        leavingUid != null &&
        leavingUid.isNotEmpty) {
      try {
        await DatabaseHelper.instance.deleteAllRecordsForUser(leavingUid);
        await UserStorage.deleteUserData(leavingUid);
      } catch (e) {
        debugPrint('[AuthProvider] Error deleting local user data on logout: $e');
      }
    }

    DatabaseHelper.instance.resetUser();

    try {
      await _authService.signOut();
    } catch (e) {
      debugPrint('Firebase signOut failed: $e');
    }

    // IMPORTANT: Never call FirebaseFirestore.instance.terminate() here because
    // terminating the singleton breaks subsequent logins without an app restart.
    _resetSession();
    _status = AuthStatus.unauthenticated;
    notifyListeners();
  }

  void _resetSession() {
    _userDocSub?.cancel();
    _userDocSub = null;
    _currentUser = null;
    _userDocId = null;
    _firebaseUid = null;
    _error = null;
  }

  @override
  void dispose() {
    _userDocSub?.cancel();
    _authSub.cancel();
    super.dispose();
  }
}
