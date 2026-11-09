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
  // الأدمن لا ينتهي اشتراكه أبداً — يكفي أن يكون الحساب مفعّلاً
  bool get isSubscriptionValid {
    if (!isActive) return false;
    if (isAdmin) return true;
    // Non-admin: both dates must exist and endDate must be in the future.
    if (endDate == null) return false;
    return DateTime.now().isBefore(endDate!);
  }

  // حساب الأيام المتبقية في الاشتراك
  int get remainingDays {
    if (!isSubscriptionValid) return 0;
    if (isAdmin || endDate == null) return -1; // unlimited
    return endDate!.difference(DateTime.now()).inDays;
  }

  /// نسبة الفترة المتبقية من الاشتراك (0.0 → 1.0) لعرضها في شريط التقدم.
  /// تُحسب كـ (الأيام المتبقية ÷ إجمالي مدة الاشتراك)، ومحصورة بين 0 و 1.
  /// الأدمن يعرض دائماً 1.0 (ممتلئ).
  double get subscriptionProgress {
    if (isAdmin) return 1.0;
    if (startDate == null || endDate == null) return 0.0;
    final totalDays = endDate!.difference(startDate!).inDays;
    if (totalDays <= 0) return 0.0;
    final remaining = endDate!.difference(DateTime.now()).inDays;
    return (remaining / totalDays).clamp(0.0, 1.0).toDouble();
  }

  // تحويل البيانات القادمة من Firestore إلى UserModel
  factory UserModel.fromMap(Map<String, dynamic> map, String docId) {
    final createdAt = (map['createdAt'] as Timestamp?)?.toDate();
    return UserModel(
      uid: docId,
      username: map['username'] ?? '',
      role: map['role'] ?? 'user',
      isActive: map['isActive'] ?? false,
      startDate: (map['startDate'] as Timestamp?)?.toDate(),
      endDate: (map['endDate'] as Timestamp?)?.toDate(),
      createdAt: createdAt,
      packageName: (map['packageName'] ?? map['package'])?.toString() ?? 'اشتراك شهري',
      lastActiveAt:
          (map['lastActiveAt'] as Timestamp?)?.toDate() ?? createdAt,
    );
  }

  // تحويل UserModel إلى Map لرفعها إلى Firestore
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