import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:pica_comic/comic_source/comic_source.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/foundation/log.dart';
import 'package:pica_comic/network/webdav.dart';
import 'package:pica_comic/tools/map_extension.dart';
import 'package:pica_comic/tools/type_util.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:synchronized/synchronized.dart';
import 'package:signals/signals.dart';

part "image_favorites.dart";

// 表名常量
const String kTableHistory = 'history';

// 字段名常量
const String kHistoryTarget = 'target';
const String kHistoryTitle = 'title';
const String kHistorySubtitle = 'subtitle';
const String kHistoryCover = 'cover';
const String kHistoryTime = 'time';
const String kHistoryType = 'type';
const String kHistoryEp = 'ep';
const String kHistoryPage = 'page';
const String kHistoryReadEpisode = 'readEpisode';
const String kHistoryMaxPage = 'max_page';

abstract mixin class HistoryMixin {
  String get title;

  String? get subTitle;

  String get cover;

  String get target;

  Object? get maxPage => null;

  HistoryType get historyType;
}

final class HistoryType {
  static HistoryType get picacg => const HistoryType(0);

  static HistoryType get ehentai => const HistoryType(1);

  static HistoryType get jmComic => const HistoryType(2);

  static HistoryType get hitomi => const HistoryType(3);

  static HistoryType get htmanga => const HistoryType(4);

  static HistoryType get nhentai => const HistoryType(5);

  static HistoryType get kemono => const HistoryType(6);

  final int value;

  String get name {
    if (value >= 0 && value <= 6) {
      return [
        "picacg",
        "ehentai",
        "jm",
        "hitomi",
        "htmanga",
        "nhentai",
        "kemono",
      ][value];
    } else {
      return ComicSource.fromIntKey(value)?.name ?? "Unknown";
    }
  }

  const HistoryType(this.value);

  @override
  bool operator ==(Object other) =>
      other is HistoryType && other.value == value;

  @override
  int get hashCode => value.hashCode;

  ComicSource? get comicSource {
    if (value >= 0 && value <= 6) {
      return ComicSource.find(name);
    } else {
      return ComicSource.fromIntKey(value);
    }
  }
}

/// 历史记录的不可变持久化快照。
///
/// 阅读器运行时仍使用 [History] 保存可变阅读进度；数据库和 JSON 边界统一
/// 通过此模型转换，避免持久化数据被运行时原地修改。
final class HistoryRecord {
  final HistoryType type;
  final DateTime time;
  final String title;
  final String subtitle;
  final String cover;
  final int ep;
  final int page;
  final String target;
  final Set<int> readEpisode;
  final int? maxPage;

  const HistoryRecord({
    required this.type,
    required this.time,
    required this.title,
    required this.subtitle,
    required this.cover,
    required this.ep,
    required this.page,
    required this.target,
    this.readEpisode = const {},
    this.maxPage,
  });

  HistoryRecord copyWith({
    HistoryType? type,
    DateTime? time,
    String? title,
    String? subtitle,
    String? cover,
    int? ep,
    int? page,
    String? target,
    Set<int>? readEpisode,
    int? maxPage,
    bool clearMaxPage = false,
  }) => HistoryRecord(
    type: type ?? this.type,
    time: time ?? this.time,
    title: title ?? this.title,
    subtitle: subtitle ?? this.subtitle,
    cover: cover ?? this.cover,
    ep: ep ?? this.ep,
    page: page ?? this.page,
    target: target ?? this.target,
    readEpisode: readEpisode ?? this.readEpisode,
    maxPage: clearMaxPage ? null : maxPage ?? this.maxPage,
  );

  static DateTime _parseTime(dynamic value) {
    final timestamp = TypeUtil.parseIntOrNull(value);
    if (timestamp != null) {
      return DateTime.fromMillisecondsSinceEpoch(timestamp);
    }
    return DateTime.tryParse(TypeUtil.parseString(value)) ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  static Set<int> _parseReadEpisode(dynamic value) {
    if (value is String) {
      return value
          .split(',')
          .map(TypeUtil.parseIntOrNull)
          .whereType<int>()
          .toSet();
    }
    return TypeUtil.parseIntList(value).toSet();
  }

  factory HistoryRecord.fromMap(Map<String, dynamic> map) => HistoryRecord(
    type: HistoryType(map.optInt(kHistoryType)),
    time: _parseTime(map[kHistoryTime]),
    title: map.optString(kHistoryTitle),
    subtitle: map.optString(kHistorySubtitle),
    cover: map.optString(kHistoryCover),
    ep: map.optInt(kHistoryEp),
    page: map.optInt(kHistoryPage),
    target: map.optString(kHistoryTarget),
    readEpisode: Set.unmodifiable(_parseReadEpisode(map[kHistoryReadEpisode])),
    maxPage: map.optIntOrNull(kHistoryMaxPage),
  );

  factory HistoryRecord.fromRow(Map<String, dynamic> map) => HistoryRecord(
    type: HistoryType(TypeUtil.parseInt(map[kHistoryType])),
    time: _parseTime(map[kHistoryTime]),
    title: TypeUtil.parseString(map[kHistoryTitle]),
    subtitle: TypeUtil.parseString(map[kHistorySubtitle]),
    cover: TypeUtil.parseString(map[kHistoryCover]),
    ep: TypeUtil.parseInt(map[kHistoryEp]),
    page: TypeUtil.parseInt(map[kHistoryPage]),
    target: TypeUtil.parseString(map[kHistoryTarget]),
    readEpisode: Set.unmodifiable(_parseReadEpisode(map[kHistoryReadEpisode])),
    maxPage: TypeUtil.parseIntOrNull(map[kHistoryMaxPage]),
  );

  Map<String, dynamic> toMap() => {
    kHistoryType: type.value,
    kHistoryTime: time.millisecondsSinceEpoch,
    kHistoryTitle: title,
    kHistorySubtitle: subtitle,
    kHistoryCover: cover,
    kHistoryEp: ep,
    kHistoryPage: page,
    kHistoryTarget: target,
    kHistoryReadEpisode: readEpisode.toList(),
    kHistoryMaxPage: maxPage,
  };

  Map<String, dynamic> toRow() => {
    kHistoryTarget: target,
    kHistoryTitle: title,
    kHistorySubtitle: subtitle,
    kHistoryCover: cover,
    kHistoryTime: time.millisecondsSinceEpoch,
    kHistoryType: type.value,
    kHistoryEp: ep,
    kHistoryPage: page,
    kHistoryReadEpisode: readEpisode.join(','),
    kHistoryMaxPage: maxPage,
  };

  factory HistoryRecord.fromJson(Map<String, dynamic> json) =>
      HistoryRecord.fromMap(json);

  Map<String, dynamic> toJson() => toMap();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HistoryRecord &&
          type == other.type &&
          time == other.time &&
          title == other.title &&
          subtitle == other.subtitle &&
          cover == other.cover &&
          ep == other.ep &&
          page == other.page &&
          target == other.target &&
          TypeUtil.equal(readEpisode, other.readEpisode) &&
          maxPage == other.maxPage;

  @override
  int get hashCode => jsonEncode(toMap()).hashCode;

  @override
  String toString() => 'HistoryRecord${jsonEncode(toMap())}';
}

base class History extends LinkedListEntry<History> {
  HistoryType type;

  DateTime time;

  String title;

  String subtitle;

  String cover;

  /// 标记为0表示没有阅读位置记录
  int ep;

  int page;

  String target;

  Set<int> readEpisode;

  int? maxPage;

  void addReadEpisode(int ep) {
    if (readEpisode.contains(ep)) return;
    try {
      readEpisode.add(ep);
    } catch (e) {
      readEpisode = readEpisode.toSet();
      readEpisode.add(ep);
    }
  }

  History(
    this.type,
    this.time,
    this.title,
    this.subtitle,
    this.cover,
    this.ep,
    this.page,
    this.target, [
    Set<int>? readEpisode,
    this.maxPage,
  ]) : readEpisode = readEpisode ?? <int>{};

  HistoryRecord toRecord() => HistoryRecord(
    type: type,
    time: time,
    title: title,
    subtitle: subtitle,
    cover: cover,
    ep: ep,
    page: page,
    target: target,
    readEpisode: Set.unmodifiable(readEpisode),
    maxPage: maxPage,
  );

  factory History.fromRecord(HistoryRecord record) => History(
    record.type,
    record.time,
    record.title,
    record.subtitle,
    record.cover,
    record.ep,
    record.page,
    record.target,
    record.readEpisode,
    record.maxPage,
  );

  History.fromModel({
    required HistoryMixin model,
    required this.ep,
    required this.page,
    Set<int>? readEpisode,
    DateTime? time,
  }) : type = model.historyType,
       title = model.title,
       subtitle = model.subTitle ?? '',
       cover = model.cover,
       target = model.target,
       readEpisode = readEpisode ?? <int>{},
       time = time ?? DateTime.now();

  Map<String, dynamic> toMap() => toRecord().toMap();

  factory History.fromMap(Map<String, dynamic> map) =>
      History.fromRecord(HistoryRecord.fromMap(map));

  @override
  String toString() {
    return 'NewHistory{type: $type, time: $time, title: $title, subtitle: $subtitle, cover: $cover, ep: $ep, page: $page, target: $target}';
  }

  factory History.fromRow(Map<String, dynamic> map) =>
      History.fromRecord(HistoryRecord.fromRow(map));

  static Future<History> findOrCreate(
    HistoryMixin model, {
    int ep = 0,
    int page = 0,
  }) async {
    var history = await HistoryManager().find(model.target);
    if (history != null) {
      history.addReadEpisode(ep); // Add this line to update read episodes
      return history;
    }
    history = History.fromModel(model: model, ep: ep, page: page);
    HistoryManager().addHistory(history);
    return history;
  }

  static Future<History> createIfNull(
    History? history,
    HistoryMixin model,
  ) async {
    if (history != null) {
      return history;
    }
    history = History.fromModel(model: model, ep: 0, page: 0);
    HistoryManager().addHistory(history);
    return history;
  }
}

class HistoryManager {
  static HistoryManager instance = HistoryManager._create();

  HistoryManager._create();

  factory HistoryManager() => instance;

  Database? _db;
  bool _initialized = false;
  final Lock _lock = Lock();
  final Completer<Database> _initCompleter = Completer<Database>();

  Future<Database> get db {
    final db = _db;
    if (db != null) {
      return SynchronousFuture(db);
    }
    return _initCompleter.future;
  }

  // 数据库版本号
  static const int _databaseVersion = 1;

  /// 缓存已查明进度的历史详情
  /// Key: target, Value: 单个被 Signal 包裹的历史信息
  /// 这样可以确保当一个漫画的历史更新时，只有监听这个特定 target 的组件才会重建
  final Map<String, Signal<History?>> historyCache = {};

  /// 待查询的 target 队列
  final Set<String> _pendingTargets = {};
  bool _isBatchQueryPending = false;

  Future<void> tryUpdateDb() async {
    var file = File("${App.dataPath}/history_temp.db");
    if (!file.existsSync()) {
      Log.i("HistoryManager.tryUpdateDb db file not exist");
      return;
    }

    // 使用 sqflite_common_ffi 替代 sqlite3
    var db = await databaseFactoryFfi.openDatabase(file.path);

    // 查询历史记录
    var newHistory0 = await db.query(
      kTableHistory,
      orderBy: '$kHistoryTime DESC',
    );
    var newHistory = newHistory0
        .map((element) => History.fromRow(element))
        .toList();

    if (file.existsSync()) {
      var skips = 0;
      for (var history in newHistory) {
        if (await findSync(history.target) == null) {
          addHistory(history);
          Log.i("HistoryManager merge history ${history.target}");
        } else {
          skips++;
        }
      }
      Log.i(
        "HistoryManager merge history, skipped $skips, added ${newHistory.length - skips}",
      );

      //import favorite images
      skips = 0;

      // 查询收藏的图片
      var newImages0 = await db.query('image_favorites');
      var newImages = newImages0.map((e) => ImageFavorite.fromRow(e)).toList();

      for (var image in newImages) {
        if (await ImageFavoriteManager.exist(image.id, image.ep, image.page)) {
          skips++;
        } else {
          ImageFavoriteManager.add(image);
          Log.i(
            "HistoryManager merge favorite image ep ${image.ep} page ${image.page} @ ${image.id}",
          );
        }
      }
      Log.i(
        "HistoryManager merge favorite images, skipped $skips, added ${newImages.length - skips}",
      );
    }

    // 关闭数据库连接
    await db.close();
    file.deleteSync();
  }

  /// 确保数据库已初始化
  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await _lock.synchronized(() async {
      if (_initialized) return;
      await _initDatabase();
    });
  }

  /// 初始化数据库
  Future<void> _initDatabase() async {
    // 初始化 sqflite_common_ffi
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    final databasePath = '${App.dataPath}/history.db';
    Log.i("HistoryManager Database path: $databasePath");

    _db = await databaseFactory.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: _databaseVersion,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      ),
    );

    _initialized = true;
    _initCompleter.complete(_db);

    // 不再启动时全量加载历史记录到内存，实现按需加载

    // 迁移早期版本的数据
    var file = File("${App.dataPath}/history.json");
    if (file.existsSync()) {
      readDataFromJson(jsonDecode(await file.readAsString()));
      file.deleteSync();
    }
  }

  /// 创建数据库表
  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $kTableHistory (
        $kHistoryTarget TEXT PRIMARY KEY,
        $kHistoryTitle TEXT,
        $kHistorySubtitle TEXT,
        $kHistoryCover TEXT,
        $kHistoryTime INTEGER,
        $kHistoryType INTEGER,
        $kHistoryEp INTEGER,
        $kHistoryPage INTEGER,
        $kHistoryReadEpisode TEXT,
        $kHistoryMaxPage INTEGER
      )
    ''');

    await ImageFavoriteManager.createTable(db);
  }

  /// 升级数据库表
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // 可以在这里添加更多版本升级逻辑
    if (oldVersion < 1) {
      await _onCreate(db, newVersion);
    }
  }

  Future<void> init() async {
    // 启动数据库初始化但不等待完成
    _ensureInitialized();
  }

  void readDataFromJson(List<dynamic> json) {
    var history = LinkedList<History>();
    for (var h in json) {
      history.add(History.fromMap((h as Map<String, dynamic>)));
    }
    vacuum();
  }

  void saveData() async {
    Webdav.uploadData();
  }

  /// add history. if exists, update time.
  ///
  /// This function would be called when user start reading.
  Future<void> addHistory(History newItem) async {
    _updateHistoryCache(newItem.target, newItem);

    await _ensureInitialized();
    final db = _db!;

    final res = await db.query(
      kTableHistory,
      where: '$kHistoryTarget = ?',
      whereArgs: [newItem.target],
    );

    if (res.isEmpty) {
      await db.insert(
        kTableHistory,
        newItem.toRecord().toRow(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } else {
      newItem.time = DateTime.now();
      await db.update(
        kTableHistory,
        {kHistoryTime: newItem.time.millisecondsSinceEpoch},
        where: '$kHistoryTarget = ?',
        whereArgs: [newItem.target],
      );
    }
    saveData();
  }

  ///退出阅读器时调用此函数, 修改阅读位置
  Future<void> saveReadHistory(
    History history, [
    bool updateMePage = true,
  ]) async {
    await _ensureInitialized();
    final db = _db!;

    history.time = DateTime.now();
    await db.update(
      kTableHistory,
      {
        kHistoryTime: history.time.millisecondsSinceEpoch,
        kHistoryEp: history.ep,
        kHistoryPage: history.page,
        kHistoryReadEpisode: history.readEpisode.join(','),
        kHistoryMaxPage: history.maxPage,
      },
      where: '$kHistoryTarget = ?',
      whereArgs: [history.target],
    );

    // 更新内存缓存
    _updateHistoryCache(history.target, history);
  }

  void clearHistory() async {
    await _ensureInitialized();
    final db = _db!;
    await db.delete(kTableHistory);
    historyCache.clear();
    _pendingTargets.clear();
  }

  void remove(String id) async {
    await _ensureInitialized();
    final db = _db!;
    await db.delete(
      kTableHistory,
      where: '$kHistoryTarget = ?',
      whereArgs: [id],
    );
    _updateHistoryCache(id, null);
  }

  /// 同步查找历史缓存。如果缓存没有，则抛入待查队列（微任务合并批量查找）
  History? findInCache(String target) {
    if (!historyCache.containsKey(target)) {
      // 先塞一个空的壳子，避免重复进入队列
      historyCache[target] = signal(null);
      _enqueueQuery(target);
    }
    return historyCache[target]!.value;
  }

  /// 异步查找历史，支持立刻返回（因为要保证旧API的兼容性）。
  /// 在使用信号系统的上层应用优先考虑直接读取 `historyCache[target]?.value` 或者 [findInCache]。
  Future<History?> find(String target) async {
    if (historyCache.containsKey(target) &&
        historyCache[target]!.value != null) {
      return historyCache[target]!.value;
    }
    await _ensureInitialized();
    return findSync(target);
  }

  Future<void> updateCache() async {
    // 按需加载不再需要主动拉取全量Cache。提供一个空实现或抛弃掉。
  }

  Future<History?> findSync(String target) async {
    if (historyCache.containsKey(target) &&
        historyCache[target]!.value != null) {
      return SynchronousFuture(historyCache[target]!.value);
    }

    final e = await _findDirect(target);
    _updateHistoryCache(target, e);
    return e;
  }

  void _updateHistoryCache(String target, History? history) {
    if (historyCache.containsKey(target)) {
      historyCache[target]!.set(history, force: true);
    } else {
      historyCache[target] = signal(history);
    }
  }

  void _enqueueQuery(String target) {
    if (_pendingTargets.contains(target)) return;

    _pendingTargets.add(target);

    if (!_isBatchQueryPending) {
      _isBatchQueryPending = true;
      Future.microtask(_processBatchQuery);
    }
  }

  Future<void> _processBatchQuery() async {
    if (_pendingTargets.isEmpty) {
      _isBatchQueryPending = false;
      return;
    }

    final queryTargets = _pendingTargets.toList();
    _pendingTargets.clear();
    _isBatchQueryPending = false;

    try {
      await _ensureInitialized();
      final db = _db!;

      // sqlite 的 IN 查询构造
      final placeholders = List.filled(queryTargets.length, '?').join(', ');
      final res = await db.query(
        kTableHistory,
        where: '$kHistoryTarget IN ($placeholders)',
        whereArgs: queryTargets,
      );

      // 先确保都有空的 Signal，防止有目标没有被查询到导致的错乱
      for (var target in queryTargets) {
        if (!historyCache.containsKey(target)) {
          historyCache[target] = signal(null);
        }
      }

      // 根据查询真实情况填充
      for (var element in res) {
        final target = element[kHistoryTarget] as String;
        if (historyCache[target]!.value == null) {
          historyCache[target]!.value = History.fromRow(element);
        }
      }
    } catch (e) {
      Log.e('Failed to process batch query: $e');
    }
  }

  Future<History?> _findDirect(String target) async {
    // 不等待初始化，因为我们已经在调用函数中确保了初始化
    await _ensureInitialized();
    final db = _db!;
    final res = await db.query(
      kTableHistory,
      where: '$kHistoryTarget = ?',
      whereArgs: [target],
    );
    if (res.isEmpty) {
      return null;
    }
    return History.fromRow(res.first);
  }

  Future<List<History>> getAll() async {
    await _ensureInitialized();
    final db = _db!;
    final res = await db.query(kTableHistory, orderBy: '$kHistoryTime DESC');
    return res.map((element) => History.fromRow(element)).toList();
  }

  void vacuum() {
    // sqflite数据库不需要手动执行vacuum
  }

  /// 获取最近一周的阅读数据, 用于生成图表, List中的元素是当天阅读的漫画数量
  Future<List<int>> getWeekData(int days) async {
    await _ensureInitialized();
    final db = _db!;
    final startTime = DateTime.now()
        .add(Duration(days: 1 - days))
        .millisecondsSinceEpoch;
    final res = await db.query(
      kTableHistory,
      where: '$kHistoryTime > ?',
      whereArgs: [startTime],
      orderBy: '$kHistoryTime ASC',
    );

    var data = List<int>.filled(days, 0);
    for (var element in res) {
      var time = DateTime.fromMillisecondsSinceEpoch(
        element[kHistoryTime] as int,
      );
      data[DateTime.now().difference(time).inDays]++;
    }
    return data.reversed.toList();
  }

  /// 获取最近阅读的漫画
  Future<List<History>> getRecent() async {
    await _ensureInitialized();
    final db = _db!;
    final res = await db.query(
      kTableHistory,
      orderBy: '$kHistoryTime DESC',
      limit: 20,
    );
    return res.map((element) => History.fromRow(element)).toList();
  }

  /// 获取历史记录的数量
  Future<int> count() async {
    await _ensureInitialized();
    final db = _db!;
    final result = await db.rawQuery('SELECT COUNT(*) FROM $kTableHistory');
    return result.first.values.first as int;
  }
}
