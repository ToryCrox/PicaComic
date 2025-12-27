import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:pica_comic/network/download/download_manager.dart';
import 'package:pica_comic/network/download/download_model.dart';
import 'package:pica_comic/tools/tags_translation.dart';
import 'components/download_tile.dart';

// ============================================================================
// 全局数据层 (Global Persistent State)
// ============================================================================

/// 所有已下载漫画的唯一真相源 (Single Source of Truth)
///
/// 直接对接 DownloadManager，无论打开多少个下载页面，都共享这一份数据。
/// 通过监听 DownloadManager.onComicsChanged 流来自动刷新。
final allDownloadedComicsProvider =
    AsyncNotifierProvider<AllDownloadedComicsNotifier, List<DownloadedItem>>(
  AllDownloadedComicsNotifier.new,
);

class AllDownloadedComicsNotifier extends AsyncNotifier<List<DownloadedItem>> {
  StreamSubscription<void>? _subscription;

  @override
  Future<List<DownloadedItem>> build() async {
    // 监听 DownloadManager 的变更通知
    _subscription?.cancel();
    _subscription = DownloadManager().onComicsChanged.listen((_) {
      _refresh();
    });

    // 当 Provider 被销毁时取消订阅
    ref.onDispose(() {
      _subscription?.cancel();
    });

    // 初始加载数据
    return _loadComics();
  }

  Future<List<DownloadedItem>> _loadComics() async {
    // 使用默认排序加载所有漫画
    return await DownloadManager().getAll('time', 'desc');
  }

  Future<void> _refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _loadComics());
  }

  /// 手动刷新，供外部调用
  Future<void> refresh() async {
    await _refresh();
  }
}

/// 标签数据 Provider
final downloadTagsProvider =
    FutureProvider.autoDispose<List<TagInfo>>((ref) async {
  // 监听已下载漫画的变化，重新计算标签信息（如封面）
  final allComics = await ref.watch(allDownloadedComicsProvider.future);

  final allTags = await DownloadManager().getAllTags();

  final List<TagInfo> tagInfos = [];

  for (final tag in allTags) {
    String? coverPath;
    if (tag.coverComicId != null) {
      try {
        final comic = allComics.firstWhere((c) => c.id == tag.coverComicId);
        coverPath = comic.coverPath;
      } catch (e) {
        // finding comic failed
      }
    }

    tagInfos.add(TagInfo(
      id: tag.id,
      name: tag.name,
      comicCount: 0, // 初始为0，具体数量通常在过滤时计算或不显示
      category: tag.category.value,
      sortOrder: tag.sortOrder,
      categorySortOrder: tag.categorySortOrder,
      coverPath: coverPath,
    ));
  }

  tagInfos.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  return tagInfos;
});

/// 漫画用户标签映射 Provider
///
/// Map<ComicId, List<TagName>>
/// 监听 onTagsChanged 流来精确刷新，不会触发漫画列表重新加载
final comicUserTagsProvider = AsyncNotifierProvider.autoDispose<
    ComicUserTagsNotifier, Map<String, List<String>>>(
  ComicUserTagsNotifier.new,
);

class ComicUserTagsNotifier
    extends AutoDisposeAsyncNotifier<Map<String, List<String>>> {
  StreamSubscription<void>? _tagsSubscription;

  @override
  Future<Map<String, List<String>>> build() async {
    // 监听 DownloadManager 的标签变更通知
    _tagsSubscription?.cancel();
    _tagsSubscription = DownloadManager().onTagsChanged.listen((_) {
      _refresh();
    });

    // 当 Provider 被销毁时取消订阅
    ref.onDispose(() {
      _tagsSubscription?.cancel();
    });

    // 初始加载数据
    return await DownloadManager().getAllComicTagsMap();
  }

  Future<void> _refresh() async {
    state = const AsyncValue.loading();
    state =
        await AsyncValue.guard(() => DownloadManager().getAllComicTagsMap());
  }

  /// 手动刷新，供外部调用
  Future<void> refresh() async {
    await _refresh();
  }
}

// ============================================================================
// 实例状态层 (Instance Ephemeral State)
// ============================================================================

/// 下载页面的实例状态
class DownloadPageState {
  /// 搜索关键词
  final String keyword;

  /// 是否处于选择模式
  final bool isSelecting;

  /// 选中的漫画ID集合
  final Set<String> selectedIds;

  /// 标签筛选
  final Set<int> selectedTagIds;

  /// 下载类型筛选
  final DownloadType? downloadTypeFilter;

  /// 排除本地
  final bool excludeLocal;

  const DownloadPageState({
    this.keyword = '',
    this.isSelecting = false,
    this.selectedIds = const {},
    this.selectedTagIds = const {},
    this.downloadTypeFilter,
    this.excludeLocal = false,
  });

  DownloadPageState copyWith({
    String? keyword,
    bool? isSelecting,
    Set<String>? selectedIds,
    Set<int>? selectedTagIds,
    DownloadType? downloadTypeFilter,
    bool? excludeLocal,
    bool clearDownloadTypeFilter = false,
  }) {
    return DownloadPageState(
      keyword: keyword ?? this.keyword,
      isSelecting: isSelecting ?? this.isSelecting,
      selectedIds: selectedIds ?? this.selectedIds,
      selectedTagIds: selectedTagIds ?? this.selectedTagIds,
      downloadTypeFilter: clearDownloadTypeFilter
          ? null
          : (downloadTypeFilter ?? this.downloadTypeFilter),
      excludeLocal: excludeLocal ?? this.excludeLocal,
    );
  }
}

/// 下载页面实例状态 Provider
///
/// 使用 StateProvider.family 实现每个页面独立的状态。
/// 使用 autoDispose 在页面关闭时自动释放。
final downloadPageStateProvider =
    StateProvider.autoDispose.family<DownloadPageState, String>((ref, pageId) {
  return const DownloadPageState();
});

// ============================================================================
// 实例状态操作辅助函数 (Adapters)
// ============================================================================

/// 更新搜索关键词
void updateKeyword(WidgetRef ref, String pageId, String keyword) {
  ref.read(downloadPageStateProvider(pageId).notifier).update((state) {
    return state.copyWith(keyword: keyword);
  });
}

/// 进入选择模式
void enterSelecting(WidgetRef ref, String pageId) {
  ref.read(downloadPageStateProvider(pageId).notifier).update((state) {
    return state.copyWith(isSelecting: true);
  });
}

/// 退出选择模式
void exitSelecting(WidgetRef ref, String pageId) {
  ref.read(downloadPageStateProvider(pageId).notifier).update((state) {
    return state.copyWith(isSelecting: false, selectedIds: {});
  });
}

/// 切换选择
void toggleSelection(WidgetRef ref, String pageId, String id) {
  ref.read(downloadPageStateProvider(pageId).notifier).update((state) {
    final newIds = Set<String>.from(state.selectedIds);
    if (newIds.contains(id)) {
      newIds.remove(id);
    } else {
      newIds.add(id);
    }
    return state.copyWith(selectedIds: newIds);
  });
}

/// 全选
void selectAll(WidgetRef ref, String pageId, List<String> ids) {
  ref.read(downloadPageStateProvider(pageId).notifier).update((state) {
    return state.copyWith(selectedIds: ids.toSet());
  });
}

/// 清除选择
void clearSelection(WidgetRef ref, String pageId) {
  ref.read(downloadPageStateProvider(pageId).notifier).update((state) {
    return state.copyWith(selectedIds: {});
  });
}

/// 更新标签筛选
void updateTagFilter(WidgetRef ref, String pageId, int? tagId) {
  ref.read(downloadPageStateProvider(pageId).notifier).update((state) {
    if (tagId == null) {
      return state.copyWith(selectedTagIds: {});
    }
    final newIds = Set<int>.from(state.selectedTagIds);
    if (newIds.contains(tagId)) {
      newIds.remove(tagId);
    } else {
      newIds.add(tagId);
    }
    return state.copyWith(selectedTagIds: newIds);
  });
}

/// 更新下载类型筛选
void updateDownloadTypeFilter(
    WidgetRef ref, String pageId, DownloadType? type) {
  ref.read(downloadPageStateProvider(pageId).notifier).update((state) {
    if (type == state.downloadTypeFilter) {
      return state.copyWith(clearDownloadTypeFilter: true);
    } else {
      return state.copyWith(downloadTypeFilter: type);
    }
  });
}

/// 更新排除本地筛选
void updateExcludeLocal(WidgetRef ref, String pageId, bool exclude) {
  ref.read(downloadPageStateProvider(pageId).notifier).update((state) {
    return state.copyWith(excludeLocal: exclude);
  });
}

// ============================================================================
// 衍生计算层 (Computed State)
// ============================================================================

/// 过滤后的漫画列表 Provider
///
/// 同时监听全局数据层和实例状态层，精确计算当前页面应显示的漫画列表。
final filteredComicsProvider = FutureProvider.autoDispose
    .family<List<DownloadedItem>, String>((ref, pageId) async {
  final comics = await ref.watch(allDownloadedComicsProvider.future);
  final userTagsMap = await ref.watch(comicUserTagsProvider.future);
  final allTags = await ref.watch(downloadTagsProvider.future);
  final pageState = ref.watch(downloadPageStateProvider(pageId));

  var filtered = comics;

  // 关键词过滤
  if (pageState.keyword.isNotEmpty) {
    final keyword = pageState.keyword.toLowerCase();
    filtered = filtered.where((comic) {
      // 1. Title & Subtitle
      if (comic.name.toLowerCase().contains(keyword) ||
          comic.subTitle.toLowerCase().contains(keyword)) {
        return true;
      }

      // 2. Tags (Translated)
      final tags = comic.tags.map((e) => e.translateTagsToCN.toLowerCase());
      if (tags.any((e) => e.contains(keyword))) {
        return true;
      }

      // 3. User Tags
      final userTags = getUserTags(comic, userTagsMap);
      if (userTags.any((e) => e.toLowerCase().contains(keyword))) {
        return true;
      }

      return false;
    }).toList();
  }

  // 下载类型过滤
  if (pageState.downloadTypeFilter != null) {
    filtered = filtered.where((comic) {
      return comic.type == pageState.downloadTypeFilter;
    }).toList();
  }

  // 排除本地
  if (pageState.excludeLocal) {
    filtered = filtered.where((comic) {
      return comic.type != DownloadType.local;
    }).toList();
  }

  // 标签过滤
  if (pageState.selectedTagIds.isNotEmpty) {
    final selectedTagNames = pageState.selectedTagIds.map((id) {
      try {
        return allTags.firstWhere((element) => element.id == id).name;
      } catch (e) {
        return null; // 标签可能已被删除
      }
    }).whereType<String>().toSet();

    if (selectedTagNames.isNotEmpty) {
      filtered = filtered.where((comic) {
        final comicTags = getUserTags(comic, userTagsMap);
        return selectedTagNames.every((tagName) => comicTags.contains(tagName));
      }).toList();
    } else {
      filtered = [];
    }
  }

  return filtered;
});

/// 选中数量 Provider (用于精确刷新标题栏)
final selectedCountProvider =
    Provider.autoDispose.family<int, String>((ref, pageId) {
  return ref.watch(
    downloadPageStateProvider(pageId)
        .select((state) => state.selectedIds.length),
  );
});

/// 已下载漫画摘要 Provider (Count, TotalSize)
final downloadedComicsSummaryProvider =
    FutureProvider.autoDispose.family<String, String>((ref, pageId) async {
  final comics = await ref.watch(filteredComicsProvider(pageId).future);

  double totalSizeMB = 0;
  for (var comic in comics) {
    // comic.comicSize within DB is usually in MB, or null.
    // If implementation varies, we assume standard double MB here.
    totalSizeMB += comic.comicSize ?? 0;
  }

  String sizeStr;
  if (totalSizeMB > 1024) {
    sizeStr = "${(totalSizeMB / 1024).toStringAsFixed(2)}GB";
  } else {
    sizeStr = "${totalSizeMB.toStringAsFixed(2)}MB";
  }

  return "(${comics.length}, $sizeStr)";
});

/// 过滤后的标签列表 Provider (用于标签筛选面板)
///
/// 根据当前过滤后的漫画列表，统计标签出现次数并排序
final filteredTagsProvider = FutureProvider.autoDispose
    .family<List<TagInfo>, String>((ref, pageId) async {
  final filteredComics = await ref.watch(filteredComicsProvider(pageId).future);
  final allTags = await ref.watch(downloadTagsProvider.future);
  final comicUserTags = await ref.watch(comicUserTagsProvider.future);
  final pageState = ref.read(downloadPageStateProvider(pageId));

  // check if filtering
  bool isFiltering = pageState.keyword.isNotEmpty ||
      pageState.downloadTypeFilter != null ||
      pageState.excludeLocal ||
      pageState.selectedTagIds.isNotEmpty;

  List<TagInfo> tags;
  if (isFiltering && filteredComics.isNotEmpty) {
    final tagCountMap = <int, int>{};
    final tagNameToIdMap = <String, int>{};
    for (final tag in allTags) {
      tagNameToIdMap[tag.name] = tag.id;
    }

    for (final comic in filteredComics) {
      final userTagNames = getUserTags(comic, comicUserTags);
      for (final tagName in userTagNames) {
        final tagId = tagNameToIdMap[tagName];
        if (tagId != null) {
          tagCountMap[tagId] = (tagCountMap[tagId] ?? 0) + 1;
        }
      }

      // original tags
      for (final tag in comic.tags) {
        final tagName = tag.translateTagsToCN;
        final tagId = tagNameToIdMap[tagName];
        if (tagId != null) {
          tagCountMap[tagId] = (tagCountMap[tagId] ?? 0) + 1;
        }
      }
    }

    tags = tagCountMap.entries
        .map((e) {
          try {
            final tagInfo = allTags.firstWhere((t) => t.id == e.key);
            return tagInfo.copyWith(comicCount: e.value);
          } catch (e) {
            return null;
          }
        })
        .whereType<TagInfo>()
        .toList();

    tags.sort((a, b) => b.comicCount.compareTo(a.comicCount));

    if (tags.length > 20) {
      tags = tags.sublist(0, 20);
    }
  } else {
    tags = List.from(allTags);
    // 如果有选中的标签，将它们移到前面
    if (pageState.selectedTagIds.isNotEmpty) {
      final selectedTags = <TagInfo>[];
      final unselectedTags = <TagInfo>[];
      for (final tag in tags) {
        if (pageState.selectedTagIds.contains(tag.id)) {
          selectedTags.add(tag);
        } else {
          unselectedTags.add(tag);
        }
      }
      tags = [...selectedTags, ...unselectedTags];
    }

    if (tags.length > 20) {
      tags = tags.sublist(0, 20);
    }
  }
  return tags;
});

// ============================================================================
// 标签处理辅助函数
// ============================================================================

List<String> getUserTags(
    DownloadedItem item, Map<String, List<String>> userTagsMap) {
  return userTagsMap[item.id] ?? [];
}

List<String> getOriginalTags(
    DownloadedItem item, Map<String, List<String>> userTagsMap) {
  final userTags = getUserTags(item, userTagsMap);
  final originalTags = item.tags.map((e) => e.translateTagsToCN);
  if (userTags.isEmpty) {
    return originalTags.toList();
  } else {
    return originalTags.where((e) => !userTags.contains(e)).toList();
  }
}

List<String> getRawTags(
    DownloadedItem item, Map<String, List<String>> userTagsMap) {
  final userTags = getUserTags(item, userTagsMap);
  if (userTags.isEmpty) {
    return item.tags.toList();
  } else {
    return item.tags
        .where((e) => !userTags.contains(e.translateTagsToCN))
        .toList();
  }
}
