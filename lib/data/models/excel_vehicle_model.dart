/// Represents a vehicle row imported from an Excel sheet for matching & auditing
class ExcelVehicleItem {
  final String id;
  final String rawPlate;
  final String normalizedPlate;
  final String carType;
  final String color;
  final String owner;
  final String notes;
  final Map<String, String> otherFields;
  final bool isAudited;
  final String? auditedAt;

  const ExcelVehicleItem({
    required this.id,
    required this.rawPlate,
    required this.normalizedPlate,
    required this.carType,
    required this.color,
    required this.owner,
    required this.notes,
    this.otherFields = const {},
    this.isAudited = false,
    this.auditedAt,
  });

  ExcelVehicleItem copyWith({
    String? id,
    String? rawPlate,
    String? normalizedPlate,
    String? carType,
    String? color,
    String? owner,
    String? notes,
    Map<String, String>? otherFields,
    bool? isAudited,
    String? auditedAt,
  }) {
    return ExcelVehicleItem(
      id: id ?? this.id,
      rawPlate: rawPlate ?? this.rawPlate,
      normalizedPlate: normalizedPlate ?? this.normalizedPlate,
      carType: carType ?? this.carType,
      color: color ?? this.color,
      owner: owner ?? this.owner,
      notes: notes ?? this.notes,
      otherFields: otherFields ?? this.otherFields,
      isAudited: isAudited ?? this.isAudited,
      auditedAt: auditedAt ?? this.auditedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'rawPlate': rawPlate,
      'normalizedPlate': normalizedPlate,
      'carType': carType,
      'color': color,
      'owner': owner,
      'notes': notes,
      'otherFields': otherFields,
      'isAudited': isAudited,
      if (auditedAt != null) 'auditedAt': auditedAt,
    };
  }

  factory ExcelVehicleItem.fromJson(Map<String, dynamic> json) {
    return ExcelVehicleItem(
      id: json['id']?.toString() ?? '',
      rawPlate: json['rawPlate']?.toString() ?? '',
      normalizedPlate: json['normalizedPlate']?.toString() ?? '',
      carType: json['carType']?.toString() ?? '-',
      color: json['color']?.toString() ?? '-',
      owner: json['owner']?.toString() ?? '-',
      notes: json['notes']?.toString() ?? '-',
      otherFields: json['otherFields'] is Map
          ? (json['otherFields'] as Map).map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''))
          : const {},
      isAudited: json['isAudited'] == true,
      auditedAt: json['auditedAt']?.toString(),
    );
  }
}

/// Represents an item in the unified live audit feed
class AuditedLogItem {
  final String id;
  final int seqNumber;
  final String plateNumber;
  final String normalizedPlate;
  final bool isMatched;
  final String carType;
  final String color;
  final String owner;
  final String notes;
  final String timestamp;
  final Map<String, String> otherFields;

  const AuditedLogItem({
    required this.id,
    required this.seqNumber,
    required this.plateNumber,
    required this.normalizedPlate,
    required this.isMatched,
    required this.carType,
    required this.color,
    required this.owner,
    required this.notes,
    required this.timestamp,
    this.otherFields = const {},
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'seqNumber': seqNumber,
      'plateNumber': plateNumber,
      'normalizedPlate': normalizedPlate,
      'isMatched': isMatched,
      'carType': carType,
      'color': color,
      'owner': owner,
      'notes': notes,
      'timestamp': timestamp,
      'otherFields': otherFields,
    };
  }

  factory AuditedLogItem.fromJson(Map<String, dynamic> json) {
    return AuditedLogItem(
      id: json['id']?.toString() ?? '',
      seqNumber: (json['seqNumber'] as num?)?.toInt() ?? 1,
      plateNumber: json['plateNumber']?.toString() ?? '',
      normalizedPlate: json['normalizedPlate']?.toString() ?? '',
      isMatched: json['isMatched'] == true,
      carType: json['carType']?.toString() ?? '-',
      color: json['color']?.toString() ?? '-',
      owner: json['owner']?.toString() ?? '-',
      notes: json['notes']?.toString() ?? '-',
      timestamp: json['timestamp']?.toString() ?? '',
      otherFields: json['otherFields'] is Map
          ? (json['otherFields'] as Map).map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''))
          : const {},
    );
  }
}

/// Structure representing a rapid multi-plate parsed vehicle
class ParsedPlateData {
  final String fullPlate; // e.g. "أ ب ج 1234"
  final String letters;   // e.g. "أ ب ج"
  final String digits;    // e.g. "1234"
  final String detectedBrand; // e.g. "تويوتا"
  final String detectedNote;  // e.g. "جراج يمين"
  final bool isComplete;      // true if 4 digits or finished by delimiter/pause

  const ParsedPlateData({
    required this.fullPlate,
    required this.letters,
    required this.digits,
    required this.detectedBrand,
    required this.detectedNote,
    this.isComplete = true,
  });
}

/// Standalone car brand and/or note spoken without a plate
class OrphanVoiceData {
  final String? brand;
  final String? note;

  const OrphanVoiceData({this.brand, this.note});

  bool get hasData =>
      (brand != null && brand != '-') || (note != null && note != '-');
}
