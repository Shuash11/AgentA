import 'package:sqflite/sqflite.dart';
import 'database_helper.dart';

enum ModelDbStatus {
  notInstalled,
  ready,
  error,
  skipped,
}

class OfflineModelDao {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  static const String _tableName = 'offline_model_status';
  static const int _singleRowId = 1;

  Future<void> setModelReady({
    required String modelType,
    String? filePath,
    String? version,
  }) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.insert(
      _tableName,
      {
        'id': _singleRowId,
        'model_type': modelType,
        'status': ModelDbStatus.ready.name,
        'downloaded_at': now,
        'file_path': filePath,
        'version': version,
        'created_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> setModelNotInstalled() async {
    final db = await _dbHelper.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.insert(
      _tableName,
      {
        'id': _singleRowId,
        'model_type': 'gemma3-1b-it-int4',
        'status': ModelDbStatus.notInstalled.name,
        'downloaded_at': null,
        'file_path': null,
        'version': null,
        'created_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> setModelError(String? errorMessage) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.insert(
      _tableName,
      {
        'id': _singleRowId,
        'model_type': 'gemma3-1b-it-int4',
        'status': ModelDbStatus.error.name,
        'downloaded_at': null,
        'file_path': null,
        'version': errorMessage,
        'created_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> setModelSkipped() async {
    final db = await _dbHelper.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.insert(
      _tableName,
      {
        'id': _singleRowId,
        'model_type': 'gemma3-1b-it-int4',
        'status': ModelDbStatus.skipped.name,
        'downloaded_at': null,
        'file_path': null,
        'version': null,
        'created_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> getModelStatus() async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      _tableName,
      where: 'id = ?',
      whereArgs: [_singleRowId],
    );

    if (rows.isEmpty) return null;
    return rows.first;
  }

  Future<ModelDbStatus> getStatus() async {
    final status = await getModelStatus();
    if (status == null) return ModelDbStatus.notInstalled;

    final statusStr = status['status'] as String?;
    switch (statusStr) {
      case 'ready':
        return ModelDbStatus.ready;
      case 'error':
        return ModelDbStatus.error;
      case 'skipped':
        return ModelDbStatus.skipped;
      default:
        return ModelDbStatus.notInstalled;
    }
  }

  Future<bool> isModelReady() async {
    final status = await getStatus();
    return status == ModelDbStatus.ready;
  }

  Future<bool> hasUserSkipped() async {
    final status = await getStatus();
    return status == ModelDbStatus.skipped;
  }

  Future<void> clearModelStatus() async {
    final db = await _dbHelper.database;
    await db.delete(
      _tableName,
      where: 'id = ?',
      whereArgs: [_singleRowId],
    );
  }
}