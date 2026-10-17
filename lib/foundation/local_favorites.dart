import 'dart:async';
import 'dart:convert';
import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/comic_source/comic_source.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/foundation/image_manager.dart';
import 'package:pica_comic/foundation/log.dart';
import 'package:pica_comic/network/eh_network/eh_models.dart';
import 'package:pica_comic/network/hitomi_network/hitomi_models.dart';
import 'package:pica_comic/network/htmanga_network/models.dart';
import 'package:pica_comic/network/jm_network/jm_image.dart';
import 'package:pica_comic/network/jm_network/jm_models.dart';
import 'package:pica_comic/network/nhentai_network/models.dart';
import 'package:pica_comic/network/picacg_network/models.dart';
import 'app_settings_repository.dart';
import 'repository_change.dart';
import 'package:pica_comic/tools/extensions.dart';
import 'package:pica_comic/tools/map_extension.dart';
import 'package:pica_comic/tools/type_util.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:synchronized/synchronized.dart';
import 'dart:io';
import '../network/base_comic.dart';
import '../network/webdav.dart';

/// 表名常量
const String kTableFolderSync = 'folder_sync';
const String kTableFolderOrder = 'folder_order';

/// folder_sync 表字段常量
const String kFolderSyncName = 'folder_name';
const String kFolderSyncTime = 'time';
const String kFolderSyncKey = 'key';
const String kFolderSyncData = 'sync_data';

/// folder_order 表字段常量
const String kFolderOrderName = 'folder_name';
const String kFolderOrderValue = 'order_value';

/// 每个漫画收藏夹表共用的字段名，持久化格式保持不变。
const String kFavoriteTarget = 'target';
const String kFavoriteName = 'name';
const String kFavoriteAuthor = 'author';
const String kFavoriteType = 'type';
const String kFavoriteTags = 'tags';
const String kFavoriteCoverPath = 'cover_path';
const String kFavoriteTime = 'time';
const String kFavoriteDisplayOrder = 'display_order';
const String kFavoriteAggregate = 'value';

/// SQLite 表结构查询使用的系统表及字段。
const String kSqliteMasterTable = 'sqlite_master';
const String kSqliteMasterName = 'name';
const String kSqliteMasterType = 'type';

/// PRAGMA 与聚合查询的字段别名。
const String kSqlitePrimaryKey = 'pk';
const String kFavoriteCount = 'c';
const String kFavoriteMaximumOrder = 'max_value';
const String kFavoriteMinimumOrder = 'min_value';

String getCurTime() {
  return DateTime.now()
      .toIso8601String()
      .replaceFirst("T", " ")
      .substring(0, 19);
}

final class FavoriteType {
  final int key;

  const FavoriteType(this.key);

  static FavoriteType get picacg => const FavoriteType(0);

  static FavoriteType get ehentai => const FavoriteType(1);

  static FavoriteType get jm => const FavoriteType(2);

  static FavoriteType get hitomi => const FavoriteType(3);

  static FavoriteType get htmanga => const FavoriteType(4);

  static FavoriteType get nhentai => const FavoriteType(6);

  ComicType get comicType {
    if (key >= 0 && key <= 6) {
      return ComicType.values[key];
    }
    return ComicType.other;
  }

  ComicSource? get comicSource {
    if (key <= 6) {
      var key = comicType.name.toLowerCase();
      return ComicSource.find(key);
    }
    return ComicSource.sources.firstWhereOrNull(
      (element) => element.intKey == key,
    );
  }

  String get name {
    if (comicType != ComicType.other) {
      return comicType.name;
    } else {
      try {
        return comicSource?.name ?? "**Unknown**";
      } catch (e) {
        return "**Unknown**";
      }
    }
  }

  @override
  bool operator ==(Object other) {
    return other is FavoriteType && other.key == key;
  }

  @override
  int get hashCode => key.hashCode;
}

/// 收藏作品的稳定身份，与标题、标签等展示字段无关。
typedef FavoriteIdentity = ({int type, String target});

/// 不可变漫画收藏记录。
class FavoriteItem {
  FavoriteIdentity get identity => (type: type.key, target: target);
  final String name;
  final String author;
  final FavoriteType type;
  final List<String> tags;
  final String target;
  final String coverPath;
  final String time;

  bool get available {
    if (type.key <= 6 && type.key >= 0) {
      return true;
    }
    return ComicSource.sources.firstWhereOrNull(
          (element) => element.intKey == type.key,
        ) !=
        null;
  }

  FavoriteItem({
    required this.target,
    required this.name,
    required this.coverPath,
    required this.author,
    required this.type,
    required List<String> tags,
    String? time,
  }) : tags = List.unmodifiable(tags),
       time = time ?? getCurTime();

  FavoriteItem.fromPicacg(ComicItemBrief comic)
    : name = comic.title,
      author = comic.author,
      type = FavoriteType.picacg,
      tags = List.unmodifiable(comic.tags),
      target = comic.id,
      coverPath = comic.path,
      time = getCurTime();

  FavoriteItem.fromEhentai(EhGalleryBrief comic)
    : name = comic.title,
      author = comic.uploader,
      type = FavoriteType.ehentai,
      tags = List.unmodifiable(comic.tags),
      target = comic.link,
      coverPath = comic.coverPath,
      time = getCurTime();

  FavoriteItem.fromJmComic(JmComicBrief comic)
    : name = comic.name,
      author = comic.author,
      type = FavoriteType.jm,
      tags = const [],
      target = comic.id,
      coverPath = getJmCoverUrl(comic.id),
      time = getCurTime();

  FavoriteItem.fromHitomi(HitomiComicBrief comic)
    : name = comic.name,
      author = comic.artist,
      type = FavoriteType.hitomi,
      tags = List.unmodifiable(
        List.generate(
          comic.tagList.length,
          (index) => comic.tagList[index].name,
        ),
      ),
      target = comic.link,
      coverPath = comic.cover,
      time = getCurTime();

  FavoriteItem.fromHtcomic(HtComicBrief comic)
    : name = comic.name,
      author = "${comic.pages}Pages",
      type = FavoriteType.htmanga,
      tags = const [],
      target = comic.id,
      coverPath = comic.image,
      time = getCurTime();

  FavoriteItem.fromNhentai(NhentaiComicBrief comic)
    : name = comic.title,
      author = "",
      type = FavoriteType.nhentai,
      tags = List.unmodifiable(comic.tags),
      target = comic.id,
      coverPath = comic.cover,
      time = getCurTime();

  FavoriteItem.custom(CustomComic comic)
    : name = comic.title,
      author = comic.subTitle,
      type = FavoriteType(comic.sourceKey.hashCode),
      tags = List.unmodifiable(comic.tags),
      target = comic.id,
      coverPath = comic.cover,
      time = getCurTime();

  /// 创建更新后的本地收藏快照。
  FavoriteItem copyWith({
    String? name,
    String? author,
    FavoriteType? type,
    List<String>? tags,
    String? target,
    String? coverPath,
    String? time,
  }) => FavoriteItem(
    name: name ?? this.name,
    author: author ?? this.author,
    type: type ?? this.type,
    tags: tags ?? this.tags,
    target: target ?? this.target,
    coverPath: coverPath ?? this.coverPath,
    time: time ?? this.time,
  );

  Map<String, dynamic> toMap() => {
    kFavoriteName: name,
    kFavoriteAuthor: author,
    kFavoriteType: type.key,
    kFavoriteTags: tags,
    kFavoriteTarget: target,
    'coverPath': coverPath,
    kFavoriteTime: time,
  };

  Map<String, dynamic> toJson() => toMap();

  Map<String, dynamic> toRow() => {
    kFavoriteName: name,
    kFavoriteAuthor: author,
    kFavoriteType: type.key,
    kFavoriteTags: tags.join(','),
    kFavoriteTarget: target,
    kFavoriteCoverPath: coverPath,
    kFavoriteTime: time,
  };

  factory FavoriteItem.fromMap(Map<String, dynamic> map) => FavoriteItem(
    name: map.optString(kFavoriteName),
    author: map.optString(kFavoriteAuthor),
    type: FavoriteType(map.optInt(kFavoriteType)),
    tags: map.optStringList(kFavoriteTags),
    target: map.optString(kFavoriteTarget),
    coverPath: map.optString('coverPath'),
    time: map.optStringOrNull(kFavoriteTime),
  );

  factory FavoriteItem.fromJson(Map<String, dynamic> json) =>
      FavoriteItem.fromMap(json);

  factory FavoriteItem.fromRow(Map row) {
    final tags = TypeUtil.parseString(
      row[kFavoriteTags],
    ).split(',').where((tag) => tag.isNotEmpty).toList();
    return FavoriteItem(
      name: TypeUtil.parseString(row[kFavoriteName]),
      author: TypeUtil.parseString(row[kFavoriteAuthor]),
      type: FavoriteType(TypeUtil.parseInt(row[kFavoriteType])),
      tags: tags,
      target: TypeUtil.parseString(row[kFavoriteTarget]),
      coverPath: TypeUtil.parseString(row[kFavoriteCoverPath]),
      time: TypeUtil.parseStringOrNull(row[kFavoriteTime]),
    );
  }

  factory FavoriteItem.fromBaseComic(BaseComic comic) {
    if (comic is ComicItemBrief) {
      return FavoriteItem.fromPicacg(comic);
    } else if (comic is EhGalleryBrief) {
      return FavoriteItem.fromEhentai(comic);
    } else if (comic is JmComicBrief) {
      return FavoriteItem.fromJmComic(comic);
    } else if (comic is HtComicBrief) {
      return FavoriteItem.fromHtcomic(comic);
    } else if (comic is NhentaiComicBrief) {
      return FavoriteItem.fromNhentai(comic);
    } else if (comic is CustomComic) {
      return FavoriteItem.custom(comic);
    }
    throw UnimplementedError();
  }

  @override
  bool operator ==(Object other) {
    return other is FavoriteItem &&
        other.target == target &&
        other.type == type;
  }

  @override
  int get hashCode => target.hashCode ^ type.hashCode;

  @override
  String toString() {
    var s = "FavoriteItem: $name $author $coverPath $hashCode $tags";
    if (s.length > 100) {
      return s.substring(0, 100);
    }
    return s;
  }
}

class FavoriteItemWithFolderInfo {
  final FavoriteItem comic;
  final String folder;

  FavoriteItemWithFolderInfo(this.comic, this.folder);

  @override
  bool operator ==(Object other) {
    return other is FavoriteItemWithFolderInfo &&
        other.comic == comic &&
        other.folder == folder;
  }

  @override
  int get hashCode => comic.hashCode ^ folder.hashCode;
}

class FolderSync {
  final String folderName;
  final String time;
  final String key;
  final String syncData; // 内容是 json, 存一下选中的文件夹 folderId

  FolderSync({
    required this.folderName,
    required this.key,
    required this.syncData,
    String? time,
  }) : time = time ?? getCurTime();

  Map<String, dynamic> get syncDataObj => TypeUtil.parseMap(syncData);

  FolderSync copyWith({
    String? folderName,
    String? time,
    String? key,
    String? syncData,
  }) => FolderSync(
    folderName: folderName ?? this.folderName,
    time: time ?? this.time,
    key: key ?? this.key,
    syncData: syncData ?? this.syncData,
  );

  factory FolderSync.fromMap(Map<String, dynamic> map) => FolderSync(
    folderName: map.optString(kFolderSyncName),
    time: map.optStringOrNull(kFolderSyncTime),
    key: map.optString(kFolderSyncKey),
    syncData: map.optString(kFolderSyncData),
  );

  Map<String, dynamic> toMap() => {
    kFolderSyncName: folderName,
    kFolderSyncTime: time,
    kFolderSyncKey: key,
    kFolderSyncData: syncData,
  };

  Map<String, dynamic> toJson() => toMap();

  factory FolderSync.fromJson(Map<String, dynamic> json) =>
      FolderSync.fromMap(json);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FolderSync &&
          folderName == other.folderName &&
          time == other.time &&
          key == other.key &&
          syncData == other.syncData;

  @override
  int get hashCode => Object.hash(folderName, time, key, syncData);

  @override
  String toString() => 'FolderSync${toMap()}';
}

extension SQL on String {
  String get toParam => replaceAll('\'', "''").replaceAll('"', "\"\"");
}

/// 批任务只合并成功写入的通知和上传，不改变逐条提交的取消语义。
class FavoriteChangeBatch {
  FavoriteChangeBatch(this._publish);
  final void Function(RepositoryChange<FavoriteIdentity>) _publish;
  final _keys = <FavoriteIdentity>{};
  final _folders = <String>{};
  bool _closed = false;

  /// 收集已成功提交的条目。
  void add(RepositoryChange<FavoriteIdentity> change) {
    if (_closed) throw StateError('批量通知已经结束');
    _keys.addAll(change.keys ?? {});
    _folders.addAll(change.folders);
  }

  /// 完成或取消后发布一次；没有写入时不发通知。
  void finish() {
    if (_closed) return;
    _closed = true;
    if (_keys.isNotEmpty)
      _publish(RepositoryChange(keys: _keys, folders: _folders));
  }
}

/// 漫画收藏数据库的兼容存储适配。
class LocalFavoritesManager {
  factory LocalFavoritesManager() =>
      cache ?? (cache = LocalFavoritesManager._create());

  LocalFavoritesManager._create()
    : _settings = AppSettingsRepository(),
      _saveCallback = null;

  /// 测试使用独立数据库与保存回调，不访问全局应用状态。
  LocalFavoritesManager.forTesting(
    Database database, {
    AppSettingsRepository? settings,
    Future<void> Function()? save,
  }) : _db = database,
       _initialized = true,
       _settings = settings ?? AppSettingsRepository(),
       _saveCallback = save;

  final AppSettingsRepository _settings;
  final Future<void> Function()? _saveCallback;
  final Lock _mutationLock = Lock();

  static LocalFavoritesManager? cache;

  Database? _db;
  bool _initialized = false;
  bool _initializing = false;
  Future<void>? _initializationFuture;
  final Completer<Database> _initCompleter = Completer<Database>();
  final Lock _lock = Lock();
  final _changeController =
      StreamController<RepositoryChange<FavoriteIdentity>>.broadcast();

  /// 收藏夹或其中漫画发生变化时触发，供功能 Provider 刷新派生状态。
  Stream<RepositoryChange<FavoriteIdentity>> get changes =>
      _changeController.stream;

  Future<void> init() {
    if (_initialized) return Future.value();
    final pending = _initializationFuture;
    if (pending != null) return pending;

    final future = _initialize();
    _initializationFuture = future;
    return future;
  }

  Future<void> _initialize() async {
    try {
      await _lock.synchronized(() async {
        if (_initialized) return;
        _initializing = true;

        try {
          final dbPath = "${App.dataPath}/local_favorite.db";
          final dir = Directory(App.dataPath);
          if (!await dir.exists()) {
            await dir.create(recursive: true);
          }

          _db = await databaseFactory.openDatabase(
            dbPath,
            options: OpenDatabaseOptions(
              version: 1,
              onCreate: _onCreate,
              onUpgrade: _onUpgrade,
            ),
          );

          await _checkAndCreate();
          await readData();
          _initialized = true;
          _initCompleter.complete(_db);
        } finally {
          _initializing = false;
        }
      });
    } catch (_) {
      _initializationFuture = null;
      rethrow;
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $kTableFolderSync (
        $kFolderSyncName TEXT PRIMARY KEY,
        $kFolderSyncTime TEXT,
        $kFolderSyncKey TEXT,
        $kFolderSyncData TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $kTableFolderOrder (
        $kFolderOrderName TEXT PRIMARY KEY,
        $kFolderOrderValue INT
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // 根据需要实现升级逻辑
  }

  /// 确保数据库已初始化并返回数据库实例
  Future<Database> _getDatabase() async {
    final db = _db;
    if (db != null) {
      return db;
    }
    // 直接访问收藏功能时也应触发懒初始化，而不是无限等待 Completer。
    await init();
    return _db!;
  }

  Future<void> _checkAndCreate() async {
    final db = await _getDatabase();
    final tables = await _getTablesWithDB(db);
    if (!tables.contains(kTableFolderSync)) {
      await db.execute('''
        CREATE TABLE $kTableFolderSync (
          $kFolderSyncName TEXT PRIMARY KEY,
          $kFolderSyncTime TEXT,
          $kFolderSyncKey TEXT,
          $kFolderSyncData TEXT
        )
      ''');
    }
    if (!tables.contains(kTableFolderOrder)) {
      await db.execute('''
        CREATE TABLE $kTableFolderOrder (
          $kFolderOrderName TEXT PRIMARY KEY,
          $kFolderOrderValue INT
        )
      ''');
    }

    // 移除系统表
    tables.remove(kTableFolderSync);
    tables.remove(kTableFolderOrder);

    if (tables.isEmpty) return;

    // 检查表结构是否需要更新
    var testTable = tables.first;
    // 获取表信息
    var columns = await db.rawQuery('PRAGMA table_info("$testTable")');
    bool shouldUpdate = false;
    for (var row in columns) {
      if (row[kFavoriteName] == kFavoriteType && row[kSqlitePrimaryKey] == 0) {
        shouldUpdate = true;
        break;
      }
    }

    if (shouldUpdate) {
      for (var table in tables) {
        var tempName = "${table}_dw5d8g2_temp";
        // 创建临时表并迁移数据
        await db.execute('''
          CREATE TABLE "$tempName" AS SELECT * FROM "$table";
          DROP TABLE "$table";
          CREATE TABLE "$table" (
            $kFavoriteTarget TEXT,
            $kFavoriteName TEXT,
            $kFavoriteAuthor TEXT,
            $kFavoriteType INT,
            $kFavoriteTags TEXT,
            $kFavoriteCoverPath TEXT,
            $kFavoriteTime TEXT,
            $kFavoriteDisplayOrder INT,
            PRIMARY KEY ($kFavoriteTarget, $kFavoriteType)
          );
          INSERT INTO "$table" SELECT * FROM "$tempName";
          DROP TABLE "$tempName";
        ''');
      }
    }
  }

  /// 存储提交后通知订阅者，存储层不持有页面或控制器。
  void notifyChanged([RepositoryChange<FavoriteIdentity>? change]) {
    _changeController.add(change ?? RepositoryChange(foldersChanged: true));
  }

  /// 在事务内完成一次写入，成功后合并通知和远端上传。
  Future<T> _commit<T>(
    Future<T> Function(Transaction txn) action,
    RepositoryChange<FavoriteIdentity> change, {
    FavoriteChangeBatch? batch,
  }) async {
    final db = await _getDatabase();
    return _mutationLock.synchronized(() async {
      final result = await db.transaction(action);
      if (batch == null) {
        _publish(change);
      } else {
        batch.add(change);
      }
      return result;
    });
  }

  /// 成功提交后统一发布并请求一次上传。
  void _publish(RepositoryChange<FavoriteIdentity> change) {
    notifyChanged(change);
    unawaited(saveData());
  }

  /// 为逐条更新任务创建独立的变更收集器。
  FavoriteChangeBatch beginChangeBatch() => FavoriteChangeBatch(_publish);

  /// 对 SQL 标识符进行转义，保持旧收藏夹名称可用。
  String _table(String name) => '"${name.replaceAll('"', '""')}"';

  /// 创建与旧数据库格式一致的收藏夹表。
  Future<void> _createTable(DatabaseExecutor db, String name) => db.execute(
    'CREATE TABLE ${_table(name)} ($kFavoriteTarget TEXT, $kFavoriteName TEXT, $kFavoriteAuthor TEXT, $kFavoriteType INT, '
    '$kFavoriteTags TEXT, $kFavoriteCoverPath TEXT, $kFavoriteTime TEXT, $kFavoriteDisplayOrder INT, PRIMARY KEY ($kFavoriteTarget, $kFavoriteType))',
  );

  Future<List<String>> find(String target, FavoriteType type) async {
    final db = await _getDatabase();
    var res = <String>[];
    final folderNames = await this.folderNames;
    for (var folder in folderNames) {
      var rows = await db.query(
        folder,
        where: '$kFavoriteTarget = ? AND $kFavoriteType = ?',
        whereArgs: [target, type.key],
      );
      if (rows.isNotEmpty) {
        res.add(folder);
      }
    }
    return res;
  }

  Future<List<String>> findWithModel(FavoriteItem item) async {
    final db = await _getDatabase();
    var res = <String>[];
    final folderNames = await this.folderNames;
    for (var folder in folderNames) {
      var rows = await db.query(
        folder,
        where: '$kFavoriteTarget = ? AND $kFavoriteType = ?',
        whereArgs: [item.target, item.type.key],
      );
      if (rows.isNotEmpty) {
        res.add(folder);
      }
    }
    return res;
  }

  Future<void> saveData() async {
    try {
      if (_saveCallback != null) {
        await _saveCallback();
      } else {
        await Webdav.uploadData();
      }
    } catch (error, stack) {
      Log.e('收藏远端同步失败', error: error, stackTrace: stack);
    }
  }

  /// 完整读取旧 JSON 或临时数据库，在单个事务内导入。
  /// 导入失败保留输入文件，避免重试前丢失备份。
  Future<void> readData({String? legacyPath, String? temporaryPath}) async {
    final legacy = File(legacyPath ?? '${App.dataPath}/localFavorite');
    final temporary = File(
      temporaryPath ?? '${App.dataPath}/local_favorite_temp.db',
    );
    final replacing = await legacy.exists();
    if (!replacing && !await temporary.exists()) return;
    final incoming = <String, List<FavoriteItem>>{};
    final folderOrder = <String, int>{};
    final syncs = <FolderSync>[];
    if (replacing) {
      final data =
          jsonDecode(await legacy.readAsString()) as Map<String, dynamic>;
      for (final entry in data.entries) {
        incoming[entry.key] = (entry.value as List)
            .map(
              (value) => FavoriteItem.fromJson(
                Map<String, dynamic>.from(value as Map),
              ),
            )
            .toList();
      }
    } else {
      final source = await databaseFactoryFfi.openDatabase(temporary.path);
      try {
        final tables = await _getTablesWithDB(source);
        for (final table in tables) {
          if (table == kTableFolderOrder) {
            for (final row in await source.query(table)) {
              folderOrder[row[kFolderOrderName] as String] =
                  row[kFolderOrderValue] as int;
            }
          } else if (table == kTableFolderSync) {
            syncs.addAll((await source.query(table)).map(FolderSync.fromMap));
          } else {
            incoming[table] = (await source.query(
              table,
              orderBy: kFavoriteDisplayOrder,
            )).map(FavoriteItem.fromRow).toList();
          }
        }
      } finally {
        await source.close();
      }
    }
    for (final name in incoming.keys) {
      if (name.isEmpty ||
          name == kTableFolderOrder ||
          name == kTableFolderSync ||
          name.startsWith('sqlite_')) {
        throw ArgumentError('备份中包含无效收藏夹名称');
      }
    }
    await _commit((txn) async {
      final tables = (await _getTablesWithDB(txn)).toSet();
      final existing = tables.difference({kTableFolderOrder, kTableFolderSync});
      if (replacing) {
        for (final folder in existing) {
          await txn.execute('DROP TABLE ${_table(folder)}');
        }
        await txn.delete(kTableFolderOrder);
        await txn.delete(kTableFolderSync);
        existing.clear();
      }
      for (final entry in incoming.entries) {
        final folder = entry.key;
        final isNew = existing.add(folder);
        if (isNew) await _createTable(txn, folder);
        final old = await txn.query(
          folder,
          columns: [kFavoriteTarget, kFavoriteType, kFavoriteDisplayOrder],
        );
        final identities = old
            .map(
              (row) => (
                type: row[kFavoriteType] as int,
                target: row[kFavoriteTarget] as String,
              ),
            )
            .toSet();
        var order = old.fold<int>(0, (value, row) {
          final position = row[kFavoriteDisplayOrder] as int? ?? 0;
          return value > position ? value : position;
        });
        for (final item in entry.value) {
          if (!identities.add(item.identity)) continue;
          await txn.insert(folder, {
            ...item.toRow(),
            kFavoriteDisplayOrder: ++order,
          });
        }
        if (isNew && folderOrder.containsKey(folder)) {
          await txn.insert(kTableFolderOrder, {
            kFolderOrderName: folder,
            kFolderOrderValue: folderOrder[folder],
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        }
      }
      for (final sync in syncs) {
        if (!existing.contains(sync.folderName)) continue;
        await txn.insert(
          kTableFolderSync,
          sync.toMap(),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    }, RepositoryChange(foldersChanged: true));
    await (replacing ? legacy : temporary).delete();
  }

  Future<List<String>> _getTablesWithDB(DatabaseExecutor db) async {
    final tablesResult = await db.rawQuery(
      "SELECT $kSqliteMasterName FROM $kSqliteMasterTable WHERE $kSqliteMasterType='table' AND $kSqliteMasterName NOT LIKE 'sqlite_%';",
    );
    final tables = tablesResult
        .map((element) => element[kFavoriteName] as String)
        .toList();
    return tables;
  }

  Future<List<String>> _getFolderNamesWithDB() async {
    final db = await _getDatabase();
    final folders = await _getTablesWithDB(db);
    folders.remove(kTableFolderSync);
    folders.remove(kTableFolderOrder);
    var folderToOrder = <String, int>{};
    for (var folder in folders) {
      var res = await db.query(
        kTableFolderOrder,
        where: '$kFolderOrderName = ?',
        whereArgs: [folder],
      );
      if (res.isNotEmpty) {
        folderToOrder[folder] = res.first[kFolderOrderValue] as int;
      } else {
        folderToOrder[folder] = 0;
      }
    }
    folders.sort((a, b) {
      return folderToOrder[a]! - folderToOrder[b]!;
    });
    return folders;
  }

  /// 原子保存收藏夹顺序。
  Future<void> updateOrder(Map<String, int> order) => _commit((txn) async {
    for (final entry in order.entries) {
      await txn.insert(kTableFolderOrder, {
        kFolderOrderName: entry.key,
        kFolderOrderValue: entry.value,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }, RepositoryChange(foldersChanged: true));

  Future<List<FolderSync>> _getFolderSyncWithDB() async {
    final db = await _getDatabase();
    final result = await db.query(kTableFolderSync);
    return result.map((element) => FolderSync.fromMap(element)).toList();
  }

  /// 修改同步时间。
  Future<void> updateFolderSyncTime(FolderSync sync) => _commit((txn) async {
    await txn.update(
      kTableFolderSync,
      {kFolderSyncTime: sync.time},
      where: '$kFolderSyncName = ?',
      whereArgs: [sync.folderName],
    );
  }, RepositoryChange(keys: {}, folders: {sync.folderName}));

  /// 保存收藏夹同步配置。
  Future<void> insertFolderSync(FolderSync sync) => _commit((txn) async {
    await txn.insert(
      kTableFolderSync,
      sync.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }, RepositoryChange(keys: {}, folders: {sync.folderName}));

  Future<int> count(String folderName) async {
    await init();
    final db = await _getDatabase();
    final result = await db.rawQuery(
      'SELECT COUNT(*) as $kFavoriteCount FROM "$folderName"',
    );
    return result.first[kFavoriteCount] as int;
  }

  Future<List<String>> get folderNames async {
    if (!_initialized && !_initializing) {
      await init();
    }
    return _getFolderNamesWithDB();
  }

  Future<List<FolderSync>> get folderSync async => await _getFolderSyncWithDB();

  Future<int> maxValue(String folder) async {
    final db = await _getDatabase();
    final result = await db.rawQuery(
      'SELECT MAX($kFavoriteDisplayOrder) AS $kFavoriteMaximumOrder FROM "$folder"',
    );
    return result.firstOrNull?[kFavoriteMaximumOrder] as int? ?? 0;
  }

  Future<int> minValue(String folder) async {
    final db = await _getDatabase();
    final result = await db.rawQuery(
      'SELECT MIN($kFavoriteDisplayOrder) AS $kFavoriteMinimumOrder FROM "$folder"',
    );
    return result.firstOrNull?[kFavoriteMinimumOrder] as int? ?? 0;
  }

  Future<List<FavoriteItem>> getAllComics(String folder) async {
    await init();
    final db = await _getDatabase();
    var rows = await db.query(folder, orderBy: kFavoriteDisplayOrder);
    return List.unmodifiable(rows.map(FavoriteItem.fromRow));
  }

  /// 为指定作品添加标签，身份同时包含漫画源。
  Future<void> addTagTo(
    String folder,
    String target,
    String tag,
    FavoriteType type, {
    FavoriteChangeBatch? batch,
  }) async {
    final comic = await getComic(folder, target, type);
    if (!comic.tags.contains(tag))
      await editTags(target, folder, [tag, ...comic.tags], type, batch: batch);
  }

  Future<List<FavoriteItemWithFolderInfo>> allComics() async {
    final db = await _getDatabase();
    var res = <FavoriteItemWithFolderInfo>[];
    for (final folder in await folderNames) {
      var comics = await db.query(folder);
      res.addAll(
        comics.map(
          (element) =>
              FavoriteItemWithFolderInfo(FavoriteItem.fromRow(element), folder),
        ),
      );
    }
    return res;
  }

  /// create a folder
  /// 创建收藏夹；导入时允许为冲突名称添加后缀。
  Future<String> createFolder(
    String name, [
    bool renameWhenInvalidName = false,
  ]) async {
    if (name.isEmpty && !renameWhenInvalidName)
      throw ArgumentError('收藏夹名称不能为空');
    if (name == kTableFolderSync ||
        name == kTableFolderOrder ||
        name.startsWith('sqlite_')) {
      throw ArgumentError('收藏夹名称不可用');
    }
    return _commit((txn) async {
      var actual = name.isEmpty ? '0' : name;
      var suffix = 0;
      while ((await txn.query(
        kSqliteMasterTable,
        columns: [kFavoriteName],
        where: '$kFavoriteName = ?',
        whereArgs: [actual],
      )).isNotEmpty) {
        if (!renameWhenInvalidName) throw StateError('收藏夹已存在');
        actual = '$name${suffix++}';
      }
      await _createTable(txn, actual);
      return actual;
    }, RepositoryChange(foldersChanged: true));
  }

  Future<bool> comicExists(String folder, String target, int type) async {
    final db = await _getDatabase();
    var res = await db.query(
      folder,
      where: '$kFavoriteTarget = ? AND $kFavoriteType = ?',
      whereArgs: [target, type],
    );
    return res.isNotEmpty;
  }

  Future<FavoriteItem> getComic(
    String folder,
    String target,
    FavoriteType type,
  ) async {
    final db = await _getDatabase();
    var res = await db.query(
      folder,
      where: '$kFavoriteTarget = ? AND $kFavoriteType = ?',
      whereArgs: [target, type.key],
    );
    if (res.isEmpty) {
      throw Exception("Comic not found");
    }
    return FavoriteItem.fromRow(res.first);
  }

  /// add comic to a folder
  ///
  /// This method will download cover to local, to avoid problems like changing url
  /// 添加作品，保存成功后才更新订阅者。
  Future<void> addComic(
    String folder,
    FavoriteItem comic, [
    int? order,
    DownloadManager? manager,
  ]) async {
    await _commit((txn) async {
      final atEnd =
          _settings.snapshot().value(
            AppSettingKeys.localFavoriteInsertPosition,
          ) ==
          '0';
      final aggregate = atEnd ? 'MAX' : 'MIN';
      final rows = await txn.rawQuery(
        'SELECT $aggregate($kFavoriteDisplayOrder) AS $kFavoriteAggregate FROM ${_table(folder)}',
      );
      final edge = rows.first[kFavoriteAggregate] as int? ?? 0;
      await txn.insert(folder, {
        ...comic.toRow(),
        kFavoriteDisplayOrder: order ?? edge + (atEnd ? 1 : -1),
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }, RepositoryChange(keys: {comic.identity}, folders: {folder}));
    if (manager != null) {
      unawaited(
        getCover(
          comic,
          manager: manager,
          loadDownloadedCover: manager.getCover,
        ).then<void>(
          (_) {},
          onError: (Object error, StackTrace stack) {
            Log.w('收藏封面准备失败', error: error, stackTrace: stack);
          },
        ),
      );
    }
  }

  /// get comic cover
  Future<File> getCover(
    FavoriteItem item, {
    required DownloadManager manager,
    required Future<File> Function(String id) loadDownloadedCover,
    String ehCookie = '',
  }) async {
    var path = "${App.dataPath}/favoritesCover";
    var hash = md5
        .convert(const Utf8Encoder().convert(item.coverPath))
        .toString();
    var file = File("$path/$hash.jpg");
    if (file.existsSync()) {
      return file;
    }
    if (item.coverPath.startsWith("file://")) {
      var data = await loadDownloadedCover(
        item.coverPath.replaceFirst("file://", ""),
      );
      file.createSync(recursive: true);
      file.writeAsBytesSync(data.readAsBytesSync());
      return file;
    }
    try {
      var res = await (ImageManager(manager).getImage(item.coverPath, {
        if (item.type == FavoriteType.ehentai) "cookie": ehCookie,
        if (item.type == FavoriteType.hitomi) "Referer": "https://hitomi.la/",
      }).last);
      file.createSync(recursive: true);
      file.writeAsBytesSync(res.getFile().readAsBytesSync());
      return file;
    } catch (e) {
      await Future.delayed(const Duration(seconds: 5));
      rethrow;
    }
  }

  /// delete a folder
  /// 删除收藏夹及其排序、同步元数据。
  Future<void> deleteFolder(String name) => _commit(
    (txn) async {
      await txn.delete(
        kTableFolderSync,
        where: '$kFolderSyncName = ?',
        whereArgs: [name],
      );
      await txn.delete(
        kTableFolderOrder,
        where: '$kFolderOrderName = ?',
        whereArgs: [name],
      );
      await txn.execute('DROP TABLE ${_table(name)}');
    },
    RepositoryChange(folders: {name}, foldersChanged: true, previousName: name),
  );

  /// 在没有引用后清理作品封面。
  Future<void> checkAndDeleteCover(FavoriteItem item) async {
    if ((await find(item.target, item.type)).isNotEmpty) return;
    final hash = md5.convert(utf8.encode(item.coverPath)).toString();
    final file = File('${App.dataPath}/favoritesCover/$hash.jpg');
    if (await file.exists()) await file.delete();
  }

  /// 删除单个收藏，封面清理失败不撤销已提交的删除。
  Future<void> deleteComic(String folder, FavoriteItem comic) async {
    await deleteComicWithTarget(folder, comic.target, comic.type);
    try {
      await checkAndDeleteCover(comic);
    } catch (error, stack) {
      Log.w('收藏封面清理失败', error: error, stackTrace: stack);
    }
  }

  /// 按作品身份删除收藏。
  Future<void> deleteComicWithTarget(
    String folder,
    String target,
    FavoriteType type,
  ) => _commit(
    (txn) async {
      await txn.delete(
        folder,
        where: '$kFavoriteTarget = ? AND $kFavoriteType = ?',
        whereArgs: [target, type.key],
      );
    },
    RepositoryChange(
      keys: {(type: type.key, target: target)},
      folders: {folder},
      removed: true,
    ),
  );

  /// 原子批量删除选中的收藏。
  Future<void> deleteComics(String folder, List<FavoriteItem> comics) =>
      _commit(
        (txn) async {
          for (final comic in comics) {
            await txn.delete(
              folder,
              where: '$kFavoriteTarget = ? AND $kFavoriteType = ?',
              whereArgs: [comic.target, comic.type.key],
            );
          }
        },
        RepositoryChange(
          keys: comics.map((e) => e.identity).toSet(),
          folders: {folder},
          removed: true,
        ),
      );

  /// 清空收藏及元数据，保留数据库结构版本。
  Future<void> clearAll() async {
    await _commit((txn) async {
      final tables = await _getTablesWithDB(txn);
      for (final table in tables) {
        if (table != kTableFolderSync && table != kTableFolderOrder) {
          await txn.execute('DROP TABLE IF EXISTS ${_table(table)}');
        }
      }
      await txn.delete(kTableFolderSync);
      await txn.delete(kTableFolderOrder);
    }, RepositoryChange(foldersChanged: true));
  }

  /// 在现有表内调整排序，保留同步配置与并发新增的作品。
  Future<void> reorder(List<FavoriteItem> requested, String folder) =>
      _commit((txn) async {
        final rows = await txn.query(folder, orderBy: kFavoriteDisplayOrder);
        final current = rows.map(FavoriteItem.fromRow).toList();
        final existing = current.map((e) => e.identity).toSet();
        final seen = <FavoriteIdentity>{};
        final merged = [
          ...requested,
          ...current,
        ].where((e) => existing.contains(e.identity) && seen.add(e.identity));
        var order = 0;
        for (final item in merged) {
          await txn.update(
            folder,
            {kFavoriteDisplayOrder: order++},
            where: '$kFavoriteTarget = ? AND $kFavoriteType = ?',
            whereArgs: [item.target, item.type.key],
          );
        }
      }, RepositoryChange(keys: {}, folders: {folder}));

  /// 重命名收藏夹，并同时迁移排序和同步元数据。
  Future<void> rename(String before, String after) async {
    if (after.isEmpty ||
        after == kTableFolderSync ||
        after == kTableFolderOrder ||
        after.startsWith('sqlite_')) {
      throw ArgumentError('收藏夹名称不可用');
    }
    await _commit(
      (txn) async {
        await txn.execute(
          'ALTER TABLE ${_table(before)} RENAME TO ${_table(after)}',
        );
        await txn.update(
          kTableFolderSync,
          {kFolderSyncName: after},
          where: '$kFolderSyncName = ?',
          whereArgs: [before],
        );
        await txn.update(
          kTableFolderOrder,
          {kFolderOrderName: after},
          where: '$kFolderOrderName = ?',
          whereArgs: [before],
        );
      },
      RepositoryChange(
        folders: {before, after},
        foldersChanged: true,
        previousName: before,
        currentName: after,
      ),
    );
  }

  /// 阅读结束时更新时间和用户配置的排序位置。
  Future<void> onReadEnd(String target, FavoriteType type) async {
    final folders = await find(target, type);
    if (folders.isEmpty) return;
    final behavior = _settings.snapshot().value(
      AppSettingKeys.localFavoriteMoveAfterReading,
    );
    await _commit(
      (txn) async {
        for (final folder in folders) {
          final updates = <String, Object?>{kFavoriteTime: getCurTime()};
          if (behavior == '1' || behavior == '2') {
            final aggregate = behavior == '1' ? 'MAX' : 'MIN';
            final rows = await txn.rawQuery(
              'SELECT $aggregate($kFavoriteDisplayOrder) AS $kFavoriteAggregate FROM ${_table(folder)}',
            );
            updates[kFavoriteDisplayOrder] =
                (rows.first[kFavoriteAggregate] as int? ?? 0) +
                (behavior == '1' ? 1 : -1);
          }
          await txn.update(
            folder,
            updates,
            where: '$kFavoriteTarget = ? AND $kFavoriteType = ?',
            whereArgs: [target, type.key],
          );
        }
      },
      RepositoryChange(
        keys: {(type: type.key, target: target)},
        folders: folders.toSet(),
      ),
    );
  }

  /// 完整抓取成功后一次性提交导入或同步，不产生部分写入。
  Future<(String, int)> importFavorites(
    String folder,
    List<FavoriteItem> comics, {
    bool create = false,
    FolderSync? sync,
  }) async {
    var actual = folder;
    final result = await _commit(
      (txn) async {
        if (create) {
          if (actual.isEmpty) actual = '收藏';
          if (actual == kTableFolderSync ||
              actual == kTableFolderOrder ||
              actual.startsWith('sqlite_')) {
            throw ArgumentError('收藏夹名称不可用');
          }
          var suffix = 0;
          while ((await txn.query(
            kSqliteMasterTable,
            columns: [kFavoriteName],
            where: '$kFavoriteName = ?',
            whereArgs: [actual],
          )).isNotEmpty) {
            actual = '$folder${suffix++}';
          }
          await _createTable(txn, actual);
        }
        final old = await txn.query(
          actual,
          columns: [kFavoriteTarget, kFavoriteType, kFavoriteDisplayOrder],
        );
        final identities = old
            .map(
              (e) => (
                type: e[kFavoriteType] as int,
                target: e[kFavoriteTarget] as String,
              ),
            )
            .toSet();
        final additions = comics
            .where((e) => identities.add(e.identity))
            .toList();
        var minOrder = 0;
        for (final row in old) {
          final order = row[kFavoriteDisplayOrder] as int? ?? 0;
          if (order < minOrder) minOrder = order;
        }
        var order = create ? 0 : minOrder - additions.length;
        for (final item in additions) {
          await txn.insert(actual, {
            ...item.toRow(),
            kFavoriteDisplayOrder: order++,
          });
        }
        if (sync != null) {
          await txn.insert(
            kTableFolderSync,
            sync.copyWith(folderName: actual, time: getCurTime()).toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        return (actual, additions.length);
      },
      RepositoryChange(foldersChanged: create, folders: create ? {} : {folder}),
    );
    return result;
  }

  /// 添加或取消同一作品的多个收藏夹归属，失败整体回滚。
  Future<void> setMembership(
    List<String> folders,
    FavoriteItem item, {
    required bool adding,
  }) => _commit(
    (txn) async {
      final atEnd =
          _settings.snapshot().value(
            AppSettingKeys.localFavoriteInsertPosition,
          ) ==
          '0';
      for (final folder in folders.toSet()) {
        if (!adding) {
          await txn.delete(
            folder,
            where: '$kFavoriteTarget = ? AND $kFavoriteType = ?',
            whereArgs: [item.target, item.type.key],
          );
        } else {
          final aggregate = atEnd ? 'MAX' : 'MIN';
          final rows = await txn.rawQuery(
            'SELECT $aggregate($kFavoriteDisplayOrder) AS $kFavoriteAggregate FROM ${_table(folder)}',
          );
          final order =
              (rows.first[kFavoriteAggregate] as int? ?? 0) + (atEnd ? 1 : -1);
          await txn.insert(folder, {
            ...item.toRow(),
            kFavoriteDisplayOrder: order,
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        }
      }
    },
    RepositoryChange(
      keys: {item.identity},
      folders: folders.toSet(),
      removed: !adding,
    ),
  );

  /// 将作品按当前插入设置复制到目标收藏夹。
  Future<void> copyComics(String folder, List<FavoriteItem> comics) => _commit(
    (txn) async {
      final atEnd =
          _settings.snapshot().value(
            AppSettingKeys.localFavoriteInsertPosition,
          ) ==
          '0';
      final aggregate = atEnd ? 'MAX' : 'MIN';
      final rows = await txn.rawQuery(
        'SELECT $aggregate($kFavoriteDisplayOrder) AS $kFavoriteAggregate FROM ${_table(folder)}',
      );
      var order = rows.first[kFavoriteAggregate] as int? ?? 0;
      for (final item in comics) {
        order += atEnd ? 1 : -1;
        await txn.insert(folder, {
          ...item.toRow(),
          kFavoriteDisplayOrder: order,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    },
    RepositoryChange(
      keys: comics.map((e) => e.identity).toSet(),
      folders: {folder},
    ),
  );

  Future<String> folderToJsonString(String folderName) async {
    final db = await _getDatabase();
    var data = <String, dynamic>{};
    data["info"] = "Generated by PicaComic.";
    data["website"] = "https://github.com/Pacalini/PicaComic";
    data[kFavoriteName] = folderName;
    var comics = await db.query(folderName);
    data["comics"] = comics
        .map((e) => FavoriteItem.fromRow(e).toJson())
        .toList();
    return const JsonEncoder().convert(data);
  }

  /// 导入收藏夹 JSON，验证完整数据后才提交。
  Future<(bool, String)> loadFolderData(String dataString) async {
    try {
      final data = jsonDecode(dataString) as Map<String, dynamic>;
      final comics = (data['comics'] as List)
          .map(
            (e) => FavoriteItem.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList();
      await importFavorites(
        data[kFavoriteName] as String,
        comics,
        create: true,
      );
      return (false, '');
    } catch (error, stack) {
      Log.e('导入收藏夹失败', error: error, stackTrace: stack);
      return (true, error.toString());
    }
  }

  Future<List<FavoriteItemWithFolderInfo>> search(String keyword) async {
    final db = await _getDatabase();
    var keywordList = keyword.split(" ");
    keyword = keywordList.first;
    var comics = <FavoriteItemWithFolderInfo>[];
    for (var table in await folderNames) {
      var searchTerm = '%$keyword%';
      var res = await db.query(
        table,
        where:
            '$kFavoriteName LIKE ? OR $kFavoriteAuthor LIKE ? OR $kFavoriteTags LIKE ?',
        whereArgs: [searchTerm, searchTerm, searchTerm],
      );
      for (var comic in res) {
        comics.add(
          FavoriteItemWithFolderInfo(FavoriteItem.fromRow(comic), table),
        );
      }
      if (comics.length > 200) {
        break;
      }
    }

    bool test(FavoriteItemWithFolderInfo comic, String keyword) {
      if (comic.comic.name.contains(keyword)) {
        return true;
      } else if (comic.comic.author.contains(keyword)) {
        return true;
      } else if (comic.comic.tags.any((element) => element.contains(keyword))) {
        return true;
      }
      return false;
    }

    for (var i = 1; i < keywordList.length; i++) {
      comics = comics
          .where((element) => test(element, keywordList[i]))
          .toList();
    }

    return comics;
  }

  /// 更新作品标签，完成后刷新所有相关视图。
  Future<void> editTags(
    String target,
    String folder,
    List<String> tags,
    FavoriteType type, {
    FavoriteChangeBatch? batch,
  }) => _commit(
    (txn) async {
      await txn.update(
        folder,
        {kFavoriteTags: tags.join(',')},
        where: '$kFavoriteTarget = ? AND $kFavoriteType = ?',
        whereArgs: [target, type.key],
      );
    },
    RepositoryChange(
      keys: {(type: type.key, target: target)},
      folders: {folder},
    ),
    batch: batch,
  );

  /// 仅加载收藏身份，用于卡片徽标，不读取所有展示字段。
  Future<Set<FavoriteIdentity>> identities() async {
    await init();
    final db = await _getDatabase();
    final result = <FavoriteIdentity>{};
    for (final folder in await folderNames) {
      final rows = await db.query(
        folder,
        columns: [kFavoriteTarget, kFavoriteType],
      );
      result.addAll(
        rows.map(
          (e) => (
            type: e[kFavoriteType] as int,
            target: e[kFavoriteTarget] as String,
          ),
        ),
      );
    }
    return Set.unmodifiable(result);
  }

  /// 保存作品的最新元数据。
  Future<void> updateInfo(
    String folder,
    FavoriteItem comic, {
    FavoriteChangeBatch? batch,
  }) => _commit(
    (txn) async {
      await txn.update(
        folder,
        {
          kFavoriteName: comic.name,
          kFavoriteAuthor: comic.author,
          kFavoriteCoverPath: comic.coverPath,
          kFavoriteTags: comic.tags.join(','),
        },
        where: '$kFavoriteTarget = ? AND $kFavoriteType = ?',
        whereArgs: [comic.target, comic.type.key],
      );
    },
    RepositoryChange(keys: {comic.identity}, folders: {folder}),
    batch: batch,
  );
}
