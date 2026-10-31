import 'package:sqflite/sqflite.dart';
import 'database_helper.dart';

enum ModelDbStatus { notInstalled, ready, error, skipped }

/// The family a failed model load belongs to (cycle-40 P1).
///
/// The class is the field-visible failure evidence: a shipped build has no
/// debug logs (every raw-exception log is `kDebugMode`-gated and tree-shaken
/// from release), so the persisted class is the only way to tell WHY a load
/// failed once the app is in the user's hands.
///
/// * [unsupportedAbi] — the device cannot run the model at all (the engine's
///   deterministic arm64-only guard);
/// * [notInstalled] — the model asset is not on the device;
/// * [file] — the asset is present but corrupt/unreadable;
/// * [engineInit] — the engine refused to initialise on an installed asset;
/// * [unknown] — the failure matched no known family.
enum OfflineModelFailureClass {
  unsupportedAbi,
  notInstalled,
  file,
  engineInit,
  unknown,
}

class OfflineModelDao {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  static const String _tableName = 'offline_model_status';
  static const int _singleRowId = 1;

  /// Whether the persisted row carries the failure-class column. Cached per
  /// DAO instance: the answer cannot change while the database is open.
  bool? _hasFailureClassColumn;

  Future<void> setModelReady({
    required String modelType,
    String? filePath,
    String? version,
  }) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.insert(_tableName, {
      'id': _singleRowId,
      'model_type': modelType,
      'status': ModelDbStatus.ready.name,
      'downloaded_at': now,
      'file_path': filePath,
      'version': version,
      'created_at': now,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> setModelNotInstalled() async {
    final db = await _dbHelper.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.insert(_tableName, {
      'id': _singleRowId,
      'model_type': 'gemma-4-e2b-it',
      'status': ModelDbStatus.notInstalled.name,
      'downloaded_at': null,
      'file_path': null,
      'version': null,
      'created_at': now,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Records a failed model operation (a failed download OR a failed load).
  ///
  /// The install markers of the current row are PRESERVED: an error on a row
  /// that already carries a completed download means "the asset is installed
  /// but the last operation failed" (e.g. the model failed to load), so the
  /// UI must offer RETRY LOAD and never re-open the download gate — that
  /// would strand the user behind a spurious 2.6 GB re-download. An error row
  /// WITHOUT a download marker means the download itself failed, so the model
  /// is genuinely not installed.
  Future<void> setModelError(String? errorMessage) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final current = await getModelStatus();

    await db.insert(_tableName, {
      'id': _singleRowId,
      'model_type': 'gemma-4-e2b-it',
      'status': ModelDbStatus.error.name,
      'downloaded_at': current?['downloaded_at'],
      'file_path': current?['file_path'],
      'version': errorMessage,
      'created_at': now,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Records the failure CLASS of the last failed load.
  ///
  /// Written AFTER [setModelError]: that write replaces the whole row, so a
  /// class stored before it would be dropped with the old row. A database
  /// whose row predates the class column is tolerated — the error row still
  /// records the failure, only the class is unavailable.
  Future<void> setFailureClass(OfflineModelFailureClass? failureClass) async {
    final db = await _dbHelper.database;
    if (!await _supportsFailureClass(db)) return;

    await db.update(
      _tableName,
      {'failure_class': failureClass?.name},
      where: 'id = ?',
      whereArgs: [_singleRowId],
    );
  }

  /// The failure class of the last failed load, or null when the last
  /// operation succeeded (or the row predates the class column).
  Future<OfflineModelFailureClass?> getFailureClass() async {
    final db = await _dbHelper.database;
    if (!await _supportsFailureClass(db)) return null;

    final status = await getModelStatus();
    final stored = status?['failure_class'] as String?;
    if (stored == null) return null;
    for (final value in OfflineModelFailureClass.values) {
      if (value.name == stored) return value;
    }
    return OfflineModelFailureClass.unknown;
  }

  /// Whether the offline-model row carries the failure-class column.
  Future<bool> _supportsFailureClass(Database db) async {
    final cached = _hasFailureClassColumn;
    if (cached != null) return cached;

    final columns = await db.rawQuery('PRAGMA table_info($_tableName)');
    final present = columns.any((column) => column['name'] == 'failure_class');
    _hasFailureClassColumn = present;
    return present;
  }

  /// Whether the model asset is present on the device.
  ///
  /// * a `ready` row — downloaded and working;
  /// * an `error` row that still carries the download marker — INSTALLED but
  ///   broken (the load failed): the UI must offer RETRY LOAD, never a
  ///   re-download;
  /// * an `error` row without the marker — the download failed: the model is
  ///   genuinely not installed.
  ///
  /// This is the durable signal the offline gate and the chat card use to
  /// decide between "retry the load" and "get the model" — the in-memory
  /// download-service status cannot answer it after a restart.
  Future<bool> isModelInstalled() async {
    final status = await getModelStatus();
    if (status == null) return false;

    switch (status['status'] as String?) {
      case 'ready':
        return true;
      case 'error':
        return status['downloaded_at'] != null;
      default:
        return false;
    }
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

  Future<void> clearModelStatus() async {
    final db = await _dbHelper.database;
    await db.delete(_tableName, where: 'id = ?', whereArgs: [_singleRowId]);
  }
}
