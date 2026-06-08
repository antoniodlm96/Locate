import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/saved_object.dart';
import '../models/object_group.dart';

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
      version: 3,
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
        await _createGroupTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE saved_objects ADD COLUMN is_active INTEGER NOT NULL DEFAULT 1'
          );
        }
        if (oldVersion < 3) {
          await _createGroupTables(db);
        }
      },
    );
  }

  Future<void> _createGroupTables(Database db) async {
    await db.execute('''
      CREATE TABLE object_groups(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE group_members(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        group_id INTEGER NOT NULL,
        object_id INTEGER NOT NULL,
        order_index INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        FOREIGN KEY (group_id) REFERENCES object_groups(id) ON DELETE CASCADE,
        FOREIGN KEY (object_id) REFERENCES saved_objects(id) ON DELETE CASCADE
      )
    ''');
  }

  // --- Saved Objects ---

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
    await db.delete('group_members', where: 'object_id = ?', whereArgs: [id]);
    return db.delete('saved_objects', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> getObjectCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM saved_objects');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  // --- Groups ---

  Future<int> insertGroup(ObjectGroup group) async {
    final db = await database;
    final map = group.toMap();
    map.remove('id');
    return db.insert('object_groups', map);
  }

  Future<void> updateGroup(int id, String name, String type) async {
    final db = await database;
    await db.update(
      'object_groups',
      {'name': name, 'type': type},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteGroup(int id) async {
    final db = await database;
    await db.delete('group_members', where: 'group_id = ?', whereArgs: [id]);
    return db.delete('object_groups', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<ObjectGroup>> getAllGroups() async {
    final db = await database;
    final maps = await db.query('object_groups', orderBy: 'created_at DESC');
    final groups = maps.map((map) => ObjectGroup.fromMap(map)).toList();
    for (final group in groups) {
      group.members = await getGroupMembers(group.id!);
    }
    return groups;
  }

  Future<List<ObjectGroupMember>> getGroupMembers(int groupId) async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT gm.*, so.id as so_id, so.name as so_name, so.type as so_type,
             so.latitude as so_latitude, so.longitude as so_longitude,
             so.is_active as so_is_active, so.created_at as so_created_at
      FROM group_members gm
      JOIN saved_objects so ON gm.object_id = so.id
      WHERE gm.group_id = ?
      ORDER BY gm.order_index ASC
    ''', [groupId]);
    return maps.map((map) {
      final member = ObjectGroupMember(
        id: map['id'] as int?,
        groupId: map['group_id'] as int,
        objectId: map['object_id'] as int,
        orderIndex: map['order_index'] as int? ?? 0,
        createdAt: DateTime.parse(map['created_at'] as String),
        object: SavedObject(
          id: map['so_id'] as int?,
          name: map['so_name'] as String,
          type: map['so_type'] as String,
          latitude: map['so_latitude'] as double,
          longitude: map['so_longitude'] as double,
          isActive: (map['so_is_active'] as int?) == 1,
          createdAt: DateTime.parse(map['so_created_at'] as String),
        ),
      );
      return member;
    }).toList();
  }

  Future<void> addMemberToGroup(int groupId, int objectId, int orderIndex) async {
    final db = await database;
    await db.insert('group_members', {
      'group_id': groupId,
      'object_id': objectId,
      'order_index': orderIndex,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> removeMember(int memberId) async {
    final db = await database;
    await db.delete('group_members', where: 'id = ?', whereArgs: [memberId]);
  }

  Future<void> reorderMember(int memberId, int newIndex) async {
    final db = await database;
    await db.update(
      'group_members',
      {'order_index': newIndex},
      where: 'id = ?',
      whereArgs: [memberId],
    );
  }

  Future<List<SavedObject>> getObjectsNotInGroup(int groupId) async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT * FROM saved_objects
      WHERE id NOT IN (
        SELECT object_id FROM group_members WHERE group_id = ?
      )
      ORDER BY created_at DESC
    ''', [groupId]);
    return maps.map((map) => SavedObject.fromMap(map)).toList();
  }
}
