import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pica_comic/foundation/file_utils.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/foundation/local_favorites.dart';
import 'package:pica_comic/network/base_comic.dart';
import 'package:pica_comic/network/download/custom_download_model.dart';
import 'package:pica_comic/network/download/download_model.dart';
import 'package:pica_comic/network/download/models/download_color_tag.dart';
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
import 'package:pica_comic/pages/download/translation_result_replace_dialog.dart';
import 'package:pica_comic/pages/download/translation_result_replacer.dart';
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

/// 显示下载批量操作结果。
void showDownloadBatchResultToast(
  DownloadBatchResult result, {
  required String actionName,
}) {
  if (result.successCount == 0 && result.failedCount == 0) {
    showToast(message: "没有可操作的网络漫画".tl);
    return;
  }

  showToast(
    message:
        "$actionName ${result.successCount} 项，跳过 ${result.skippedCount} 项，失败 ${result.failedCount} 项",
  );
}

/// 显示重新下载选项，并返回是否覆盖已有文件。
Future<bool?> showRedownloadDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (context) {
      var overwriteExisting = false;
      return StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text("重新下载".tl),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CheckboxListTile(
                value: overwriteExisting,
                title: Text("覆盖已有文件".tl),
                subtitle: Text("勾选后会重新下载并替换同名图片".tl),
                contentPadding: EdgeInsets.zero,
                onChanged: (value) {
                  setState(() => overwriteExisting = value ?? false);
                },
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: Text("不勾选时只下载缺失图片".tl),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("取消".tl),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, overwriteExisting),
              child: Text("确定".tl),
            ),
          ],
        ),
      );
    },
  );
}

/// 显示删除下载确认对话框，并返回是否删除漫画文件。
Future<bool?> showDeleteDownloadDialog(
  BuildContext context, {
  required int count,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) {
      var deleteFiles = true;
      return StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text("确认删除".tl),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("${"确认删除".tl} $count ${"项".tl}?"),
              CheckboxListTile(
                value: deleteFiles,
                title: Text("删除文件".tl),
                subtitle: Text("同时删除漫画目录中的文件".tl),
                contentPadding: EdgeInsets.zero,
                onChanged: (value) {
                  setState(() => deleteFiles = value ?? false);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("取消".tl),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, deleteFiles),
              child: Text("确认".tl),
            ),
          ],
        ),
      );
    },
  );
}

/// 根据删除文件选项删除下载记录。
Future<void> deleteDownloadedComics(
  List<String> ids, {
  required bool deleteFiles,
}) async {
  if (deleteFiles) {
    await downloadManager.delete(ids);
  } else {
    await downloadManager.deleteWithoutFile(ids);
  }
}

/// 显示漫画颜色选择对话框。
Future<DownloadColorTag?> showDownloadColorDialog(BuildContext context) {
  return showDialog<DownloadColorTag>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text("选择颜色".tl),
      children: [
        for (var tag in DownloadColorTag.values)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, tag),
            child: Row(
              children: [
                if (tag.color != null)
                  Icon(Icons.circle, color: tag.color!, size: 24)
                else
                  const Icon(Icons.circle_outlined, size: 24),
                const SizedBox(width: 12),
                Text(tag.label),
              ],
            ),
          ),
      ],
    ),
  );
}

/// 解析右键菜单的操作目标。
///
/// 选择模式下使用当前选中项，否则使用右键所在漫画。
List<DownloadedItem> resolveDownloadMenuTargets(
  DownloadedItem comic,
  List<DownloadedItem> selectedComics,
) {
  return selectedComics.isEmpty ? [comic] : selectedComics;
}

/// 显示选择模式菜单。
List<PopupMenuEntry<void>> buildSelectingMenuItems({
  required BuildContext context,
  required WidgetRef ref,
  required String pageId,
  required List<DownloadedItem> selectedComics,
  required List<String> Function(DownloadedItem) getOriginalTags,
  required VoidCallback onRefresh,
  required VoidCallback onRefreshTags,
  required VoidCallback onExitSelecting,
}) {
  return [
    popupMenuItem<void>(
      text: "全选".tl,
      icon: Icons.select_all,
      onTap: () {
        final allComics = ref.read(filteredComicsProvider(pageId));
        allComics.whenData((comics) {
          selectAll(ref, pageId, comics.map((e) => e.id).toList());
        });
      },
    ),
    popupMenuItem<void>(
      text: "删除".tl,
      icon: Icons.delete_outline,
      onTap: () {
        if (selectedComics.isEmpty) return;
        Future.delayed(const Duration(milliseconds: 200), () async {
          final deleteFiles = await showDeleteDownloadDialog(
            App.globalContext!,
            count: selectedComics.length,
          );
          if (deleteFiles == null) return;
          await deleteDownloadedComics(
            selectedComics.map((e) => e.id).toList(),
            deleteFiles: deleteFiles,
          );
          onExitSelecting();
          onRefresh();
        });
      },
    ),
    popupMenuItem<void>(
      text: "重新下载".tl,
      icon: Icons.download,
      onTap: () => Future.delayed(const Duration(milliseconds: 200), () async {
        if (selectedComics.isEmpty) return;
        final overwriteExisting = await showRedownloadDialog(
          App.globalContext!,
        );
        if (overwriteExisting == null) return;
        final result = await downloadManager.redownloadComics(
          selectedComics,
          overwriteExisting: overwriteExisting,
        );
        showDownloadBatchResultToast(result, actionName: "已加入重新下载队列".tl);
        if (result.successCount > 0) {
          onExitSelecting();
          onRefresh();
        }
      }),
    ),
    popupMenuItem<void>(
      text: "更新封面".tl,
      icon: Icons.refresh,
      onTap: () => Future.delayed(const Duration(milliseconds: 200), () async {
        final result = await downloadManager.refreshComicCovers(selectedComics);
        showDownloadBatchResultToast(result, actionName: "已更新封面".tl);
        if (result.successCount > 0) {
          onExitSelecting();
          onRefresh();
        }
      }),
    ),
    popupMenuItem<void>(
      text: "管理标签".tl,
      icon: Icons.label_outline,
      onTap: () => Future.delayed(const Duration(milliseconds: 200), () async {
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
      }),
    ),
    popupMenuItem<void>(
      text: "标记颜色".tl,
      icon: Icons.color_lens_outlined,
      onTap: () => Future.delayed(const Duration(milliseconds: 200), () async {
        final color = await showDownloadColorDialog(App.globalContext!);
        if (color == null) return;
        await downloadManager.batchUpdateColor(
          selectedComics.map((e) => e.id).toList(),
          color,
        );
        onExitSelecting();
        onRefresh();
      }),
    ),
    popupMenuItem<void>(
      text: "重命名下载目录".tl,
      icon: Icons.drive_file_rename_outline,
      onTap: () => Future.delayed(const Duration(milliseconds: 200), () async {
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
      }),
    ),
    popupMenuItem<void>(
      text: "查看漫画详情".tl,
      icon: Icons.info_outline,
      onTap: () => Future.delayed(const Duration(milliseconds: 200), () {
        if (selectedComics.length != 1) {
          showToast(message: "请选择一个漫画".tl);
        } else {
          toComicInfoPage(selectedComics.first);
        }
      }),
    ),
    popupMenuItem<void>(
      text: "更新漫画文件大小".tl,
      icon: Icons.data_usage,
      onTap: () => Future.delayed(const Duration(milliseconds: 200), () async {
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
      }),
    ),
    popupMenuItem<void>(
      text: "添加至本地收藏".tl,
      icon: Icons.favorite_border,
      onTap: () => Future.delayed(
        const Duration(milliseconds: 200),
        () => addToLocalFavoriteFolder(
          context: App.globalContext!,
          comics: selectedComics,
        ),
      ),
    ),
  ];
}

/// 构建漫画排序下拉菜单。
Widget buildComicSortMenuAnchor({required VoidCallback onChanged}) {
  final currentSortType = appdata.settings[26][0];
  final isAscending = appdata.settings[26][1] == "1";

  void updateSetting(int index, String value) {
    if (appdata.settings[26][index] == value) return;
    appdata.settings[26] = appdata.settings[26].setValueAt(value, index);
    appdata.updateSettings();
    onChanged();
  }

  return MenuAnchor(
    menuChildren: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text("漫画排序模式".tl),
      ),
      ...[
        ("时间", Icons.schedule_outlined),
        ("漫画名", Icons.title),
        ("作者名", Icons.person_outline),
        ("大小", Icons.data_usage),
      ].asMap().entries.map((entry) {
        final value = entry.key.toString();
        return MenuItemButton(
          leadingIcon: Icon(entry.value.$2),
          trailingIcon: currentSortType == value
              ? const Icon(Icons.check)
              : const SizedBox(width: 24),
          onPressed: () => updateSetting(0, value),
          child: Text(entry.value.$1.tl),
        );
      }),
      const Divider(height: 1),
      MenuItemButton(
        leadingIcon: const Icon(Icons.arrow_upward),
        trailingIcon: isAscending
            ? const Icon(Icons.check)
            : const SizedBox(width: 24),
        onPressed: () => updateSetting(1, "1"),
        child: Text("正序".tl),
      ),
      MenuItemButton(
        leadingIcon: const Icon(Icons.arrow_downward),
        trailingIcon: !isAscending
            ? const Icon(Icons.check)
            : const SizedBox(width: 24),
        onPressed: () => updateSetting(1, "0"),
        child: Text("倒序".tl),
      ),
    ],
    builder: (context, controller, child) {
      return Tooltip(
        message: "排序".tl,
        child: IconButton(
          icon: const Icon(Icons.sort),
          onPressed: () {
            if (controller.isOpen) {
              controller.close();
            } else {
              controller.open();
            }
          },
        ),
      );
    },
  );
}

/// 显示下载类型筛选菜单
List<PopupMenuEntry<DownloadType?>> buildDownloadTypeFilterMenuItems({
  required WidgetRef ref,
  required String pageId,
}) {
  final pageState = ref.read(downloadPageStateProvider(pageId));

  return [
    PopupMenuItem<DownloadType?>(
      value: null,
      child: Row(
        children: [
          Icon(
            pageState.downloadTypeFilter == null && !pageState.excludeLocal
                ? Icons.check
                : Icons.select_all,
            size: 20,
          ),
          const SizedBox(width: 12),
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
          Icon(
            pageState.excludeLocal ? Icons.check : Icons.public_off,
            size: 20,
          ),
          const SizedBox(width: 12),
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
            Icon(
              pageState.downloadTypeFilter == type
                  ? Icons.check
                  : Icons.category_outlined,
              size: 20,
            ),
            const SizedBox(width: 12),
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
  ];
}

/// 显示右键菜单
Future<void> showTileContextMenu({
  required BuildContext context,
  required TapDownDetails details,
  required DownloadedItem comic,
  required List<String> Function(DownloadedItem) getOriginalTags,
  required VoidCallback onRefresh,
  required VoidCallback onRefreshTags,
  required VoidCallback onRemoveComic,
  required VoidCallback onShowInfo,
  VoidCallback? onShowImageList,
  List<DownloadedItem> selectedComics = const <DownloadedItem>[],
  VoidCallback? onBatchComplete,
}) async {
  final translationResultRootDirectory =
      appdata.appSettings.translationResultDirectory;
  final isBatch = selectedComics.isNotEmpty;
  final targetComics = resolveDownloadMenuTargets(comic, selectedComics);
  String buildBatchMenuText(String text) {
    final translatedText = text.tl;
    return isBatch ? '$translatedText（${targetComics.length}）' : translatedText;
  }

  final canRedownloadTarget = targetComics.any(downloadManager.canRedownload);
  final canRefreshCoverTarget = targetComics.any(
    downloadManager.canRefreshCover,
  );
  final hasTranslationResult = isBatch
      ? true
      : await TranslationResultReplacer().hasReplacementCandidate(
          comic.directoryPath,
          translationResultRootDirectory: translationResultRootDirectory,
          scanLegacyResultDirectories: true,
        );
  showContextMenu(
    context: App.globalContext!,
    globalPosition: details.globalPosition,
    items: [
      if (hasTranslationResult)
        popupMenuItem<void>(
          text: isBatch ? '应用选中翻译结果（${targetComics.length}）' : '应用翻译结果'.tl,
          icon: Icons.translate,
          onTap: () async {
            await Future<void>.delayed(const Duration(milliseconds: 300));
            if (!context.mounted) return;
            await TranslationResultReplaceDialog.show(
              context,
              comics: targetComics,
              translationResultRootDirectory: translationResultRootDirectory,
              onComplete: onBatchComplete ?? onRefresh,
              scanLegacyResultDirectories: true,
            );
          },
        ),
      popupMenuItem<void>(
        text: "阅读".tl,
        icon: Icons.menu_book_outlined,
        onTap: () async {
          comic.read();
        },
      ),
      popupMenuItem<void>(
        text: "图片列表".tl,
        icon: Icons.photo_library_outlined,
        onTap: () async {
          if (onShowImageList != null) {
            onShowImageList();
          }
        },
      ),
      if (canRedownloadTarget)
        popupMenuItem<void>(
          text: buildBatchMenuText("重新下载"),
          icon: Icons.download,
          onTap: () async {
            await Future.delayed(const Duration(milliseconds: 300));
            final overwriteExisting = await showRedownloadDialog(
              App.globalContext!,
            );
            if (overwriteExisting == null) return;
            final result = await downloadManager.redownloadComics([
              ...targetComics,
            ], overwriteExisting: overwriteExisting);
            showDownloadBatchResultToast(result, actionName: "已加入重新下载队列".tl);
            if (result.successCount > 0) {
              (onBatchComplete ?? onRefresh)();
            }
          },
        ),
      if (canRefreshCoverTarget)
        popupMenuItem<void>(
          text: buildBatchMenuText("更新封面"),
          icon: Icons.refresh,
          onTap: () async {
            await Future.delayed(const Duration(milliseconds: 300));
            final result = await downloadManager.refreshComicCovers(
              targetComics,
            );
            showDownloadBatchResultToast(result, actionName: "已更新封面".tl);
            if (result.successCount > 0) {
              (onBatchComplete ?? onRefresh)();
            }
          },
        ),
      if (comic.downloadedEps.isNotEmpty)
        popupMenuItem<void>(
          text: "查看章节".tl,
          icon: Icons.list_alt,
          onTap: () async {
            Future.delayed(const Duration(milliseconds: 300), () {
              onShowInfo();
            });
          },
        ),
      popupMenuItem<void>(
        text: buildBatchMenuText("删除"),
        icon: Icons.delete_outline,
        onTap: () {
          Future.delayed(const Duration(milliseconds: 200), () async {
            final deleteFiles = await showDeleteDownloadDialog(
              App.globalContext!,
              count: targetComics.length,
            );
            if (deleteFiles == null) return;
            await deleteDownloadedComics(
              targetComics.map((e) => e.id).toList(),
              deleteFiles: deleteFiles,
            );
            (onBatchComplete ?? onRemoveComic)();
          });
        },
      ),
      popupMenuItem<void>(
        text: "查看漫画详情".tl,
        icon: Icons.info_outline,
        onTap: () {
          Future.delayed(const Duration(milliseconds: 300), () {
            toComicInfoPage(comic);
          });
        },
      ),
      popupMenuItem<void>(
        text: buildBatchMenuText("更新文件大小"),
        icon: Icons.data_usage,
        onTap: () async {
          await Future.delayed(const Duration(milliseconds: 300));
          if (!context.mounted) return;
          await showDialog(
            context: context,
            builder: (context) => UpdateSizeDialog(
              comics: targetComics,
              onComplete: onBatchComplete ?? onRefresh,
            ),
          );
        },
      ),
      popupMenuItem<void>(
        text: buildBatchMenuText("管理标签"),
        icon: Icons.label_outline,
        onTap: () async {
          await Future.delayed(const Duration(milliseconds: 300));
          if (!context.mounted) return;
          final suggestedTags = [
            ...targetComics.map((e) => e.name),
            ...targetComics.map((e) => e.subTitle),
            ...targetComics.expand(getOriginalTags),
          ];
          final result = await showDialog<bool>(
            context: context,
            builder: (context) => TagAssignmentDialog(
              comicIds: targetComics.map((e) => e.id).toList(),
              suggestedTags: suggestedTags,
            ),
          );
          if (result == true) {
            (onBatchComplete ?? onRefreshTags)();
          }
        },
      ),
      popupMenuItem<void>(
        text: buildBatchMenuText("标记颜色"),
        icon: Icons.color_lens_outlined,
        onTap: () async {
          await Future.delayed(const Duration(milliseconds: 300));
          final color = await showDownloadColorDialog(App.globalContext!);
          if (color == null) return;
          if (isBatch) {
            await downloadManager.batchUpdateColor(
              targetComics.map((e) => e.id).toList(),
              color,
            );
          } else {
            await downloadManager.updateColor(comic.id, color);
          }
          (onBatchComplete ?? onRefresh)();
        },
      ),
      popupMenuItem<void>(
        text: "复制路径".tl,
        icon: Icons.content_copy,
        onTap: () async {
          Future.delayed(const Duration(milliseconds: 300), () async {
            var path = await downloadManager.getFullDirectory(comic.id);
            Clipboard.setData(ClipboardData(text: path));
          });
        },
      ),
      popupMenuItem<void>(
        text: "打开文件".tl,
        icon: Icons.folder_open,
        onTap: () async {
          var path = await downloadManager.getFullDirectory(comic.id);
          FileUtils.openFileOrDirectory(path);
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
                            (comic as DownloadedComic).comicItem.toBrief(),
                          ),
                          DownloadType.ehentai => FavoriteItem.fromEhentai(
                            (comic as DownloadedGallery).gallery.toBrief(),
                          ),
                          DownloadType.jm => FavoriteItem.fromJmComic(
                            (comic as DownloadedJmComic).comic.toBrief(),
                          ),
                          DownloadType.nhentai => FavoriteItem.fromNhentai(
                            NhentaiComicBrief(
                              comic.name,
                              (comic as NhentaiDownloadedComic).cover,
                              comic.id,
                              "",
                              const [],
                            ),
                          ),
                          DownloadType.hitomi => FavoriteItem.fromHitomi(
                            (comic as DownloadedHitomiComic).comic.toBrief(
                              comic.link,
                              comic.cover,
                            ),
                          ),
                          DownloadType.htmanga => FavoriteItem.fromHtcomic(
                            (comic as DownloadedHtComic).comic.toBrief(),
                          ),
                          DownloadType.other => () {
                            var c = (comic as CustomDownloadedItem);
                            return FavoriteItem.custom(
                              CustomComic(
                                c.name,
                                c.subTitle,
                                c.cover,
                                c.comicId,
                                c.tags,
                                "",
                                c.sourceKey,
                              ),
                            );
                          }(),
                          DownloadType.favorite => throw UnimplementedError(),
                          DownloadType.local => throw UnimplementedError(
                            '本地漫画不支持添加到收藏',
                          ),
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
      buildComicSortMenuAnchor(onChanged: () => triggerSortUpdate(ref)),
    if (!isSelecting && !isSearchMode)
      Tooltip(
        message: "下载管理器".tl,
        child: IconButton(
          icon: const Icon(Icons.download_for_offline),
          onPressed: () {
            showPopUpWidget(App.globalContext!, const DownloadingPage());
          },
        ),
      ),
    if (!isSelecting)
      PopupMenuButton<DownloadType?>(
        tooltip: "类型筛选".tl,
        position: PopupMenuPosition.under,
        icon: const Icon(Icons.filter_list),
        itemBuilder: (_) =>
            buildDownloadTypeFilterMenuItems(ref: ref, pageId: pageId),
      )
    else if (isSelecting)
      PopupMenuButton<void>(
        tooltip: "更多".tl,
        position: PopupMenuPosition.under,
        icon: const Icon(Icons.more_horiz),
        itemBuilder: (_) => buildSelectingMenuItems(
          context: context,
          ref: ref,
          pageId: pageId,
          selectedComics: selectedComics,
          getOriginalTags: getOriginalTags,
          onRefresh: onRefresh,
          onRefreshTags: onRefreshTags,
          onExitSelecting: onExitSelecting,
        ),
      ),
    if (!isSelecting)
      Tooltip(
        message: "搜索".tl,
        child: IconButton(
          icon: const Icon(Icons.search),
          onPressed: onToggleSearchMode,
        ),
      ),
  ];
}
