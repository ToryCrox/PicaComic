/// 存储提交后的变更；keys 为 null 表示所有记录失效，空集合表示仅目录元数据变化。
class RepositoryChange<K> {
  RepositoryChange({
    Set<K>? keys,
    Set<String> folders = const {},
    this.foldersChanged = false,
    this.removed = false,
    this.previousName,
    this.currentName,
  }) : keys = keys == null ? null : Set.unmodifiable(keys),
       folders = Set.unmodifiable(folders);

  final Set<K>? keys;
  final Set<String> folders;
  final bool foldersChanged;
  final bool removed;
  final String? previousName;
  final String? currentName;

  /// 判断单条查询是否需要重取。
  bool affects(K key) => keys == null || keys!.contains(key);
}
