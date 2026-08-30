import 'dart:async';

import 'package:flutter/material.dart';

import 'package:pica_comic/base.dart';
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

  const EpsData(this.eps, this.onTap);
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
  String get downloadedId =>
      downloadManager.getDownloadIdFromComicId(comicType, id);

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

class FavoriteComicWidget extends StatefulWidget {
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
    required this.setFavorite,
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

  final void Function(bool favorite) setFavorite;

  @override
  State<FavoriteComicWidget> createState() => _FavoriteComicWidgetState();
}

class _FavoriteComicWidgetState extends State<FavoriteComicWidget> {
  late List<String> selected;
  late int page = 0;

  /// network folders
  late Map<String, String> folders;

  /// network folders that have been added to favorite
  var favoritedFolders = <String>[];
  bool loadedData = false;
  List<String> addedFolders = [];
  bool isAdding = false;

  @override
  void initState() {
    LocalFavoritesManager()
        .find(widget.localFavoriteItem.target, widget.localFavoriteItem.type)
        .then((folder) {
          Future.microtask(() => setState(() => addedFolders = folder));
        });
    selected = widget.initialFolder != null ? [widget.initialFolder!] : [];
    if (!widget.havePlatformFavorite) {
      page = 1;
    }
    folders = widget.folders;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    assert(widget.havePlatformFavorite || page != 0);

    Widget buildFolder(String name, String id, int p) {
      bool isSelected = selected.contains(id);
      return InkWell(
        mouseCursor: appClickableMouseCursor,
        onTap: () => setState(() {
          page = p;
          if (isSelected) {
            selected.remove(id);
            return;
          }
          if (p == 0) {
            selected.clear();
            selected.add(id);
          } else {
            selected.add(id);
          }
        }),
        child: SizedBox(
          height: App.isDesktop ? 42 : 48,
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                Icon(
                  isSelected ? Icons.folder : Icons.folder_outlined,
                  size: App.isDesktop ? 24 : 28,
                  color: Theme.of(context).colorScheme.secondary,
                ),
                const SizedBox(width: 12),
                Text(name),
                if ((addedFolders.contains(name) && p == 1) ||
                    (favoritedFolders.contains(id) && p == 0))
                  const SizedBox(width: 12),
                if ((addedFolders.contains(name) && p == 1) ||
                    (favoritedFolders.contains(id) && p == 0))
                  Container(
                    height: 30,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.tertiaryContainer,
                      borderRadius: const BorderRadius.all(Radius.circular(16)),
                    ),
                    child: Center(child: Text("已收藏".tl)),
                  ),
                const Spacer(),
                if (isSelected) const AnimatedCheckIcon(),
              ],
            ),
          ),
        ),
      );
    }

    Widget button = Button.filled(
      isLoading: isAdding,
      child: Text("收藏".tl),
      onPressed: () async {
        if (selected.isNotEmpty) {
          setState(() {
            isAdding = true;
          });
          Res<bool> res = const Res(true);
          for (var id in selected) {
            if (addedFolders.contains(id)) {
              continue;
            }
            res = await widget.selectFolderCallback!.call(id, page);
          }
          if (res.success) {
            widget.setFavorite(true);
            if (context.mounted) {
              context.pop();
            }
            showToast(message: "添加收藏成功".tl);
          } else {
            setState(() {
              isAdding = false;
            });
            showToast(message: res.errorMessage!);
          }
        }
      },
    );

    Widget platform = SingleChildScrollView(
      child: Column(
        children: List.generate(
          folders.length,
          (index) => buildFolder(
            folders.values.elementAt(index),
            folders.keys.elementAt(index),
            0,
          ),
        ),
      ),
    );

    if (widget.favoriteOnPlatform == true) {
      platform = Center(child: Text("已收藏".tl));
      if (page == 0) {
        button = Button.filled(
          isLoading: isAdding,
          onPressed: () async {
            setState(() {
              isAdding = true;
            });
            var res = await widget.cancelPlatformFavorite!.call();
            if (res.success) {
              if (addedFolders.isEmpty) {
                widget.setFavorite(false);
              }
              showToast(message: "取消收藏成功".tl);
              if (context.mounted) {
                context.pop();
              }
            } else {
              setState(() {
                isAdding = false;
              });
              showToast(message: res.errorMessage!);
            }
          },
          child: Text("取消收藏".tl),
        );
      }
    }

    if (page == 1 &&
        selected.isNotEmpty &&
        selected.every((e) => addedFolders.contains(e))) {
      button = Button.filled(
        onPressed: () {
          context.hideMessages();
          App.globalBack();
          if (addedFolders.length == 1 &&
              widget.favoriteOnPlatform == false &&
              favoritedFolders.isEmpty) {
            widget.setFavorite(false);
          }
          for (var id in selected) {
            LocalFavoritesManager().deleteComic(id, widget.localFavoriteItem);
          }
          showToast(message: "取消收藏成功".tl);
        },
        child: Text("取消收藏".tl),
      );
    } else if (widget.havePlatformFavorite &&
        widget.needLoadFolderData &&
        !loadedData) {
      widget.foldersLoader!.call().then((res) {
        if (res.error) {
          showToast(message: res.errorMessage ?? "Error");
        } else {
          setState(() {
            loadedData = true;
            folders = res.data;
            favoritedFolders = res.subData ?? [];
          });
        }
      });
      platform = const Center(child: CircularProgressIndicator());
    } else if (page == 0 &&
        selected.length == 1 &&
        favoritedFolders.contains(selected[0])) {
      button = Button.filled(
        onPressed: () async {
          var res = await widget.cancelPlatformFavoriteWithFolder!(selected[0]);
          if (res.success) {
            showToast(message: "取消收藏成功".tl);
            if (context.mounted) {
              context.pop();
            }
          } else {
            showToast(message: res.errorMessage!);
          }
        },
        child: Text("取消收藏".tl),
      );
    }

    Widget local;

    local = SingleChildScrollView(
      child: FutureBuilder<List<String>>(
        future: LocalFavoritesManager().folderNames,
        builder: (context, snapshot) {
          final localFolders = snapshot.data ?? [];
          return Column(
            children: [
              for (var index = 0; index < localFolders.length; index++)
                buildFolder(localFolders[index], localFolders[index], 1),
              SizedBox(
                height: 56,
                width: double.infinity,
                child: Center(
                  child: TextButton(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text("新建".tl),
                        const SizedBox(width: 4),
                        const Icon(Icons.add),
                      ],
                    ),
                    onPressed: () => showDialog(
                      context: App.globalContext!,
                      builder: (_) => const CreateFolderDialog(),
                    ).then((value) => setState(() {})),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );

    return DefaultTabController(
      length: widget.havePlatformFavorite ? 2 : 1,
      child: Column(
        children: [
          TabBar(
            onTap: (i) {
              setState(() {
                selected.clear();
                if (i == 0 && widget.initialFolder != null) {
                  selected.add(widget.initialFolder!);
                }
                page = i;
                if (!widget.havePlatformFavorite) {
                  page = 1;
                }
              });
            },
            tabs: [
              if (widget.havePlatformFavorite) Tab(text: "网络".tl),
              Tab(text: "本地".tl),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [if (widget.havePlatformFavorite) platform, local],
            ),
          ),
          SizedBox(height: 60, child: Center(child: button)),
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }
}
