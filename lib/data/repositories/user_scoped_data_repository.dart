import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/car_record_model.dart';
import '../models/comparison_history_model.dart';

/// Firestore service for data scoped to a single authenticated account.
///
/// Everything is written under the account's own document as a subcollection:
///   `users/{docId}/saved_data/{item}`
/// where `{docId}` is the Firestore user id (1:1 with the Firebase Auth mirror
/// account — see `AuthService.currentUserDocId`). Keying off the existing user
/// doc keeps the admin's top-level `users` listing clean (no ghost documents)
/// while still giving every account its own private data path.
///
/// Each item carries a `kind` discriminator (`car_record` / `comparison`). Reads
/// order by `createdAt` only and filter `kind` in Dart, which deliberately
/// avoids requiring a composite Firestore index.
class UserScopedDataRepository {
  UserScopedDataRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _savedData(String userDocId) =>
      _firestore.collection('users').doc(userDocId).collection('saved_data');

  // ─── Car records (plates) ───────────────────────────────────────────────

  /// Mirrors a locally-saved [record] to the account's cloud `saved_data`.
  /// The local SQLite row id is stripped so it never leaks across devices.
  Future<void> saveCarRecord(String userDocId, CarRecord record) async {
    final payload = record.toMap()..remove('id');
    payload['kind'] = 'car_record';
    payload['createdAt'] = FieldValue.serverTimestamp();
    await _savedData(userDocId).add(payload);
  }

  /// Live stream of the account's cloud car records, newest first.
  Stream<List<CarRecord>> watchCarRecords(String userDocId) {
    return _savedData(userDocId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(_mapCarRecords);
  }

  /// One-shot fetch of the account's cloud car records, newest first.
  Future<List<CarRecord>> fetchCarRecords(String userDocId) async {
    final snap = await _savedData(userDocId)
        .orderBy('createdAt', descending: true)
        .get();
    return _mapCarRecords(snap);
  }

  List<CarRecord> _mapCarRecords(
    QuerySnapshot<Map<String, dynamic>> snap,
  ) {
    return snap.docs
        .where((d) => (d.data()['kind'] ?? 'car_record') == 'car_record')
        .map((d) => CarRecord.fromMap(d.data()))
        .toList();
  }

  /// Deletes the cloud mirror(s) of a locally-deleted car record, matched by
  /// plate + registration date, so it is not re-imported by restoreFromCloud.
  /// Equality-only filters need no composite index.
  Future<void> deleteCarRecord(
    String userDocId, {
    required String plateNumber,
    required String registrationDateIso,
  }) async {
    final snap = await _savedData(userDocId)
        .where('kind', isEqualTo: 'car_record')
        .where('plate_number', isEqualTo: plateNumber)
        .where('registration_date', isEqualTo: registrationDateIso)
        .get();
    if (snap.docs.isEmpty) return;
    final batch = _firestore.batch();
    for (final doc in snap.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
    debugPrint('[UserData] deleted ${snap.size} cloud mirror(s) of a record');
  }

  // ─── Comparison history ─────────────────────────────────────────────────

  /// Persists a comparison-run summary to the account's cloud `saved_data`.
  Future<void> saveComparison(
    String userDocId,
    ComparisonHistoryEntry entry,
  ) async {
    await _savedData(userDocId).add(entry.toMap());
  }

  /// Live stream of the account's comparison history, newest first.
  Stream<List<ComparisonHistoryEntry>> watchComparisons(String userDocId) {
    return _savedData(userDocId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .where((d) => d.data()['kind'] == 'comparison')
            .map(ComparisonHistoryEntry.fromDoc)
            .toList());
  }

  /// One-shot fetch of the account's comparison history, newest first.
  Future<List<ComparisonHistoryEntry>> fetchComparisons(
    String userDocId,
  ) async {
    final snap = await _savedData(userDocId)
        .orderBy('createdAt', descending: true)
        .get();
    return snap.docs
        .where((d) => d.data()['kind'] == 'comparison')
        .map(ComparisonHistoryEntry.fromDoc)
        .toList();
  }

  /// Deletes every `saved_data` item for the account (used on cache clear).
  Future<void> clearSavedData(String userDocId) async {
    final snap = await _savedData(userDocId).get();
    final batch = _firestore.batch();
    for (final doc in snap.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
    debugPrint('[UserData] cleared ${snap.size} saved_data items');
  }
}
