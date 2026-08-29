import 'dart:async';
import 'dart:convert';
import 'package:signals/signals.dart';
import 'package:pica_comic/foundation/database/download_database.dart';
import 'package:pica_comic/foundation/log.dart';
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

  final Map<String, Signal<LocalHistory?>> historyCache = {};
  final Set<String> _pendingTargets = {};
  bool _isBatchQueryPending = false;

  final DownloadDatabase _db = DownloadDatabase();

  /// 同步查找缓存，用于实时构建UI
  LocalHistory? findInCache(String path) {
    return historyCache.putIfAbsent(path, () {
      _enqueueQuery(path);
      return signal(null);
    }).value;
  }

  Future<LocalHistory?> find(String path) async {
    final cached = historyCache[path]?.value;
    if (cached != null) return cached;
    return _findSync(path);
  }

  Future<LocalHistory?> _findSync(String path) async {
    final res = await _db.getLocalHistory(path);
    if (res == null) {
      _updateHistoryCache(path, null);
      return null;
    }

    final e = LocalHistory.fromMap(res);
    _updateHistoryCache(path, e);
    return e;
  }

  Future<void> updateLocalHistoryPageCount(String path, int count) async {
    await _db.updateLocalHistoryPageCount(path, count);
    final currentSig = historyCache[path];
    if (currentSig?.value != null) {
      currentSig!.set(
        currentSig.value!.copyWith(totalPages: count),
        force: true,
      );
    }
  }

  void _updateHistoryCache(String path, LocalHistory? history) {
    if (historyCache.containsKey(path)) {
      historyCache[path]!.set(history, force: true);
    } else {
      historyCache[path] = signal(history);
    }
  }

  void _enqueueQuery(String path) {
    if (_pendingTargets.contains(path)) return;

    _pendingTargets.add(path);

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
      final res = await _db.getLocalHistoryByPaths(queryTargets);

      for (var target in queryTargets) {
        if (!historyCache.containsKey(target)) {
          historyCache[target] = signal(null);
        }
      }

      for (var element in res) {
        final path = element[kLocalHistoryPath] as String;
        if (historyCache[path]!.value == null) {
          historyCache[path]!.value = LocalHistory.fromMap(element);
        }
      }
    } catch (e) {
      Log.e('Failed to process batch query: $e');
    }
  }

  /// 退出阅读器时调用
  Future<void> saveReadHistory(LocalHistory history) async {
    final updatedHistory = history.copyWith(
      time: DateTime.now().millisecondsSinceEpoch,
    );
    await _db.addOrUpdateLocalHistory(
      path: updatedHistory.path,
      isReversed: updatedHistory.isReversed,
      pageIndex: updatedHistory.pageIndex,
      time: updatedHistory.time,
      json: updatedHistory.json,
      totalPages: updatedHistory.totalPages,
    );
    _updateHistoryCache(updatedHistory.path, updatedHistory);
  }

  Future<void> remove(String path) async {
    await _db.deleteLocalHistory(path);
    _updateHistoryCache(path, null);
  }

  void clearHistory() {
    // Requires a clear all method in download_database
    historyCache.clear();
    _pendingTargets.clear();
  }

  Future<List<LocalHistory>> getAll() async {
    final res = await _db.getAllLocalHistory();
    return res.map((element) => LocalHistory.fromMap(element)).toList();
  }
}
