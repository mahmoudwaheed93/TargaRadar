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

  /// Queries `users` case-insensitively (`usernameLower` first, then legacy `username`),
  /// verifies the password, updates `lastActiveAt` best-effort, and returns [UserModel].
  Future<UserModel> login({
    required String username,
    required String password,
  }) async {
    final trimmed = username.trim();
    final lower = trimmed.toLowerCase();
    try {
      var snapshot = await _firestore
          .collection('users')
          .where('usernameLower', isEqualTo: lower)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) {
        snapshot = await _firestore
            .collection('users')
            .where('username', isEqualTo: trimmed)
            .limit(1)
            .get();
      }

      if (snapshot.docs.isEmpty) {
        throw const AuthException('اسم المستخدم غير موجود');
      }

      final doc = snapshot.docs.first;
      final data = doc.data();

      final rawStored = data['pass'] ?? data['password'];
      final storedPassword = rawStored?.toString() ?? '';

      if (storedPassword != password) {
        throw const AuthException('كلمة المرور غير صحيحة');
      }

      // Record login activity timestamp best-effort without blocking login
      doc.reference.update({
        'lastActiveAt': FieldValue.serverTimestamp(),
        if (data['usernameLower'] == null) 'usernameLower': lower,
      }).catchError((_) {});

      return UserModel.fromMap(data, doc.id);
    } on AuthException {
      rethrow;
    } on FirebaseException catch (e) {
      throw AuthException('تعذر الاتصال بالخادم، حاول مجدداً لاحقاً (${e.code})');
    } on Exception catch (e) {
      throw AuthException('تعذر تسجيل الدخول، حاول مجدداً ($e)');
    }
  }

  /// Loads a single user document by its id.
  Future<UserModel?> fetchUserByUid(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (!doc.exists) return null;
      return UserModel.fromMap(doc.data()!, doc.id);
    } on FirebaseException catch (e) {
      throw AuthException('تعذر الاتصال بالخادم، حاول مجدداً لاحقاً (${e.code})');
    } on Exception catch (e) {
      throw AuthException('تعذر قراءة بيانات الحساب ($e)');
    }
  }
}
