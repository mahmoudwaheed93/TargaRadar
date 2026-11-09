import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/subscription_duration.dart';
import '../models/user_model.dart';

/// Exception carrying a user-facing Arabic message for user-management failures.
class UserRepositoryException implements Exception {
  final String message;
  const UserRepositoryException(this.message);

  @override
  String toString() => message;
}

/// Data layer for managing the `users` collection (admin control panel).
///
/// Pure persistence concerns live here: streaming the roster, enforcing unique
/// usernames, and writing new documents. Deriving the end date from the chosen
/// [SubscriptionDuration] is delegated to that value object.
class UserRepository {
  UserRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  /// Real-time stream of all users, sorted by username (A→Z / أ→ي).
  ///
  /// Sorting is done client-side so documents missing `username` are never
  /// silently dropped by a Firestore `orderBy` and no index is required.
  Stream<List<UserModel>> watchUsers() {
    return _users.snapshots().map((snapshot) {
      final users = snapshot.docs
          .map((doc) => UserModel.fromMap(doc.data(), doc.id))
          .toList()
        ..sort((a, b) => a.username.compareTo(b.username));
      return users;
    });
  }

  /// Renews the subscription for an existing user.
  ///
  /// Sets `isActive = true`, updates `startDate` to now, and recalculates
  /// `endDate` from [duration]. Throws [UserRepositoryException] on failure.
  Future<void> renewSubscription({
    required String uid,
    required SubscriptionDuration duration,
  }) async {
    try {
      final startDate = DateTime.now();
      final endDate = duration.resolveEndDate(startDate);

      await _users.doc(uid).update({
        'isActive': true,
        'startDate': Timestamp.fromDate(startDate),
        'endDate': Timestamp.fromDate(endDate),
      });
    } on FirebaseException catch (e) {
      throw UserRepositoryException('تعذر تجديد الاشتراك، حاول مجدداً (${e.code})');
    }
  }

  /// Creates a new user document.
  ///
  /// - Rejects duplicate usernames with an Arabic [UserRepositoryException].
  /// - `startDate` is always "now"; `endDate` comes from [duration].
  /// - The plaintext [password] is persisted alongside the [UserModel] fields
  ///   (the model itself intentionally never exposes it).
  Future<UserModel> createUser({
    required String username,
    required String password,
    required bool isActive,
    required SubscriptionDuration duration,
    String role = 'user',
  }) async {
    final trimmedUsername = username.trim();

    if (trimmedUsername.isEmpty) {
      throw const UserRepositoryException('يرجى إدخال اسم المستخدم');
    }
    if (password.isEmpty) {
      throw const UserRepositoryException('يرجى إدخال كلمة المرور');
    }

    try {
      final duplicate = await _users
          .where('username', isEqualTo: trimmedUsername)
          .limit(1)
          .get();
      if (duplicate.docs.isNotEmpty) {
        throw const UserRepositoryException('اسم المستخدم موجود مسبقاً');
      }

      final docRef = _users.doc();
      final startDate = DateTime.now();
      final endDate = duration.resolveEndDate(startDate);

      final user = UserModel(
        uid: docRef.id,
        username: trimmedUsername,
        role: role,
        isActive: isActive,
        startDate: startDate,
        endDate: endDate,
        createdAt: startDate,
        lastActiveAt: startDate,
      );

      await docRef.set({
        ...user.toMap(),
        'password': password,
      });

      return user;
    } on UserRepositoryException {
      rethrow;
    } on FirebaseException catch (e) {
      throw UserRepositoryException('تعذر إنشاء الحساب، حاول مجدداً (${e.code})');
    }
  }
}
