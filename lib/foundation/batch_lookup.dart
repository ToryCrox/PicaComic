import 'dart:async';

/// 合并同一微任务内的查询，并阻止写入前发起的查询覆盖新数据。
class BatchLookup<K, V> {
  BatchLookup(this.load, {this.capacity = 1024});

  final Future<Map<K, V>> Function(List<K> keys) load;
  final int capacity;
  final _cache = <K, V?>{};
  final _pending = <K, Completer<V?>>{};
  int _revision = 0;

  /// 查询失败不缓存；查无记录会缓存空值。
  Future<V?> get(K key) {
    if (_cache.containsKey(key)) {
      final value = _cache.remove(key);
      _cache[key] = value;
      return Future.value(value);
    }
    final pending = _pending[key];
    if (pending != null) return pending.future;
    final completer = Completer<V?>();
    if (_pending.isEmpty) scheduleMicrotask(_flush);
    _pending[key] = completer;
    return completer.future;
  }

  /// 发布持久化成功的快照，同时使在途查询失效。
  void set(K key, V? value) {
    _revision++;
    _cache.remove(key);
    _cache[key] = value;
    while (_cache.length > capacity) {
      _cache.remove(_cache.keys.first);
    }
  }

  /// 清空缓存；旧查询只能重新读取当前数据库。
  void clear() {
    _revision++;
    _cache.clear();
  }

  /// 按批执行查询，并在数据发生变化时重取当前快照。
  Future<void> _flush() async {
    final pending = Map<K, Completer<V?>>.of(_pending);
    _pending.clear();
    final revision = _revision;
    try {
      final values = await load(pending.keys.toList());
      for (final entry in pending.entries) {
        if (revision != _revision) {
          entry.value.complete(await get(entry.key));
        } else {
          final value = values[entry.key];
          _cache[entry.key] = value;
          while (_cache.length > capacity) {
            _cache.remove(_cache.keys.first);
          }
          entry.value.complete(value);
        }
      }
    } catch (error, stack) {
      for (final completer in pending.values) {
        if (!completer.isCompleted) completer.completeError(error, stack);
      }
    }
  }
}
