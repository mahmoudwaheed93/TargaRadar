import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/car_record_model.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;
  static Future<Database>? _initFuture;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _initFuture ??= _initDB('car_logix_v3.db');
    try {
      _database = await _initFuture;
      return _database!;
    } catch (e) {
      _initFuture = null;
      rethrow;
    }
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 3,
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
      onOpen: (db) async {
        await db.execute('CREATE INDEX IF NOT EXISTS idx_car_records_user_date ON car_records(user_id, registration_date DESC)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_car_records_plate ON car_records(plate_number)');
      },
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE car_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        plate_number TEXT NOT NULL,
        gps_url TEXT NOT NULL,
        registration_date TEXT NOT NULL,
        district TEXT NOT NULL,
        street TEXT NOT NULL,
        notes TEXT,
        car_type TEXT NOT NULL,
        recorder_name TEXT NOT NULL,
        is_matched INTEGER DEFAULT 0,
        color TEXT DEFAULT '-',
        owner TEXT DEFAULT '-',
        session_id TEXT DEFAULT 'default-session',
        user_id TEXT DEFAULT ''
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      for (final ddl in [
        'ALTER TABLE car_records ADD COLUMN is_matched INTEGER DEFAULT 0',
        'ALTER TABLE car_records ADD COLUMN color TEXT DEFAULT "-"',
        'ALTER TABLE car_records ADD COLUMN owner TEXT DEFAULT "-"',
        'ALTER TABLE car_records ADD COLUMN session_id TEXT DEFAULT "default-session"',
      ]) {
        try {
          await db.execute(ddl);
        } catch (_) {}
      }
    }
    if (oldVersion < 3) {
      try {
        await db.execute("ALTER TABLE car_records ADD COLUMN user_id TEXT DEFAULT ''");
      } catch (_) {}
    }
  }

  /// The uid of the currently signed-in user. Must be set before any
  /// query/insert so that records are scoped per account.
  String _currentUserId = '';
  set currentUserId(String uid) => _currentUserId = uid;
  String get currentUserId => _currentUserId;
  void resetUser() => _currentUserId = '';

  Future<int> insertCarRecord(CarRecord record) async {
    final db = await database;
    final map = record.toMap();
    map['user_id'] = _currentUserId;
    return await db.insert(
      'car_records',
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<CarRecord>> getAllCarRecords() async {
    final db = await database;
    final result = await db.query(
      'car_records',
      where: 'user_id = ?',
      whereArgs: [_currentUserId],
      orderBy: 'registration_date DESC',
    );
    return result.map((json) => CarRecord.fromMap(json)).toList();
  }

  Future<List<CarRecord>> getRecentCarRecords({int limit = 10}) async {
    final db = await database;
    final result = await db.query(
      'car_records',
      where: 'user_id = ?',
      whereArgs: [_currentUserId],
      orderBy: 'registration_date DESC',
      limit: limit,
    );
    return result.map((json) => CarRecord.fromMap(json)).toList();
  }

  Future<int> deleteCarRecord(int id) async {
    final db = await database;
    return await db.delete(
      'car_records',
      where: 'id = ? AND user_id = ?',
      whereArgs: [id, _currentUserId],
    );
  }

  Future<int> updateCarRecordNotes(int id, String notes) async {
    final db = await database;
    return await db.update(
      'car_records',
      {'notes': notes},
      where: 'id = ? AND user_id = ?',
      whereArgs: [id, _currentUserId],
    );
  }

  Future<int> updateCarRecordBrandAndNotes(int id, {String? carType, String? notes}) async {
    final values = <String, dynamic>{};
    if (carType != null && carType.isNotEmpty && carType != '-') values['car_type'] = carType;
    if (notes != null && notes.isNotEmpty) values['notes'] = notes;
    if (values.isEmpty) return 0;
    final db = await database;
    return await db.update(
      'car_records',
      values,
      where: 'id = ? AND user_id = ?',
      whereArgs: [id, _currentUserId],
    );
  }

  Future<int> updateCarRecord(CarRecord record) async {
    if (record.id == null) return 0;
    final db = await database;
    final map = record.toMap();
    map['user_id'] = _currentUserId;
    return await db.update(
      'car_records',
      map,
      where: 'id = ? AND user_id = ?',
      whereArgs: [record.id, _currentUserId],
    );
  }

  Future<void> clearAllRecords() async {
    final db = await database;
    await db.delete(
      'car_records',
      where: 'user_id = ?',
      whereArgs: [_currentUserId],
    );
  }

  Future<int> deleteAllRecordsForUser(String uid) async {
    final db = await database;
    return await db.delete(
      'car_records',
      where: 'user_id = ?',
      whereArgs: [uid],
    );
  }

  Future<void> close() async {
    if (_database != null) {
      final db = _database!;
      _database = null;
      _initFuture = null;
      await db.close();
    }
  }
}
