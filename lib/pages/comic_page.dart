import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'favorites/favorite_panel_providers.dart';
import 'favorites/local_favorites_providers.dart';
import 'favorites/network_favorites_providers.dart';

import 'package:pica_comic/base.dart';
import 'package:pica_comic/comic_source/comic_chapter_group.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/foundation/def.dart';
import 'package:pica_comic/foundation/history.dart';
import 'package:pica_comic/foundation/local_favorites.dart';
import 'package:pica_comic/foundation/log.dart';
import 'package:pica_comic/network/res.dart';
import 'package:pica_comic/pages/comic_page/comic_page_widget.dart';
import 'package:pica_comic/pages/favorites/local_favorites.dart';
import 'package:pica_comic/tools/translations.dart';

/// 漫画详情页入口。
///
/// 旧实现已经迁移到 [ComicPageWidget]，此类保留为统一路由入口和旧代码兼容层。
class ComicPage extends StatelessWidget {
  const ComicPage({
    super.key,
    required this.comicType,
    required this.id,
    this.cover,
  });

  final ComicType comicType;
  final String id;
  final String? cover;

  @override
  Widget build(BuildContext context) {
    return ComicPageWidget(comicType: comicType, id: id, cover: cover);
  }
}

/// 章节列表数据。
class EpsData {
  /// 章节标题。
  final List<String> eps;

  /// 点击章节时触发。
  final void Function(int) onTap;

  final List<ComicChapterGroup> groups;
  final List<String> chapterIds;

  const EpsData(
    this.eps,
    this.onTap, {
    this.groups = const [],
    this.chapterIds = const [],
  });
}

/// 缩略图分页数据。
class ThumbnailsData {
  ThumbnailsData(this.thumbnails, this.load, this.maxPage);

  List<String> thumbnails;
  int current = 1;
  final int maxPage;
  final Future<Res<List<String>>> Function(int page) load;
  bool isGetting = false;

  Future<void> get(void Function() update) async {
    if (current >= maxPage || isGetting) {
      return;
    }
    isGetting = true;
    final res = await load(current + 1);
    if (res.success) {
      thumbnails.addAll(res.data);
      current++;
      update();
    } else {
      Log.e("Network Failed to load thumbnails: ${res.errorMessage}");
    }
    isGetting = false;
  }
}

/// 旧漫画页逻辑兼容类型。
///
/// 旧的 UI 已删除，部分旧页面类仍保留方法实现以兼容历史入口，
/// 这些方法不再参与详情页渲染。
class ComicPageLogic<T extends Object> {
  T? data;
  History? history;
  List<String>? localImages;
  String? coverPath;
}

/// 旧来源详情页的兼容基类。
///
/// 子类名仍可被旧入口引用，但实际构建统一交给 [ComicPageWidget]。
abstract class BaseComicPage<T extends Object> extends StatelessWidget {
  const BaseComicPage({super.key});

  ComicType get comicType;
  String get id;
  String? get cover => null;

  T? get data => null;
  ComicPageLogic<T> get logic => ComicPageLogic<T>();
  History? get history => null;
  BuildContext get context => App.globalContext!;
  bool get favorite => false;
  set favorite(bool value) {}

  String get tag => "${comicType.name} comic page $id";
  String get cacheKey => tag;
  String get source => comicType.name;
  String? get url => null;
  String? get title => null;
  String? get subTitle => null;
  String? get introduction => null;
  int? get pages => null;
  Map<String, List<String>>? get tags => null;
  EpsData? get eps => null;
  ThumbnailsData? get thumbnailsCreator => null;
  bool get supportThumbnails => true;
  bool get enableTranslationToCN => false;
  bool? get favoriteOnPlatformInitial => null;
  String? get commentsCount => null;
  String? get likeCount => null;
  bool get isLiked => false;
  Card? get uploaderInfo => null;
  Widget? get buildMoreInfo => null;
  List<Widget>? get extraActionButtons => null;
  Future<Res<T>> loadData() async =>
      const Res(null, errorMessage: "Not supported");
  Future<T?> loadCachedData() async => null;
  Future<bool> loadFavorite(T data) async => false;
  void update() {}
  void download() {}
  void read(History? history) {}
  void openFavoritePanel() {}
  ActionFunc? get openComments => null;
  ActionFunc? get onLike => null;
  ActionFunc? get searchSimilar => null;
  Widget? recommendationBuilder(T data) => null;
  Card? buildUploaderInfo(BuildContext context) => null;
  List<Widget>? buildActionsOverride(BuildContext context) => null;
  FavoriteItem toLocalFavoriteItem([T? comicData]) {
    throw UnimplementedError("旧详情页兼容层不再创建收藏项");
  }

  Widget buildCover(
    BuildContext context,
    ComicPageLogic logic,
    double height,
    double width,
  ) {
    return SizedBox(width: width, height: height);
  }

  Widget thumbnailImageBuilder(int index, String imageUrl) =>
      const SizedBox.shrink();

  void tapOnTag(String tag, String key) {}
  void onThumbnailTapped(int index) {}

  Widget buildActionItem(
    BuildContext context,
    String text,
    IconData icon,
    void Function() onTap, [
    void Function()? onLongPress,
  ]) {
    return const SizedBox.shrink();
  }

  void favoriteComic(FavoriteComicWidget widget) {
    final context = App.globalContext!;
    showSideBar(context, widget, title: "收藏漫画".tl, useSurfaceTintColor: true);
  }

  @override
  Widget build(BuildContext context) {
    return ComicPageWidget(comicType: comicType, id: id, cover: cover);
  }
}

class FavoriteComicWidget extends ConsumerStatefulWidget {
  const FavoriteComicWidget({
    required this.havePlatformFavorite,
    required this.needLoadFolderData,
    required this.localFavoriteItem,
    this.folders = const {},
    this.foldersLoader,
    this.selectFolderCallback,
    this.initialFolder,
    this.favoriteOnPlatform = false,
    this.cancelPlatformFavorite,
    this.cancelPlatformFavoriteWithFolder,
    this.setFavorite,
    super.key,
  });

  /// whether this platform has favorites feather
  final bool havePlatformFavorite;

  /// need load folder data before show folders
  final bool needLoadFolderData;

  /// initial folders, default is empty
  ///
  /// key - folder's name, value - folders id(used by callback)
  final Map<String, String> folders;

  /// load folders method
  final Future<Res<Map<String, String>>> Function()? foldersLoader;

  /// callback when user choose a folder
  ///
  /// type=0: platform, type=1:local
  final FutureOr<Res<bool>> Function(String id, int type)? selectFolderCallback;

  /// initial selected folder id
  final String? initialFolder;

  /// whether this comic have been added to platform's favorite folder
  /// if this is null, it is required to send a request to check it
  final bool? favoriteOnPlatform;

  /// identifier for the comic
  final FavoriteItem localFavoriteItem;

  final Future<Res<bool>> Function()? cancelPlatformFavorite;

  final Future<Res<bool>> Function(String folder)?
  cancelPlatformFavoriteWithFolder;

  final void Function(bool favorite)? setFavorite;

  @override
  ConsumerState<FavoriteComicWidget> createState() =>
      _FavoriteComicWidgetState();
}

/// 收藏面板只保存当前页签和未提交勾选。
class _FavoriteComicWidgetState extends ConsumerState<FavoriteComicWidget> {
  final _sessionId = UniqueKey().toString();
  late List<String> _selected;
  late int _page;

  FavoritePanelConfig get _config => FavoritePanelConfig(
    sessionId: _sessionId,
    item: widget.localFavoriteItem,
    loadFolders: widget.needLoadFolderData,
    initialFolders: widget.folders,
    foldersLoader: widget.foldersLoader,
    selectFolder: widget.selectFolderCallback,
    cancelPlatform: widget.cancelPlatformFavorite,
    cancelFolder: widget.cancelPlatformFavoriteWithFolder,
  );

  @override
  void initState() {
    super.initState();
    _selected = widget.initialFolder == null ? [] : [widget.initialFolder!];
    _page = widget.havePlatformFavorite ? 0 : 1;
  }

  /// 只有操作成功才关闭面板，详情状态由同一份收藏数据同步。
  Future<void> _submit({
    required bool removing,
    String? networkFolder,
    required bool remainingFavorite,
  }) async {
    final config = _config;
    final actions = ref.read(favoritePanelActionsProvider(config).notifier);
    Res<bool> result;
    if (_page == 1) {
      result = removing
          ? await actions.removeLocal(_selected.toList())
          : await actions.add(_selected.toList(), 1);
    } else {
      result = removing
          ? await actions.removePlatform(networkFolder)
          : await actions.add(_selected.toList(), 0);
    }
    if (!mounted) return;
    if (result.error) {
      showToast(message: result.errorMessageWithoutNull);
      return;
    }
    widget.setFavorite?.call(removing ? remainingFavorite : true);
    showToast(message: removing ? '取消收藏成功'.tl : '添加收藏成功'.tl);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    final membership = ref.watch(
      favoriteMembershipProvider(widget.localFavoriteItem.identity),
    );
    final localAdded = membership.asData?.value.toSet() ?? <String>{};
    final network = ref.watch(favoritePanelFoldersProvider(config));
    final networkValue = network.asData?.value;
    final remoteStatus = ref
        .watch(networkFavoriteRevisionProvider(config.sourceKey))
        .statuses[widget.localFavoriteItem.target];
    final favoriteOnPlatform = remoteStatus ?? widget.favoriteOnPlatform;
    final remoteAdded = networkValue?.selected ?? <String>{};
    final pending = ref.watch(favoritePanelActionsProvider(config)).isLoading;
    final localFolders = ref.watch(localFavoritesProvider);
    final removeLocal =
        _page == 1 &&
        _selected.isNotEmpty &&
        _selected.every(localAdded.contains);
    final removeFolder =
        _page == 0 &&
        _selected.length == 1 &&
        remoteAdded.contains(_selected.first);
    final removeAll = _page == 0 && favoriteOnPlatform == true;
    final removing = removeLocal || removeFolder || removeAll;
    bool hasRemoteAfter;
    if (removeAll) {
      hasRemoteAfter = false;
    } else if (removeFolder) {
      hasRemoteAfter = remoteAdded.any((id) => id != _selected.first);
    } else {
      hasRemoteAfter = favoriteOnPlatform == true || remoteAdded.isNotEmpty;
    }
    final hasLocalAfter = removeLocal
        ? localAdded.any((id) => !_selected.contains(id))
        : localAdded.isNotEmpty;
    final ready = _page == 1
        ? membership.hasValue && localFolders.hasValue
        : network.hasValue;
    return DefaultTabController(
      length: widget.havePlatformFavorite ? 2 : 1,
      child: Column(
        children: [
          TabBar(
            onTap: (index) => setState(() {
              _page = widget.havePlatformFavorite ? index : 1;
              _selected = _page == 0 && widget.initialFolder != null
                  ? [widget.initialFolder!]
                  : [];
            }),
            tabs: [
              if (widget.havePlatformFavorite) Tab(text: '网络'.tl),
              Tab(text: '本地'.tl),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                if (widget.havePlatformFavorite)
                  network.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (error, _) => _retry(
                      error,
                      () =>
                          ref.invalidate(favoritePanelFoldersProvider(config)),
                    ),
                    data: (data) => favoriteOnPlatform == true
                        ? Center(child: Text('已收藏'.tl))
                        : SingleChildScrollView(
                            child: Column(
                              children: [
                                for (final entry in data.folders.entries)
                                  _folder(
                                    entry.value,
                                    entry.key,
                                    0,
                                    remoteAdded.contains(entry.key),
                                  ),
                              ],
                            ),
                          ),
                  ),
                localFolders.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) => _retry(
                    error,
                    () => ref.invalidate(localFavoritesProvider),
                  ),
                  data: (data) => SingleChildScrollView(
                    child: Column(
                      children: [
                        for (final folder in data.folderNames)
                          _folder(
                            folder,
                            folder,
                            1,
                            localAdded.contains(folder),
                          ),
                        SizedBox(
                          height: 56,
                          child: Center(
                            child: TextButton.icon(
                              onPressed: () => showDialog(
                                context: context,
                                builder: (_) => const CreateFolderDialog(),
                              ),
                              icon: const Icon(Icons.add),
                              label: Text('新建'.tl),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 60,
            child: Center(
              child: Button.filled(
                isLoading: pending,
                disabled: pending || !ready || (!removing && _selected.isEmpty),
                onPressed: () => _submit(
                  removing: removing,
                  networkFolder: removeFolder && !removeAll
                      ? _selected.first
                      : null,
                  remainingFavorite: hasLocalAfter || hasRemoteAfter,
                ),
                child: Text(removing ? '取消收藏'.tl : '收藏'.tl),
              ),
            ),
          ),
          SizedBox(height: MediaQuery.paddingOf(context).bottom),
        ],
      ),
    );
  }

  /// 读取错误允许重试，不在构建期间发起额外请求。
  Widget _retry(Object error, VoidCallback retry) => Center(
    child: TextButton(onPressed: retry, child: Text('加载失败，点击重试: $error')),
  );

  /// 文件夹勾选属于当前未提交草稿。
  Widget _folder(String title, String id, int page, bool added) {
    final selected = _selected.contains(id) && _page == page;
    return InkWell(
      mouseCursor: appClickableMouseCursor,
      onTap: () => setState(() {
        if (_page != page) _selected.clear();
        _page = page;
        if (selected) {
          _selected.remove(id);
        } else {
          if (page == 0) _selected.clear();
          _selected.add(id);
        }
      }),
      child: SizedBox(
        height: App.isDesktop ? 42 : 48,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(
                selected ? Icons.folder : Icons.folder_outlined,
                size: App.isDesktop ? 24 : 28,
                color: Theme.of(context).colorScheme.secondary,
              ),
              const SizedBox(width: 12),
              Text(title),
              if (added)
                Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text('已收藏'.tl),
                  ),
                ),
              const Spacer(),
              if (selected) const AnimatedCheckIcon(),
            ],
          ),
        ),
      ),
    );
  }
}
