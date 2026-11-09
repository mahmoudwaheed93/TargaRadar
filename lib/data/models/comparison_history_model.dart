import 'package:cloud_firestore/cloud_firestore.dart';

/// A persisted summary of one sorting/comparison run, stored under
/// `users/{docId}/saved_data` so a user sees their history after re-login.
///
/// Only a lightweight summary is kept (file names, chosen columns, match count,
/// and a capped sample of matched keys) — the full row payload stays in the
/// exported Excel file rather than bloating Firestore.
class ComparisonHistoryEntry {
  final String? id;
  final String referenceFileName;
  final String inspectionFileName;
  final String referenceColumn;
  final String inspectionColumn;
  final int matchedCount;
  final List<String> matchedKeys;
  final DateTime createdAt;

  const ComparisonHistoryEntry({
    this.id,
    required this.referenceFileName,
    required this.inspectionFileName,
    required this.referenceColumn,
    required this.inspectionColumn,
    required this.matchedCount,
    required this.matchedKeys,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'kind': 'comparison',
      'referenceFileName': referenceFileName,
      'inspectionFileName': inspectionFileName,
      'referenceColumn': referenceColumn,
      'inspectionColumn': inspectionColumn,
      'matchedCount': matchedCount,
      'matchedKeys': matchedKeys,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  factory ComparisonHistoryEntry.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return ComparisonHistoryEntry(
      id: doc.id,
      referenceFileName: data['referenceFileName'] as String? ?? '',
      inspectionFileName: data['inspectionFileName'] as String? ?? '',
      referenceColumn: data['referenceColumn'] as String? ?? '',
      inspectionColumn: data['inspectionColumn'] as String? ?? '',
      matchedCount: (data['matchedCount'] as num?)?.toInt() ?? 0,
      matchedKeys: (data['matchedKeys'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const <String>[],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}
