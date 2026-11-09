import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/car_record_model.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('car_logix_v3.db');
    return _database!;
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
      try {
        await db.execute('ALTER TABLE car_records ADD COLUMN is_matched INTEGER DEFAULT 0');
        await db.execute('ALTER TABLE car_records ADD COLUMN color TEXT DEFAULT "-"');
        await db.execute('ALTER TABLE car_records ADD COLUMN owner TEXT DEFAULT "-"');
        await db.execute('ALTER TABLE car_records ADD COLUMN session_id TEXT DEFAULT "default-session"');
      } catch (_) {}
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
    final db = await database;
    await db.close();
  }
}
