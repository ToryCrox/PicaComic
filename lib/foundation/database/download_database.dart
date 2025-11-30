import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:synchronized/synchronized.dart';

/// 表名常量
const String kTableDownload = 'download';
const String kTableLocalComic = 'local_comic';
const String kTableLocalHistory = 'local_history';
const String kTableTags = 'tags';
const String kTableComicTags = 'comic_tags';

/// download 表字段常量
const String kDownloadId = 'id';
const String kDownloadTitle = 'title';
const String kDownloadSubtitle = 'subtitle';
const String kDownloadTime = 'time';
const String kDownloadDirectory = 'directory';
const String kDownloadSize = 'size';
const String kDownloadJson = 'json';

/// tags 表字段常量
const String kTagId = 'id';
const String kTagName = 'name';
const String kTagCoverComicId = 'cover_comic_id';
const String kTagCreatedTime = 'created_time';
const String kTagSortOrder = 'sort_order';
const String kTagUpdatedTime = 'updated_time';
const String kTagCategory = 'category';
const String kTagCategorySortOrder = 'category_sort_order';

/// comic_tags 表字段常量
const String kComicTagsComicId = 'comic_id';
const String kComicTagsTagId = 'tag_id';

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
            version: 4,
            onCreate: _onCreate,
            onUpgrade: _onUpgrade,
            onOpen: (db) async {
              // 启用外键约束支持,确保 ON DELETE CASCADE 生效
              await db.execute('PRAGMA foreign_keys = ON');
            },
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
    if (oldVersion < 2) {
      await _createTagTables(db);
    }
    if (oldVersion < 3) {
      // 为tags表添加新字段
      await db.execute(
          'ALTER TABLE $kTableTags ADD COLUMN $kTagSortOrder INTEGER DEFAULT 0');
      await db.execute(
          'ALTER TABLE $kTableTags ADD COLUMN $kTagUpdatedTime INTEGER DEFAULT 0');
      await db.execute(
          'ALTER TABLE $kTableTags ADD COLUMN $kTagCategory INTEGER DEFAULT 0');
    }
    if (oldVersion < 4) {
      await db.execute(
          'ALTER TABLE $kTableTags ADD COLUMN $kTagCategorySortOrder INTEGER DEFAULT 0');
    }
  }

  /// 创建标签相关表
  Future<void> _createTagTables(Database db) async {
    // 创建 tags 表 - 使用漫画ID作为封面引用
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $kTableTags (
        $kTagId INTEGER PRIMARY KEY AUTOINCREMENT,
        $kTagName TEXT UNIQUE NOT NULL,
        $kTagCoverComicId TEXT,
        $kTagCreatedTime INTEGER,
        $kTagSortOrder INTEGER DEFAULT 0,
        $kTagUpdatedTime INTEGER DEFAULT 0,
        $kTagCategory INTEGER DEFAULT 0,
        $kTagCategorySortOrder INTEGER DEFAULT 0,
        FOREIGN KEY ($kTagCoverComicId) REFERENCES $kTableDownload($kDownloadId) ON DELETE SET NULL
      )
    ''');

    // 创建 comic_tags 表
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $kTableComicTags (
        $kComicTagsComicId TEXT NOT NULL,
        $kComicTagsTagId INTEGER NOT NULL,
        PRIMARY KEY ($kComicTagsComicId, $kComicTagsTagId),
        FOREIGN KEY ($kComicTagsComicId) REFERENCES $kTableDownload($kDownloadId) ON DELETE CASCADE,
        FOREIGN KEY ($kComicTagsTagId) REFERENCES $kTableTags($kTagId) ON DELETE CASCADE
      )
    ''');
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

    // 创建标签相关表
    await _createTagTables(db);
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
    await db.insert(
        kTableDownload,
        {
          kDownloadId: id,
          kDownloadTitle: title,
          kDownloadSubtitle: subtitle,
          kDownloadTime: time,
          kDownloadDirectory: directory,
          kDownloadSize: size,
          kDownloadJson: json,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// 更新目录
  Future<bool> updateDownloadDirectory(String id, String directory) async {
    final db = await _getDatabase();
    final result = await db.update(
      kTableDownload,
      {kDownloadDirectory: directory},
      where: '$kDownloadId = ?',
      whereArgs: [id],
    );
    return result > 0;
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
    await db.insert(
        kTableLocalComic,
        {
          kLocalComicPath: path,
          kLocalComicTitle: title,
          kLocalComicSubtitle: subtitle,
          kLocalComicJson: json,
          kLocalComicSize: size,
          kLocalComicCover: cover,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
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
    await db.insert(
        kTableLocalHistory,
        {
          kLocalHistoryPath: path,
          kLocalHistoryIsReversed: isReversed,
          kLocalHistoryPageIndex: pageIndex,
          kLocalHistoryTime: time,
          kLocalHistoryJson: json,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
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

  // ==================== Tag Management Methods ====================

  /// 创建标签
  Future<int> createTag(String name,
      {String? coverComicId, int category = 0}) async {
    final db = await _getDatabase();
    // 获取当前最大的排序值
    final result = await db
        .rawQuery('SELECT MAX($kTagSortOrder) as maxOrder FROM $kTableTags');
    final maxOrder = (result.first['maxOrder'] as int?) ?? -1;
    final now = DateTime.now().millisecondsSinceEpoch;

    return await db.insert(kTableTags, {
      kTagName: name,
      kTagCoverComicId: coverComicId,
      kTagCreatedTime: now,
      kTagSortOrder: maxOrder + 1,
      kTagUpdatedTime: now,
      kTagCategory: category,
      kTagCategorySortOrder: maxOrder + 1,
    });
  }

  /// 获取所有标签
  Future<List<Map<String, Object?>>> getAllTags() async {
    final db = await _getDatabase();
    return await db.query(
      kTableTags,
      orderBy: '$kTagSortOrder ASC, $kTagCreatedTime DESC',
    );
  }

  /// 根据ID获取标签
  Future<Map<String, Object?>?> getTagById(int tagId) async {
    final db = await _getDatabase();
    final result = await db.query(
      kTableTags,
      where: '$kTagId = ?',
      whereArgs: [tagId],
    );
    return result.isEmpty ? null : result.first;
  }

  /// 更新标签名称
  Future<void> updateTagName(int tagId, String newName) async {
    final db = await _getDatabase();
    await db.update(
      kTableTags,
      {kTagName: newName},
      where: '$kTagId = ?',
      whereArgs: [tagId],
    );
  }

  /// 更新标签封面（使用漫画ID）
  Future<void> updateTagCover(int tagId, String coverComicId) async {
    final db = await _getDatabase();
    await db.update(
      kTableTags,
      {kTagCoverComicId: coverComicId},
      where: '$kTagId = ?',
      whereArgs: [tagId],
    );
  }

  /// 删除标签
  Future<void> deleteTag(int tagId) async {
    final db = await _getDatabase();
    await db.delete(
      kTableTags,
      where: '$kTagId = ?',
      whereArgs: [tagId],
    );
  }

  /// 为漫画添加标签(自动设置封面并更新时间)
  Future<void> addTagToComic(String comicId, int tagId) async {
    final db = await _getDatabase();

    // 检查标签是否已有封面
    final tag = await getTagById(tagId);
    final hasCover = tag != null && tag[kTagCoverComicId] != null;

    // 添加标签关联
    await db.insert(
      kTableComicTags,
      {
        kComicTagsComicId: comicId,
        kComicTagsTagId: tagId,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // 更新标签的updated_time
    await db.update(
      kTableTags,
      {kTagUpdatedTime: DateTime.now().millisecondsSinceEpoch},
      where: '$kTagId = ?',
      whereArgs: [tagId],
    );

    // 如果标签没有封面,自动设置当前漫画为封面
    if (!hasCover) {
      await updateTagCover(tagId, comicId);
    }
  }

  /// 获取所有漫画的标签
  Future<Map<String, List<String>>> getAllComicTags() async {
    final db = await _getDatabase();
    final results = await db.rawQuery('''
      SELECT ct.$kComicTagsComicId, t.$kTagName
      FROM $kTableComicTags ct
      JOIN $kTableTags t ON ct.$kComicTagsTagId = t.$kTagId
    ''');

    final map = <String, List<String>>{};
    for (var row in results) {
      final comicId = row[kComicTagsComicId] as String;
      final tagName = row[kTagName] as String;
      if (!map.containsKey(comicId)) {
        map[comicId] = [];
      }
      map[comicId]!.add(tagName);
    }
    return map;
  }

  /// 从漫画移除标签
  Future<void> removeTagFromComic(String comicId, int tagId) async {
    final db = await _getDatabase();
    await db.delete(
      kTableComicTags,
      where: '$kComicTagsComicId = ? AND $kComicTagsTagId = ?',
      whereArgs: [comicId, tagId],
    );
  }

  /// 获取漫画的所有标签
  Future<List<Map<String, Object?>>> getComicTags(String comicId) async {
    final db = await _getDatabase();
    return await db.rawQuery('''
      SELECT t.* FROM $kTableTags t
      INNER JOIN $kTableComicTags ct ON t.$kTagId = ct.$kComicTagsTagId
      WHERE ct.$kComicTagsComicId = ?
      ORDER BY t.$kTagName
    ''', [comicId]);
  }

  /// 获取漫画都有的标签
  Future<List<Map<String, Object?>>> getCommonComicTags(
      List<String> comicIds) async {
    final db = await _getDatabase();
    return await db.rawQuery('''
      SELECT t.* FROM $kTableTags t
      INNER JOIN $kTableComicTags ct ON t.$kTagId = ct.$kComicTagsTagId
      WHERE ct.$kComicTagsComicId IN (${comicIds.map((e) => '?').join(',')})
      GROUP BY t.$kTagId
      HAVING COUNT(t.$kTagId) = ?
    ''', [...comicIds, comicIds.length]);
  }

  /// 获取标签下的所有漫画ID
  Future<List<String>> getComicIdsByTag(int tagId) async {
    final db = await _getDatabase();
    final result = await db.query(
      kTableComicTags,
      columns: [kComicTagsComicId],
      where: '$kComicTagsTagId = ?',
      whereArgs: [tagId],
    );
    return result.map((e) => e[kComicTagsComicId] as String).toList();
  }

  /// 获取标签下的漫画数量
  Future<int> getTagComicCount(int tagId) async {
    final db = await _getDatabase();
    final result = await db.rawQuery('''
      SELECT COUNT(*) as count FROM $kTableComicTags
      WHERE $kComicTagsTagId = ?
    ''', [tagId]);
    return result.first['count'] as int;
  }

  /// 清除漫画的所有标签
  Future<void> clearComicTags(String comicId) async {
    final db = await _getDatabase();
    await db.delete(
      kTableComicTags,
      where: '$kComicTagsComicId = ?',
      whereArgs: [comicId],
    );
  }

  /// 更新标签排序
  Future<void> updateTagSortOrder(int tagId, int sortOrder) async {
    final db = await _getDatabase();
    await db.update(
      kTableTags,
      {kTagSortOrder: sortOrder},
      where: '$kTagId = ?',
      whereArgs: [tagId],
    );
  }

  /// 批量更新标签排序
  Future<void> updateTagsSortOrder(List<int> tagIds) async {
    final db = await _getDatabase();
    for (int i = 0; i < tagIds.length; i++) {
      await db.update(
        kTableTags,
        {kTagSortOrder: i},
        where: '$kTagId = ?',
        whereArgs: [tagIds[i]],
      );
    }
  }

  /// 更新标签分类
  Future<void> updateTagCategory(int tagId, int category) async {
    final db = await _getDatabase();
    await db.update(
      kTableTags,
      {
        kTagCategory: category,
        kTagUpdatedTime: DateTime.now().millisecondsSinceEpoch,
      },
      where: '$kTagId = ?',
      whereArgs: [tagId],
    );
  }

  /// 按分类获取标签
  Future<List<Map<String, Object?>>> getTagsByCategory(int category) async {
    final db = await _getDatabase();
    return await db.query(
      kTableTags,
      where: '$kTagCategory = ?',
      whereArgs: [category],
      orderBy: '$kTagCategorySortOrder ASC, $kTagCreatedTime DESC',
    );
  }

  /// 更新标签分类排序
  Future<void> updateTagCategorySortOrder(int tagId, int sortOrder) async {
    final db = await _getDatabase();
    await db.update(
      kTableTags,
      {kTagCategorySortOrder: sortOrder},
      where: '$kTagId = ?',
      whereArgs: [tagId],
    );
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
