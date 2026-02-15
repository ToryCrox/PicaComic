import 'dart:async';
import 'dart:convert';
import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/comic_source/comic_source.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/foundation/image_manager.dart';
import 'package:pica_comic/foundation/log.dart';
import 'package:pica_comic/network/eh_network/eh_main_network.dart';
import 'package:pica_comic/network/eh_network/eh_models.dart';
import 'package:pica_comic/network/eh_network/get_gallery_id.dart';
import 'package:pica_comic/network/hitomi_network/hitomi_models.dart';
import 'package:pica_comic/network/htmanga_network/models.dart';
import 'package:pica_comic/network/jm_network/jm_image.dart';
import 'package:pica_comic/network/jm_network/jm_models.dart';
import 'package:pica_comic/network/nhentai_network/models.dart';
import 'package:pica_comic/network/picacg_network/models.dart';
import 'package:pica_comic/pages/favorites/main_favorites_page.dart';
import 'package:pica_comic/tools/extensions.dart';
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
    return ComicSource.sources
        .firstWhereOrNull((element) => element.intKey == key);
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

class FavoriteItem {
  String name;
  String author;
  FavoriteType type;
  List<String> tags;
  String target;
  String coverPath;
  String time = getCurTime();

  bool get available {
    if (type.key <= 6 && type.key >= 0) {
      return true;
    }
    return ComicSource.sources
            .firstWhereOrNull((element) => element.intKey == type.key) !=
        null;
  }

  String toDownloadId() {
    try {
      return switch (type.comicType) {
        ComicType.picacg => target,
        ComicType.ehentai => getGalleryId(target),
        ComicType.jm => "jm$target",
        ComicType.hitomi => RegExp(r"\d+(?=\.html)").hasMatch(target)
            ? "hitomi${RegExp(r"\d+(?=\.html)").firstMatch(target)?[0]}"
            : target,
        ComicType.htmanga => "ht$target",
        ComicType.nhentai => "nhentai$target",
        _ => type.comicSource == null ? target : downloadManager.generateId(type.comicSource!.key.name, target)
      };
    } catch (e) {
      return "**Invalid ID**";
    }
  }

  FavoriteItem({
    required this.target,
    required this.name,
    required this.coverPath,
    required this.author,
    required this.type,
    required this.tags,
  });

  FavoriteItem.fromPicacg(ComicItemBrief comic)
      : name = comic.title,
        author = comic.author,
        type = FavoriteType.picacg,
        tags = comic.tags,
        target = comic.id,
        coverPath = comic.path;

  FavoriteItem.fromEhentai(EhGalleryBrief comic)
      : name = comic.title,
        author = comic.uploader,
        type = FavoriteType.ehentai,
        tags = comic.tags,
        target = comic.link,
        coverPath = comic.coverPath;

  FavoriteItem.fromJmComic(JmComicBrief comic)
      : name = comic.name,
        author = comic.author,
        type = FavoriteType.jm,
        tags = [],
        target = comic.id,
        coverPath = getJmCoverUrl(comic.id);

  FavoriteItem.fromHitomi(HitomiComicBrief comic)
      : name = comic.name,
        author = comic.artist,
        type = FavoriteType.hitomi,
        tags = List.generate(
            comic.tagList.length, (index) => comic.tagList[index].name),
        target = comic.link,
        coverPath = comic.cover;

  FavoriteItem.fromHtcomic(HtComicBrief comic)
      : name = comic.name,
        author = "${comic.pages}Pages",
        type = FavoriteType.htmanga,
        tags = [],
        target = comic.id,
        coverPath = comic.image;

  FavoriteItem.fromNhentai(NhentaiComicBrief comic)
      : name = comic.title,
        author = "",
        type = FavoriteType.nhentai,
        tags = comic.tags,
        target = comic.id,
        coverPath = comic.cover;

  FavoriteItem.custom(CustomComic comic)
      : name = comic.title,
        author = comic.subTitle,
        type = FavoriteType(comic.sourceKey.hashCode),
        tags = comic.tags,
        target = comic.id,
        coverPath = comic.cover;

  Map<String, dynamic> toJson() => {
        "name": name,
        "author": author,
        "type": type.key,
        "tags": tags,
        "target": target,
        "coverPath": coverPath,
        "time": time
      };

  FavoriteItem.fromJson(Map<String, dynamic> json)
      : name = json["name"],
        author = json["author"],
        type = FavoriteType(json["type"]),
        tags = List<String>.from(json["tags"]),
        target = json["target"],
        coverPath = json["coverPath"],
        time = json["time"];

  FavoriteItem.fromRow(Map row)
      : name = row["name"],
        author = row["author"],
        type = FavoriteType(row["type"]),
        tags = (row["tags"] as String).split(","),
        target = row["target"],
        coverPath = row["cover_path"],
        time = row["time"] {
    tags.remove("");
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
    return other is FavoriteItem && other.target == target && other.type == type;
  }

  @override
  int get hashCode => target.hashCode ^ type.hashCode;

  @override
  String toString() {
    var s = "FavoriteItem: $name $author $coverPath $hashCode $tags";
    if(s.length > 100) {
      return s.substring(0, 100);
    }
    return s;
  }
}

class FavoriteItemWithFolderInfo {
  FavoriteItem comic;
  String folder;

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
  String folderName;
  String time = getCurTime();
  String key;
  String syncData; // 内容是 json, 存一下选中的文件夹 folderId
  FolderSync(this.folderName, this.key, this.syncData);

  Map<String, dynamic> get syncDataObj => jsonDecode(syncData);

  factory FolderSync.fromMap(Map<String, dynamic> map) {
    return FolderSync(
      map[kFolderSyncName],
      map[kFolderSyncKey],
      map[kFolderSyncData],
    );
  }
}

extension SQL on String {
  String get toParam => replaceAll('\'', "''").replaceAll('"', "\"\"");
}

class LocalFavoritesManager {
  factory LocalFavoritesManager() =>
      cache ?? (cache = LocalFavoritesManager._create());

  LocalFavoritesManager._create();

  static LocalFavoritesManager? cache;

  Database? _db;
  bool _initialized = false;
  final Completer<Database> _initCompleter = Completer<Database>();
  final Lock _lock = Lock();

  Future<void> init() async {
    if (_initialized) return;
    await _lock.synchronized(() async {
      if (_initialized) return;
      
      final dbPath = "${App.dataPath}/local_favorite.db";
      final dir = Directory(App.dataPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      _db = await databaseFactory.openDatabase(dbPath,
          options: OpenDatabaseOptions(
            version: 1,
            onCreate: _onCreate,
            onUpgrade: _onUpgrade,
          ));

      _checkAndCreate();
      await readData();
      _initialized = true;
      _initCompleter.complete(_db);
    });
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
  Future<Database> _getDatabase() {
    final db = _db;
    if (db != null) {
      return SynchronousFuture(db);
    }
    return _initCompleter.future;
  }

  void _checkAndCreate() async {
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
    
    if(tables.isEmpty) return;
    
    // 检查表结构是否需要更新
    var testTable = tables.first;
    // 获取表信息
    var columns = await db.rawQuery('PRAGMA table_info("$testTable")');
    bool shouldUpdate = false;
    for (var row in columns) {
      if (row["name"] == "type" && row["pk"] == 0) {
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
            target TEXT,
            name TEXT,
            author TEXT,
            type INT,
            tags TEXT,
            cover_path TEXT,
            time TEXT,
            display_order INT,
            PRIMARY KEY (target, type)
          );
          INSERT INTO "$table" SELECT * FROM "$tempName";
          DROP TABLE "$tempName";
        ''');
      }
    }
  }

  void updateUI() {
    Future.microtask(
        () => StateController.findOrNull(tag: "me page")?.update());
    Future.microtask(
        () => StateController.findOrNull<FavoritesPageController>()?.update());
  }

  Future<List<String>> find(String target, FavoriteType type) async {
    final db = await _getDatabase();
    var res = <String>[];
    final folderNames = await this.folderNames;
    for (var folder in folderNames) {
      var rows = await db.query(
        folder,
        where: 'target = ? AND type = ?',
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
        where: 'target = ? AND type = ?',
        whereArgs: [item.target, item.type.key],
      );
      if (rows.isNotEmpty) {
        res.add(folder);
      }
    }
    return res;
  }

  Future<void> saveData() async {
    Webdav.uploadData();
  }

  /// read data from json file or temp db.
  ///
  /// This function will delete current database, then create a new one, finally
  /// import data.
  Future<void> readData() async {
    var file = File("${App.dataPath}/localFavorite");
    if (file.existsSync()) {
      Map<String, List<FavoriteItem>> allComics = {};
      try {
        var data = (const JsonDecoder().convert(await file.readAsString()))
            as Map<String, dynamic>;

        for (var key in data.keys.toList()) {
          Set<FavoriteItem> comics = {};
          for (var comic in data[key]!) {
            comics.add(FavoriteItem.fromJson(comic));
          }
          if (allComics.containsKey(key)) {
            comics.addAll(allComics[key]!);
          }
          allComics[key] = comics.toList();
        }

        await clearAll();

        for (var folder in allComics.keys) {
          createFolder(folder, true);
          var comics = allComics[folder]!;
          for (int i = 0; i < comics.length; i++) {
            addComic(folder, comics[i]);
          }
        }
      } catch (e, s) {
        Log.e("IO $e\n$s");
      } finally {
        file.deleteSync();
      }
    } else if ((file = File("${App.dataPath}/local_favorite_temp.db"))
        .existsSync()) {
      var tmpDbFactory = databaseFactoryFfi;
      final tmpDb = await tmpDbFactory.openDatabase(file.path);
      
      final folders = await tmpDb.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table';");
      final folderNames = folders
          .map((element) => element["name"] as String)
          .toList();
          
      folderNames.remove(kTableFolderSync);
      folderNames.remove(kTableFolderOrder);
      Log.i("LocalFavoritesManager.readData read folders from local database $folderNames");
      var folderToOrder = <String, int>{};
      for (var folder in folderNames) {
        var res = await tmpDb.query(
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
      folderNames.sort((a, b) {
        return folderToOrder[a]! - folderToOrder[b]!;
      });
      var res = <FavoriteItemWithFolderInfo>[];
      for (final folder in folderNames) {
        var comics = await tmpDb.query(folder);
        Log.i("LocalFavoritesManager.readData read $folder gets ${comics.length} comics");
        res.addAll(comics.map((element) =>
            FavoriteItemWithFolderInfo(FavoriteItem.fromRow(element), folder)));
      }
      var skips = 0;
      for (var comic in res) {
        if (!folderNames.contains(comic.folder)) {
          createFolder(comic.folder);
        }
        if (!(await comicExists(comic.folder, comic.comic.target, comic.comic.type.key))) {
          addComic(comic.folder, comic.comic);
          Log.i("LocalFavoritesManager add comic ${comic.comic.target} to ${comic.folder}");
        } else {
          skips++;
        }
      }
      Log.i("LocalFavoritesManager skipped $skips comics, total ${res.length}");
      await tmpDb.close();
      file.deleteSync();
    } else {
      Log.i("LocalFavoritesManager no local favorites db file found");
    }
  }

  Future<List<String>> _getTablesWithDB(Database db) async {
    final tablesResult = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table';");
    final tables = tablesResult
        .map((element) => element["name"] as String)
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

  void updateOrder(Map<String, int> order) async {
    final db = await _getDatabase();
    for (var folder in order.keys) {
      await db.insert(
        kTableFolderOrder,
        {
          kFolderOrderName: folder,
          kFolderOrderValue: order[folder],
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  Future<List<FolderSync>> _getFolderSyncWithDB() async {
    final db = await _getDatabase();
    final result = await db.query(kTableFolderSync);
    return result.map((element) => FolderSync.fromMap(element)).toList();
  }

  void updateFolderSyncTime(FolderSync folderSync) async {
    final db = await _getDatabase();
    await db.update(
      kTableFolderSync,
      {kFolderSyncTime: folderSync.time},
      where: '$kFolderSyncName = ?',
      whereArgs: [folderSync.folderName],
    );
  }

  void insertFolderSync(FolderSync folderSync) async {
    final db = await _getDatabase();
    await db.insert(kTableFolderSync, {
      kFolderSyncName: folderSync.folderName,
      kFolderSyncTime: folderSync.time,
      kFolderSyncKey: folderSync.key,
      kFolderSyncData: folderSync.syncData,
    });
  }

  Future<int> count(String folderName) async {
    final db = await _getDatabase();
    final result = await db.rawQuery('SELECT COUNT(*) as c FROM "$folderName"');
    return result.first["c"] as int;
  }

  Future<List<String>> get folderNames async => await _getFolderNamesWithDB();

  Future<List<FolderSync>> get folderSync async => await _getFolderSyncWithDB();

  Future<int> maxValue(String folder) async {
    final db = await _getDatabase();
    final result = await db.rawQuery(
        'SELECT MAX(display_order) AS max_value FROM "$folder"');
    return result.firstOrNull?["max_value"] as int? ?? 0;
  }

  Future<int> minValue(String folder) async {
    final db = await _getDatabase();
    final result = await db.rawQuery(
        'SELECT MIN(display_order) AS min_value FROM "$folder"');
    return result.firstOrNull?["min_value"] as int? ?? 0;
  }

  Future<List<FavoriteItem>> getAllComics(String folder) async {
    final db = await _getDatabase();
    var rows = await db.query(folder, orderBy: 'display_order');
    return rows.map((element) => FavoriteItem.fromRow(element)).toList();
  }

  void addTagTo(String folder, String target, String tag) async {
    final db = await _getDatabase();
    // 先获取现有标签
    final result = await db.query(
      folder,
      columns: ['tags'],
      where: 'target = ?',
      whereArgs: [target],
    );

    if (result.isNotEmpty) {
      final existingTags = result.first['tags'] as String;
      final newTags = '$tag,$existingTags';
      
      await db.update(
        folder,
        {'tags': newTags},
        where: 'target = ?',
        whereArgs: [target],
      );
      saveData();
    }
  }

  Future<List<FavoriteItemWithFolderInfo>> allComics() async {
    final db = await _getDatabase();
    var res = <FavoriteItemWithFolderInfo>[];
    for (final folder in await folderNames) {
      var comics = await db.query(folder);
      res.addAll(comics.map((element) =>
          FavoriteItemWithFolderInfo(FavoriteItem.fromRow(element), folder)));
    }
    return res;
  }

  /// create a folder
  Future<String> createFolder(String name, [bool renameWhenInvalidName = false]) async {
    if (name.isEmpty) {
      if (renameWhenInvalidName) {
        int i = 0;
        while ((await folderNames).contains(i.toString())) {
          i++;
        }
        name = i.toString();
      } else {
        throw "name is empty!";
      }
    }
    if ((await folderNames).contains(name)) {
      if (renameWhenInvalidName) {
        var prevName = name;
        int i = 0;
        while ((await folderNames).contains(i.toString())) {
          i++;
        }
        name = prevName + i.toString();
      } else {
        throw Exception("Folder is existing");
      }
    }
    
    final db = await _getDatabase();
    await db.execute('''
      CREATE TABLE "$name"(
        target TEXT,
        name TEXT,
        author TEXT,
        type INT,
        tags TEXT,
        cover_path TEXT,
        time TEXT,
        display_order INT,
        PRIMARY KEY (target, type)
      )
    ''');
    saveData();
    return name;
  }

  Future<bool> comicExists(String folder, String target, int type) async {
    final db = await _getDatabase();
    var res = await db.query(
      folder,
      where: 'target = ? AND type = ?',
      whereArgs: [target, type],
    );
    return res.isNotEmpty;
  }

  Future<FavoriteItem> getComic(String folder, String target, FavoriteType type) async {
    final db = await _getDatabase();
    var res = await db.query(
      folder,
      where: 'target = ? AND type = ?',
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
  void addComic(String folder, FavoriteItem comic, [int? order]) async {
    _modifiedAfterLastCache = true;
    if (!(await folderNames).contains(folder)) {
      throw Exception("Folder does not exists");
    }
    
    final db = await _getDatabase();
    var res = await db.query(
      folder,
      where: 'target = ?',
      whereArgs: [comic.target],
    );
    if (res.isNotEmpty) {
      return;
    }
    
    int displayOrder;
    if (order != null) {
      displayOrder = order;
    } else if (appdata.settings[53] == "0") {
      displayOrder = (await maxValue(folder)) + 1;
    } else {
      displayOrder = (await minValue(folder)) - 1;
    }

    await db.insert(folder, {
      'target': comic.target,
      'name': comic.name,
      'author': comic.author,
      'type': comic.type.key,
      'tags': comic.tags.join(','),
      'cover_path': comic.coverPath,
      'time': comic.time,
      'display_order': displayOrder,
    });

    updateUI();
    saveData();
    try {
      var file =
          (await (ImageManager().getImage(comic.coverPath)).last).getFile();
      var path =
          "${(await getApplicationSupportDirectory()).path}${pathSep}favoritesCover";
      var directory = Directory(path);
      if (!directory.existsSync()) {
        directory.createSync();
      }
      var hash =
          md5.convert(const Utf8Encoder().convert(comic.coverPath)).toString();
      file.copySync("$path$pathSep$hash.jpg");
    } catch (e) {
      //忽略
    }
  }

  /// get comic cover
  Future<File> getCover(FavoriteItem item) async {
    var path = "${App.dataPath}/favoritesCover";
    var hash =
        md5.convert(const Utf8Encoder().convert(item.coverPath)).toString();
    var file = File("$path/$hash.jpg");
    if (file.existsSync()) {
      return file;
    }
    if (item.coverPath.startsWith("file://")) {
      var data = await downloadManager
          .getCover(item.coverPath.replaceFirst("file://", ""));
      file.createSync(recursive: true);
      file.writeAsBytesSync(data.readAsBytesSync());
      return file;
    }
    try {
      if (EhNetwork().cookiesStr == "") {
        await EhNetwork().getCookies(false);
      }
      var res = await (ImageManager().getImage(item.coverPath, {
        if (item.type == FavoriteType.ehentai) "cookie": EhNetwork().cookiesStr,
        if (item.type == FavoriteType.hitomi) "Referer": "https://hitomi.la/"
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
  void deleteFolder(String name) async {
    _modifiedAfterLastCache = true;
    final db = await _getDatabase();
    await db.delete(
      kTableFolderSync,
      where: '$kFolderSyncName = ?',
      whereArgs: [name],
    );
    await db.execute('DROP TABLE "$name"');
  }

  void checkAndDeleteCover(FavoriteItem item) async {
    if ((await find(item.target, item.type)).isEmpty) {
      (await getCover(item)).deleteSync();
    }
  }

  void deleteComic(String folder, FavoriteItem comic) {
    _modifiedAfterLastCache = true;
    deleteComicWithTarget(folder, comic.target, comic.type);
    checkAndDeleteCover(comic);
  }

  void deleteComicWithTarget(String folder, String target, FavoriteType type) async {
    _modifiedAfterLastCache = true;
    final db = await _getDatabase();
    await db.delete(
      folder,
      where: 'target = ? AND type = ?',
      whereArgs: [target, type.key],
    );
    saveData();
  }

  Future<void> clearAll() async {
    final db = await _getDatabase();
    await db.close();
    File("${App.dataPath}/local_favorite.db").deleteSync();
    await init();
    saveData();
  }

  void reorder(List<FavoriteItem> newFolder, String folder) async {
    if (!(await folderNames).contains(folder)) {
      throw Exception("Failed to reorder: folder not found");
    }
    deleteFolder(folder);
    await createFolder(folder);
    for (int i = 0; i < newFolder.length; i++) {
      addComic(folder, newFolder[i], i);
    }
    updateUI();
  }

  void rename(String before, String after) async {
    if ((await folderNames).contains(after)) {
      throw "Name already exists!";
    }
    if (after.contains('"')) {
      throw "Invalid name";
    }
    
    final db = await _getDatabase();
    await db.execute('ALTER TABLE "$before" RENAME TO "$after"');
    
    if ((await folderSync).isNotEmpty) {
      await db.update(
        kTableFolderSync,
        {kFolderSyncName: after},
        where: '$kFolderSyncName = ?',
        whereArgs: [before],
      );
    }
    saveData();
  }

  void onReadEnd(String target, FavoriteType type) async {
    _modifiedAfterLastCache = true;
    bool isModified = false;
    final db = await _getDatabase();
    for (final folder in await folderNames) {
      var rows = await db.query(
        folder,
        where: 'target = ? AND type = ?',
        whereArgs: [target, type.key],
      );
      if (rows.isNotEmpty) {
        isModified = true;
        var newTime = DateTime.now()
            .toIso8601String()
            .replaceFirst("T", " ")
            .substring(0, 19);
            
        Map<String, dynamic> updates = {'time': newTime};
        if (appdata.settings[54] == "1") {
          int maxValue = await this.maxValue(folder);
          updates['display_order'] = maxValue + 1;
        } else if (appdata.settings[54] == "2") {
          int minValue = await this.minValue(folder);
          updates['display_order'] = minValue - 1;
        }
        
        await db.update(
          folder,
          updates,
          where: 'target = ?',
          whereArgs: [target],
        );
      }
    }
    if (isModified) {
      updateUI();
    }
    saveData();
  }

  Future<String> folderToJsonString(String folderName) async {
    final db = await _getDatabase();
    var data = <String, dynamic>{};
    data["info"] = "Generated by PicaComic.";
    data["website"] = "https://github.com/Pacalini/PicaComic";
    data["name"] = folderName;
    var comics = await db.query(folderName);
    data["comics"] = comics.map((e) => FavoriteItem.fromRow(e).toJson()).toList();
    return const JsonEncoder().convert(data);
  }

  Future<(bool, String)> loadFolderData(String dataString) async {
    try {
      var data =
          const JsonDecoder().convert(dataString) as Map<String, dynamic>;
      final name_ = data["name"] as String;
      var name = name_;
      int i = 0;
      while ((await folderNames).contains(name)) {
        name = name_ + i.toString();
        i++;
      }
      await createFolder(name);
      for (var json in data["comics"]) {
        addComic(name, FavoriteItem.fromJson(json));
      }
      return (false, "");
    } catch (e, s) {
      Log.e("IO Failed to load data.\n$e\n$s");
      return (true, e.toString());
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
        where: 'name LIKE ? OR author LIKE ? OR tags LIKE ?',
        whereArgs: [searchTerm, searchTerm, searchTerm],
      );
      for (var comic in res) {
        comics.add(
            FavoriteItemWithFolderInfo(FavoriteItem.fromRow(comic), table));
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
      comics =
          comics.where((element) => test(element, keywordList[i])).toList();
    }

    return comics;
  }

  void editTags(String target, String folder, List<String> tags) async {
    final db = await _getDatabase();
    await db.update(
      folder,
      {'tags': tags.join(',')},
      where: 'target = ?',
      whereArgs: [target],
    );
  }

  final _cachedFavoritedTargets = <String, bool>{};

  bool isExist(String target) {
    if (_modifiedAfterLastCache) {
      _cacheFavoritedTargets();
    }
    return _cachedFavoritedTargets.containsKey(target);
  }

  bool _modifiedAfterLastCache = true;

  void _cacheFavoritedTargets() async {
    _modifiedAfterLastCache = false;
    _cachedFavoritedTargets.clear();
    final db = await _getDatabase();
    for (var folder in await folderNames) {
      var res = await db.query(folder, columns: ['target']);
      for (var row in res) {
        _cachedFavoritedTargets[row["target"] as String] = true;
      }
    }
  }

  void updateInfo(String folder, FavoriteItem comic) async {
    final db = await _getDatabase();
    await db.update(
      folder,
      {
        'name': comic.name,
        'author': comic.author,
        'cover_path': comic.coverPath,
        'tags': comic.tags.join(','),
      },
      where: 'target = ? AND type = ?',
      whereArgs: [comic.target, comic.type.key],
    );
  }
}
