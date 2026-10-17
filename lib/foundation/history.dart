import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:pica_comic/comic_source/comic_source.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/foundation/log.dart';
import 'package:pica_comic/network/webdav.dart';
import 'package:pica_comic/tools/map_extension.dart';
import 'package:pica_comic/tools/type_util.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:synchronized/synchronized.dart';
import 'batch_lookup.dart';
import 'repository_change.dart';

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
const String kHistoryChapterId = 'chapter_id';
const String kHistoryReadChapterIds = 'read_chapter_ids';

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
  final String? chapterId;
  final Set<String> readChapterIds;

  HistoryRecord({
    required this.type,
    required this.time,
    required this.title,
    required this.subtitle,
    required this.cover,
    required this.ep,
    required this.page,
    required this.target,
    Set<int> readEpisode = const {},
    this.maxPage,
    this.chapterId,
    Set<String> readChapterIds = const {},
  }) : readEpisode = Set.unmodifiable(readEpisode),
       readChapterIds = Set.unmodifiable(readChapterIds);

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
    String? chapterId,
    Set<String>? readChapterIds,
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
    chapterId: chapterId ?? this.chapterId,
    readChapterIds: readChapterIds ?? this.readChapterIds,
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

  /// 兼容数据库 JSON 文本与导入导出数组。
  static Set<String> _parseChapterIds(Object? value) {
    if (value is String) {
      try {
        value = jsonDecode(value);
      } on FormatException {
        return {};
      }
    }
    return TypeUtil.parseStringList(value).toSet();
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
    chapterId: map[kHistoryChapterId] as String?,
    readChapterIds: _parseChapterIds(map[kHistoryReadChapterIds]),
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
    chapterId: map[kHistoryChapterId] as String?,
    readChapterIds: _parseChapterIds(map[kHistoryReadChapterIds]),
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
    kHistoryChapterId: chapterId,
    kHistoryReadChapterIds: readChapterIds.toList(),
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
    kHistoryChapterId: chapterId,
    kHistoryReadChapterIds: jsonEncode(readChapterIds.toList()),
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
          maxPage == other.maxPage &&
          chapterId == other.chapterId &&
          TypeUtil.equal(readChapterIds, other.readChapterIds);

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

  /// 可选稳定章节标识，仅支持该能力的来源写入。
  String? chapterId;
  Set<String> readChapterIds = {};

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
    chapterId: chapterId,
    readChapterIds: Set.unmodifiable(readChapterIds),
  );

  factory History.fromRecord(HistoryRecord record) =>
      History(
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
        )
        ..chapterId = record.chapterId
        ..readChapterIds = record.readChapterIds.toSet();

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
    await HistoryManager().addHistory(history);
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
    await HistoryManager().addHistory(history);
    return history;
  }
}

class HistoryManager {
  static HistoryManager instance = HistoryManager._create();

  HistoryManager._create();

  factory HistoryManager() => instance;

  Database? _db;
  bool _initialized = false;
  Future<void>? _initializationFuture;
  final Lock _lock = Lock();
  final Completer<Database> _initCompleter = Completer<Database>();
  final _changeController =
      StreamController<RepositoryChange<String>>.broadcast();
  final Lock _writeLock = Lock();

  /// 历史记录发生变化时通知功能 Provider 刷新派生数据。
  Stream<RepositoryChange<String>> get changes => _changeController.stream;

  void _notifyChanged([String? target]) => _changeController.add(
    RepositoryChange(keys: target == null ? null : {target}),
  );

  Future<Database> get db async {
    final db = _db;
    if (db != null) {
      return db;
    }
    // 允许图片收藏页、阅读器等直接调用方按需触发历史数据库初始化，
    // 避免在未打开数据库时永久等待 Completer。
    await init();
    return _db!;
  }

  // 数据库版本号
  static const int _databaseVersion = 2;

  late final _lookup = BatchLookup<String, HistoryRecord>(_loadRecords);

  /// 清理查询缓存，适用于重新导入和测试隔离。
  void clearCache() => _lookup.clear();

  /// 批量加载不可变进度，超过 SQLite 参数限制时分块查询。
  Future<Map<String, HistoryRecord>> _loadRecords(List<String> targets) async {
    await _ensureInitialized();
    final result = <String, HistoryRecord>{};
    for (var offset = 0; offset < targets.length; offset += 400) {
      final chunk = targets.skip(offset).take(400).toList();
      final rows = await _db!.query(
        kTableHistory,
        where:
            '$kHistoryTarget IN (${List.filled(chunk.length, '?').join(',')})',
        whereArgs: chunk,
      );
      for (final row in rows) {
        final record = HistoryRecord.fromRow(row);
        result[record.target] = record;
      }
    }
    return result;
  }

  /// 合并 WebDAV 临时数据库，成功后才移除输入文件。
  Future<void> tryUpdateDb() async {
    final file = File('${App.dataPath}/history_temp.db');
    if (!await file.exists()) return;
    final incoming = await databaseFactoryFfi.openDatabase(file.path);
    try {
      final rows = await incoming.query(
        kTableHistory,
        orderBy: '$kHistoryTime DESC',
      );
      final records = rows
          .map(HistoryRecord.fromRow)
          .map((record) => record.toMap())
          .toList();
      await readDataFromJson(records);
    } finally {
      await incoming.close();
    }
    await file.delete();
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

    // 迁移早期版本的数据
    var file = File("${App.dataPath}/history.json");
    if (file.existsSync()) {
      final values = jsonDecode(await file.readAsString()) as List;
      await _importRecords(
        values
            .map(
              (value) => HistoryRecord.fromMap(
                Map<String, dynamic>.from(value as Map),
              ),
            )
            .toList(),
      );
      file.deleteSync();
    }
    _initialized = true;
    if (!_initCompleter.isCompleted) _initCompleter.complete(_db);
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
        $kHistoryMaxPage INTEGER,
        $kHistoryChapterId TEXT,
        $kHistoryReadChapterIds TEXT
      )
    ''');
  }

  /// 升级数据库表
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 1) {
      await _onCreate(db, newVersion);
      return;
    }
    if (oldVersion < 2) {
      await db.execute(
        'ALTER TABLE $kTableHistory ADD COLUMN $kHistoryChapterId TEXT',
      );
      await db.execute(
        'ALTER TABLE $kTableHistory ADD COLUMN $kHistoryReadChapterIds TEXT',
      );
    }
  }

  /// 确保历史数据库初始化完成。
  ///
  /// 多个功能 Provider 可能同时读取历史和图片收藏，所有调用共享同一个
  /// Future，避免重复打开数据库或在数据库尚未就绪时读取。
  Future<void> init() {
    if (_initialized) return Future.value();
    final pending = _initializationFuture;
    if (pending != null) return pending;

    final future = _initializeWithRetry();
    _initializationFuture = future;
    return future;
  }

  Future<void> _initializeWithRetry() async {
    try {
      await _ensureInitialized();
    } catch (_) {
      _initializationFuture = null;
      rethrow;
    }
  }

  /// 兼容旧 JSON，在事务中合并并发布全量失效通知。
  Future<void> readDataFromJson(List<dynamic> json) async {
    final records = json
        .map(
          (value) =>
              HistoryRecord.fromMap(Map<String, dynamic>.from(value as Map)),
        )
        .toList();
    await _writeLock.synchronized(() async {
      await _ensureInitialized();
      await _importRecords(records);
    });
  }

  /// 初始化和运行期导入共用事务，初始化期间不重复获取写锁。
  Future<void> _importRecords(List<HistoryRecord> records) async {
    await _db!.transaction((txn) async {
      for (final record in records) {
        await txn.insert(
          kTableHistory,
          record.toRow(),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    });
    _lookup.clear();
    _notifyChanged();
  }

  /// 将已提交的数据交给现有 WebDAV 队列。
  Future<void> saveData() async {
    try {
      await Webdav.uploadData();
    } catch (error, stack) {
      Log.e('历史远端同步失败', error: error, stackTrace: stack);
    }
  }

  /// 开始阅读时添加记录；已有记录仅更新阅读时间。
  Future<void> addHistory(History newItem) {
    final snapshot = newItem.toRecord().copyWith(time: DateTime.now());
    return _writeLock.synchronized(() async {
      await _ensureInitialized();
      final rows = await _db!.query(
        kTableHistory,
        where: '$kHistoryTarget = ?',
        whereArgs: [snapshot.target],
      );
      final record = rows.isEmpty
          ? snapshot
          : HistoryRecord.fromRow(rows.first).copyWith(time: snapshot.time);
      await _db!.insert(
        kTableHistory,
        record.toRow(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      _lookup.set(record.target, record);
      _notifyChanged(record.target);
      unawaited(saveData());
    });
  }

  /// 立即捕获阅读快照，异步保存期间不再访问可变会话对象。
  Future<void> saveReadHistory(History history) {
    final snapshot = history.toRecord().copyWith(time: DateTime.now());
    return _writeLock.synchronized(() async {
      await _ensureInitialized();
      await _db!.insert(
        kTableHistory,
        snapshot.toRow(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      _lookup.set(snapshot.target, snapshot);
      _notifyChanged(snapshot.target);
    });
  }

  /// 清空持久化记录并使全部在途查询失效。
  Future<void> clearHistory() => _writeLock.synchronized(() async {
    await _ensureInitialized();
    await _db!.delete(kTableHistory);
    _lookup.clear();
    _notifyChanged();
    unawaited(saveData());
  });

  /// 删除记录并发布空快照。
  Future<void> remove(String id) => _writeLock.synchronized(() async {
    await _ensureInitialized();
    await _db!.delete(
      kTableHistory,
      where: '$kHistoryTarget = ?',
      whereArgs: [id],
    );
    _lookup.set(id, null);
    _notifyChanged(id);
    unawaited(saveData());
  });

  /// 查询不可变快照，同一微任务内的请求合并为批量查询。
  Future<HistoryRecord?> findRecord(String target) => _lookup.get(target);

  /// 为旧阅读器接口创建独立的可变对象。
  Future<History?> find(String target) async {
    final record = await findRecord(target);
    return record == null ? null : History.fromRecord(record);
  }

  /// 兼容旧调用名称；查询始终异步且不会共享可变对象。
  Future<History?> findSync(String target) => find(target);

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

  /// 分页获取历史记录，避免为单页请求读取整个历史表。
  Future<List<History>> getPage(int page, {int pageSize = 30}) async {
    await _ensureInitialized();
    final db = _db!;
    final safePage = page < 0 ? 0 : page;
    final res = await db.query(
      kTableHistory,
      orderBy: '$kHistoryTime DESC',
      limit: pageSize,
      offset: safePage * pageSize,
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
