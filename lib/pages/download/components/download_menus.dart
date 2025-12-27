

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_file/open_file.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/foundation/local_favorites.dart';
import 'package:pica_comic/network/base_comic.dart';
import 'package:pica_comic/network/download/custom_download_model.dart';
import 'package:pica_comic/network/download/download_manager.dart';
import 'package:pica_comic/network/download/download_model.dart';
import 'package:pica_comic/network/eh_network/eh_download_model.dart';
import 'package:pica_comic/network/hitomi_network/hitomi_download_model.dart';
import 'package:pica_comic/network/htmanga_network/ht_download_model.dart';
import 'package:pica_comic/network/jm_network/jm_download.dart';
import 'package:pica_comic/network/nhentai_network/download.dart';
import 'package:pica_comic/network/nhentai_network/nhentai_main_network.dart';
import 'package:pica_comic/network/picacg_network/picacg_download_model.dart';
import 'package:pica_comic/pages/download/downloading_page.dart';
import 'package:pica_comic/pages/download/import_local_comic_dialog.dart';
import 'package:pica_comic/pages/download/local_repository_management_page.dart';
import 'package:pica_comic/pages/rename_download_dialog.dart';

import 'package:pica_comic/pages/download/tag_assignment_dialog.dart';
import 'package:pica_comic/pages/download/tag_management_page.dart';
import 'package:pica_comic/pages/update_size_dialog.dart';
import 'package:pica_comic/tools/extensions.dart';
import 'package:pica_comic/tools/translations.dart';

import '../download_providers.dart';
import 'package:pica_comic/pages/download/download_helper.dart';
import 'download_tile.dart';

/// 获取下载类型的显示名称
String getDownloadTypeName(DownloadType type) {
  switch (type) {
    case DownloadType.picacg:
      return "哔咔";
    case DownloadType.ehentai:
      return "E-Hentai";
    case DownloadType.jm:
      return "禁漫";
    case DownloadType.hitomi:
      return "Hitomi";
    case DownloadType.htmanga:
      return "HTManga";
    case DownloadType.nhentai:
      return "nhentai";
    case DownloadType.other:
      return "其他";
    case DownloadType.favorite:
      return "收藏";
    case DownloadType.local:
      return "本地".tl;
  }
}

/// 显示选择模式菜单
void showSelectingMenu({
  required BuildContext context,
  required WidgetRef ref,
  required String pageId,
  required List<DownloadedItem> selectedComics,
  required List<String> Function(DownloadedItem) getOriginalTags,
  required VoidCallback onRefresh,
  required VoidCallback onRefreshTags,
  required VoidCallback onExitSelecting,
}) {
  showMenu(
    context: context,
    position: RelativeRect.fromLTRB(
      MediaQuery.of(context).size.width - 60,
      50,
      MediaQuery.of(context).size.width - 60,
      50,
    ),
    items: [
      PopupMenuItem(
        child: Text("全选".tl),
        onTap: () {
          final allComics = ref.read(filteredComicsProvider(pageId));
          allComics.whenData((comics) {
            selectAll(ref, pageId, comics.map((e) => e.id).toList());
          });
        },
      ),
      PopupMenuItem(
        child: Text("删除".tl),
        onTap: () {
          if (selectedComics.isEmpty) return;
          Future.delayed(const Duration(milliseconds: 200), () {
            showDialog(
              context: App.globalContext!,
              builder: (context) => AlertDialog(
                title: Text("确认删除".tl),
                content: Text("${"确认删除".tl} ${selectedComics.length} ${"项".tl}?"),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text("取消".tl),
                  ),
                  TextButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      await DownloadManager().delete(
                        selectedComics.map((e) => e.id).toList(),
                      );
                      onExitSelecting();
                      onRefresh();
                    },
                    child: Text("确认".tl),
                  ),
                ],
              ),
            );
          });
        },
      ),
      PopupMenuItem(
        child: Text("管理标签".tl),
        onTap: () => Future.delayed(
          const Duration(milliseconds: 200),
          () async {
            final suggestedTags = [
              ...selectedComics.map((e) => e.name),
              ...selectedComics.map((e) => e.subTitle),
              ...selectedComics.expand((e) => getOriginalTags(e)),
            ];

            final result = await showDialog<bool>(
              context: App.globalContext!,
              builder: (context) => TagAssignmentDialog(
                comicIds: selectedComics.map((e) => e.id).toList(),
                suggestedTags: suggestedTags,
              ),
            );
            if (result == true) {
              onExitSelecting();
              onRefreshTags();
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
                comics: selectedComics,
                onComplete: () {
                  onExitSelecting();
                  onRefresh();
                },
              ),
            );
          },
        ),
      ),
      PopupMenuItem(
        child: Text("查看漫画详情".tl),
        onTap: () => Future.delayed(const Duration(milliseconds: 200), () {
          if (selectedComics.length != 1) {
            showToast(message: "请选择一个漫画".tl);
          } else {
            toComicInfoPage(selectedComics.first);
          }
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
                comics: selectedComics,
                onComplete: () {
                  onExitSelecting();
                  onRefresh();
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
          () => addToLocalFavoriteFolder(
            context: App.globalContext!,
            comics: selectedComics,
          ),
        ),
      ),
    ],
  );
}

/// 显示排序对话框
Future<void> showComicSortDialog({
  required BuildContext context,
  required VoidCallback onRefresh,
}) async {
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
    onRefresh();
  }
}

/// 显示下载类型筛选菜单
void showDownloadTypeFilterMenu({
  required BuildContext buttonContext,
  required WidgetRef ref,
  required String pageId,
}) {
  final RenderBox? renderBox = buttonContext.findRenderObject() as RenderBox?;
  if (renderBox == null) return;

  final Offset offset = renderBox.localToGlobal(Offset.zero);
  final Size buttonSize = renderBox.size;
  final Size screenSize = MediaQuery.of(App.globalContext!).size;
  final pageState = ref.read(downloadPageStateProvider(pageId));

  showMenu<DownloadType?>(
    context: App.globalContext!,
    position: RelativeRect.fromLTRB(
      offset.dx,
      offset.dy + buttonSize.height,
      screenSize.width - offset.dx - buttonSize.width,
      screenSize.height - offset.dy - buttonSize.height,
    ),
    items: [
      PopupMenuItem<DownloadType?>(
        value: null,
        child: Row(
          children: [
            if (pageState.downloadTypeFilter == null && !pageState.excludeLocal)
              const Icon(Icons.check, size: 20),
            const SizedBox(width: 8),
            Text("全部".tl),
          ],
        ),
        onTap: () {
          Future.delayed(const Duration(milliseconds: 100), () {
            updateDownloadTypeFilter(ref, pageId, null);
            updateExcludeLocal(ref, pageId, false);
          });
        },
      ),
      PopupMenuItem<DownloadType?>(
        child: Row(
          children: [
            if (pageState.excludeLocal) const Icon(Icons.check, size: 20),
            if (!pageState.excludeLocal) const SizedBox(width: 28),
            Text("非本地".tl),
          ],
        ),
        onTap: () {
          Future.delayed(const Duration(milliseconds: 100), () {
            updateExcludeLocal(ref, pageId, !pageState.excludeLocal);
          });
        },
      ),
      const PopupMenuDivider(),
      ...DownloadType.values.map((type) {
        final typeName = getDownloadTypeName(type);
        return PopupMenuItem<DownloadType?>(
          value: type,
          child: Row(
            children: [
              if (pageState.downloadTypeFilter == type)
                const Icon(Icons.check, size: 20),
              if (pageState.downloadTypeFilter != type)
                const SizedBox(width: 28),
              Text(typeName),
            ],
          ),
          onTap: () {
            Future.delayed(const Duration(milliseconds: 100), () {
              updateDownloadTypeFilter(ref, pageId, type);
            });
          },
        );
      }),
    ],
  );
}

/// 显示右键菜单
void showTileContextMenu({
  required BuildContext context,
  required TapDownDetails details,
  required DownloadedItem comic,
  required List<String> Function(DownloadedItem) getOriginalTags,
  required VoidCallback onRefresh,
  required VoidCallback onRefreshTags,
  required VoidCallback onRemoveComic,
  required VoidCallback onShowInfo,
  VoidCallback? onShowImageList,
}) {
  showDesktopMenu(
    App.globalContext!,
    Offset(details.globalPosition.dx, details.globalPosition.dy),
    [
      DesktopMenuEntry(
        text: "阅读".tl,
        onClick: () async {
          comic.read();
        },
      ),
      DesktopMenuEntry(
        text: "图片列表".tl,
        onClick: () async {
          if (onShowImageList != null) {
             onShowImageList();
          }
        },
      ),
      if (comic.downloadedEps.isNotEmpty)
        DesktopMenuEntry(
          text: "查看章节".tl,
          onClick: () async {
            Future.delayed(const Duration(milliseconds: 300), () {
              onShowInfo();
            });
          },
        ),
      if (comic.type != DownloadType.local)
        DesktopMenuEntry(
          text: "删除".tl,
          onClick: () {
            showConfirmDialog(context, "确认删除".tl, "此操作无法撤销, 是否继续?".tl, () {
              downloadManager.delete([comic.id]);
              onRemoveComic();
            });
          },
        ),
      DesktopMenuEntry(
        text: "删除(不包括文件)".tl,
        onClick: () {
          showConfirmDialog(context, "确认删除，不包括文件".tl, "此操作无法撤销, 是否继续?".tl, () {
            downloadManager.deleteWithoutFile([comic.id]);
            onRemoveComic();
          });
        },
      ),
      DesktopMenuEntry(
        text: "查看漫画详情".tl,
        onClick: () {
          Future.delayed(const Duration(milliseconds: 300), () {
            toComicInfoPage(comic);
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
              onComplete: onRefresh,
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
            ...getOriginalTags(comic),
          ];
          final result = await showDialog<bool>(
            context: context,
            builder: (context) => TagAssignmentDialog(
              comicIds: [comic.id],
              suggestedTags: suggestedTags,
            ),
          );
          if (result == true) {
            onRefreshTags();
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
    ],
  );
}

/// 添加到本地收藏夹
void addToLocalFavoriteFolder({
  required BuildContext context,
  required List<DownloadedItem> comics,
}) {
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
                },
              ),
              const Spacer(),
              Center(
                child: FilledButton(
                  child: Text("确认".tl),
                  onPressed: () {
                    if (folder == null) {
                      return;
                    }
                    for (final comic in comics) {
                      LocalFavoritesManager().addComic(
                        folder!,
                        switch (comic.type) {
                          DownloadType.picacg => FavoriteItem.fromPicacg(
                              (comic as DownloadedComic).comicItem.toBrief()),
                          DownloadType.ehentai => FavoriteItem.fromEhentai(
                              (comic as DownloadedGallery).gallery.toBrief()),
                          DownloadType.jm => FavoriteItem.fromJmComic(
                              (comic as DownloadedJmComic).comic.toBrief()),
                          DownloadType.nhentai => FavoriteItem.fromNhentai(
                              NhentaiComicBrief(
                                  comic.name,
                                  (comic as NhentaiDownloadedComic).cover,
                                  comic.id,
                                  "",
                                  const [])),
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
                          DownloadType.favorite => throw UnimplementedError(),
                          DownloadType.local =>
                            throw UnimplementedError('本地漫画不支持添加到收藏'),
                        },
                      );
                    }
                    App.globalBack();
                  },
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ],
    ),
  );
}

/// 构建 AppBar 操作按钮
List<Widget> buildAppBarActions({
  required BuildContext context,
  required WidgetRef ref,
  required String pageId,
  required bool isSelecting,
  required bool isSearchMode,
  required List<DownloadedItem> selectedComics,
  required List<String> Function(DownloadedItem) getOriginalTags,
  required VoidCallback onRefresh,
  required VoidCallback onRefreshTags,
  required VoidCallback onExitSelecting,
  required VoidCallback onToggleSearchMode,
}) {
  return [
    if (!isSelecting)
      Tooltip(
        message: "标签管理".tl,
        child: IconButton(
          icon: const Icon(Icons.label_outline),
          onPressed: () async {
            final tagId = await App.globalTo(() => const TagManagementPage());
            if (tagId != null && tagId is int) {
              updateTagFilter(ref, pageId, tagId);
            }
          },
        ),
      ),
    if (!isSelecting)
      Tooltip(
        message: "导入本地漫画".tl,
        child: IconButton(
          icon: const Icon(Icons.folder_open),
          onPressed: () async {
            await showDialog(
              context: context,
              builder: (context) => const ImportLocalComicDialog(),
            );
            onRefresh();
          },
        ),
      ),
    if (!isSelecting)
      Tooltip(
        message: "存储库管理".tl,
        child: IconButton(
          icon: const Icon(Icons.storage),
          onPressed: () {
            App.globalTo(() => const LocalRepositoryManagementPage());
          },
        ),
      ),
    if (!isSelecting)
      Tooltip(
        message: "排序".tl,
        child: IconButton(
          icon: const Icon(Icons.sort),
          onPressed: () async {
            await showComicSortDialog(context: context, onRefresh: onRefresh);
          },
        ),
      ),
    if (!isSelecting && !isSearchMode)
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
      ),
    if (!isSelecting)
      Builder(
        builder: (buttonContext) => Tooltip(
          message: "类型筛选".tl,
          child: IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () {
              showDownloadTypeFilterMenu(
                buttonContext: buttonContext,
                ref: ref,
                pageId: pageId,
              );
            },
          ),
        ),
      )
    else if (isSelecting)
      Tooltip(
        message: "更多".tl,
        child: IconButton(
          icon: const Icon(Icons.more_horiz),
          onPressed: () {
            showSelectingMenu(
              context: context,
              ref: ref,
              pageId: pageId,
              selectedComics: selectedComics,
              getOriginalTags: getOriginalTags,
              onRefresh: onRefresh,
              onRefreshTags: onRefreshTags,
              onExitSelecting: onExitSelecting,
            );
          },
        ),
      ),
    if (!isSelecting)
      Tooltip(
        message: "搜索".tl,
        child: IconButton(
          icon: const Icon(Icons.search),
          onPressed: onToggleSearchMode,
        ),
      )
  ];
}
