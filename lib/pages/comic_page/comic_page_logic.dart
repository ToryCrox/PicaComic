import 'dart:async';

import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../base.dart';
import '../../foundation/history.dart';
import '../../network/download/download_model.dart';
import '../../network/download/models/download_tag.dart';
import '../comic_page.dart' show ThumbnailsData;
import 'comic_page_adapter.dart';
import 'default_comic_page_adapter.dart';

part 'comic_page_logic.g.dart';

// ============================================================================
// ComicPageState — 不可变状态
// ============================================================================

/// 漫画详情页的完整UI状态。
///
/// 使用 [copyWith] 创建部分更新的新状态。
class ComicPageState {
  final bool loading;
  final String? message; // 非null表示有错误信息
  final bool favorite;
  final History? history;
  final bool reverseEpsOrder;
  final bool showFullEps;
  final int colorIndex;
  final bool? favoriteOnPlatform;
  final bool isDownloaded;
  final List<DownloadTag> localTags;
  final List<String>? localImages;
  final String? coverPath;
  final bool showAppbarTitle;

  const ComicPageState({
    this.loading = true,
    this.message,
    this.favorite = false,
    this.history,
    this.reverseEpsOrder = false,
    this.showFullEps = false,
    this.colorIndex = 0,
    this.favoriteOnPlatform,
    this.isDownloaded = false,
    this.localTags = const [],
    this.localImages,
    this.coverPath,
    this.showAppbarTitle = false,
  });

  ComicPageState copyWith({
    bool? loading,
    String? message,
    bool? favorite,
    History? history,
    bool? reverseEpsOrder,
    bool? showFullEps,
    int? colorIndex,
    bool? favoriteOnPlatform,
    bool? isDownloaded,
    List<DownloadTag>? localTags,
    List<String>? localImages,
    String? coverPath,
    bool? showAppbarTitle,
    bool clearMessage = false,
    bool clearHistory = false,
    bool clearLocalImages = false,
    bool clearCoverPath = false,
    bool clearFavoriteOnPlatform = false,
  }) {
    return ComicPageState(
      loading: loading ?? this.loading,
      message: clearMessage ? null : (message ?? this.message),
      favorite: favorite ?? this.favorite,
      history: clearHistory ? null : (history ?? this.history),
      reverseEpsOrder: reverseEpsOrder ?? this.reverseEpsOrder,
      showFullEps: showFullEps ?? this.showFullEps,
      colorIndex: colorIndex ?? this.colorIndex,
      favoriteOnPlatform: clearFavoriteOnPlatform
          ? null
          : (favoriteOnPlatform ?? this.favoriteOnPlatform),
      isDownloaded: isDownloaded ?? this.isDownloaded,
      localTags: localTags ?? this.localTags,
      localImages: clearLocalImages ? null : (localImages ?? this.localImages),
      coverPath: clearCoverPath ? null : (coverPath ?? this.coverPath),
      showAppbarTitle: showAppbarTitle ?? this.showAppbarTitle,
    );
  }
}

// ============================================================================
// ComicPageLogic — Riverpod Notifier
// ============================================================================

/// 漫画详情页的逻辑控制器。
///
/// 通过 [(ComicType, String)] 作为 family key 进行区分：
/// - 不同漫画类型 → 不同 adapter
/// - 不同漫画ID → 不同数据
///
/// autoDispose 确保页面关闭时自动释放资源。

@Riverpod(keepAlive: false, name: 'comicPageLogicProvider')
class ComicPageLogic extends _$ComicPageLogic implements ComicPageBridge {
  // 内部可变状态（不参与Riverpod state diff）
  late final ScrollController _controller;
  late final ComicPageAdapter _adapter;
  Object? _data;
  ThumbnailsData? _thumbnailsData;

  // 保存key以便 refresh_() 使用
  (ComicType, String) _key = (ComicType.picacg, '');

  // ========================================================================
  // ComicPageBridge 实现
  // ========================================================================

  @override
  bool get favorite => state.favorite;

  @override
  set favorite(bool value) {
    state = state.copyWith(favorite: value);
  }

  @override
  bool? get favoriteOnPlatform => state.favoriteOnPlatform;

  @override
  void updateState() {
    ref.notifyListeners();
  }

  // ========================================================================
  // 公开访问器
  // ========================================================================

  /// 漫画数据（调用方负责类型转换）
  Object? get data => _data;
  ScrollController get controller => _controller;
  ComicPageAdapter get adapter => _adapter;
  ThumbnailsData? get thumbnailsData => _thumbnailsData;

  // ========================================================================
  // build — 初始化
  // ========================================================================

  @override
  ComicPageState build((ComicType, String) key) {
    _key = key;
    final (comicType, id) = key;
    _adapter =
        ComicPageAdapterRegistry.find(comicType) ??
        DefaultComicPageAdapter(comicType);

    _controller = ScrollController();
    _controller.addListener(_scrollListener);
    ref.onDispose(() => _controller.dispose());

    _load(id);
    return const ComicPageState();
  }

  // ========================================================================
  // 核心加载逻辑（缓存优先 + 并发网络）
  // ========================================================================

  Future<void> _load(String id) async {
    // 第一步：下载记录和普通磁盘缓存互不依赖，并行读取。
    final downloadId = _adapter.downloadId(id);
    final cachedDataFuture = _adapter.loadCachedData(id);
    final downloadedItem = await _loadDownloadedItem(downloadId);
    final downloaded = downloadedItem == null
        ? null
        : _adapter.dataFromDownloadedItem(downloadedItem);

    // 先提供本地封面，让加载骨架也能参与列表到详情页的 Hero 动画。
    if (downloadedItem != null && ref.mounted) {
      state = state.copyWith(coverPath: downloadedItem.coverPath);
    }

    // 磁盘缓存与本地标签互不依赖，并行读取；两者完成后再显示详情内容，
    // 既缩短首屏等待时间，也避免本地标签和删除按钮后插入布局。
    final localStateFuture = _loadLocalDownloadState(
      downloadId,
      downloaded: downloadedItem,
      hasLoadedDownloadedItem: true,
    );
    final results = await Future.wait<Object?>([
      cachedDataFuture,
      localStateFuture.then<Object?>((_) => null),
    ]);
    final cached = downloaded ?? results.first;
    if (!ref.mounted) return;
    if (cached != null) {
      _data = cached;
      // 本地状态已与缓存并行完成，可直接显示稳定的首帧内容。
      state = state.copyWith(loading: false);
      // 缓存数据加载后立即获取历史、收藏；本地缩略图可延后加载。
      _loadHistory(id);
      _loadFavorite(cached);
      unawaited(_loadLocalImages(downloadId));
    }

    // 第二步：并发加载网络数据（至少等待100ms避免闪屏）
    final res = await _adapter.loadData(id);
    if (!ref.mounted) return;
    if (res.error) {
      final msg = res.errorMessage;
      if (msg != "Exit") {
        state = state.copyWith(loading: false, message: msg);
      } else {
        state = state.copyWith(loading: false);
      }
      return;
    }

    final networkData = res.data;
    _data = networkData;
    await _syncDownloadedData(id, networkData);
    if (!ref.mounted) return;
    _loadHistory(id);
    _loadFavorite(networkData);
    await _loadLocalDownloadState(downloadId);
    if (!ref.mounted) return;
    state = state.copyWith(loading: false, clearMessage: true);
  }

  /// 从下载数据库读取详情页数据。
  Future<DownloadedItem?> _loadDownloadedItem(String downloadId) async {
    if (downloadId.isEmpty) return null;
    return downloadManager.getComicOrNull(downloadId);
  }

  /// 网络请求成功后，将最新详情同步到已有下载记录。
  Future<void> _syncDownloadedData(String id, Object data) async {
    final downloadId = _adapter.downloadId(id);
    if (downloadId.isEmpty) return;
    final original = await downloadManager.getComicOrNull(downloadId);
    if (original == null) return;
    final updated = _adapter.mergeDownloadedItem(original, data);
    if (updated == null) return;
    await downloadManager.updateDownloadedDetails(original, updated);
  }

  // ========================================================================
  // 历史记录
  // ========================================================================

  Future<void> _loadHistory(String id) async {
    final h = await HistoryManager().find(id);
    if (!ref.mounted) return;
    if (h != null) {
      state = state.copyWith(history: h);
    }
  }

  // ========================================================================
  // 收藏状态
  // ========================================================================

  Future<void> _loadFavorite(Object data) async {
    final fav = await _adapter.loadFavorite(data);
    if (!ref.mounted) return;
    state = state.copyWith(favorite: fav);
  }

  // ========================================================================
  // 本地下载标签 & 缩略图
  // ========================================================================

  /// 读取本地下载状态和标签。
  ///
  /// 该方法在详情首帧显示前调用，使相关组件一次性出现，避免布局跳动。
  Future<void> _loadLocalDownloadState(
    String downloadId, {
    DownloadedItem? downloaded,
    bool hasLoadedDownloadedItem = false,
  }) async {
    if (!hasLoadedDownloadedItem) {
      downloaded = await _loadDownloadedItem(downloadId);
    }
    if (!ref.mounted) return;
    if (downloaded == null) {
      state = state.copyWith(
        isDownloaded: false,
        localTags: const [],
        clearLocalImages: true,
        clearCoverPath: true,
      );
      return;
    }

    final tags = await downloadManager.getComicTags(downloadId);
    if (!ref.mounted) return;
    state = state.copyWith(
      isDownloaded: true,
      localTags: tags,
      coverPath: downloaded.coverPath,
    );
  }

  /// 延后读取本地缩略图，避免文件扫描阻塞详情页首帧。
  Future<void> _loadLocalImages(String downloadId) async {
    if (downloadId.isEmpty ||
        !_adapter.supportThumbnails ||
        !state.isDownloaded) {
      return;
    }
    final images = await downloadManager.getAllImageFileList(downloadId, 0);
    if (!ref.mounted || !state.isDownloaded) return;
    state = state.copyWith(localImages: images);
  }

  // ========================================================================
  // 公开方法
  // ========================================================================

  /// 刷新页面（重新加载）
  void refresh_() {
    final id = _key.$2;
    _data = null;
    _thumbnailsData = null;
    state = const ComicPageState();
    _load(id);
  }

  /// 下载被删除后立即同步页面本地状态。
  void markDownloadDeleted() {
    state = state.copyWith(
      isDownloaded: false,
      localTags: const [],
      clearLocalImages: true,
      clearCoverPath: true,
    );
  }

  /// 阅读器页面关闭后更新历史记录
  void updateHistory(History? newHistory) {
    if (newHistory != null) {
      state = state.copyWith(history: newHistory);
    }
  }

  /// 更新缩略图数据
  void initThumbnails(ThumbnailsData? td) {
    _thumbnailsData = td;
  }

  // ========================================================================
  // 滚动监听
  // ========================================================================

  void _scrollListener() {
    final show = _controller.hasClients && _controller.position.pixels > 136;
    if (state.showAppbarTitle != show) {
      state = state.copyWith(showAppbarTitle: show);
    }
  }
}
