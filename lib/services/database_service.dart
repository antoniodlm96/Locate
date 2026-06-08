import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/saved_object.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._();
  DatabaseService._();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final path = join(await getDatabasesPath(), 'locate.db');
    return openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE saved_objects(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            type TEXT NOT NULL,
            latitude REAL NOT NULL,
            longitude REAL NOT NULL,
            is_active INTEGER NOT NULL DEFAULT 1,
            created_at TEXT NOT NULL
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE saved_objects ADD COLUMN is_active INTEGER NOT NULL DEFAULT 1'
          );
        }
      },
    );
  }

  Future<int> insertObject(SavedObject obj) async {
    final db = await database;
    final map = obj.toMap();
    map.remove('id');
    return db.insert('saved_objects', map);
  }

  Future<List<SavedObject>> getAllObjects() async {
    final db = await database;
    final maps = await db.query('saved_objects', orderBy: 'created_at DESC');
    return maps.map((map) => SavedObject.fromMap(map)).toList();
  }

  Future<List<SavedObject>> getActiveObjects() async {
    final db = await database;
    final maps = await db.query(
      'saved_objects',
      where: 'is_active = ?',
      whereArgs: [1],
      orderBy: 'created_at DESC',
    );
    return maps.map((map) => SavedObject.fromMap(map)).toList();
  }

  Future<void> updateObject(SavedObject obj) async {
    final db = await database;
    await db.update(
      'saved_objects',
      obj.toMap(),
      where: 'id = ?',
      whereArgs: [obj.id],
    );
  }

  Future<void> updateObjectName(int id, String name) async {
    final db = await database;
    await db.update(
      'saved_objects',
      {'name': name},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateObjectActive(int id, bool isActive) async {
    final db = await database;
    await db.update(
      'saved_objects',
      {'is_active': isActive ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteObject(int id) async {
    final db = await database;
    return db.delete('saved_objects', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> getObjectCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM saved_objects');
    return Sqflite.firstIntValue(result) ?? 0;
  }
}
