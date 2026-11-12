import '../../core/utils/date_formatter.dart';
import 'package:excel/excel.dart';

/// Data model representing a registered vehicle record in CarLogix.
class CarRecord {
  final int? id;
  final String plateNumber;
  final String gpsUrl;
  final DateTime registrationDate;
  final String district;
  final String street;
  final String notes;
  final String carType;
  final String recorderName;
  final bool isMatched;
  final String color;
  final String owner;
  final String sessionId;

  const CarRecord({
    this.id,
    required this.plateNumber,
    required this.gpsUrl,
    required this.registrationDate,
    required this.district,
    required this.street,
    required this.notes,
    required this.carType,
    required this.recorderName,
    this.isMatched = false,
    this.color = '-',
    this.owner = '-',
    this.sessionId = 'default-session',
  });

  /// Factory helper to build Google Maps direction URL from latitude & longitude
  static String buildGpsUrl(double latitude, double longitude) {
    return 'https://www.google.com/maps/dir/?api=1&destination=$latitude,$longitude';
  }

  /// Convert CarRecord instance to a Map for SQLite & JSON storage
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'plate_number': plateNumber,
      'gps_url': gpsUrl,
      'registration_date': registrationDate.toIso8601String(),
      'district': district,
      'street': street,
      'notes': notes,
      'car_type': carType,
      'recorder_name': recorderName,
      'is_matched': isMatched ? 1 : 0,
      'color': color,
      'owner': owner,
      'session_id': sessionId,
    };
  }

  /// Create a CarRecord instance from a Map (SQLite / JSON)
  factory CarRecord.fromMap(Map<String, dynamic> map) {
    return CarRecord(
      id: map['id'] as int?,
      plateNumber: map['plate_number'] as String? ?? '',
      gpsUrl: map['gps_url'] as String? ?? '',
      registrationDate: map['registration_date'] is String
          ? (DateTime.tryParse(map['registration_date'] as String) ?? DateTime.now())
          : DateTime.now(),
      district: map['district'] as String? ?? '',
      street: map['street'] as String? ?? '',
      notes: map['notes'] as String? ?? '',
      carType: map['car_type'] as String? ?? '',
      recorderName: map['recorder_name'] as String? ?? '',
      isMatched: (map['is_matched'] as int? ?? 0) == 1,
      color: map['color'] as String? ?? '-',
      owner: map['owner'] as String? ?? '-',
      sessionId: map['session_id'] as String? ?? 'default-session',
    );
  }

  /// Excel headers in Arabic for exported sheets
  static List<CellValue> get excelHeaders => [
        TextCellValue('م'),
        TextCellValue('رقم اللوحة'),
        TextCellValue('نوع السيارة'),
        TextCellValue('مطابقة للشيت'),
        TextCellValue('الحي'),
        TextCellValue('الشارع'),
        TextCellValue('اسم المسجّل'),
        TextCellValue('تاريخ ووقت التسجيل'),
        TextCellValue('رابط الموقع (Google Maps)'),
        TextCellValue('ملاحظات'),
      ];

  /// Outputs a formatted row list for the `excel` package
  List<CellValue> toExcelRow({int? rowIndex}) {
    return [
      TextCellValue(rowIndex?.toString() ?? (id?.toString() ?? '-')),
      TextCellValue(plateNumber),
      TextCellValue(carType),
      TextCellValue(isMatched ? 'نعم (مطابقة)' : 'لا (غير بالشيت)'),
      TextCellValue(district),
      TextCellValue(street),
      TextCellValue(recorderName),
      TextCellValue(
        AppDateFormatter.formatDateTime12(registrationDate),
      ),
      TextCellValue(gpsUrl),
      TextCellValue(notes),
    ];
  }

  /// CopyWith helper for immutable state modifications
  CarRecord copyWith({
    int? id,
    String? plateNumber,
    String? gpsUrl,
    DateTime? registrationDate,
    String? district,
    String? street,
    String? notes,
    String? carType,
    String? recorderName,
    bool? isMatched,
    String? color,
    String? owner,
    String? sessionId,
  }) {
    return CarRecord(
      id: id ?? this.id,
      plateNumber: plateNumber ?? this.plateNumber,
      gpsUrl: gpsUrl ?? this.gpsUrl,
      registrationDate: registrationDate ?? this.registrationDate,
      district: district ?? this.district,
      street: street ?? this.street,
      notes: notes ?? this.notes,
      carType: carType ?? this.carType,
      recorderName: recorderName ?? this.recorderName,
      isMatched: isMatched ?? this.isMatched,
      color: color ?? this.color,
      owner: owner ?? this.owner,
      sessionId: sessionId ?? this.sessionId,
    );
  }
}
