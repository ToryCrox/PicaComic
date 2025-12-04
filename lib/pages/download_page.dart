import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as Path;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/comic_source/comic_source.dart';
import 'package:pica_comic/foundation/history.dart';
import 'package:pica_comic/foundation/local_favorites.dart';
import 'package:pica_comic/foundation/log.dart';
import 'package:pica_comic/network/download.dart';
import 'package:pica_comic/network/download_model.dart';
import 'package:pica_comic/network/htmanga_network/ht_download_model.dart';
import 'package:pica_comic/network/models/download_tag.dart';
import 'package:pica_comic/network/nhentai_network/download.dart';
import 'package:pica_comic/network/nhentai_network/nhentai_main_network.dart';
import 'package:pica_comic/pages/comic_page.dart';
import 'package:pica_comic/pages/picacg/comic_page.dart';
import 'package:pica_comic/pages/reader/comic_reading_page.dart';
import 'package:pica_comic/pages/tag_assignment_dialog.dart';
import 'package:pica_comic/pages/tag_management_page.dart';
import 'package:pica_comic/pages/rename_download_dialog.dart';
import 'package:pica_comic/pages/update_size_dialog.dart';
import 'package:pica_comic/tools/extensions.dart';
import 'package:pica_comic/tools/image_utils.dart';
import 'package:pica_comic/tools/io_extensions.dart';
import 'package:pica_comic/tools/io_tools.dart';
import 'package:pica_comic/tools/pdf.dart';
import 'package:pica_comic/tools/tags_translation.dart';
import 'package:pica_comic/tools/translations.dart';
import 'package:open_file/open_file.dart';

import 'package:pica_comic/pages/search_result_page.dart';
import 'package:pica_comic/network/custom_download_model.dart';
import '../components/components.dart';
import '../pages/components/download_tag_filter_panel.dart';
import '../foundation/app.dart';
import '../foundation/state_controller.dart';
import '../foundation/ui_mode.dart';
import '../network/app_dio.dart';
import '../network/base_comic.dart';

import '../network/eh_network/eh_download_model.dart';
import '../network/hitomi_network/hitomi_download_model.dart';
import '../network/jm_network/jm_download.dart';
import '../network/picacg_network/picacg_download_model.dart';
import '../tools/type_util.dart';
import 'downloading_page.dart';
import 'ehentai/eh_gallery_page.dart';
import 'hitomi/hitomi_comic_page.dart';
import 'htmanga/ht_comic_page.dart';
import 'jm/jm_comic_page.dart';
import 'local/local_thumbs_page.dart';
import 'nhentai/comic_page.dart';

extension ReadComic on DownloadedItem {
  void read({int? ep, int? initialPage}) async {
    var comic = this;
    if (comic.type == DownloadType.picacg) {
      var history =
          await History.findOrCreate((comic as DownloadedComic).comicItem);
      App.globalTo(
        () => ComicReadingPage.picacg(
          comic.id,
          ep ?? history.ep,
          comic.eps,
          comic.name,
          initialPage: initialPage ?? (ep == null ? history.page : 0),
        ),
      );
    } else if (comic.type == DownloadType.ehentai) {
      var history =
          await History.findOrCreate((comic as DownloadedGallery).gallery);
      App.globalTo(
        () => ComicReadingPage.ehentai(
          (comic).gallery,
          initialPage: initialPage ?? (ep == null ? history.page : 0),
        ),
      );
    } else if (comic.type == DownloadType.jm) {
      var history =
          await History.findOrCreate((comic as DownloadedJmComic).comic);
      App.globalTo(
        () => ComicReadingPage.jmComic(
          comic.comic,
          ep ?? history.ep,
          initialPage: initialPage ?? (ep == null ? history.page : 0),
        ),
      );
    } else if (comic.type == DownloadType.hitomi) {
      var history =
          await History.findOrCreate((comic as DownloadedHitomiComic).comic);
      App.globalTo(
        () => ComicReadingPage.hitomi(
          comic.comic,
          comic.link,
          initialPage: initialPage ?? (ep == null ? history.page : 0),
        ),
      );
    } else if (comic.type == DownloadType.htmanga) {
      var history =
          await History.findOrCreate((comic as DownloadedHtComic).comic);
      App.globalTo(
        () => ComicReadingPage.htmanga(
          comic.comic.id,
          comic.comic.title,
          initialPage: initialPage ?? (ep == null ? history.page : 0),
        ),
      );
    } else if (comic.type == DownloadType.nhentai) {
      var nc = NhentaiComic(
          comic.id.replaceFirst("nhentai", ""),
          comic.name,
          comic.subTitle,
          (comic as NhentaiDownloadedComic).cover,
          {},
          false,
          [],
          [],
          "");
      var history = await History.findOrCreate(nc);
      App.globalTo(
        () => ComicReadingPage.nhentai(
          comic.id.replaceFirst("nhentai", ""),
          comic.title,
          initialPage: initialPage ?? (ep == null ? history.page : 0),
        ),
      );
    } else if (comic.type == DownloadType.other) {
      comic as CustomDownloadedItem;
      var data = ComicInfoData(
        name,
        subTitle,
        comic.cover,
        null,
        {},
        null,
        null,
        null,
        0,
        null,
        comic.sourceKey,
        comic.id.replaceFirst("${comic.sourceKey}-", ""),
      );
      var history = await History.findOrCreate(data);
      App.globalTo(
        () => ComicReadingPage(
          CustomReadingData(
            data.target,
            data.title,
            ComicSource.find(comic.sourceKey),
            comic.chapters,
          ),
          ep == null ? history.page : 0,
          ep ?? history.ep,
        ),
      );
    }
  }
}

class DownloadPageLogic extends StateController {
  bool isInit = false;

  ///是否正在加载
  bool loading = true;

  ///是否处于选择状态
  bool selecting = false;

  ///已选择的数量
  int get selectedNum => selected.length;

  ///已选择的漫画
  //var selected = <bool>[];
  var selected = <String>{};

  /// 退出选择状态
  void exitSelecting() {
    selecting = false;
    selected.clear();
    update();
  }

  List<DownloadedItem> get selectedComics =>
      baseComics.where((element) => selected.contains(element.id)).toList();

  ///已下载的漫画
  var comics = <DownloadedItem>[];

  var baseComics = <DownloadedItem>[];

  final Map<int, DownloadTag> _tagInfoMap = {};

  bool _searchMode = false;

  bool get searchMode => _searchMode;

  Future<void> updateSearchMode(bool mode) async {
    final wasFiltering = isFiltering;
    _searchMode = mode;
    _showAppBar = true; // 确保AppBar显示以反映状态变化

    // 进入过滤模式时保存位置，退出时恢复
    if (mode && !wasFiltering) {
      _saveScrollPosition();
    }

    await updateComics();
    update();

    // 退出过滤模式后恢复位置
    if (!isFiltering && wasFiltering) {
      _restoreScrollPosition();
    }
  }

  bool searchInit = false;

  String _keyword = "";

  /// 当前选中的标签筛选
  int? selectedTagId;

  /// 是否展开标签
  bool expandTags = false;

  /// 所有标签
  List<TagInfo> allTags = [];

  /// 是否显示AppBar和TagFilter
  bool _showAppBar = true;

  final textFieldController = TextEditingController();

  /// 滚动控制器
  final scrollController = ScrollController();

  /// 保存的滚动位置（用于退出搜索/过滤模式时恢复）
  double? _savedScrollPosition;

  /// 是否处于过滤状态（搜索模式或标签筛选）
  bool get isFiltering => _searchMode || selectedTagId != null;

  /// 保存当前滚动位置
  void _saveScrollPosition() {
    if (scrollController.hasClients) {
      _savedScrollPosition = scrollController.offset;
    }
  }

  /// 恢复滚动位置
  void _restoreScrollPosition() {
    if (_savedScrollPosition != null && scrollController.hasClients) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (scrollController.hasClients) {
          scrollController.jumpTo(_savedScrollPosition!);
          _savedScrollPosition = null;
        }
      });
    }
  }

  // void change() {
  //   try {
  //     update();
  //   } catch (e) {
  //     //忽视
  //   }
  // }

  String get allComicSize {
    final sizeMB = comics.fold(0.0,
        (previousValue, element) => previousValue + (element.comicSize ?? 0));
    if (sizeMB > 1024) {
      return "${(sizeMB / 1024).toStringAsFixed(2)}GB";
    } else {
      return "${sizeMB.toStringAsFixed(2)}MB";
    }
  }

  @override
  void update([List<Object>? ids]) {
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((t) {
        super.update();
      });
    } else {
      super.update();
    }
  }

  Future<void> updateKeyword(String keyword,
      {bool updateTextField = true}) async {
    if (updateTextField) {
      textFieldController.text = keyword;
    }
    if (_keyword != keyword || !_searchMode) {
      final wasFiltering = isFiltering;
      _keyword = keyword;
      _searchMode = true;

      // 进入过滤模式时保存位置
      if (!wasFiltering) {
        _saveScrollPosition();
      }

      await updateComics();
      update();
    }
  }

  Future<void> updateComics() async {
    comics.clear();

    // 如果有标签筛选，先按标签过滤
    List<DownloadedItem> filteredComics = baseComics;
    if (selectedTagId != null) {
      final comicIds = await downloadManager.getComicIdsByTag(selectedTagId!);
      filteredComics =
          baseComics.where((e) => comicIds.contains(e.id)).toList();
    }

    // 再按关键词过滤
    if (_keyword == "" || !searchMode) {
      comics.addAll(filteredComics);
    } else {
      final keyword = _keyword.toLowerCase();
      for (var element in filteredComics) {
        if (element.name.toLowerCase().contains(keyword) ||
            element.subTitle.toLowerCase().contains(keyword) ||
            getAllTags(element).any((e) => e.toLowerCase().contains(keyword))) {
          comics.add(element);
        }
      }
    }
  }

  /// 更新标签筛选
  Future<void> updateTagFilter(int? tagId) async {
    final wasFiltering = isFiltering;

    if (tagId == selectedTagId) {
      selectedTagId = null;
    } else {
      selectedTagId = tagId;
    }

    // 进入过滤模式时保存位置
    if (selectedTagId != null && !wasFiltering) {
      _saveScrollPosition();
    }

    _showAppBar = true; // 确保AppBar显示以反映状态变化
    await updateComics();
    update();

    // 退出过滤模式后恢复位置
    if (!isFiltering && wasFiltering) {
      _restoreScrollPosition();
    }
  }

  void removeComic(DownloadedItem comic) {
    comics.remove(comic);
    baseComics.remove(comic);
    selected.remove(comic.id);
    update();
  }

  Map<String, List<String>> comicUserTags = {};

  List<String> getUserTags(DownloadedItem item) {
    return comicUserTags[item.id] ?? [];
  }

  List<String> getOriginalTags(DownloadedItem item) {
    final userTags = getUserTags(item);
    final originalTags = item.tags.map((e) => e.translateTagsToCN);
    if (userTags.isEmpty) {
      return originalTags.toList();
    } else {
      return originalTags.whereNot((e) => userTags.contains(e)).toList();
    }
  }

  List<String> getAllTags(DownloadedItem item) {
    return [...getOriginalTags(item), ...getUserTags(item)];
  }

  List<String> getRawTags(DownloadedItem item) {
    final userTags = getUserTags(item);
    if (userTags.isEmpty) {
      return item.tags.toList();
    } else {
      return item.tags
          .where((e) => !userTags.contains(e.translateTagsToCN))
          .toList();
    }
  }

  @override
  void refresh() {
    _loadComics();
  }

  /// 只刷新标签数据,不重新加载漫画列表
  /// 用于标签编辑后的轻量级刷新
  Future<void> refreshTags() async {
    await _loadTagsData();
    await updateComics();
    update();
  }

  /// 加载标签数据(包括标签映射、标签信息和封面路径)
  Future<void> _loadTagsData() async {
    // 重新加载漫画标签映射
    comicUserTags = await downloadManager.getAllComicTagsMap();

    // 重新加载所有标签
    final allTags = await downloadManager.getAllTags();
    _tagInfoMap.clear();
    _tagInfoMap.addAll(allTags.groupFoldBy((e) => e.id, (g, t) => t));

    this.allTags = allTags
        .map((e) => TagInfo(
              id: e.id,
              name: e.name,
              comicCount: 0,
              category: e.category.value,
              sortOrder: e.sortOrder,
              categorySortOrder: e.categorySortOrder,
              coverPath: _tagInfoMap[e.id]?.coverComicId != null
                  ? _tagInfoMap[e.id]!.coverComicId!
                  : null,
            ))
        .toList();

    // 填充标签封面路径
    for (var tag in this.allTags) {
      if (_tagInfoMap[tag.id]?.coverComicId != null) {
        final comicId = _tagInfoMap[tag.id]!.coverComicId!;
        final comic = baseComics.firstWhereOrNull((e) => e.id == comicId);
        if (comic != null) {
          tag.coverPath = comic.coverPath;
        }
      }
    }

    this.allTags.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }

  Future<void> _loadComics({bool isFirstLoad = false}) async {
    loading = true;
    var order = '', direction = 'desc';
    switch (appdata.settings[26][0]) {
      case "0":
        order = 'time';
      case "1":
        order = 'title';
      case "2":
        order = 'subtitle';
      case "3":
        order = 'size';
      default:
        throw UnimplementedError();
    }
    if (appdata.settings[26][1] == "1") {
      direction = 'asc';
    }
    final allComics = await DownloadManager().getAll(order, direction);
    baseComics = allComics;

    await _loadTagsData();
    await updateComics();

    loading = false;
    update();
  }

  String getTagName(int tagId) {
    return _tagInfoMap[tagId]?.name ?? "";
  }

  bool _isSortByCategory = false;

  void sortByCategory() {
    expandTags = true;
    _isSortByCategory = !_isSortByCategory;
    allTags.sort((a, b) {
      if (a.category != b.category && _isSortByCategory) {
        return a.category.compareTo(b.category);
      }
      return a.sortOrder.compareTo(b.sortOrder);
    });
    update();
  }
}

class DownloadPage extends StatelessWidget {
  const DownloadPage({Key? key, this.showBack = true}) : super(key: key);

  final bool showBack;

  @override
  Widget build(BuildContext context) {
    return StateBuilder<DownloadPageLogic>(
      init: DownloadPageLogic(),
      builder: (logic) {
        if (!logic.isInit) {
          logic.isInit = true;
          logic._loadComics();
        }
        if (logic.loading && logic.comics.isEmpty) {
          return Scaffold(
            appBar: AppBar(
              title: Text("下载"),
            ),
            body: const Center(
              child: CircularProgressIndicator(),
            ),
          );
        }
        return Scaffold(
          floatingActionButton:
              logic._showAppBar ? buildFAB(context, logic) : null,
          body: NotificationListener<ScrollUpdateNotification>(
            onNotification: (notification) {
              final ScrollDirection direction = notification.scrollDelta! < 0
                  ? ScrollDirection.forward
                  : ScrollDirection.reverse;
              var showAppBar = logic._showAppBar;
              if (direction == ScrollDirection.reverse) {
                logic._showAppBar = false;
              } else if (direction == ScrollDirection.forward) {
                logic._showAppBar = true;
              }
              if (logic._showAppBar == showAppBar) return true;
              logic.update();
              return false;
            },
            child: CustomScrollView(
              controller: logic.scrollController,
              slivers: [
                // AppBar作为SliverPersistentHeader
                if (!logic.selecting)
                  SliverPersistentHeader(
                    pinned:
                        logic._showAppBar && SmoothScrollProvider.isMouseScroll,
                    floating: !SmoothScrollProvider.isMouseScroll,
                    delegate: _SliverAppBarDelegate(
                      minHeight: 56,
                      maxHeight: 56,
                      child: _buildAppBarContent(context, logic),
                    ),
                  ),
                // 选择模式下的AppBar
                if (logic.selecting)
                  SliverAppBar(
                    pinned: true,
                    backgroundColor:
                        Theme.of(context).colorScheme.primaryContainer,
                    leading: IconButton(
                      onPressed: () {
                        logic.exitSelecting();
                      },
                      icon: const Icon(Icons.close),
                    ),
                    title: buildTitle(context, logic),
                    actions: buildActions(context, logic),
                  ),
                // TagFilter作为SliverPersistentHeader
                if (!logic.selecting)
                  SliverPersistentHeader(
                    pinned:
                        logic._showAppBar && SmoothScrollProvider.isMouseScroll,
                    floating: !SmoothScrollProvider.isMouseScroll,
                    delegate: _SliverAppBarDelegate(
                      minHeight: 48,
                      maxHeight: 48,
                      child: _buildTagFilter(context, logic),
                    ),
                  ),
                // 漫画列表
                buildComics(context, logic),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAppBarContent(BuildContext context, DownloadPageLogic logic) {
    Widget? leading;
    if (logic.selectedTagId != null || logic.searchMode) {
      leading = IconButton(
        onPressed: () {
          if (logic.searchMode) {
            logic.updateSearchMode(false);
          } else if (logic.selectedTagId != null) {
            logic.updateTagFilter(null);
          }
        },
        icon: const Icon(Icons.close),
      );
    } else if (showBack) {
      leading = IconButton(
        onPressed: () {
          if (logic.selectedTagId != null) {
            logic.updateTagFilter(null);
          } else if (logic.searchMode) {
            logic.updateSearchMode(false);
          } else {
            Navigator.maybePop(context);
          }
        },
        icon: const Icon(Icons.arrow_back),
      );
    } else {
      leading = const SizedBox.shrink();
    }

    return Material(
      elevation: 1,
      surfaceTintColor: Theme.of(context).colorScheme.surfaceTint,
      child: Container(
        padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
        child: Appbar(
          leading: leading,
          title: buildTitle(context, logic),
          actions: buildActions(context, logic),
        ),
      ),
    );
  }

  Widget _buildTagFilter(BuildContext context, DownloadPageLogic logic) {
    var tags = logic.allTags;

    // If selected tag is not in the first 20, move it to the front for display
    if (logic.selectedTagId != null) {
      final selectedIndex = tags.indexWhere((t) => t.id == logic.selectedTagId);
      if (selectedIndex >= 20) {
        final selectedTag = tags[selectedIndex];
        tags = [
          selectedTag,
          ...tags.sublist(0, 19),
        ];
      } else if (tags.length > 20) {
        tags = tags.sublist(0, 20);
      }
    } else if (tags.length > 20) {
      tags = tags.sublist(0, 20);
    }

    return Material(
      elevation: 1,
      surfaceTintColor: Theme.of(context).colorScheme.surfaceTint,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (var tag in tags)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: InkWell(
                          key: ValueKey(tag.id),
                          onTap: () => logic.updateTagFilter(tag.id),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: logic.selectedTagId == tag.id
                                  ? Theme.of(context).colorScheme.primary
                                  : TagCategory.fromValue(tag.category)
                                      .color
                                      .withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                              border: logic.selectedTagId == tag.id
                                  ? null
                                  : Border.all(
                                      color: TagCategory.fromValue(tag.category)
                                          .color,
                                      width: 1,
                                    ),
                            ),
                            child: Text(
                              tag.name,
                              style: TextStyle(
                                fontSize: 12,
                                color: logic.selectedTagId == tag.id
                                    ? Theme.of(context).colorScheme.onPrimary
                                    : Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  constraints: const BoxConstraints(maxWidth: 1000),
                  backgroundColor: Colors.transparent,
                  builder: (context) => DownloadTagFilterPanel(
                    tags: logic.allTags,
                    selectedTagId: logic.selectedTagId,
                    onTagSelected: (id) {
                      logic.updateTagFilter(id);
                      Navigator.pop(context);
                    },
                    onClose: () => Navigator.pop(context),
                    onManageTags: () {
                      Navigator.pop(context);
                      App.globalTo(() => const TagManagementPage());
                    },
                  ),
                );
              },
              icon: const Icon(Icons.keyboard_arrow_down),
              tooltip: "展开标签".tl,
            ),
          ],
        ),
      ),
    );
  }

  Widget buildComics(BuildContext context, DownloadPageLogic logic) {
    //logic.find();
    final comics = logic.comics;
    return SliverGrid(
      delegate: SliverChildBuilderDelegate(childCount: comics.length,
          (context, index) {
        return buildItem(context, logic, index);
      }),
      gridDelegate: SliverGridDelegateWithComics(),
    );
  }

  Future<void> export(DownloadPageLogic logic) async {
    var comics = logic.selectedComics;
    if (comics.isEmpty) {
      return;
    }
    bool res;
    if (comics.length > 1) {
      res = await exportComics(comics);
    } else {
      res = await exportComic(
          comics.first.id, comics.first.name, comics.first.eps);
    }
    App.globalBack();
    if (!res) {
      showToast(message: "导出失败".tl);
    }
  }

  Widget buildItem(BuildContext context, DownloadPageLogic logic, int index) {
    final item = logic.comics[index];
    bool selected = logic.selected.contains(item.id);
    var type = logic.comics[index].type.name;
    if (item.type == DownloadType.other) {
      type = (item as CustomDownloadedItem).sourceName;
    }
    final comic = logic.comics[index];

    String name = comic.name;
    String maxPage = '';
    if (comic.type == DownloadType.ehentai) {
      maxPage = (comic as DownloadedGallery).gallery.maxPage;
    }
    if (maxPage.isNotEmpty && maxPage != '0') {
      name = '(${maxPage}P)[${comic.id}]${comic.name}';
    } else {
      name = '[${comic.id}]${comic.name}';
    }
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Container(
        decoration: BoxDecoration(
          color: selected
              ? Theme.of(context).colorScheme.surfaceContainerHighest
              : Colors.transparent,
          borderRadius: const BorderRadius.all(
            Radius.circular(16),
          ),
        ),
        child: DownloadedComicTile(
          id: item.id,
          name: name,
          author: item.subTitle,
          imagePath: File(item.coverPath ?? ''),
          type: type,
          primaryTags: logic.getUserTags(item),
          tag: logic.getRawTags(item),
          onTagTap: (tag) => logic.updateKeyword(tag),
          onTagSecondaryTap: (tag, details) =>
              _showTagMenu(context, logic, tag, item, false, details),
          onPrimaryTagSecondaryTap: (tag, details) =>
              _showTagMenu(context, logic, tag, item, true, details),
          onPrimaryTagTap: (tag) async {
            // find tag id by name
            final tagId = logic.allTags
                .firstWhereOrNull((element) => element.name == tag)
                ?.id;
            if (tagId != null) {
              logic.updateTagFilter(tagId);
            }
          },
          onTap: () async {
            if (logic.selecting) {
              if (logic.selected.contains(comic.id)) {
                logic.selected.remove(comic.id);
              } else {
                logic.selected.add(comic.id);
              }
              if (logic.selectedNum == 0) {
                logic.selecting = false;
              }
              logic.update();
            } else {
              showInfo(index, logic, context);
            }
          },
          size: () {
            if (logic.comics[index].comicSize != null) {
              return logic.comics[index].comicSize!.toStringAsFixed(2);
            } else {
              return "未知大小".tl;
            }
          }.call(),
          onLongTap: () {
            if (logic.selecting) return;
            logic.selected.add(item.id);
            logic.selecting = true;
            logic.update();
          },
          onSecondaryTap: (details) async {
            _onTileSecondaryTap(context, details, index, logic);
          },
        ),
      ),
    );
  }

  Future<void> _onTileSecondaryTap(BuildContext context, TapDownDetails details,
      int index, DownloadPageLogic logic) async {
    final comic = logic.comics[index];
    showDesktopMenu(App.globalContext!,
        Offset(details.globalPosition.dx, details.globalPosition.dy), [
      DesktopMenuEntry(
        text: "阅读".tl,
        onClick: () async {
          //await Future.delayed(const Duration(milliseconds: 250));
          logic.comics[index].read();
        },
      ),
      DesktopMenuEntry(
        text: "图片列表".tl,
        onClick: () async {
          //await Future.delayed(const Duration(milliseconds: 250));
          _goLocalComicPage(comic);
        },
      ),
      DesktopMenuEntry(
        text: "删除".tl,
        onClick: () {
          showConfirmDialog(context, "确认删除".tl, "此操作无法撤销, 是否继续?".tl, () {
            final comic = logic.comics[index];
            downloadManager.delete([comic.id]);
            logic.removeComic(comic);
          });
        },
      ),
      DesktopMenuEntry(
        text: "删除(不包括文件)".tl,
        onClick: () {
          showConfirmDialog(context, "确认删除，不包括文件".tl, "此操作无法撤销, 是否继续?".tl, () {
            downloadManager.deleteWithoutFile([comic.id]);
            logic.removeComic(comic);
            logic.update();
          });
        },
      ),
      DesktopMenuEntry(
        text: "查看漫画详情".tl,
        onClick: () {
          Future.delayed(const Duration(milliseconds: 300), () {
            toComicInfoPage(logic.comics[index]);
          });
        },
      ),
      DesktopMenuEntry(
        text: "更新文件大小".tl,
        onClick: () async {
          await Future.delayed(const Duration(milliseconds: 300));
          await showDialog(
            context: context,
            builder: (context) => UpdateSizeDialog(
              comics: [comic],
              onComplete: () {
                logic.update();
              },
            ),
          );
        },
      ),
      DesktopMenuEntry(
        text: "管理标签".tl,
        onClick: () async {
          await Future.delayed(const Duration(milliseconds: 300));
          final suggestedTags = [
            comic.name,
            comic.subTitle,
            ...logic.getOriginalTags(comic)
          ];
          final result = await showDialog<bool>(
            context: context,
            builder: (context) => TagAssignmentDialog(
              comicIds: [comic.id],
              suggestedTags: suggestedTags,
            ),
          );
          if (result == true) {
            logic.refreshTags();
          }
        },
      ),
      DesktopMenuEntry(
        text: "复制路径".tl,
        onClick: () async {
          Future.delayed(const Duration(milliseconds: 300), () async {
            var path = comic.directoryPath;
            Clipboard.setData(ClipboardData(text: path));
          });
        },
      ),
      DesktopMenuEntry(
        text: "打开文件".tl,
        onClick: () async {
          var path = comic.directoryPath;
          OpenFile.open(path);
        },
      ),
    ]);
  }

  void _showTagMenu(BuildContext context, DownloadPageLogic logic, String tag,
      DownloadedItem comic, bool isPrimary, TapDownDetails details) {
    showDesktopMenu(App.globalContext!,
        Offset(details.globalPosition.dx, details.globalPosition.dy), [
      DesktopMenuEntry(
        text: "管理标签".tl,
        onClick: () async {
          await Future.delayed(const Duration(milliseconds: 300));
          final suggestedTags = [
            comic.name,
            comic.subTitle,
            ...logic.getOriginalTags(comic)
          ];
          final result = await showDialog<bool>(
            context: context,
            builder: (context) => TagAssignmentDialog(
              comicIds: [comic.id],
              suggestedTags: suggestedTags,
            ),
          );
          if (result == true) {
            logic.refreshTags();
          }
        },
      ),
      DesktopMenuEntry(
        text: "复制".tl,
        onClick: () {
          Clipboard.setData(ClipboardData(text: tag));
        },
      ),
      DesktopMenuEntry(
        text: "本地搜索".tl,
        onClick: () {
          logic.updateKeyword(tag);
        },
      ),
      DesktopMenuEntry(
        text: "搜索漫画".tl,
        onClick: () {
          String searchTag = tag;
          if (!isPrimary) {
            // Find original tag
            searchTag = comic.tags.firstWhere((t) => t.translateTagsToCN == tag,
                orElse: () => tag);
          } else {
            // Check if the user tag corresponds to an original tag
            var originalTag = comic.tags.firstWhereOrNull(
                (t) => t.translateTagsToCN == tag || t == tag);
            if (originalTag != null) {
              searchTag = originalTag;
            }
          }
          String sourceKey = "picacg";
          if (comic.type == DownloadType.ehentai) {
            sourceKey = "ehentai";
          } else if (comic.type == DownloadType.jm) {
            sourceKey = "jm";
          } else if (comic.type == DownloadType.hitomi) {
            sourceKey = "hitomi";
          } else if (comic.type == DownloadType.htmanga) {
            sourceKey = "htmanga";
          } else if (comic.type == DownloadType.nhentai) {
            sourceKey = "nhentai";
          } else if (comic.type == DownloadType.other) {
            if (comic is CustomDownloadedItem) {
              sourceKey = comic.sourceKey;
            }
          }
          context.to(() => SearchResultPage(
                keyword: searchTag,
                sourceKey: sourceKey,
              ));
        },
      ),
    ]);
  }

  void _goLocalComicPage(DownloadedItem comic) {
    var dirPath = comic.directoryPath;
    App.globalTo(() => LocalThumbsPage(
          dirPath: dirPath,
          onItemTap: (index, filePath) async {
            if (index <= 0) {
              comic.read();
              return;
            }
            int ep = 0;
            final file = File(filePath);
            final absPath = file.absolute.path;
            if (comic.type == DownloadType.picacg ||
                comic.type == DownloadType.jm) {
              final fileParent = file.parent;
              final fileParentPath = Path.normalize(file.parent.absolute.path);
              for (final e in comic.downloadedEps) {
                final epDirPath = Path.normalize("$dirPath/$e");
                //debugPrint("epDirPath: $epDirPath, fileParent: $fileParent");
                if (epDirPath == fileParentPath) {
                  ep = e;
                  sFileRelativeFromPath = fileParent.path;
                  final imageNames =
                      (await fileParent.list(recursive: true).toList())
                          .where(predictImageFile)
                          .sortedByName()
                          .map((e) => e.name)
                          .toList();
                  index = imageNames.indexOf(Path.basename(absPath));
                  if (index < 0) {
                    index = 0;
                  }
                  index += 1;
                  break;
                }
              }
            }
            debugPrint(
                "Local thumbs eps: ${comic.downloadedEps}, ep: $ep, index: $index, page: $filePath");
            comic.read(initialPage: index, ep: ep);
          },
        ));
  }

  void toComicInfoPage(DownloadedItem comic) => _toComicInfoPage(comic);

  void showInfo(int index, DownloadPageLogic logic, BuildContext context) {
    if (UiMode.m1(context)) {
      showModalBottomSheet(
          context: context,
          builder: (context) {
            return DownloadedComicInfoView(logic.comics[index], logic);
          });
    } else {
      showSideBar(App.globalContext!,
          DownloadedComicInfoView(logic.comics[index], logic),
          useSurfaceTintColor: true);
    }
  }

  Widget buildFAB(BuildContext context, DownloadPageLogic logic) =>
      FloatingActionButton(
        enableFeedback: true,
        onPressed: () {
          if (!logic.selecting) {
            logic.selecting = true;
            logic.update();
          } else {
            if (logic.selectedNum == 0) return;
            showDialog(
                context: context,
                builder: (dialogContext) {
                  return AlertDialog(
                    title: Text("删除".tl),
                    content: Text("要删除已选择的项目吗? 此操作无法撤销".tl),
                    actions: [
                      TextButton(
                          onPressed: () => App.globalBack(),
                          child: Text("取消".tl)),
                      TextButton(
                          onPressed: () async {
                            App.globalBack();
                            var comics =
                                logic.selectedComics.map((e) => e.id).toList();
                            await downloadManager.delete(comics);
                            logic.refresh();
                          },
                          child: Text("确认".tl)),
                    ],
                  );
                });
          }
        },
        child: logic.selecting
            ? const Icon(Icons.delete_forever_outlined)
            : const Icon(Icons.checklist_outlined),
      );

  Widget buildTitle(BuildContext context, DownloadPageLogic logic) {
    if (logic.searchMode && !logic.selecting) {
      bool focus = logic.searchMode;
      return TextField(
        decoration:
            InputDecoration(border: InputBorder.none, hintText: "搜索".tl),
        controller: logic.textFieldController,
        onChanged: (s) {
          logic.updateKeyword(s.toLowerCase(), updateTextField: false);
        },
      );
    } else {
      String suffix = '';
      if (logic.selectedTagId != null) {
        final tagName = logic.getTagName(logic.selectedTagId ?? 0);
        if (tagName.isNotEmpty) {
          suffix = ' [$tagName]';
        }
      }
      return logic.selecting
          ? Text("已选择 @num 个项目$suffix"
              .tlParams({"num": logic.selectedNum.toString()}))
          : Text(
              '${"已下载".tl}(${logic.baseComics.length}, ${logic.allComicSize})$suffix');
    }
  }

  List<Widget> buildActions(BuildContext context, DownloadPageLogic logic) {
    return [
      if (!logic.selecting)
        Tooltip(
          message: "标签管理".tl,
          child: IconButton(
            icon: const Icon(Icons.label_outline),
            onPressed: () async {
              final tagId = await App.globalTo(() => const TagManagementPage());
              if (tagId != null && tagId is int) {
                // 应用标签筛选
                logic.updateTagFilter(tagId);
              }
            },
          ),
        ),
      if (!logic.selecting)
        Tooltip(
          message: "排序".tl,
          child: IconButton(
            icon: const Icon(Icons.sort),
            onPressed: () async {
              await _showComicSortDialog(context, logic);
            },
          ),
        ),
      if (!logic.selecting && !logic.searchMode)
        Tooltip(
          message: "下载管理器".tl,
          child: IconButton(
            icon: const Icon(Icons.download_for_offline),
            onPressed: () {
              showPopUpWidget(
                App.globalContext!,
                const DownloadingPage(),
              );
            },
          ),
        )
      else if (logic.selecting)
        Tooltip(
          message: "更多".tl,
          child: IconButton(
            icon: const Icon(Icons.more_horiz),
            onPressed: () {
              _showSelectingMenu(context, logic);
            },
          ),
        ),
      if (!logic.selecting)
        Tooltip(
          message: "搜索".tl,
          child: IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              logic.updateSearchMode(!logic.searchMode);
              logic.update();
            },
          ),
        )
    ];
  }

  void _showSelectingMenu(BuildContext context, DownloadPageLogic logic) {
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(MediaQuery.of(context).size.width - 60,
          50, MediaQuery.of(context).size.width - 60, 50),
      items: [
        PopupMenuItem(
          child: Text("全选".tl),
          onTap: () {
            logic.selected.addAll(logic.comics.map((e) => e.id));
            logic.update();
          },
        ),
        PopupMenuItem(
          child: Text("管理标签".tl),
          onTap: () => Future.delayed(
            const Duration(milliseconds: 200),
            () async {
              final selectedComics = logic.selectedComics;
              final suggestedTags = [
                ...selectedComics.map((e) => e.name),
                ...selectedComics.map((e) => e.subTitle),
                ...selectedComics.expand((e) => logic.getOriginalTags(e)),
              ];

              final result = await showDialog<bool>(
                context: App.globalContext!,
                builder: (context) => TagAssignmentDialog(
                  comicIds: selectedComics.map((e) => e.id).toList(),
                  suggestedTags: suggestedTags,
                ),
              );
              if (result == true) {
                logic.exitSelecting();
                logic.refreshTags();
              }
            },
          ),
        ),
        PopupMenuItem(
          child: Text("重命名下载目录".tl),
          onTap: () => Future.delayed(
            const Duration(milliseconds: 200),
            () async {
              await showDialog(
                context: App.globalContext!,
                builder: (context) => RenameDownloadDialog(
                  comics: logic.selectedComics,
                  onComplete: () {
                    logic.exitSelecting();
                    logic.refresh();
                  },
                ),
              );
            },
          ),
        ),
        // PopupMenuItem(
        //   child: Text("导出".tl),
        //   onTap: () => exportSelectedComic(context, logic),
        // ),
        // PopupMenuItem(
        //   child: Text("导出为pdf".tl),
        //   onTap: () => exportAsPdf(null, logic),
        // ),
        PopupMenuItem(
          child: Text("查看漫画详情".tl),
          onTap: () => Future.delayed(const Duration(milliseconds: 200), () {
            if (logic.selectedNum != 1) {
              showToast(message: "请选择一个漫画".tl);
            } else {}
          }),
        ),
        PopupMenuItem(
          child: Text("更新漫画文件大小".tl),
          onTap: () => Future.delayed(
            const Duration(milliseconds: 200),
            () async {
              await showDialog(
                context: App.globalContext!,
                builder: (context) => UpdateSizeDialog(
                  comics: logic.selectedComics,
                  onComplete: () {
                    logic.exitSelecting();
                    logic.refresh();
                  },
                ),
              );
            },
          ),
        ),
        PopupMenuItem(
          child: Text("添加至本地收藏".tl),
          onTap: () => Future.delayed(
            const Duration(milliseconds: 200),
            () => addToLocalFavoriteFolder(App.globalContext!, logic),
          ),
        ),
      ],
    );
  }

  Future<void> _showComicSortDialog(
      BuildContext context, DownloadPageLogic logic) async {
    bool changed = false;
    await showDialog(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: Text("漫画排序模式".tl),
          children: [
            SizedBox(
              width: 400,
              child: Column(
                children: [
                  ListTile(
                    title: Text("漫画排序模式".tl),
                    trailing: Select(
                      initialValue: int.parse(appdata.settings[26][0]),
                      onChange: (i) {
                        appdata.settings[26] =
                            appdata.settings[26].setValueAt(i.toString(), 0);
                        appdata.updateSettings();
                        changed = true;
                      },
                      values: ["时间", "漫画名", "作者名", "大小"].tl,
                    ),
                  ),
                  ListTile(
                    title: Text("倒序".tl),
                    trailing: StatefulSwitch(
                      initialValue: appdata.settings[26][1] == "1",
                      onChanged: (b) {
                        if (b) {
                          appdata.settings[26] =
                              appdata.settings[26].setValueAt("1", 1);
                        } else {
                          appdata.settings[26] =
                              appdata.settings[26].setValueAt("0", 1);
                        }
                        appdata.updateSettings();
                        changed = true;
                      },
                    ),
                  ),
                ],
              ),
            )
          ],
        );
      },
    );
    if (changed) {
      logic.refresh();
    }
  }

  void addToLocalFavoriteFolder(BuildContext context, DownloadPageLogic logic) {
    String? folder;
    showDialog(
      context: App.globalContext!,
      builder: (context) => SimpleDialog(
        title: const Text("复制到..."),
        children: [
          SizedBox(
            width: 400,
            height: 132,
            child: Column(
              children: [
                FutureBuilder<List<String>>(
                    future: LocalFavoritesManager().folderNames,
                    builder: (context, snapshot) {
                      final folderNames = snapshot.data;
                      if (folderNames == null) {
                        return const SizedBox();
                      }
                      return ListTile(
                        title: Text("收藏夹".tl),
                        trailing: Select(
                          width: 156,
                          values: folderNames,
                          initialValue: null,
                          onChange: (i) => folder = folderNames[i],
                        ),
                      );
                    }),
                const Spacer(),
                Center(
                  child: FilledButton(
                    child: Text("确认".tl),
                    onPressed: () {
                      if (folder == null) {
                        return;
                      }
                      final comics = logic.selectedComics;
                      for (final c in comics) {
                        var comic = c;
                        LocalFavoritesManager().addComic(
                            folder!,
                            switch (comic.type) {
                              DownloadType.picacg => FavoriteItem.fromPicacg(
                                  (comic as DownloadedComic)
                                      .comicItem
                                      .toBrief()),
                              DownloadType.ehentai => FavoriteItem.fromEhentai(
                                  (comic as DownloadedGallery)
                                      .gallery
                                      .toBrief()),
                              DownloadType.jm => FavoriteItem.fromJmComic(
                                  (comic as DownloadedJmComic).comic.toBrief()),
                              DownloadType.nhentai => FavoriteItem.fromNhentai(
                                  NhentaiComicBrief(
                                      comic.name,
                                      (comic as NhentaiDownloadedComic).cover,
                                      comic.id,
                                      "", const [])),
                              DownloadType.hitomi => FavoriteItem.fromHitomi(
                                  (comic as DownloadedHitomiComic)
                                      .comic
                                      .toBrief(comic.link, comic.cover)),
                              DownloadType.htmanga => FavoriteItem.fromHtcomic(
                                  (comic as DownloadedHtComic).comic.toBrief()),
                              DownloadType.other => () {
                                  var c = (comic as CustomDownloadedItem);
                                  return FavoriteItem.custom(CustomComic(
                                      c.name,
                                      c.subTitle,
                                      c.cover,
                                      c.comicId,
                                      c.tags,
                                      "",
                                      c.sourceKey));
                                }(),
                              DownloadType.favorite =>
                                throw UnimplementedError(),
                            });
                      }

                      App.globalBack();
                    },
                  ),
                ),
                const SizedBox(
                  height: 16,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class DownloadedComicInfoView extends StatefulWidget {
  const DownloadedComicInfoView(this.item, this.logic, {Key? key})
      : super(key: key);
  final DownloadedItem item;
  final DownloadPageLogic logic;

  @override
  State<DownloadedComicInfoView> createState() =>
      _DownloadedComicInfoViewState();
}

class _DownloadedComicInfoViewState extends State<DownloadedComicInfoView> {
  String name = "";
  List<String> eps = [];
  List<int> downloadedEps = [];
  late final comic = widget.item;

  deleteEpisode(int i) {
    showConfirmDialog(context, "确认删除".tl, "要删除这个章节吗".tl, () async {
      var message = await DownloadManager().deleteEpisode(comic, i);
      if (message == null) {
        setState(() {});
      } else {
        showToast(message: message);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    getInfo();
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 16, 0, 16),
            child: Text(
              name,
              style: const TextStyle(fontSize: 22),
            ),
          ),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 300,
                childAspectRatio: 4,
              ),
              itemBuilder: (BuildContext context, int i) {
                return Padding(
                  padding: const EdgeInsets.all(4),
                  child: InkWell(
                    borderRadius: const BorderRadius.all(Radius.circular(16)),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius:
                            const BorderRadius.all(Radius.circular(16)),
                        color: downloadedEps.contains(i)
                            ? Theme.of(context).colorScheme.primaryContainer
                            : Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                      ),
                      child: Row(
                        children: [
                          const SizedBox(
                            width: 16,
                          ),
                          Expanded(
                            child: Text(
                              eps[i],
                            ),
                          ),
                          const SizedBox(
                            width: 4,
                          ),
                          if (downloadedEps.contains(i))
                            const Icon(Icons.download_done),
                          const SizedBox(
                            width: 16,
                          ),
                        ],
                      ),
                    ),
                    onTap: () => readSpecifiedEps(i),
                    onLongPress: () {
                      deleteEpisode(i);
                    },
                    onSecondaryTapDown: (details) {
                      deleteEpisode(i);
                    },
                  ),
                );
              },
              itemCount: eps.length,
            ),
          ),
          SizedBox(
              height: 50,
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton(
                        onPressed: () {
                          App.globalBack();
                          _toComicInfoPage(widget.item);
                        },
                        child: Text("查看详情".tl)),
                  ),
                  const SizedBox(
                    width: 16,
                  ),
                  Expanded(
                    child: FilledButton(
                        onPressed: () => read(), child: Text("阅读".tl)),
                  ),
                ],
              )),
          SizedBox(
            height: MediaQuery.of(context).padding.bottom,
          )
        ],
      ),
    );
  }

  void getInfo() {
    name = comic.name;
    eps = comic.eps;
    downloadedEps = comic.downloadedEps;
  }

  void read() {
    comic.read();
  }

  void readSpecifiedEps(int i) {
    comic.read(ep: i + 1);
  }
}

class DownloadedComicTile extends ComicTile {
  final String id;
  final String size;
  final File imagePath;
  final String author;
  final String name;
  final String type;

  @override
  final List<String> primaryTags;
  final List<String> tag;
  final void Function() onTap;
  final void Function() onLongTap;
  final void Function(TapDownDetails details) onSecondaryTap;
  final void Function(String tag)? onTagTap;
  final void Function(String tag)? onPrimaryTagTap;
  @override
  final void Function(String tag, TapDownDetails details)? onTagSecondaryTap;
  @override
  final void Function(String tag, TapDownDetails details)?
      onPrimaryTagSecondaryTap;

  List<String>? get tags => tag
      .map((e) => App.locale.languageCode == "zh" ? e.translateTagsToCN : e)
      .toList();

  @override
  String get description => "${size}MB";

  @override
  Widget get image => Image.file(
        imagePath,
        fit: BoxFit.cover,
        height: double.infinity,
        cacheWidth:
            (100 * MediaQuery.of(App.globalContext!).devicePixelRatio).toInt(),
      );

  @override
  void onTap_() => onTap();

  @override
  String get subTitle => author;

  @override
  String get title => name;

  @override
  void onLongTap_() => onLongTap();

  @override
  void onSecondaryTap_(details) => onSecondaryTap(details);

  @override
  Widget? get badge => Text(type);

  const DownloadedComicTile({
    required this.id,
    required this.size,
    required this.imagePath,
    required this.author,
    required this.name,
    required this.onTap,
    required this.onLongTap,
    required this.onSecondaryTap,
    required this.type,
    required this.tag,
    this.primaryTags = const [],
    this.onTagTap,
    this.onPrimaryTagTap,
    this.onTagSecondaryTap,
    this.onPrimaryTagSecondaryTap,
    super.key,
  });
}

void _toComicInfoPage(DownloadedItem comic) {
  var context = App.mainNavigatorKey!.currentContext!;
  if (comic is DownloadedComic) {
    context.to(() => PicacgComicPage((comic).comicItem.id, null));
  } else if (comic is DownloadedGallery) {
    context.to(() => EhGalleryPage((comic).gallery.toBrief()));
  } else if (comic is DownloadedJmComic) {
    context.to(() => JmComicPage((comic).comic.id));
  } else if (comic is DownloadedHitomiComic) {
    context.to(() => HitomiComicPage(comic.toBrief()));
  } else if (comic is DownloadedHtComic) {
    context.to(() => HtComicPage(comic.id.replaceFirst('Ht', '')));
  } else if (comic is NhentaiDownloadedComic) {
    context.to(() => NhentaiComicPage(comic.id.replaceFirst("nhentai", "")));
  } else if (comic is CustomDownloadedItem) {
    context.to(() => ComicPage(sourceKey: comic.sourceKey, id: comic.comicId));
  }
}

class TagInfo {
  final int id;
  final String name;
  String? coverPath;
  final int comicCount;
  final int category;
  final int sortOrder;
  final int categorySortOrder;

  TagInfo({
    required this.id,
    required this.name,
    this.coverPath,
    required this.comicCount,
    this.category = 0,
    this.sortOrder = 0,
    this.categorySortOrder = 0,
  });

  TagInfo copyWith({
    int? id,
    String? name,
    String? coverPath,
    int? comicCount,
    int? category,
    int? sortOrder,
    int? categorySortOrder,
  }) {
    return TagInfo(
      id: id ?? this.id,
      name: name ?? this.name,
      coverPath: coverPath ?? this.coverPath,
      comicCount: comicCount ?? this.comicCount,
      category: category ?? this.category,
      sortOrder: sortOrder ?? this.sortOrder,
      categorySortOrder: categorySortOrder ?? this.categorySortOrder,
    );
  }

  @override
  String toString() {
    return 'TagInfo{id: $id, name: $name, coverPath: $coverPath, comicCount: $comicCount, category: $category, sortOrder: $sortOrder, categorySortOrder: $categorySortOrder}';
  }

  factory TagInfo.fromMap(Map<String, dynamic> map) {
    return TagInfo(
      id: TypeUtil.parseInt(map['id']),
      name: TypeUtil.parseString(map['name']),
      coverPath: map['cover_path'] == null
          ? null
          : TypeUtil.parseString(map['cover_path']),
      comicCount: TypeUtil.parseInt(map['comic_count']),
      category: TypeUtil.parseInt(map['category']),
      sortOrder: TypeUtil.parseInt(map['sort_order']),
      categorySortOrder: TypeUtil.parseInt(map['category_sort_order']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'cover_path': coverPath,
      'comic_count': comicCount,
      'category': category,
      'sort_order': sortOrder,
      'category_sort_order': categorySortOrder,
    };
  }
}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  _SliverAppBarDelegate(
      {required this.child, required this.maxHeight, required this.minHeight});

  final double minHeight;
  final double maxHeight;
  final Widget child;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return SizedBox.expand(
      child: child,
    );
  }

  @override
  double get maxExtent => minHeight;

  @override
  double get minExtent => max(maxHeight, minHeight);

  @override
  bool shouldRebuild(SliverPersistentHeaderDelegate oldDelegate) {
    // 始终重建以确保内容变化时能够更新
    return true;
  }
}
