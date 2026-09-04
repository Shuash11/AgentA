import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../../core/constants/app_constants.dart';

class DatabaseHelper {
  DatabaseHelper._internal();
  static final DatabaseHelper instance = DatabaseHelper._internal();
  static Database? _database;

  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    return openDatabase(
      join(dbPath, AppConstants.dbName),
      version: AppConstants.dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS pending_signups (
          local_id TEXT PRIMARY KEY,
          email TEXT NOT NULL,
          password TEXT NOT NULL,
          display_name TEXT NOT NULL,
          recovery_code TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          is_synced INTEGER DEFAULT 0
        )
      ''');
    }
    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS offline_model_status (
          id INTEGER PRIMARY KEY,
          model_type TEXT NOT NULL,
          status TEXT NOT NULL,
          downloaded_at INTEGER,
          file_path TEXT,
          version TEXT,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''');
    }
    if (oldVersion < 4) {
      await db.execute('ALTER TABLE chat_sessions ADD COLUMN is_deleted INTEGER DEFAULT 0');
      await db.execute('ALTER TABLE messages ADD COLUMN is_deleted INTEGER DEFAULT 0');
    }
    if (oldVersion < 5) {
      await _createIndexes(db);
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE chat_sessions (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        title TEXT NOT NULL,
        last_message TEXT,
        updated_at INTEGER NOT NULL,
        unread INTEGER DEFAULT 0,
        is_synced INTEGER DEFAULT 0,
        is_deleted INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE messages (
        id TEXT PRIMARY KEY,
        chat_id TEXT NOT NULL,
        text TEXT NOT NULL,
        is_user INTEGER NOT NULL,
        timestamp INTEGER NOT NULL,
        is_synced INTEGER DEFAULT 0,
        is_deleted INTEGER DEFAULT 0,
        FOREIGN KEY (chat_id) REFERENCES chat_sessions(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE user_profile (
        uid TEXT PRIMARY KEY,
        display_name TEXT,
        email TEXT,
        photo_url TEXT,
        recovery_code TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE pending_signups (
        local_id TEXT PRIMARY KEY,
        email TEXT NOT NULL,
        password TEXT NOT NULL,
        display_name TEXT NOT NULL,
        recovery_code TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        is_synced INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS offline_model_status (
        id INTEGER PRIMARY KEY,
        model_type TEXT NOT NULL,
        status TEXT NOT NULL,
        downloaded_at INTEGER,
        file_path TEXT,
        version TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    await _createIndexes(db);
  }

  Future<void> _createIndexes(Database db) async {
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_chat_sessions_user_deleted_updated
      ON chat_sessions(user_id, is_deleted, updated_at DESC)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_chat_sessions_deleted_updated
      ON chat_sessions(is_deleted, updated_at DESC)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_chat_sessions_sync_deleted
      ON chat_sessions(is_synced, is_deleted)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_messages_chat_deleted_timestamp
      ON messages(chat_id, is_deleted, timestamp ASC)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_messages_sync_deleted
      ON messages(is_synced, is_deleted)
    ''');
  }
}
