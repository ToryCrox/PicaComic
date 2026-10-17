import 'package:pica_comic/foundation/app_settings_provider.dart';
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/foundation/history.dart';
import 'package:pica_comic/foundation/log.dart';
import 'package:pica_comic/network/download/download_manager.dart';
import 'package:pica_comic/pages/comic_page.dart';
import 'package:pica_comic/pages/pre_search_page.dart';
import 'package:pica_comic/pages/reader/comic_reading_page.dart';
import 'package:pica_comic/tools/translations.dart';
import 'package:flutter/material.dart';
import 'package:pica_comic/tools/tags_translation.dart';
import 'package:pica_comic/pages/download/download_helper.dart';
import 'favorite_action_widgets.dart';
import 'favorites_order_page.dart';
import 'local_favorites_providers.dart';
import 'network_to_local.dart';
import 'package:pica_comic/foundation/local_favorites.dart';
import 'package:pica_comic/components/components.dart';
import '../../foundation/app.dart';
import '../../network/comic_source_services.dart';
import '../../tools/io_tools.dart';

extension LocalFavoritesExt on FavoriteItem {
  String toDownloadId(DownloadManager manager) =>
      manager.getDownloadIdFromComicId(type.comicType, target);

  Future<void> addDownload(DownloadManager manager) async {
    if (await manager.isExists(toDownloadId(manager))) {
      return;
    }
    try {
      manager.addFavoriteDownload(this);
    } catch (e) {
      Log.e("Failed to add a download.\n Missing comic source config file.");
    }
  }
}

/// 收藏信息更新的兼容界面入口，任务由 Riverpod 管理。
abstract final class UpdateFavoritesInfoDialog {
  /// 启动或复用目标收藏夹的更新任务。
  static Future<void> show(List<FavoriteItem> comics, String folder) =>
      showFavoriteJobDialog(
        App.globalContext!,
        folder: folder,
        title: '更新漫画信息'.tl,
        start: (job) => job.updateItems(comics),
      );
}

/// 创建收藏夹并在弹窗生命周期内管理输入草稿。
class CreateFolderDialog extends ConsumerStatefulWidget {
  const CreateFolderDialog({super.key});

  @override
  ConsumerState<CreateFolderDialog> createState() => _CreateFolderDialogState();
}

class _CreateFolderDialogState extends ConsumerState<CreateFolderDialog> {
  final controller = TextEditingController();
  final focusNode = FocusNode();

  @override
  void dispose() {
    controller.dispose();
    focusNode.dispose();
    super.dispose();
  }

  Future<void> _submit(BuildContext context, WidgetRef ref, String name) async {
    try {
      await ref.read(localFavoritesProvider.notifier).createFolder(name);
      if (context.mounted) context.pop();
    } catch (e) {
      showToast(message: e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: Text("创建收藏夹".tl),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
          child: TextField(
            focusNode: focusNode,
            autofocus: true,
            controller: controller,
            onEditingComplete: () =>
                unawaited(_submit(context, ref, controller.text)),
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: "名称".tl,
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: 260,
          child: Row(
            children: [
              const Spacer(),
              TextButton(
                child: Text("从文件导入".tl),
                onPressed: () async {
                  final actions = ref.read(localFavoritesProvider.notifier);
                  context.pop();
                  var data = await getDataFromUserSelectedFile(["json"]);
                  if (data == null) {
                    return;
                  }
                  await performFavoriteAction(() => actions.importFolder(data));
                },
              ),
              const Spacer(),
              TextButton(
                child: Text("从网络导入".tl),
                onPressed: () async {
                  App.globalBack();
                  await Future.delayed(const Duration(milliseconds: 200));
                  networkToLocal();
                },
              ),
              const Spacer(),
            ],
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 35,
          child: Center(
            child: FilledButton(
              onPressed: () =>
                  unawaited(_submit(context, ref, controller.text)),
              child: Text("提交".tl),
            ),
          ),
        ),
      ],
    );
  }
}

/// 重命名收藏夹，输入控制器随弹窗释放。
class RenameFolderDialog extends ConsumerStatefulWidget {
  const RenameFolderDialog(this.before, {super.key});
  final String before;

  @override
  ConsumerState<RenameFolderDialog> createState() => _RenameFolderDialogState();
}

class _RenameFolderDialogState extends ConsumerState<RenameFolderDialog> {
  late final controller = TextEditingController(text: widget.before);
  final focusNode = FocusNode();

  @override
  void dispose() {
    controller.dispose();
    focusNode.dispose();
    super.dispose();
  }

  Future<void> _submit(BuildContext context, WidgetRef ref, String name) async {
    try {
      await ref
          .read(localFavoritesProvider.notifier)
          .renameFolder(widget.before, name);
      if (context.mounted) context.pop();
    } catch (e) {
      showToast(message: e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: Text("重命名".tl),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            autofocus: true,
            onEditingComplete: () =>
                unawaited(_submit(context, ref, controller.text)),
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: "名称".tl,
            ),
          ),
        ),
        const SizedBox(width: 200, height: 10),
        SizedBox(
          height: 35,
          child: Center(
            child: TextButton(
              onPressed: () =>
                  unawaited(_submit(context, ref, controller.text)),
              child: Text("提交".tl),
            ),
          ),
        ),
      ],
    );
  }
}

class LocalFavoriteTile extends ComicTile {
  const LocalFavoriteTile(
    this.comic,
    this.folderName,
    this._enableLongPressed, {
    this.showFolderInfo = false,
    this.onLongPressed,
    this.onTap,
    super.key,
  });

  final FavoriteItem comic;

  final String folderName;

  /// return true to disable default action
  final bool Function()? onTap;

  final bool _enableLongPressed;

  final void Function()? onLongPressed;

  final bool showFolderInfo;

  @override
  Widget? buildBadge(BuildContext context, WidgetRef ref) {
    final downloaded = ref.watch(favoriteDownloadedProvider(comic.identity));
    return downloaded.asData?.value == true
        ? Text('已下载'.tl)
        : const SizedBox.shrink();
  }

  @override
  bool get enableLongPressed => _enableLongPressed;

  @override
  String get description => "${comic.time} | ${comic.type.name}";

  @override
  bool get showFavorite => false;

  @override
  Widget buildImage(BuildContext context, WidgetRef ref) {
    final cover = ref.watch(
      favoriteCoverProvider((
        type: comic.type.key,
        target: comic.target,
        cover: comic.coverPath,
      )),
    );
    return cover.when(
      data: (file) => Image.file(
        file,
        fit: BoxFit.cover,
        height: double.infinity,
        filterQuality: FilterQuality.medium,
      ),
      loading: () =>
          ColoredBox(color: Theme.of(context).colorScheme.secondaryContainer),
      error: (_, __) => Center(
        child: IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () => ref.invalidate(
            favoriteCoverProvider((
              type: comic.type.key,
              target: comic.target,
              cover: comic.coverPath,
            )),
          ),
        ),
      ),
    );
  }

  BuildContext get context => App.mainNavigatorKey!.currentContext!;

  void showInfo() {
    if (comic.type.comicSource == null) {
      showToast(message: "漫画源已移除".tl);
      return;
    }
    context.to(
      () => ComicPage(
        comicType: comic.type.comicSource!.key,
        id: comic.target,
        cover: comic.coverPath,
      ),
    );
  }

  @override
  String get subTitle => comic.author;

  @override
  String get title => comic.name;

  List<String> _generateTags(List<String> tags) {
    if (App.locale.languageCode != "zh") {
      return tags;
    }
    List<String> res = [];
    List<String> res2 = [];
    for (var tag in tags) {
      if (tag.contains(":")) {
        var splits = tag.split(":");
        var lowLevelKey = ["character", "artist", "cosplayer", "group"];
        if (lowLevelKey.contains(splits[0])) {
          res2.add(splits[1].translateTagsToCN);
        } else {
          res.add(splits[1].translateTagsToCN);
        }
      } else {
        var name = tag;
        if (name.contains('♀')) {
          name = "${name.replaceFirst(" ♀", "").translateTagsToCN}♀";
        } else if (name.contains('♂')) {
          name = "${name.replaceFirst(" ♂", "").translateTagsToCN}♂";
        } else {
          name = name.translateTagsToCN;
        }
        res.add(name);
      }
    }
    return res + res2;
  }

  @override
  List<String>? get tags => _generateTags(comic.tags);

  @override
  void onSecondaryTap_(
    TapDownDetails details,
    WidgetRef ref,
    String defaultFavoriteFolder,
  ) {
    final manager = ref.read(downloadManagerProvider.notifier);
    final context = App.globalContext!;
    showContextMenu(
      context: context,
      globalPosition: details.globalPosition,
      items: [
        popupMenuItem(text: "查看".tl, icon: Icons.info_outline, onTap: showInfo),
        popupMenuItem(
          text: "阅读".tl,
          icon: Icons.menu_book_outlined,
          onTap: () => readComic(manager),
        ),
        popupMenuItem(
          text: "搜索".tl,
          icon: Icons.search,
          onTap: () {
            if (context.mounted) {
              context.to(() => PreSearchPage(initialValue: title));
            }
          },
        ),
        popupMenuItem(
          text: "取消收藏".tl,
          icon: Icons.favorite_border,
          onTap: () {
            unawaited(
              performFavoriteAction(
                () => favoriteActionsOf(context).deleteComic(folderName, comic),
              ),
            );
          },
        ),
        popupMenuItem(
          text: "复制到".tl,
          icon: Icons.drive_file_move_outlined,
          onTap: copyTo,
        ),
        popupMenuItem(
          text: "编辑标签".tl,
          icon: Icons.edit_outlined,
          onTap: editTags,
        ),
        popupMenuItem(
          text: "下载".tl,
          icon: Icons.download,
          onTap: () {
            comic.addDownload(manager);
            showToast(message: "已添加下载任务".tl);
          },
        ),
        popupMenuItem(
          text: "更新漫画信息".tl,
          icon: Icons.sync,
          onTap: () {
            UpdateFavoritesInfoDialog.show([comic], folderName);
          },
        ),
      ],
    );
  }

  @override
  void onLongTap_(WidgetRef ref, String defaultFavoriteFolder) {
    if (onLongPressed != null) {
      onLongPressed!();
    } else {
      showMenu(ref.read(downloadManagerProvider.notifier));
    }
  }

  void showMenu(DownloadManager manager) {
    showDialog(
      context: App.globalContext!,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: SelectableText(
                  title.replaceAll("\n", ""),
                  style: const TextStyle(fontSize: 22),
                ),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.article),
                title: Text("查看详情".tl),
                onTap: () {
                  App.back(context);
                  showInfo();
                },
              ),
              ListTile(
                leading: const Icon(Icons.bookmark_remove),
                title: Text("取消收藏".tl),
                onTap: () {
                  App.globalBack();
                  unawaited(
                    performFavoriteAction(
                      () => favoriteActionsOf(
                        context,
                      ).deleteComic(folderName, comic),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.chrome_reader_mode_rounded),
                title: Text("阅读".tl),
                onTap: () {
                  App.globalBack();
                  readComic(manager);
                },
              ),
              ListTile(
                leading: const Icon(Icons.copy),
                title: Text("复制到".tl),
                onTap: () {
                  App.globalBack();
                  copyTo();
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit_note),
                title: Text("编辑标签".tl),
                onTap: () {
                  App.globalBack();
                  editTags();
                },
              ),
              ListTile(
                leading: const Icon(Icons.download),
                title: Text("下载".tl),
                onTap: () {
                  App.globalBack();
                  comic.addDownload(manager);
                  showToast(message: "已添加下载任务".tl);
                },
              ),
              ListTile(
                leading: const Icon(Icons.update),
                title: Text("更新漫画信息".tl),
                onTap: () {
                  App.globalBack();
                  UpdateFavoritesInfoDialog.show([comic], folderName);
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> readComic(DownloadManager manager) async {
    final downloadId = comic.toDownloadId(manager);
    if (await manager.isExists(downloadId)) {
      var download = await manager.getComicOrNull(downloadId);
      if (download != null) {
        download.read();
        return;
      }
    }
    bool cancel = false;
    var controller = showLoadingDialog(
      App.globalContext!,
      onCancel: () => cancel = true,
      barrierDismissible: false,
    );
    switch (comic.type.comicType) {
      case ComicType.picacg:
        {
          var res = await appComicSourceServices.picacg.getEps(comic.target);
          if (cancel) return;
          controller.close();
          if (res.error) {
            showToast(message: res.errorMessage ?? "Error");
          } else {
            var history = await HistoryManager().find(comic.target);
            if (history == null) {
              history = History(
                HistoryType.picacg,
                DateTime.now(),
                comic.name,
                comic.author,
                comic.coverPath,
                0,
                0,
                comic.target,
              );
              await HistoryManager().addHistory(history);
            }
            App.globalTo(
              () => ComicReadingPage.picacg(
                comic.target,
                history!.ep,
                res.data,
                comic.name,
                initialPage: history.page,
              ),
            );
          }
        }
      case ComicType.ehentai:
        {
          var res = await appComicSourceServices.ehentai.getGalleryInfo(
            comic.target,
          );
          if (cancel) return;
          controller.close();
          if (res.error) {
            showToast(message: res.errorMessage ?? "Error");
          } else {
            var history = await History.findOrCreate(res.data);
            App.globalTo(
              () =>
                  ComicReadingPage.ehentai(res.data, initialPage: history.page),
            );
          }
        }
      case ComicType.jm:
        {
          var res = await appComicSourceServices.jm.getComicInfo(comic.target);
          if (cancel) return;
          controller.close();
          if (res.error) {
            showToast(message: res.errorMessage ?? "Error");
          } else {
            var history = await History.findOrCreate(res.data);
            App.globalTo(
              () => ComicReadingPage.jmComic(
                res.data,
                history.ep,
                initialPage: history.page,
              ),
            );
          }
        }
      case ComicType.hitomi:
        {
          var res = await appComicSourceServices.hitomi.getComicInfo(
            comic.target,
          );
          if (cancel) return;
          controller.close();
          if (res.error) {
            showToast(message: res.errorMessage ?? "Error");
          } else {
            var history = await History.findOrCreate(res.data);
            App.globalTo(
              () => ComicReadingPage.hitomi(
                res.data,
                comic.target,
                initialPage: history.page,
              ),
            );
          }
        }
      case ComicType.htmanga:
        {
          var res = await appComicSourceServices.htmanga.getComicInfo(
            comic.target,
          );
          if (cancel) return;
          controller.close();
          if (res.error) {
            showToast(message: res.errorMessage ?? "Error");
          } else {
            var history = await History.findOrCreate(res.data);
            App.globalTo(
              () => ComicReadingPage.htmanga(
                res.data.id,
                comic.name,
                initialPage: history.page,
              ),
            );
          }
        }
      case ComicType.nhentai:
        {
          var res = await appComicSourceServices.nhentai.getComicInfo(
            comic.target,
          );
          if (cancel) return;
          controller.close();
          if (res.error) {
            showToast(message: res.errorMessage ?? "Error");
          } else {
            var history = await History.findOrCreate(res.data);
            App.globalTo(
              () => ComicReadingPage.nhentai(
                res.data.id,
                res.data.title,
                initialPage: history.page,
              ),
            );
          }
        }
      default:
        {
          if (comic.type.comicSource == null) {
            showToast(message: "漫画源已移除".tl);
            controller.close();
            return;
          }
          var res = await loadComicInfoFromProvider(
            ProviderScope.containerOf(App.globalContext!, listen: false),
            ComicInfoQuery(comic.type.comicSource!.key.name, comic.target),
          );
          if (cancel) return;
          controller.close();
          if (res.error) {
            showToast(message: res.errorMessage ?? "Error");
          } else {
            var history = await History.findOrCreate(res.data);
            App.globalTo(
              () => ComicReadingPage(
                ReadingData.fromSource(
                  res.data.target,
                  res.data.title,
                  comic.type.comicSource,
                  res.data.chapters,
                ),
                history.page,
                history.ep,
              ),
            );
          }
        }
    }
  }

  @override
  ActionFunc? readAction(WidgetRef ref) =>
      () => readComic(ref.read(downloadManagerProvider.notifier));

  /// 复制当前快照，目标收藏夹由弹窗选择。
  void copyTo() => copyAllTo(folderName, [comic]);

  @override
  void onTapWithRef(WidgetRef ref) {
    if (onTap != null) {
      var res = onTap!();
      if (res) return;
    }
    if (!comic.available) {
      showToast(message: "无效的漫画".tl);
      return;
    }
    if (ref.read(appSettingProvider(AppSettingKeys.localFavoriteTapAction)) ==
        "0") {
      showInfo();
    } else {
      readComic(ref.read(downloadManagerProvider.notifier));
    }
  }

  @override
  String get comicID => comic.target;

  Future<void> editTags() async {
    final tags = comic.tags.toList();
    final controller = TextEditingController();
    try {
      await showDialog(
        context: App.globalContext!,
        builder: (context) {
          return SimpleDialog(
            elevation: 1,
            title: Text("编辑标签".tl),
            children: [
              StatefulBuilder(
                builder: (context, setState) => SizedBox(
                  width: 400,
                  child: Column(
                    children: [
                      Wrap(
                        children: tags
                            .map(
                              (e) => Container(
                                margin: const EdgeInsets.all(4),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.secondaryContainer,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(e),
                                    const SizedBox(width: 4),
                                    InkWell(
                                      mouseCursor: appClickableMouseCursor,
                                      borderRadius: BorderRadius.circular(10),
                                      child: const Icon(Icons.close, size: 20),
                                      onTap: () {
                                        tags.remove(e);
                                        setState(() {});
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 56,
                        child: TextField(
                          controller: controller,
                          decoration: InputDecoration(
                            border: const UnderlineInputBorder(),
                            suffix: IconButton(
                              icon: const Icon(Icons.add),
                              onPressed: () {
                                var value = controller.text;
                                if (value.isNotEmpty) {
                                  controller.clear();
                                  tags.add(value);
                                  setState(() {});
                                }
                              },
                            ).paddingTop(8),
                          ),
                          onSubmitted: (value) {
                            if (value.isNotEmpty) {
                              tags.add(value);
                              controller.clear();
                              setState(() {});
                            }
                          },
                        ),
                      ).paddingHorizontal(36),
                      const SizedBox(height: 16),
                      Center(
                        child: FilledButton(
                          onPressed: () async {
                            final actions = favoriteActionsOf(context);
                            if (await performFavoriteAction(
                                  () =>
                                      actions.editTags(folderName, comic, tags),
                                ) &&
                                context.mounted) {
                              Navigator.pop(context);
                            }
                          },
                          child: Text("提交".tl),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      );
    } finally {
      controller.dispose();
    }
  }
}

/// 复制收藏的选择弹窗。
void copyAllTo(String source, List<FavoriteItem> comics) {
  showDialog(
    context: App.globalContext!,
    builder: (_) => _CopyFavoritesDialog(comics),
  );
}

/// 未提交的目标选择留在界面内，列表和操作由 Provider 管理。
class _CopyFavoritesDialog extends ConsumerStatefulWidget {
  const _CopyFavoritesDialog(this.comics);
  final List<FavoriteItem> comics;
  @override
  ConsumerState<_CopyFavoritesDialog> createState() =>
      _CopyFavoritesDialogState();
}

class _CopyFavoritesDialogState extends ConsumerState<_CopyFavoritesDialog> {
  String? _folder;
  @override
  Widget build(BuildContext context) {
    final folders = ref.watch(localFavoritesProvider);
    return SimpleDialog(
      title: Text('复制到'.tl),
      children: [
        folders.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => TextButton(
            onPressed: () => ref.invalidate(localFavoritesProvider),
            child: Text('加载失败，点击重试: $error'),
          ),
          data: (data) => SizedBox(
            width: 280,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: Text('收藏夹'.tl),
                  trailing: Select(
                    outline: true,
                    width: 156,
                    values: data.folderNames,
                    initialValue: null,
                    onChange: (i) =>
                        setState(() => _folder = data.folderNames[i]),
                  ),
                ),
                FilledButton(
                  onPressed:
                      _folder == null || !data.folderNames.contains(_folder)
                      ? null
                      : () async {
                          final actions = ref.read(
                            localFavoritesProvider.notifier,
                          );
                          if (await performFavoriteAction(
                                () =>
                                    actions.copyComics(_folder!, widget.comics),
                              ) &&
                              context.mounted) {
                            Navigator.pop(context);
                          }
                        },
                  child: Text('确认'.tl),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 收藏夹作品排序入口。
class LocalFavoritesFolder extends StatelessWidget {
  const LocalFavoritesFolder(this.name, {super.key});
  final String name;
  @override
  Widget build(BuildContext context) => FavoritesOrderPage(folder: name);
}

/// 检查任务保留已经完成的结果，普通网络错误不标记失效。
Future<void> checkFolder(String name) async {
  final context = App.globalContext!;
  final container = ProviderScope.containerOf(context, listen: false);
  try {
    final items = await container.read(folderFavoritesProvider(name).future);
    if (!context.mounted) return;
    await showFavoriteJobDialog(
      context,
      folder: name,
      title: '检查漫画存活'.tl,
      start: (job) => job.updateItems(items, checkAvailability: true),
    );
  } catch (error) {
    showToast(message: '检查失败: $error');
  }
}
