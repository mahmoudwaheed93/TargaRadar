import 'package:cloud_firestore/cloud_firestore.dart';

/// A persisted summary of one sorting/comparison run, stored under
/// `users/{docId}/saved_data` so a user sees their history after re-login.
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
    final rawDate = data['createdAt'];
    final DateTime createdAt;
    if (rawDate is Timestamp) {
      createdAt = rawDate.toDate();
    } else if (rawDate is int) {
      createdAt = DateTime.fromMillisecondsSinceEpoch(rawDate);
    } else if (rawDate is String) {
      createdAt = DateTime.tryParse(rawDate) ?? DateTime.now();
    } else {
      createdAt = DateTime.now();
    }

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
      createdAt: createdAt,
    );
  }
}
