import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:pica_comic/base.dart';
import 'package:pica_comic/network/download/download_model.dart';
import 'package:pica_comic/network/download/models/download_tag.dart';
import 'package:pica_comic/tools/extensions.dart';
import 'package:pica_comic/tools/tags_translation.dart';
import 'components/download_tile.dart';

part 'download_providers.g.dart';

// ============================================================================
// 全局数据层 (Global Persistent State)
// ============================================================================

/// 所有已下载漫画的唯一真相源 (Single Source of Truth)
///
/// 直接对接 DownloadManager，无论打开多少个下载页面，都共享这一份数据。
/// 通过监听 DownloadManager.onComicsChanged 流来自动刷新。
@Riverpod(keepAlive: true)
class AllDownloadedComics extends _$AllDownloadedComics {
  StreamSubscription<void>? _subscription;

  @override
  Future<List<DownloadedItem>> build() async {
    _subscription?.cancel();
    _subscription = downloadManager.onComicsChanged.listen((_) {
      _refresh();
    });

    ref.onDispose(() {
      _subscription?.cancel();
    });

    return _loadComics();
  }

  Future<List<DownloadedItem>> _loadComics() async {
    return await downloadManager.getAll('time', 'desc');
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

/// 下载状态枚举
enum DownloadStatus {
  downloading,
  waiting,
  paused, // 所有的暂停状态（包括暂停中/等待中但管理器暂停）
}

/// 正在下载/等待/暂停的漫画状态 Provider (Map<String, DownloadStatus>)
///
/// 监听 DownloadManager 的状态变化，提供当前任务的状态映射。
@Riverpod(keepAlive: true)
class DownloadingItems extends _$DownloadingItems {
  @override
  Map<String, DownloadStatus> build() {
    downloadManager.addListener(_update);
    ref.onDispose(() {
      downloadManager.removeListener(_update);
    });
    return _computeStatus();
  }

  Map<String, DownloadStatus> _computeStatus() {
    final Map<String, DownloadStatus> statusMap = {};

    final runningIds = downloadManager.runningTaskIds;
    final waitingIds = downloadManager.waitingTaskIds;
    final isManagerDownloading = downloadManager.isDownloading;

    if (!isManagerDownloading) {
      for (var id in runningIds) {
        statusMap[id] = DownloadStatus.paused;
      }
      for (var id in waitingIds) {
        statusMap[id] = DownloadStatus.paused;
      }
    } else {
      for (var id in runningIds) {
        statusMap[id] = DownloadStatus.downloading;
      }
      for (var id in waitingIds) {
        statusMap[id] = DownloadStatus.waiting;
      }
    }

    return statusMap;
  }

  void _update() {
    final statusMap = _computeStatus();

    if (!mapEquals(state, statusMap)) {
      state = statusMap;
    }
  }
}

/// 已下载漫画ID集合 Provider (Set<String>)
///
/// 用于 O(1) 快速查找漫画是否已下载。
@Riverpod(keepAlive: true)
Set<String> downloadedIds(Ref ref) {
  final comicsAsync = ref.watch(allDownloadedComicsProvider);

  return comicsAsync.when(
    data: (comics) {
      final ids = <String>{};
      for (var comic in comics) {
        ids.add(comic.id);
      }
      return ids;
    },
    error: (_, __) => const {},
    loading: () => const {},
  );
}

/// 所有标签的唯一真相源 (Single Source of Truth)
///
/// 直接对接 DownloadManager，通过监听 onTagsChanged 流来自动刷新。
/// 避免每次漫画列表变化时重复调用数据库加载标签。
@Riverpod(keepAlive: true)
class AllTags extends _$AllTags {
  StreamSubscription<void>? _subscription;

  @override
  Future<List<DownloadTag>> build() async {
    _subscription?.cancel();
    _subscription = downloadManager.onTagsChanged.listen((_) {
      _refresh();
    });

    ref.onDispose(() {
      _subscription?.cancel();
    });

    return await downloadManager.getAllTags();
  }

  Future<void> _refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => downloadManager.getAllTags());
  }

  /// 手动刷新，供外部调用
  Future<void> refresh() async {
    await _refresh();
  }
}

/// 标签数据 Provider（包含封面路径等计算后的信息）
@Riverpod(keepAlive: false)
Future<List<TagInfo>> downloadTags(Ref ref) async {
  final allComics = await ref.watch(allDownloadedComicsProvider.future);

  final allTags = await ref.watch(allTagsProvider.future);

  final List<TagInfo> tagInfos = [];

  for (final tag in allTags) {
    String? coverPath;
    if (tag.coverComicId != null) {
      coverPath = allComics
          .firstWhereOrNull((c) => c.id == tag.coverComicId)
          ?.coverPath;
    }

    tagInfos.add(
      TagInfo(
        id: tag.id,
        name: tag.name,
        comicCount: 0,
        category: tag.category.value,
        sortOrder: tag.sortOrder,
        categorySortOrder: tag.categorySortOrder,
        coverPath: coverPath,
      ),
    );
  }

  tagInfos.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  return tagInfos;
}

/// 漫画用户标签映射 Provider
///
/// Map<ComicId, List<TagName>>
/// 监听 onTagsChanged 流来精确刷新，不会触发漫画列表重新加载
@Riverpod(keepAlive: false)
class ComicUserTags extends _$ComicUserTags {
  StreamSubscription<void>? _tagsSubscription;

  @override
  Future<Map<String, List<String>>> build() async {
    _tagsSubscription?.cancel();
    _tagsSubscription = downloadManager.onTagsChanged.listen((_) {
      _refresh();
    });

    ref.onDispose(() {
      _tagsSubscription?.cancel();
    });

    return await downloadManager.getAllComicTagsMap();
  }

  Future<void> _refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => downloadManager.getAllComicTagsMap());
  }

  /// 手动刷新，供外部调用
  Future<void> refresh() async {
    await _refresh();
  }
}

// ============================================================================
// 实例状态层 (Instance Ephemeral State)
// ============================================================================

class DownloadPageState {
  /// 搜索关键词
  final String keyword;

  /// 是否处于选择模式
  final bool isSelecting;

  /// 选中的漫画ID集合
  final Set<String> selectedIds;

  /// 标签筛选
  final Set<int> selectedTagIds;

  /// 标签分类筛选
  final int? tagCategoryFilter;

  /// 下载类型筛选
  final DownloadType? downloadTypeFilter;

  /// 排除本地
  final bool excludeLocal;

  /// 排序版本号（用于触发排序更新）
  final int sortVersion;

  /// 是否处于搜索模式
  final bool isSearching;

  /// 是否禁用拖动
  final bool isDragDisabled;

  const DownloadPageState({
    this.keyword = '',
    this.isSelecting = false,
    this.selectedIds = const {},
    this.selectedTagIds = const {},
    this.tagCategoryFilter,
    this.downloadTypeFilter,
    this.excludeLocal = false,
    this.sortVersion = 0,
    this.isSearching = false,
    this.isDragDisabled = true,
  });

  DownloadPageState copyWith({
    String? keyword,
    bool? isSelecting,
    Set<String>? selectedIds,
    Set<int>? selectedTagIds,
    int? tagCategoryFilter,
    bool clearTagCategoryFilter = false,
    DownloadType? downloadTypeFilter,
    bool? excludeLocal,
    bool clearDownloadTypeFilter = false,
    int? sortVersion,
    bool? isSearching,
    bool? isDragDisabled,
  }) {
    return DownloadPageState(
      keyword: keyword ?? this.keyword,
      isSelecting: isSelecting ?? this.isSelecting,
      selectedIds: selectedIds ?? this.selectedIds,
      selectedTagIds: selectedTagIds ?? this.selectedTagIds,
      tagCategoryFilter: clearTagCategoryFilter
          ? null
          : (tagCategoryFilter ?? this.tagCategoryFilter),
      downloadTypeFilter: clearDownloadTypeFilter
          ? null
          : (downloadTypeFilter ?? this.downloadTypeFilter),
      excludeLocal: excludeLocal ?? this.excludeLocal,
      sortVersion: sortVersion ?? this.sortVersion,
      isSearching: isSearching ?? this.isSearching,
      isDragDisabled: isDragDisabled ?? this.isDragDisabled,
    );
  }
}

/// 下载页面实例状态 Provider
///
/// 使用 family 实现每个页面独立的状态。
/// 使用 autoDispose 在页面关闭时自动释放。
/// 通过 build 方法的 pageId 参数生成 family provider。
@Riverpod(keepAlive: false, name: 'downloadPageStateProvider')
class DownloadPageStateNotifier extends _$DownloadPageStateNotifier {
  @override
  DownloadPageState build(String pageId) => const DownloadPageState();

  void update(DownloadPageState Function(DownloadPageState) updater) {
    state = updater(state);
  }
}

// ============================================================================
// 实例状态操作辅助函数 (Adapters)
// ============================================================================

/// 更新搜索关键词
void updateKeyword(WidgetRef ref, String pageId, String keyword) {
  ref.read(downloadPageStateProvider(pageId).notifier).update((state) {
    return state.copyWith(
      keyword: keyword,
      isSearching: keyword.isNotEmpty ? true : state.isSearching,
    );
  });
}

/// 进入选择模式
void enterSelecting(WidgetRef ref, String pageId) {
  ref.read(downloadPageStateProvider(pageId).notifier).update((state) {
    return state.copyWith(isSelecting: true, isSearching: false);
  });
}

/// 切换搜索模式
void setIsSearching(WidgetRef ref, String pageId, bool isSearching) {
  ref.read(downloadPageStateProvider(pageId).notifier).update((state) {
    return state.copyWith(
      isSearching: isSearching,
      keyword: isSearching ? state.keyword : '',
    );
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
///
/// 同类别只能选一个标签，不同类别可以多选
void updateTagFilter(WidgetRef ref, String pageId, int? tagId) {
  // 获取所有标签信息以便判断类别
  final tagsAsync = ref.read(downloadTagsProvider);
  final allTags = tagsAsync.value ?? [];

  ref.read(downloadPageStateProvider(pageId).notifier).update((state) {
    if (tagId == null) {
      return state.copyWith(selectedTagIds: {});
    }

    // 获取要选择的标签的类别
    final tagInfo = allTags.firstWhere(
      (t) => t.id == tagId,
      orElse: () => TagInfo(id: tagId, name: '', comicCount: 0),
    );
    final tagCategory = tagInfo.category;

    final newIds = Set<int>.from(state.selectedTagIds);

    // 如果已选中该标签，则取消选择
    if (newIds.contains(tagId)) {
      newIds.remove(tagId);
    } else {
      // 移除同类的其他标签
      newIds.removeWhere((id) {
        final existingTag = allTags.firstWhere(
          (t) => t.id == id,
          orElse: () => TagInfo(id: id, name: '', comicCount: 0, category: -1),
        );
        return existingTag.category == tagCategory;
      });
      // 添加新标签
      newIds.add(tagId);
    }

    return state.copyWith(selectedTagIds: newIds);
  });
}

/// 更新标签分类筛选
void updateTagCategoryFilter(WidgetRef ref, String pageId, int? category) {
  ref.read(downloadPageStateProvider(pageId).notifier).update((state) {
    if (category == null || category == state.tagCategoryFilter) {
      return state.copyWith(clearTagCategoryFilter: true);
    }
    return state.copyWith(tagCategoryFilter: category);
  });
}

/// 更新下载类型筛选
///
/// 选择特定类型时会自动取消"排除本地"选项
void updateDownloadTypeFilter(
  WidgetRef ref,
  String pageId,
  DownloadType? type,
) {
  ref.read(downloadPageStateProvider(pageId).notifier).update((state) {
    if (type == state.downloadTypeFilter) {
      return state.copyWith(clearDownloadTypeFilter: true);
    } else {
      // 选择特定类型时，取消排除本地选项
      return state.copyWith(downloadTypeFilter: type, excludeLocal: false);
    }
  });
}

/// 更新排除本地筛选
///
/// 启用"排除本地"时会自动取消特定类型选择
void updateExcludeLocal(WidgetRef ref, String pageId, bool exclude) {
  ref.read(downloadPageStateProvider(pageId).notifier).update((state) {
    if (exclude) {
      // 启用排除本地时，取消特定类型选择
      return state.copyWith(
        excludeLocal: exclude,
        clearDownloadTypeFilter: true,
      );
    }
    return state.copyWith(excludeLocal: exclude);
  });
}

/// 切换拖动禁用状态
void toggleDragDisabled(WidgetRef ref, String pageId) {
  ref.read(downloadPageStateProvider(pageId).notifier).update((state) {
    return state.copyWith(isDragDisabled: !state.isDragDisabled);
  });
}

// ============================================================================
// 辅助函数
// ============================================================================

/// 触发排序更新
///
/// 通过增加 sortVersion 来触发 filteredComicsProvider 重新计算
void triggerSortUpdate(WidgetRef ref, String pageId) {
  ref.read(downloadPageStateProvider(pageId).notifier).update((state) {
    final currentVersion = state.sortVersion;
    return state.copyWith(sortVersion: currentVersion + 1);
  });
}

/// 在内存中对漫画列表进行排序
///
/// 根据 appdata.settings[26] 的设置进行排序，避免每次排序变化都从数据库重新读取
List<DownloadedItem> _sortComics(List<DownloadedItem> comics) {
  if (comics.isEmpty) return comics;

  final sortType = appdata.settings[26][0]; // 0:时间, 1:标题, 2:副标题, 3:大小
  final isAscending = appdata.settings[26][1] == "1";

  final sorted = List<DownloadedItem>.from(comics);

  sorted.sort((a, b) {
    int result;
    switch (sortType) {
      case "1": // 标题
        result = a.name.compareTo(b.name);
        break;
      case "2": // 副标题
        result = a.subTitle.compareTo(b.subTitle);
        break;
      case "3": // 大小
        result = (a.comicSize ?? 0).compareTo(b.comicSize ?? 0);
        break;
      case "0": // 时间（默认）
      default:
        final aTime = a.time ?? DateTime(1970);
        final bTime = b.time ?? DateTime(1970);
        result = aTime.compareTo(bTime);
        break;
    }
    return isAscending ? result : -result;
  });

  return sorted;
}

// ============================================================================
// 衍生计算层 (Computed State)
// ============================================================================

/// 过滤后的漫画列表 Provider
///
/// 同时监听全局数据层和实例状态层，精确计算当前页面应显示的漫画列表。
@Riverpod(keepAlive: false)
Future<List<DownloadedItem>> filteredComics(Ref ref, String pageId) async {
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

  // 标签分类过滤：只筛选拥有该分类自定义标签的漫画
  if (pageState.tagCategoryFilter != null) {
    final categoryTagNames = allTags
        .where((tag) => tag.category == pageState.tagCategoryFilter)
        .map((tag) => tag.name)
        .toSet();

    if (categoryTagNames.isNotEmpty) {
      filtered = filtered.where((comic) {
        final comicTags = getUserTags(comic, userTagsMap);
        return comicTags.any(categoryTagNames.contains);
      }).toList();
    } else {
      filtered = [];
    }
  }

  // 标签过滤
  if (pageState.selectedTagIds.isNotEmpty) {
    final selectedTagNames = pageState.selectedTagIds
        .map((id) {
          return allTags.firstWhereOrNull((element) => element.id == id)?.name;
        })
        .whereType<String>()
        .toSet();

    if (selectedTagNames.isNotEmpty) {
      filtered = filtered.where((comic) {
        final comicTags = getUserTags(comic, userTagsMap);
        return selectedTagNames.every((tagName) => comicTags.contains(tagName));
      }).toList();
    } else {
      filtered = [];
    }
  }

  // 在内存中进行排序（避免每次排序变化都从数据库重新读取）
  final sortResult = _sortComics(filtered);

  return sortResult;
}

/// 选中数量 Provider (用于精确刷新标题栏)
@Riverpod(keepAlive: false)
int selectedCount(Ref ref, String pageId) {
  return ref.watch(
    downloadPageStateProvider(
      pageId,
    ).select((state) => state.selectedIds.length),
  );
}

/// 已下载漫画摘要 Provider (Count, TotalSize)
@Riverpod(keepAlive: false)
Future<String> downloadedComicsSummary(Ref ref, String pageId) async {
  final comics = await ref.watch(filteredComicsProvider(pageId).future);

  double totalSizeMB = 0;
  for (var comic in comics) {
    totalSizeMB += comic.comicSize ?? 0;
  }

  String sizeStr;
  if (totalSizeMB > 1024) {
    sizeStr = "${(totalSizeMB / 1024).toStringAsFixed(2)}GB";
  } else {
    sizeStr = "${totalSizeMB.toStringAsFixed(2)}MB";
  }

  return "(${comics.length}, $sizeStr)";
}

/// 过滤后的标签列表 Provider (用于标签筛选面板)
///
/// 根据当前过滤后的漫画列表，统计标签出现次数并排序
@Riverpod(keepAlive: false)
Future<List<TagInfo>> filteredTags(Ref ref, String pageId) async {
  final filteredComics = await ref.watch(filteredComicsProvider(pageId).future);
  final allTags = await ref.watch(downloadTagsProvider.future);
  final comicUserTags = await ref.watch(comicUserTagsProvider.future);
  final pageState = ref.watch(downloadPageStateProvider(pageId));

  // check if filtering
  bool isFiltering =
      pageState.keyword.isNotEmpty ||
      pageState.downloadTypeFilter != null ||
      pageState.excludeLocal ||
      pageState.tagCategoryFilter != null ||
      pageState.selectedTagIds.isNotEmpty;

  List<TagInfo> applyCategoryFilter(List<TagInfo> tags) {
    if (pageState.tagCategoryFilter == null) return tags;
    return tags.where((tag) {
      return tag.category == pageState.tagCategoryFilter;
    }).toList();
  }

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
          final tagInfo = allTags.firstWhereOrNull((t) => t.id == e.key);
          return tagInfo?.copyWith(comicCount: e.value);
        })
        .whereType<TagInfo>()
        .toList();

    tags.sort((a, b) => b.comicCount.compareTo(a.comicCount));
    tags = applyCategoryFilter(tags);

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

    tags = applyCategoryFilter(tags);

    if (tags.length > 20) {
      tags = tags.sublist(0, 20);
    }
  }

  return tags;
}

// ============================================================================
// 标签处理辅助函数
// ============================================================================

List<String> getUserTags(
  DownloadedItem item,
  Map<String, List<String>> userTagsMap,
) {
  return userTagsMap[item.id] ?? [];
}

List<String> getOriginalTags(
  DownloadedItem item,
  Map<String, List<String>> userTagsMap,
) {
  final userTags = getUserTags(item, userTagsMap);
  final originalTags = item.tags.map((e) => e.translateTagsToCN);
  if (userTags.isEmpty) {
    return originalTags.toList();
  } else {
    return originalTags.where((e) => !userTags.contains(e)).toList();
  }
}

List<String> getRawTags(
  DownloadedItem item,
  Map<String, List<String>> userTagsMap,
) {
  final userTags = getUserTags(item, userTagsMap);
  if (userTags.isEmpty) {
    return item.tags.toList();
  } else {
    return item.tags
        .where((e) => !userTags.contains(e.translateTagsToCN))
        .toList();
  }
}
