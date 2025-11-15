import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:synchronized/synchronized.dart';

/// 表名常量
const String kTableDownload = 'download';
const String kTableLocalComic = 'local_comic';
const String kTableLocalHistory = 'local_history';

/// download 表字段常量
const String kDownloadId = 'id';
const String kDownloadTitle = 'title';
const String kDownloadSubtitle = 'subtitle';
const String kDownloadTime = 'time';
const String kDownloadDirectory = 'directory';
const String kDownloadSize = 'size';
const String kDownloadJson = 'json';

/// local_comic 表字段常量
const String kLocalComicPath = 'path';
const String kLocalComicTitle = 'title';
const String kLocalComicSubtitle = 'subtitle';
const String kLocalComicJson = 'json';
const String kLocalComicSize = 'size';
const String kLocalComicCover = 'cover';

/// local_history 表字段常量
const String kLocalHistoryPath = 'path';
const String kLocalHistoryIsReversed = 'isReversed';
const String kLocalHistoryPageIndex = 'pageIndex';
const String kLocalHistoryTime = 'time';
const String kLocalHistoryJson = 'json';

class DownloadDatabase {
  static DownloadDatabase? _instance;
  static final Lock _lock = Lock();

  factory DownloadDatabase() => _instance ??= DownloadDatabase._internal();

  DownloadDatabase._internal();

  Database? _db;
  bool _initialized = false;
  final Completer<Database> _initCompleter = Completer<Database>();

  /// 初始化数据库
  Future<void> init({required String dbPath}) async {
    if (_initialized) return;
    await _lock.synchronized(() async {
      if (_initialized) return;

      // 确保目录存在
      final dir = Directory(dirname(dbPath));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      _db = await databaseFactory.openDatabase(dbPath,
          options: OpenDatabaseOptions(
            version: 1,
            onCreate: _onCreate,
            onUpgrade: _onUpgrade,
          ));

      _initialized = true;
      _initCompleter.complete(_db);
    });
  }

  /// 创建表
  Future<void> _onCreate(Database db, int version) async {
    await _createTables(db);
  }

  /// 升级数据库
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // 根据需要实现升级逻辑
    // 目前版本为1，无需特殊处理
  }

  /// 创建所有表
  Future<void> _createTables(Database db) async {
    // 创建 download 表
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $kTableDownload (
        $kDownloadId TEXT PRIMARY KEY,
        $kDownloadTitle TEXT,
        $kDownloadSubtitle TEXT,
        $kDownloadTime INTEGER,
        $kDownloadDirectory TEXT,
        $kDownloadSize REAL,
        $kDownloadJson TEXT
      )
    ''');

    // 创建 local_comic 表
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $kTableLocalComic (
        $kLocalComicPath TEXT PRIMARY KEY,
        $kLocalComicTitle TEXT,
        $kLocalComicSubtitle TEXT,
        $kLocalComicJson TEXT,
        $kLocalComicSize REAL,
        $kLocalComicCover TEXT
      )
    ''');

    // 创建 local_history 表
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $kTableLocalHistory (
        $kLocalHistoryPath TEXT PRIMARY KEY,
        $kLocalHistoryIsReversed INTEGER,
        $kLocalHistoryPageIndex INTEGER,
        $kLocalHistoryTime INTEGER,
        $kLocalHistoryJson TEXT
      )
    ''');
  }

  /// 修改表结构的方法示例
  Future<void> upgradeTableStructure() async {
    // 示例：如果需要添加新字段或其他表结构调整
    // 可以在这里实现具体的升级逻辑
    // 例如：
    /*
    final db = await _getDatabase();
    await db.execute('ALTER TABLE $kTableDownload ADD COLUMN new_field TEXT');
    */
  }

  /// 确保数据库已初始化并返回数据库实例
  Future<Database> _getDatabase() {
    final db = _db;
    if (db != null) {
      return SynchronousFuture(db);
    }

    return _initCompleter.future;
  }

  /// 添加或更新下载项
  Future<void> addToDownload(
    String id,
    String title,
    String subtitle,
    int time,
    String directory,
    double size,
    String json,
  ) async {
    final db = await _getDatabase();
    await db.insert(kTableDownload, {
      kDownloadId: id,
      kDownloadTitle: title,
      kDownloadSubtitle: subtitle,
      kDownloadTime: time,
      kDownloadDirectory: directory,
      kDownloadSize: size,
      kDownloadJson: json,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// 更新下载项大小
  Future<void> updateDownloadSize(String id, double size) async {
    final db = await _getDatabase();
    await db.update(
      kTableDownload,
      {kDownloadSize: size},
      where: '$kDownloadId = ?',
      whereArgs: [id],
    );
  }

  /// 检查下载项是否存在
  Future<bool> isDownloadExists(String id) async {
    final db = await _getDatabase();
    final result = await db.query(
      kTableDownload,
      columns: [kDownloadId],
      where: '$kDownloadId = ?',
      whereArgs: [id],
    );
    return result.isNotEmpty;
  }

  /// 删除下载项
  Future<void> deleteDownload(String id) async {
    final db = await _getDatabase();
    await db.delete(
      kTableDownload,
      where: '$kDownloadId = ?',
      whereArgs: [id],
    );
  }

  /// 获取下载项
  Future<Map<String, Object?>?> getDownloadById(String id) async {
    final db = await _getDatabase();
    final result = await db.query(
      kTableDownload,
      where: '$kDownloadId = ?',
      whereArgs: [id],
    );
    return result.isEmpty ? null : result.first;
  }

  /// 获取下载总数
  Future<int> getDownloadTotalCount() async {
    final db = await _getDatabase();
    final result = await db.rawQuery('SELECT COUNT(*) FROM $kTableDownload');
    return result.first.values.first as int;
  }

  /// 获取所有下载项
  Future<List<Map<String, Object?>>> getAllDownloads({
    String orderBy = kDownloadTime,
    bool descending = true,
  }) async {
    final db = await _getDatabase();
    final order = descending ? 'DESC' : 'ASC';
    return await db.query(
      kTableDownload,
      orderBy: '$orderBy $order',
    );
  }

  /// 获取目录名
  Future<String?> getDownloadDirectory(String id) async {
    final db = await _getDatabase();
    final result = await db.query(
      kTableDownload,
      columns: [kDownloadDirectory],
      where: '$kDownloadId = ?',
      whereArgs: [id],
    );
    return result.isEmpty ? null : result.first[kDownloadDirectory] as String?;
  }

  /// 添加或更新本地漫画项
  Future<void> addLocalComic({
    required String path,
    required String title,
    required String subtitle,
    required String json,
    required double size,
    required String cover,
  }) async {
    final db = await _getDatabase();
    await db.insert(kTableLocalComic, {
      kLocalComicPath: path,
      kLocalComicTitle: title,
      kLocalComicSubtitle: subtitle,
      kLocalComicJson: json,
      kLocalComicSize: size,
      kLocalComicCover: cover,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// 获取所有本地漫画
  Future<List<Map<String, Object?>>> getAllLocalComics() async {
    final db = await _getDatabase();
    return await db.query(kTableLocalComic);
  }

  /// 删除本地漫画
  Future<void> deleteLocalComic(String path) async {
    final db = await _getDatabase();
    await db.delete(
      kTableLocalComic,
      where: '$kLocalComicPath = ?',
      whereArgs: [path],
    );
  }

  /// 添加或更新本地阅读历史
  Future<void> addOrUpdateLocalHistory({
    required String path,
    required int isReversed,
    required int pageIndex,
    required int time,
    required String json,
  }) async {
    final db = await _getDatabase();
    await db.insert(kTableLocalHistory, {
      kLocalHistoryPath: path,
      kLocalHistoryIsReversed: isReversed,
      kLocalHistoryPageIndex: pageIndex,
      kLocalHistoryTime: time,
      kLocalHistoryJson: json,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// 获取本地阅读历史
  Future<Map<String, Object?>?> getLocalHistory(String path) async {
    final db = await _getDatabase();
    final result = await db.query(
      kTableLocalHistory,
      where: '$kLocalHistoryPath = ?',
      whereArgs: [path],
    );
    return result.isEmpty ? null : result.first;
  }

  /// 关闭数据库连接
  Future<void> close() async {
    if (_db != null && _initialized) {
      await _db!.close();
      _db = null;
      _initialized = false;
    }
  }
}