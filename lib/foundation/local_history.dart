import 'dart:async';
import 'dart:convert';
import 'package:synchronized/synchronized.dart';
import 'batch_lookup.dart';
import 'repository_change.dart';
import 'package:pica_comic/foundation/database/download_database.dart';
import 'package:pica_comic/tools/map_extension.dart';

class LocalHistory {
  final String path;
  final int isReversed;
  final int pageIndex;
  final int time;
  final String json;
  final int totalPages;

  const LocalHistory({
    required this.path,
    required this.isReversed,
    required this.pageIndex,
    required this.time,
    this.json = '',
    this.totalPages = 0,
  });

  factory LocalHistory.fromMap(Map<String, dynamic> map) {
    return LocalHistory(
      path: map.optString(kLocalHistoryPath),
      isReversed: map.optInt(kLocalHistoryIsReversed),
      pageIndex: map.optInt(kLocalHistoryPageIndex, 1),
      time: map.optInt(kLocalHistoryTime),
      json: map.optString(kLocalHistoryJson),
      totalPages: map.optInt(kLocalHistoryTotalPages),
    );
  }

  factory LocalHistory.fromJson(Map<String, dynamic> json) =>
      LocalHistory.fromMap(json);

  Map<String, dynamic> toJson() => toMap();

  LocalHistory copyWith({
    String? path,
    int? isReversed,
    int? pageIndex,
    int? time,
    String? json,
    int? totalPages,
  }) {
    return LocalHistory(
      path: path ?? this.path,
      isReversed: isReversed ?? this.isReversed,
      pageIndex: pageIndex ?? this.pageIndex,
      time: time ?? this.time,
      json: json ?? this.json,
      totalPages: totalPages ?? this.totalPages,
    );
  }

  int optInt(String key, [int defaultValue = 0]) {
    switch (key) {
      case 'isReversed':
        return isReversed;
      case 'pageIndex':
        return pageIndex;
      case 'time':
        return time;
      case 'total_pages':
        return totalPages;
      default:
        return defaultValue;
    }
  }

  Map<String, dynamic> toMap() => {
    kLocalHistoryPath: path,
    kLocalHistoryIsReversed: isReversed,
    kLocalHistoryPageIndex: pageIndex,
    kLocalHistoryTime: time,
    kLocalHistoryJson: json,
    kLocalHistoryTotalPages: totalPages,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LocalHistory &&
          path == other.path &&
          isReversed == other.isReversed &&
          pageIndex == other.pageIndex &&
          time == other.time &&
          json == other.json &&
          totalPages == other.totalPages;

  @override
  int get hashCode =>
      Object.hash(path, isReversed, pageIndex, time, json, totalPages);

  @override
  String toString() => 'LocalHistory${jsonEncode(toMap())}';
}

class LocalHistoryManager {
  static LocalHistoryManager instance = LocalHistoryManager._create();

  LocalHistoryManager._create();

  factory LocalHistoryManager() => instance;

  Future<void> Function()? _ensureReady;

  /// 由应用作用域注入共享下载数据库的就绪回调。
  void bindDatabaseReady(Future<void> Function() ensureReady) =>
      _ensureReady = ensureReady;

  final DownloadDatabase _db = DownloadDatabase();
  final Lock _writeLock = Lock();
  final _changes = StreamController<RepositoryChange<String>>.broadcast();
  late final _lookup = BatchLookup<String, LocalHistory>(_loadRecords);

  /// 本地历史提交后的变更通知。
  Stream<RepositoryChange<String>> get changes => _changes.stream;

  /// 按目录批量加载历史。
  Future<Map<String, LocalHistory>> _loadRecords(List<String> paths) async {
    await _ensureReady?.call();
    final result = <String, LocalHistory>{};
    for (var offset = 0; offset < paths.length; offset += 400) {
      final rows = await _db.getLocalHistoryByPaths(
        paths.skip(offset).take(400).toList(),
      );
      for (final row in rows) {
        final record = LocalHistory.fromMap(row);
        result[record.path] = record;
      }
    }
    return result;
  }

  /// 查询历史，失败不缓存，允许下次重试。
  Future<LocalHistory?> find(String path) => _lookup.get(path);

  /// 更新总页数并发布最新记录。
  Future<void> updateLocalHistoryPageCount(String path, int count) =>
      _writeLock.synchronized(() async {
        await _ensureReady?.call();
        await _db.updateLocalHistoryPageCount(path, count);
        _lookup.clear();
        _changes.add(RepositoryChange(keys: {path}));
      });

  /// 保存退出前已捕获的本地阅读进度。
  Future<void> saveReadHistory(LocalHistory history) {
    final record = history.copyWith(
      time: DateTime.now().millisecondsSinceEpoch,
    );
    return _writeLock.synchronized(() async {
      await _ensureReady?.call();
      await _db.addOrUpdateLocalHistory(
        path: record.path,
        isReversed: record.isReversed,
        pageIndex: record.pageIndex,
        time: record.time,
        json: record.json,
        totalPages: record.totalPages,
      );
      _lookup.set(record.path, record);
      _changes.add(RepositoryChange(keys: {record.path}));
    });
  }

  /// 删除目录的阅读进度。
  Future<void> remove(String path) => _writeLock.synchronized(() async {
    await _ensureReady?.call();
    await _db.deleteLocalHistory(path);
    _lookup.set(path, null);
    _changes.add(RepositoryChange(keys: {path}));
  });

  /// 清空数据库记录并通知所有消费者。
  Future<void> clearHistory() => _writeLock.synchronized(() async {
    await _ensureReady?.call();
    await _db.clearLocalHistory();
    _lookup.clear();
    _changes.add(RepositoryChange());
  });

  /// 按最近阅读顺序加载列表。
  Future<List<LocalHistory>> getAll() async {
    await _ensureReady?.call();
    return List.unmodifiable(
      (await _db.getAllLocalHistory()).map(LocalHistory.fromMap),
    );
  }
}
