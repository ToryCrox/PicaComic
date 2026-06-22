import 'package:flutter/material.dart';

import '../../foundation/def.dart';
import '../../foundation/history.dart';
import '../../foundation/local_favorites.dart';
import '../../network/download/models/download_tag.dart';
import '../../network/download/download_model.dart';
import '../../network/res.dart';

// 从原 comic_page.dart 引入的数据类型
import '../comic_page.dart' show EpsData, ThumbnailsData;

// ============================================================================
// ComicPageBridge — 适配器与逻辑层之间的双向通信桥梁
// ============================================================================

/// 适配器通过此桥梁读取和更新UI状态，避免与Riverpod逻辑层的循环依赖。
abstract class ComicPageBridge {
  bool get favorite;
  set favorite(bool value);
  bool? get favoriteOnPlatform;
  void updateState();
}

// ============================================================================
// ComicPageAdapter<T> — 漫画页面适配器接口
// ============================================================================

/// 每个漫画来源实现此接口，将来源特定的数据加载、元数据提取和操作封装在一起。
///
/// 类型参数 T 是该来源返回的漫画数据模型类型（如 ComicItem, Gallery 等）。
abstract class ComicPageAdapter<T extends Object> {
  // -------- A. 核心标识 --------

  /// 来源名称（用于UI展示，如 "Picacg"）
  String get source;

  /// 来源类型枚举
  ComicType get comicType;

  /// 生成唯一标识标签（用于缓存key等）
  String tag(String id);

  /// 获取下载管理器使用的ID
  String downloadId(String id);

  /// 漫画原始链接（可选）
  String? url(T data);

  // -------- B. 数据加载 --------

  /// 从网络加载漫画数据
  Future<Res<T>> loadData(String id);

  /// 从缓存加载漫画数据（返回null表示无缓存）
  Future<T?> loadCachedData(String id);

  /// 从已下载记录中提取可用于详情页的数据。
  T? dataFromDownloadedItem(DownloadedItem item) => null;

  /// 将最新网络详情合并到原下载记录，返回 null 表示该类型不支持同步。
  ///
  /// 实现必须基于 [item] 更新，只替换详情数据，保留下载章节、大小、颜色等状态。
  DownloadedItem? mergeDownloadedItem(DownloadedItem item, T data) => null;

  /// 检查是否已收藏
  Future<bool> loadFavorite(T data);

  // -------- C. 元数据提取 --------

  String? title(T data);
  String? subTitle(T data);
  String? cover(T data);
  int? pages(T data);
  String? introduction(T data);
  Map<String, List<String>>? tags(T data);
  EpsData? eps(T data, BuildContext context);
  bool? favoriteOnPlatformInitial(T data);
  bool get enableTranslationToCN => false;
  bool get supportThumbnails => true;
  ThumbnailsData? createThumbnails(T data);
  String? commentsCount(T data);
  String? likeCount(T data);

  /// 构建缩略图组件
  Widget buildThumbnailImage(
    int index,
    String imageUrl,
    BuildContext context, {
    required T data,
    List<String>? localImages,
  });

  // -------- D. 操作 --------

  void read(T data, History? history, BuildContext context);
  void download(T data, BuildContext context);
  void openFavoritePanel(T data, ComicPageBridge bridge, BuildContext context);
  ActionFunc? openComments(T data, BuildContext context);
  ActionFunc? onLike(T data, BuildContext context);
  bool isLiked(T data);
  ActionFunc? searchSimilar(T data, BuildContext context);
  void onTagTapped(String tag, String key, T data, BuildContext context);
  void onThumbnailTapped(int index, T data, BuildContext context);

  // -------- E. 自定义UI片段 & 转换 --------

  Widget? buildRecommendation(T data, BuildContext context);
  Card? buildUploaderInfo(T data, BuildContext context);
  Widget? buildMoreInfo(T data, BuildContext context);

  /// 额外的操作按钮（在阅读/收藏/下载按钮之后）
  List<Widget>? buildExtraActionButtons(
    T data,
    BuildContext context,
    Widget Function(
      BuildContext,
      String,
      IconData,
      VoidCallback, [
      VoidCallback?,
    ])
    buildActionItem,
  );

  /// 转换为本地收藏项
  FavoriteItem toLocalFavoriteItem(T data);
}

// ============================================================================
// ComicPageAdapterRegistry — 适配器注册表
// ============================================================================

class ComicPageAdapterRegistry {
  static final Map<ComicType, dynamic> _adapters = {};

  static void register(dynamic adapter) {
    _adapters[(adapter as ComicPageAdapter).comicType] = adapter;
  }

  static ComicPageAdapter? find(ComicType comicType) =>
      _adapters[comicType] as ComicPageAdapter?;

  static void registerAll() {
    // 适配器注册在 Step 5 完成
  }
}
