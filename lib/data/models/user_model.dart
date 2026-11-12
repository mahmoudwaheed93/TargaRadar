import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String uid;
  final String username;
  final String role; // 'admin' or 'user'
  final bool isActive;
  final DateTime? startDate;
  final DateTime? endDate;
  final DateTime? createdAt;
  final String packageName;
  final DateTime? lastActiveAt;

  UserModel({
    required this.uid,
    required this.username,
    required this.role,
    required this.isActive,
    this.startDate,
    this.endDate,
    this.createdAt,
    this.packageName = 'اشتراك شهري',
    this.lastActiveAt,
  });

  /// Whether this is an admin account (admins skip date checks entirely).
  bool get isAdmin => role == 'admin';

  // التحقق هل الاشتراك ما زال سارياً أم انتهى
  bool get isSubscriptionValid {
    if (!isActive) return false;
    if (isAdmin) return true;
    if (endDate == null) return false;
    return DateTime.now().isBefore(endDate!);
  }

  // حساب الأيام المتبقية في الاشتراك (بتقريب الساعات للأعلى حتى لا يظهر 0 في اليوم الأخير)
  int get remainingDays {
    if (!isSubscriptionValid) return 0;
    if (isAdmin || endDate == null) return -1; // unlimited
    final diff = endDate!.difference(DateTime.now());
    if (diff.isNegative) return 0;
    return (diff.inHours / 24).ceil();
  }

  /// نسبة الفترة المتبقية من الاشتراك (0.0 → 1.0) بدقة المللي ثانية.
  double get subscriptionProgress {
    if (isAdmin) return 1.0;
    if (startDate == null || endDate == null) return 0.0;
    final totalMs = endDate!.difference(startDate!).inMilliseconds;
    if (totalMs <= 0) return 0.0;
    final remainingMs = endDate!.difference(DateTime.now()).inMilliseconds;
    return (remainingMs / totalMs).clamp(0.0, 1.0).toDouble();
  }

  factory UserModel.fromMap(Map<String, dynamic> map, String docId) {
    final createdAt = (map['createdAt'] as Timestamp?)?.toDate();
    return UserModel(
      uid: docId,
      username: map['username']?.toString() ?? '',
      role: map['role']?.toString() ?? 'user',
      isActive: map['isActive'] == true,
      startDate: (map['startDate'] as Timestamp?)?.toDate(),
      endDate: (map['endDate'] as Timestamp?)?.toDate(),
      createdAt: createdAt,
      packageName: (map['packageName'] ?? map['package'])?.toString() ?? 'اشتراك شهري',
      lastActiveAt: (map['lastActiveAt'] as Timestamp?)?.toDate() ?? createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'username': username,
      'role': role,
      'isActive': isActive,
      'startDate': startDate != null ? Timestamp.fromDate(startDate!) : null,
      'endDate': endDate != null ? Timestamp.fromDate(endDate!) : null,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
      'packageName': packageName,
      'lastActiveAt': lastActiveAt != null ? Timestamp.fromDate(lastActiveAt!) : null,
    };
  }
}
