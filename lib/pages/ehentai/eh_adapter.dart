import 'dart:math';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../base.dart';
import '../../components/components.dart';
import '../../comic_source/built_in/ehentai.dart';
import '../../foundation/app.dart';
import '../../foundation/app_page_route.dart';
import '../../foundation/def.dart';
import '../../foundation/disk_cache.dart';
import '../../foundation/history.dart';
import '../../foundation/local_favorites.dart';
import '../../foundation/pica_image_manager.dart';
import '../../foundation/ui_mode.dart';
import '../../network/download/download_model.dart';
import '../../network/eh_network/eh_download_model.dart';
import '../../network/eh_network/eh_main_network.dart';
import '../../network/eh_network/eh_models.dart';
import '../../network/res.dart';
import '../../tools/extensions.dart';
import '../../tools/translations.dart';
import '../../tools/type_util.dart';
import '../comic_page.dart' show EpsData, FavoriteComicWidget, ThumbnailsData;
import '../reader/comic_reading_page.dart';
import '../search_result_page.dart';
import '../comic_page/comic_page_adapter.dart';
import '../comic_page/comic_page_logic.dart';
import 'eh_comments_page.dart';
import 'eh_gallery_page.dart' show RatingLogic, RatingWidget, EhThumbnailLoader;

// ============================================================================
// EhAdapter — E-Hentai
// ============================================================================

class EhAdapter extends ComicPageAdapter<Gallery> {
  @override
  String get source => "EHentai";
  @override
  ComicType get comicType => ComicType.ehentai;
  @override
  String tag(String id) => comicPageTag(comicType, id);
  @override
  String downloadId(String id) =>
      downloadManager.getDownloadIdFromComicId(comicType, id);
  @override
  String url(Gallery data) => data.link ?? '';
  @override
  bool get enableTranslationToCN => App.locale.languageCode == "zh";

  // -------- B. 数据加载 --------
  @override
  Future<Res<Gallery>> loadData(String id) async {
    var res = await EhNetwork().getGalleryInfo(id, appdata.settings[47] == "1");
    if (res.error && res.errorMessage == "Content Warning") {
      bool shouldIgnore = false;
      await showDialog(
        context: App.globalContext!,
        builder: (ctx) => AlertDialog(
          title: Text("警告".tl),
          content: Text("此画廊存在令人不适的内容\n在设置中可以禁用此警告".tl),
          actions: [
            TextButton(onPressed: () => App.globalBack(), child: Text("返回".tl)),
            TextButton(
              onPressed: () {
                shouldIgnore = true;
                App.globalBack();
              },
              child: Text("忽略".tl),
            ),
          ],
        ),
      );
      if (shouldIgnore) {
        return await EhNetwork().getGalleryInfo(id, true);
      }
      return const Res(null, errorMessage: "Exit");
    }
    final data = res.dataOrNull;
    if (data != null) {
      DiskCache.writeString(tag(id), TypeUtil.parseString(data.toJson()));
    }
    return res;
  }

  @override
  Future<Gallery?> loadCachedData(String id) async {
    return DiskCache.readModel(tag(id), (map) => Gallery.fromJson(map));
  }

  @override
  Gallery? dataFromDownloadedItem(DownloadedItem item) =>
      item is DownloadedGallery ? item.gallery : null;

  @override
  DownloadedItem? mergeDownloadedItem(DownloadedItem item, Gallery data) {
    if (item is! DownloadedGallery) return null;
    return DownloadedGallery(data, item.comicSize, color: item.color);
  }

  @override
  Future<bool> loadFavorite(Gallery data) async =>
      data.favorite ||
      (await LocalFavoritesManager().findWithModel(
        toLocalFavoriteItem(data),
      )).isNotEmpty;

  // -------- C. 元数据提取 --------
  @override
  String? title(Gallery data) => data.title;
  @override
  String? subTitle(Gallery data) => data.subTitle;
  @override
  String? cover(Gallery data) =>
      data.coverPath?.replaceFirst("s.exhentai.org", "ehgt.org");
  @override
  int? pages(Gallery data) => int.tryParse(data.maxPage ?? "");
  @override
  String? introduction(Gallery data) => null;
  @override
  bool? favoriteOnPlatformInitial(Gallery data) => data.favorite;
  @override
  String? commentsCount(Gallery data) => null;
  @override
  String? likeCount(Gallery data) => null;

  @override
  Map<String, List<String>>? tags(Gallery data) => {
    "类型".tl: data.type.toList(),
    "时间".tl: data.time.toList(),
    "上传者".tl: data.uploader.toList(),
    ...data.tags,
  };

  @override
  EpsData? eps(Gallery data, BuildContext context) => null;

  @override
  ThumbnailsData? createThumbnails(Gallery data) {
    if (data.auth?["thumbnailKey"] != null &&
        data.auth!["thumbnailKey"]!.startsWith("large thumbnail")) {
      return ThumbnailsData(
        data.thumbnails,
        (page) => EhNetwork().getThumbnails(data, page),
        int.tryParse(data.auth!["thumbnailKey"]!.nums) ?? 1,
      );
    }
    return ThumbnailsData(
      List.generate(
        min(data.pageSize, int.tryParse(data.maxPage) ?? 1),
        (_) => data.auth!["thumbnailKey"]!.split(" ")[0],
      ),
      (page) => EhNetwork().getThumbnails(data, page),
      int.tryParse(data.auth!["thumbnailKey"]!.split(" ")[1]) ?? 1,
    );
  }

  @override
  Widget buildThumbnailImage(
    int index,
    String imageUrl,
    BuildContext context, {
    required Gallery data,
    List<String>? localImages,
  }) {
    if (localImages != null && index < localImages.length) {
      return PicaImage(
        url: Uri.file(localImages[index]).toString(),
        fit: BoxFit.contain,
        memCacheWidth: 200,
      );
    }
    imageUrl = imageUrl.replaceAll("s.exhentai.org", "ehgt.org");
    if (data.auth?["thumbnailKey"] != null &&
        data.auth!["thumbnailKey"]!.startsWith("large thumbnail")) {
      return PicaImage(
        url: imageUrl,
        headers: {"sourceKey": comicType.name, "isThumbnail": "true"},
        fit: BoxFit.contain,
        cacheKey: "eh_thumb_${data.link}_$index",
        memCacheWidth: 200,
      );
    }
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      key: ValueKey("eh_thumb_${data.link}_$index"),
      child: EhThumbnailLoader(
        image: CachedNetworkImageProvider(
          imageUrl,
          cacheManager: picaImageManager,
          headers: _headers,
          cacheKey: "eh_thumb_${data.link}_${index ~/ data.pageSize}",
        ),
        pageSize: data.pageSize,
        width: data.width,
        index: index,
      ),
    );
  }

  Map<String, String> get _headers => {
    "Cookie": EhNetwork().cookiesStr,
    "User-Agent": webUA,
    "Referer": EhNetwork().ehBaseUrl,
  };

  // -------- D. 操作 --------
  @override
  void read(Gallery data, History? history, BuildContext context) async {
    final h = await History.createIfNull(history, data);
    App.globalTo(() => ComicReadingPage.ehentai(data, initialPage: h!.page));
  }

  @override
  void download(Gallery data, BuildContext context) {
    _showDownloadDialog(data, context);
  }

  @override
  void openFavoritePanel(
    Gallery data,
    ComicPageBridge bridge,
    BuildContext context,
  ) {
    final widget = FavoriteComicWidget(
      havePlatformFavorite: ehentai.isLogin,
      needLoadFolderData: false,
      folders: Map<String, String>.fromIterable(EhNetwork().folderNames),
      favoriteOnPlatform: data.favorite,
      localFavoriteItem: toLocalFavoriteItem(data),
      setFavorite: (b) {
        if (bridge.favorite != b) {
          bridge.favorite = b;
          bridge.updateState();
        }
      },
      selectFolderCallback: (folder, page) async {
        if (page == 0) {
          var res = await EhNetwork().favorite(
            data.auth!["gid"]!,
            data.auth!["token"]!,
            id: EhNetwork().folderNames.indexOf(folder).toString(),
          );
          if (res) {
            data.favorite = true;
            return const Res(true);
          }
          return Res.error("网络错误".tl);
        }
        LocalFavoritesManager().addComic(
          folder,
          FavoriteItem.fromEhentai(data.toBrief()),
        );
        return const Res(true);
      },
      cancelPlatformFavorite: () async {
        var res = await EhNetwork().unfavorite(
          data.auth!["gid"]!,
          data.auth!["token"]!,
        );
        if (res) {
          data.favorite = false;
          return const Res(true);
        }
        return Res.error("网络错误".tl);
      },
    );
    if (UiMode.m1(context)) {
      showModalBottomSheet(context: context, builder: (_) => widget);
    } else {
      showSideBar(
        App.globalContext!,
        widget,
        title: "收藏漫画".tl,
        useSurfaceTintColor: true,
      );
    }
  }

  @override
  ActionFunc? openComments(Gallery data, BuildContext context) => () {
    showComments(
      App.globalContext!,
      data.link ?? '',
      data.uploader,
      data.auth ?? {},
    );
  };

  @override
  ActionFunc? onLike(Gallery data, BuildContext context) => null;
  @override
  bool isLiked(Gallery data) => false;

  @override
  ActionFunc? searchSimilar(Gallery data, BuildContext context) => () {
    var title = data.subTitle ?? data.title;
    title = title
        .replaceAll(RegExp(r"\[.*?\]"), "")
        .replaceAll(RegExp(r"\(.*?\)"), "");
    Navigator.of(context).push(
      AppPageRoute(
        builder: (_) => SearchResultPage(
          keyword: "\"$title\"".trim(),
          comicType: comicType,
        ),
      ),
    );
  };

  @override
  void onTagTapped(String tag, String key, Gallery data, BuildContext context) {
    var namespace = "";
    for (var entry in data.tags.entries) {
      if (entry.value.contains(tag)) {
        namespace = entry.key;
        break;
      }
    }
    if (tag == data.uploader) namespace = "uploader";
    var t = tag;
    if (t.contains(" ")) t = "\"$t\"";
    if (namespace != "") t = "$namespace:$t";
    Navigator.of(context).push(
      AppPageRoute(
        builder: (_) => SearchResultPage(keyword: t, comicType: comicType),
      ),
    );
  }

  @override
  void onThumbnailTapped(int index, Gallery data, BuildContext context) async {
    await History.findOrCreate(data);
    App.globalTo(() => ComicReadingPage.ehentai(data, initialPage: index + 1));
  }

  // -------- E. 自定义UI & 转换 --------
  @override
  Widget? buildRecommendation(Gallery data, BuildContext context) => null;

  @override
  Card? buildUploaderInfo(Gallery data, BuildContext context) => null;

  @override
  Widget? buildMoreInfo(Gallery data, BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _showStarRating(context, data),
        child: SizedBox(
          height: 30,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int i = 0; i < (data.stars ~/ 0.5) ~/ 2; i++)
                const Icon(Icons.star, size: 30, color: Color(0xffffbf00)),
              if ((data.stars ~/ 0.5) % 2 == 1)
                const Icon(Icons.star_half, size: 30, color: Color(0xffffbf00)),
              for (
                int i = 0;
                i < 5 - (data.stars ~/ 0.5) ~/ 2 - (data.stars ~/ 0.5) % 2;
                i++
              )
                const Icon(
                  Icons.star_border,
                  size: 30,
                  color: Color(0xffffbf00),
                ),
              const SizedBox(width: 5),
              if (data.rating != null) Text(data.rating!),
            ],
          ),
        ),
      ),
    );
  }

  @override
  List<Widget>? buildExtraActionButtons(
    Gallery data,
    BuildContext context,
    Widget Function(
      BuildContext,
      String,
      IconData,
      VoidCallback, [
      VoidCallback?,
    ])
    buildActionItem,
  ) => null;

  @override
  FavoriteItem toLocalFavoriteItem(Gallery data) =>
      FavoriteItem.fromEhentai(data.toBrief());

  // -------- 评分弹窗 --------
  void _showStarRating(BuildContext context, Gallery data) {
    if (!ehentai.isLogin) {
      showToast(message: "未登录".tl);
      return;
    }
    showDialog(
      context: context,
      builder: (dialogContext) => StateBuilder<RatingLogic>(
        init: RatingLogic(),
        builder: (logic) => SimpleDialog(
          title: const Text("评分"),
          alignment: Alignment.center,
          children: [
            SizedBox(
              height: 100,
              child: Center(
                child: SizedBox(
                  width: 210,
                  child: Column(
                    children: [
                      const SizedBox(height: 10),
                      RatingWidget(
                        padding: 2,
                        onRatingUpdate: (value) => logic.rating = value,
                        value: 0,
                        selectAble: true,
                        size: 40,
                      ),
                      const Spacer(),
                      Button.filled(
                        isLoading: logic.running,
                        onPressed: () {
                          logic.running = true;
                          logic.update();
                          EhNetwork()
                              .rateGallery(data.auth!, logic.rating.toInt())
                              .then((b) {
                                if (!dialogContext.mounted) return;
                                if (b) {
                                  Navigator.of(dialogContext).pop();
                                  showToast(message: "评分成功".tl);
                                } else {
                                  logic.running = false;
                                  logic.update();
                                  showToast(message: "网络错误".tl);
                                }
                              });
                        },
                        child: Text("提交".tl),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------- 下载弹窗 --------
  void _showDownloadDialog(Gallery data, BuildContext context) {
    int current = 0;
    bool loading = true;
    ArchiveDownloadInfo? info;
    bool cancelUnlock = false;

    showDialog(
      context: App.globalContext!,
      builder: (dialogContext) => Dialog(
        child: StatefulBuilder(
          builder: (ctx, setState) {
            void load() async {
              if (data.auth?["archiveDownload"] == null) return;
              Res<ArchiveDownloadInfo> res;
              if (cancelUnlock) {
                cancelUnlock = false;
                res = await EhNetwork().cancelAndReloadArchiveInfo(info!);
              } else {
                res = await EhNetwork().getArchiveDownloadInfo(
                  data.auth!["archiveDownload"]!,
                );
              }
              if (res.error) {
                showToast(message: "网络错误".tl);
              } else {
                info = res.data;
                loading = false;
                if (ctx.mounted) setState(() {});
              }
            }

            if (loading) load();

            return Container(
              width: 350,
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "下载".tl,
                    style: const TextStyle(fontSize: 20),
                  ).paddingLeft(16),
                  const Divider(),
                  RadioListTile(
                    value: 0,
                    groupValue: current,
                    onChanged: (value) =>
                        setState(() => current = value as int),
                    title: Text("普通下载".tl),
                  ),
                  ExpansionTile(
                    title: Text("归档下载".tl),
                    shape: Border.all(color: Colors.transparent),
                    children: [
                      if (loading)
                        const CircularProgressIndicator()
                            .paddingVertical(8)
                            .toCenter()
                      else
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            RadioListTile(
                              value: 1,
                              groupValue: current,
                              onChanged: (value) =>
                                  setState(() => current = value as int),
                              title: Text("Original".tl),
                              subtitle: Text(
                                "${info!.originCost} ${info!.originSize}",
                              ),
                            ),
                            RadioListTile(
                              value: 2,
                              groupValue: current,
                              onChanged: (value) =>
                                  setState(() => current = value as int),
                              title: Text("Resample".tl),
                              subtitle: Text(
                                "${info!.resampleCost} ${info!.resampleSize}",
                              ),
                            ),
                            if (info!.cancelUnlockUrl != null)
                              ListTile(
                                leading: const Icon(Icons.lock_open),
                                title: Text("取消解锁".tl),
                                subtitle: Text("长按执行此操作".tl),
                                onLongPress: () {
                                  setState(() {
                                    cancelUnlock = true;
                                    loading = true;
                                  });
                                },
                              ).paddingLeft(6),
                          ],
                        ),
                    ],
                  ),
                  FilledButton(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      _startDownload(data, current);
                    },
                    child: Text("确认".tl),
                  ).toCenter(),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _startDownload(Gallery data, int type) async {
    final id = downloadManager.getDownloadIdFromComicId(
      comicType,
      data.link ?? '',
    );
    if (await downloadManager.isExists(id)) {
      showToast(message: "已下载".tl);
      return;
    }
    for (var i in downloadManager.downloading) {
      if (i.id == id) {
        showToast(message: "下载中".tl);
        return;
      }
    }
    downloadManager.addEhDownload(data, type);
    showToast(message: "已加入下载队列".tl);
  }
}
