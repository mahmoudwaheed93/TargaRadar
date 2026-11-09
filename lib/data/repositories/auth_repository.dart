import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';

/// Exception carrying a user-facing Arabic message for authentication failures.
class AuthException implements Exception {
  final String message;
  const AuthException(this.message);

  @override
  String toString() => message;
}

/// Data layer repository responsible for verifying credentials
/// against the `users` collection in Firestore.
class AuthRepository {
  AuthRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  /// Queries the `users` collection by [username], verifies the stored
  /// password, and maps the document into a [UserModel].
  ///
  /// Throws [AuthException] with an Arabic message when:
  /// - the username does not exist,
  /// - the password is incorrect,
  /// - Firestore is unreachable.
  Future<UserModel> login({
    required String username,
    required String password,
  }) async {
    try {
      final snapshot = await _firestore
          .collection('users')
          .where('username', isEqualTo: username.trim())
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) {
        throw const AuthException('اسم المستخدم غير موجود');
      }

      final doc = snapshot.docs.first;
      final data = doc.data();

      // Read 'pass' (the actual Firestore field); fall back to 'password' for
      // any documents that may use the longer key.
      final rawStored = data['pass'] ?? data['password'];
      final storedPassword = rawStored?.toString() ?? '';

      if (storedPassword != password) {
        throw const AuthException('كلمة المرور غير صحيحة');
      }

      return UserModel.fromMap(data, doc.id);
    } on AuthException {
      rethrow;
    } on FirebaseException catch (e) {
      throw AuthException('تعذر الاتصال بالخادم، حاول مجدداً لاحقاً (${e.code})');
    }
  }

  /// Loads a single user document by its id.
  ///
  /// Returns `null` when the account no longer exists (e.g. an admin deleted
  /// it), and throws [AuthException] when Firestore is unreachable. Used on
  /// cold start to resolve the profile behind a persisted Firebase session.
  Future<UserModel?> fetchUserByUid(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (!doc.exists) return null;
      return UserModel.fromMap(doc.data()!, doc.id);
    } on FirebaseException catch (e) {
      throw AuthException('تعذر الاتصال بالخادم، حاول مجدداً لاحقاً (${e.code})');
    }
  }
}
