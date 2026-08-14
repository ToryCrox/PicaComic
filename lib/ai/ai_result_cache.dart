import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class AiCachedResult {
  final String resultText;

  const AiCachedResult(this.resultText);
}

/// 持久化 AI 结果缓存，按原文哈希自动淘汰过期结果。
class AiResultCache {
  static const _tableName = 'ai_cached_results';
  static const maxEntries = 10000;

  Database? _database;
  Future<Database>? _opening;

  static String hashSource(String sourceText) =>
      sha256.convert(utf8.encode(sourceText)).toString();

  Future<AiCachedResult?> get({
    required String sceneId,
    required String resourceKey,
    required String sourceText,
  }) async {
    final db = await _getDatabase();
    final rows = await db.query(
      _tableName,
      where: 'scene_id = ? AND resource_key = ? AND source_hash = ?',
      whereArgs: [sceneId, resourceKey, hashSource(sourceText)],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    await db.update(
      _tableName,
      {'accessed_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [rows.first['id']],
    );
    return AiCachedResult(rows.first['result_text'] as String);
  }

  Future<void> put({
    required String sceneId,
    required String resourceKey,
    required String sourceText,
    required String resultText,
  }) async {
    final db = await _getDatabase();
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert(_tableName, {
      'scene_id': sceneId,
      'resource_key': resourceKey,
      'source_hash': hashSource(sourceText),
      'result_text': resultText,
      'created_at': now,
      'accessed_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await _prune(db);
  }

  Future<int> clearScene(String sceneId) async {
    final db = await _getDatabase();
    return db.delete(_tableName, where: 'scene_id = ?', whereArgs: [sceneId]);
  }

  Future<Database> _getDatabase() async {
    final current = _database;
    if (current != null && current.isOpen) return current;
    final opening = _opening ??= _open();
    try {
      return await opening;
    } catch (_) {
      if (identical(_opening, opening)) _opening = null;
      rethrow;
    }
  }

  Future<Database> _open() async {
    final db = await databaseFactory.openDatabase(
      join(App.dataPath, 'ai_result_cache.db'),
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (database, _) => database.execute('''
CREATE TABLE $_tableName (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  scene_id TEXT NOT NULL,
  resource_key TEXT NOT NULL,
  source_hash TEXT NOT NULL,
  result_text TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  accessed_at INTEGER NOT NULL,
  UNIQUE(scene_id, resource_key, source_hash)
)
'''),
      ),
    );
    _database = db;
    _opening = null;
    return db;
  }

  Future<void> _prune(Database db) async {
    final rows = await db.rawQuery('SELECT COUNT(*) AS count FROM $_tableName');
    final count = (rows.first['count'] as num?)?.toInt() ?? 0;
    final excess = count - maxEntries;
    if (excess <= 0) return;
    await db.rawDelete(
      'DELETE FROM $_tableName WHERE id IN '
      '(SELECT id FROM $_tableName ORDER BY accessed_at ASC LIMIT ?)',
      [excess],
    );
  }
}
