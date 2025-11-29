import 'dart:io';
import 'dart:ui';

import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as Path;
import 'package:flutter/material.dart';
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
import 'package:pica_comic/tools/extensions.dart';
import 'package:pica_comic/tools/image_utils.dart';
import 'package:pica_comic/tools/io_extensions.dart';
import 'package:pica_comic/tools/io_tools.dart';
import 'package:pica_comic/tools/pdf.dart';
import 'package:pica_comic/tools/tags_translation.dart';
import 'package:pica_comic/tools/translations.dart';
import 'package:open_file/open_file.dart';
import '../components/components.dart';
import '../pages/components/download_tag_filter_panel.dart';
import '../foundation/app.dart';
import '../foundation/state_controller.dart';
import '../foundation/ui_mode.dart';
import '../network/app_dio.dart';
import '../network/base_comic.dart';
import '../network/custom_download_model.dart';
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

  List<DownloadedItem> get selectedComics =>
      baseComics.where((element) => selected.contains(element.id)).toList();

  ///已下载的漫画
  var comics = <DownloadedItem>[];

  var baseComics = <DownloadedItem>[];

  final Map<int, DownloadTag> _tagInfoMap = {};

  bool _searchMode = false;

  bool get searchMode => _searchMode;

  Future<void> updateSearchMode(bool mode) async {
    _searchMode = mode;
    await updateComics();
    update();
  }

  bool searchInit = false;

  String _keyword = "";

  /// 当前选中的标签筛选
  int? selectedTagId;

  /// 是否展开标签
  bool expandTags = false;

  /// 所有标签
  List<TagInfo> allTags = [];

  final textFieldController = TextEditingController();

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
      _keyword = keyword;
      _searchMode = true;
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
    if (tagId == selectedTagId) {
      selectedTagId = null;
    } else {
      selectedTagId = tagId;
    }
    await updateComics();
    update();
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

  @override
  void refresh() {
    _loadComics();
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
    await Future.wait([
      for (var comic in allComics)
        DownloadManager().fillDownloadingItemCover(comic),
    ]);
    baseComics = allComics;
    comicUserTags = await downloadManager.getAllComicTagsMap();
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
                  ? _tagInfoMap[e.id]!
                      .coverComicId! // This is comic ID, we need path. logic.
                  : null,
            ))
        .toList();

    // Fill cover paths
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
    this.allTags.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    await updateComics();
    // if (isFirstLoad) {
    //   await Future.delayed(const Duration(milliseconds: 150));
    // }
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
          floatingActionButton: buildFAB(context, logic),
          appBar: buildAppbar(context, logic),
          body: Column(
            children: [
              if (!logic.selecting) _buildTagFilter(context, logic),
              Expanded(
                child: CustomScrollView(
                  slivers: [buildComics(context, logic)],
                ),
              ),
            ],
          ),
        );
      },
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

  void downloadFont() async {
    bool canceled = false;
    var cancelToken = CancelToken();
    var controller = showLoadingDialog(
      App.globalContext!,
      onCancel: () {
        canceled = true;
        cancelToken.cancel();
      },
      barrierDismissible: false,
      allowCancel: true,
      message: "Downloading",
    );
    var dio = logDio();
    try {
      await dio.download(
        "https://raw.githubusercontent.com/Pacalini/PicaComic/master/fonts/NotoSansSC-Regular.ttf",
        "${App.dataPath}/font.ttf",
        cancelToken: cancelToken,
      );
    } catch (e) {
      showToast(message: "下载失败".tl);
      controller.close();
      return;
    }
    if (!canceled) {
      controller.close();
      showToast(message: "下载完成".tl);
    }
  }

  void exportAsPdf(DownloadedItem? comic, DownloadPageLogic logic) async {
    if (comic == null) {
      for (var a in logic.comics) {
        final c = logic.comics.firstWhereOrNull((e) => e.id == a);
        if (c != null) {
          comic = c;
        }
      }
    }
    if (comic == null) {
      showToast(message: "请选择一个漫画".tl);
      return;
    }
    var file = File("${App.dataPath}/font.ttf");
    if (!App.isWindows && !await file.exists()) {
      showConfirmDialog(App.globalContext!, "缺少字体".tl,
          "需要下载字体文件(10.1MB), 是否继续?".tl, downloadFont);
    } else {
      bool canceled = false;
      var controller = showLoadingDialog(
        App.globalContext!,
        onCancel: () => canceled = true,
        allowCancel: false,
      );
      var fileName = "${comic.name}.pdf";
      fileName = fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '');
      await createPdfFromComicWithIsolate(
          title: comic.name,
          comicPath: await downloadManager.getFullDirectory(comic.id),
          savePath: "${App.cachePath}/$fileName",
          chapters: comic.eps,
          chapterIndexes: comic.downloadedEps);
      if (!canceled) {
        controller.close();
        await exportPdf("${App.cachePath}/$fileName");
      }
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
            borderRadius: const BorderRadius.all(Radius.circular(16))),
        child: DownloadedComicTile(
          id: item.id,
          name: name,
          author: item.subTitle,
          imagePath: File(item.coverPath ?? ''),
          type: type,
          primaryTags: logic.getUserTags(item),
          tag: logic.getOriginalTags(item),
          onTagTap: (tag) => logic.updateKeyword(tag),
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
                  var dirPath =
                      await downloadManager.getFullDirectory(comic.id);
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
                            final fileParentPath =
                                Path.normalize(file.parent.absolute.path);
                            for (final e in comic.downloadedEps) {
                              final epDirPath = Path.normalize("$dirPath/$e");
                              //debugPrint("epDirPath: $epDirPath, fileParent: $fileParent");
                              if (epDirPath == fileParentPath) {
                                ep = e;
                                sFileRelativeFromPath = fileParent.path;
                                final imageNames = (await fileParent
                                        .list(recursive: true)
                                        .toList())
                                    .where(predictImageFile)
                                    .sortedByName()
                                    .map((e) => e.name)
                                    .toList();
                                index =
                                    imageNames.indexOf(Path.basename(absPath));
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
                },
              ),
              DesktopMenuEntry(
                text: "删除".tl,
                onClick: () {
                  showConfirmDialog(context, "确认删除".tl, "此操作无法撤销, 是否继续?".tl,
                      () {
                    final comic = logic.comics[index];
                    downloadManager.delete([comic.id]);
                    logic.removeComic(comic);
                  });
                },
              ),
              DesktopMenuEntry(
                text: "删除(不包括文件)".tl,
                onClick: () {
                  showConfirmDialog(
                      context, "确认删除，不包括文件".tl, "此操作无法撤销, 是否继续?".tl, () {
                    downloadManager.deleteWithoutFile([item.id]);
                    logic.removeComic(item);
                    logic.update();
                  });
                },
              ),
              // DesktopMenuEntry(
              //   text: "导出".tl,
              //   onClick: () =>
              //       Future.delayed(const Duration(milliseconds: 200), () {
              //     Future<void>.delayed(
              //       const Duration(milliseconds: 200),
              //       () => showDialog(
              //         context: App.globalContext!,
              //         barrierDismissible: false,
              //         barrierColor: Colors.black26,
              //         builder: (context) => SimpleDialog(
              //           children: [
              //             SizedBox(
              //               width: 200,
              //               height: 200,
              //               child: Center(
              //                 child: SizedBox(
              //                   width: 50,
              //                   height: 80,
              //                   child: Column(
              //                     children: [
              //                       const SizedBox(
              //                         height: 10,
              //                       ),
              //                       const CircularProgressIndicator(),
              //                       const SizedBox(
              //                         height: 9,
              //                       ),
              //                       Text("打包中".tl)
              //                     ],
              //                   ),
              //                 ),
              //               ),
              //             )
              //           ],
              //         ),
              //       ),
              //     );
              //     Future<void>.delayed(const Duration(milliseconds: 500),
              //         () async {
              //       var res = await exportComic(logic.comics[index].id,
              //           logic.comics[index].name, logic.comics[index].eps);
              //       App.globalBack();
              //       if (res) {
              //         //忽视
              //       } else {
              //         showToast(message: "导出失败".tl);
              //       }
              //     });
              //   }),
              // ),
              // DesktopMenuEntry(
              //   text: "导出为pdf".tl,
              //   onClick: () {
              //     exportAsPdf(logic.comics[index], logic);
              //   },
              // ),
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
                  await downloadManager.updateComicSize(comic);
                  logic.update();
                },
              ),
              // DesktopMenuEntry(
              //   text: "过滤同作者".tl,
              //   onClick: () async {
              //     logic.textFieldController.text = comic.subTitle;
              //     logic.updateKeyword(comic.subTitle);
              //   },
              // ),
              DesktopMenuEntry(
                text: "管理标签".tl,
                onClick: () async {
                  await Future.delayed(const Duration(milliseconds: 300));
                  final result = await showDialog<bool>(
                    context: context,
                    builder: (context) => TagAssignmentDialog(
                      comicIds: [comic.id],
                    ),
                  );
                  if (result == true) {
                    logic.refresh();
                  }
                },
              ),
              DesktopMenuEntry(
                text: "复制路径".tl,
                onClick: () async {
                  Future.delayed(const Duration(milliseconds: 300), () async {
                    var path = await downloadManager.getFullDirectory(comic.id);
                    Clipboard.setData(ClipboardData(text: path));
                  });
                },
              ),
              DesktopMenuEntry(
                text: "打开文件".tl,
                onClick: () async {
                  var path = await downloadManager.getFullDirectory(comic.id);
                  OpenFile.open(path);
                },
              ),
            ]);
          },
        ),
      ),
    );
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

  PreferredSizeWidget buildAppbar(
      BuildContext context, DownloadPageLogic logic) {
    Widget? leading;
    if (logic.selecting || logic.selectedTagId != null || logic.searchMode) {
      leading = IconButton(
        onPressed: () {
          if (logic.selecting) {
            logic.selecting = false;
            logic.selected.clear();
            logic.update();
          } else if (logic.selectedTagId != null) {
            logic.updateTagFilter(null);
          } else if (logic.searchMode) {
            logic.updateSearchMode(false);
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
    Log.d(
        "selecting: ${logic.selecting}, tagId: ${logic.selectedTagId}, searchMode: ${logic.searchMode}, leading: $leading");
    return Appbar(
      // radius: UiMode.m1(context) ? 0 : 16,
      backgroundColor: logic.selecting
          ? Theme.of(context).colorScheme.primaryContainer
          : null,
      leading: leading,
      title: buildTitle(context, logic),
      actions: buildActions(context, logic),
    );
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
              bool changed = false;
              await showDialog(
                  context: context,
                  builder: (context) => SimpleDialog(
                        title: Text("漫画排序模式".tl),
                        children: [
                          SizedBox(
                            width: 400,
                            child: Column(
                              children: [
                                ListTile(
                                  title: Text("漫画排序模式".tl),
                                  trailing: Select(
                                    initialValue:
                                        int.parse(appdata.settings[26][0]),
                                    onChange: (i) {
                                      appdata.settings[26] = appdata
                                          .settings[26]
                                          .setValueAt(i.toString(), 0);
                                      appdata.updateSettings();
                                      changed = true;
                                    },
                                    values: ["时间", "漫画名", "作者名", "大小"].tl,
                                  ),
                                ),
                                ListTile(
                                  title: Text("倒序".tl),
                                  trailing: StatefulSwitch(
                                    initialValue:
                                        appdata.settings[26][1] == "1",
                                    onChanged: (b) {
                                      if (b) {
                                        appdata.settings[26] = appdata
                                            .settings[26]
                                            .setValueAt("1", 1);
                                      } else {
                                        appdata.settings[26] = appdata
                                            .settings[26]
                                            .setValueAt("0", 1);
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
                      ));
              if (changed) {
                logic.refresh();
              }
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
              showMenu(
                  context: context,
                  position: RelativeRect.fromLTRB(
                      MediaQuery.of(context).size.width - 60,
                      50,
                      MediaQuery.of(context).size.width - 60,
                      50),
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
                          final result = await showDialog<bool>(
                            context: App.globalContext!,
                            builder: (context) => TagAssignmentDialog(
                              comicIds: logic.selectedComics
                                  .map((e) => e.id)
                                  .toList(),
                            ),
                          );
                          if (result == true) {
                            logic.refresh();
                          }
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
                      onTap: () =>
                          Future.delayed(const Duration(milliseconds: 200), () {
                        if (logic.selectedNum != 1) {
                          showToast(message: "请选择一个漫画".tl);
                        } else {}
                      }),
                    ),
                    PopupMenuItem(
                      child: Text("更新漫画文件大小".tl),
                      onTap: () async {
                        final selected = List.from(logic.selected);
                        final comics = List.from(logic.comics);
                        for (int i = 0; i < selected.length; i++) {
                          if (selected[i]) {
                            await downloadManager.updateComicSize(comics[i]);
                            logic.update();
                            await Future.delayed(
                                const Duration(milliseconds: 50));
                          }
                        }
                        showToast(message: "更新完成".tl);
                      },
                    ),
                    PopupMenuItem(
                      child: Text("添加至本地收藏".tl),
                      onTap: () => Future.delayed(
                        const Duration(milliseconds: 200),
                        () =>
                            addToLocalFavoriteFolder(App.globalContext!, logic),
                      ),
                    ),
                  ]);
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

  void exportSelectedComic(BuildContext context, DownloadPageLogic logic) {
    if (logic.selectedNum == 0) {
      showToast(message: "请选择漫画".tl);
    } else {
      Future<void>.delayed(
        const Duration(milliseconds: 200),
        () => showDialog(
          context: App.globalContext!,
          barrierColor: Colors.black26,
          barrierDismissible: false,
          builder: (context) => const SimpleDialog(
            children: [
              SizedBox(
                width: 200,
                height: 200,
                child: Center(
                  child: SizedBox(
                    width: 50,
                    height: 75,
                    child: Column(
                      children: [
                        SizedBox(
                          height: 10,
                        ),
                        CircularProgressIndicator(),
                        SizedBox(
                          height: 9,
                        ),
                        Text("打包中")
                      ],
                    ),
                  ),
                ),
              )
            ],
          ),
        ),
      );
      Future<void>.delayed(
          const Duration(milliseconds: 500), () => export(logic));
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
                                    DownloadType.picacg =>
                                      FavoriteItem.fromPicacg(
                                          (comic as DownloadedComic)
                                              .comicItem
                                              .toBrief()),
                                    DownloadType.ehentai =>
                                      FavoriteItem.fromEhentai(
                                          (comic as DownloadedGallery)
                                              .gallery
                                              .toBrief()),
                                    DownloadType.jm => FavoriteItem.fromJmComic(
                                        (comic as DownloadedJmComic)
                                            .comic
                                            .toBrief()),
                                    DownloadType.nhentai =>
                                      FavoriteItem.fromNhentai(
                                          NhentaiComicBrief(
                                              comic.name,
                                              (comic as NhentaiDownloadedComic)
                                                  .cover,
                                              comic.id,
                                              "",
                                              const [])),
                                    DownloadType.hitomi =>
                                      FavoriteItem.fromHitomi((comic
                                              as DownloadedHitomiComic)
                                          .comic
                                          .toBrief(comic.link, comic.cover)),
                                    DownloadType.htmanga =>
                                      FavoriteItem.fromHtcomic(
                                          (comic as DownloadedHtComic)
                                              .comic
                                              .toBrief()),
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
                )
              ],
            ));
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
