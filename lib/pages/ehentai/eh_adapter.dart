import 'dart:math';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
import '../../foundation/theme/app_mouse_cursor.dart';
import '../../network/download/download_model.dart';
import '../../network/eh_network/eh_download_model.dart';
import '../../network/download/download_manager.dart';
import '../../network/eh_network/eh_models.dart';
import '../../network/res.dart';
import '../../tools/extensions.dart';
import '../../tools/translations.dart';
import '../../tools/type_util.dart';
import '../comic_page.dart' show EpsData, FavoriteComicWidget, ThumbnailsData;
import '../reader/comic_reading_page.dart';
import '../search_result_page.dart';
import '../comic_page/comic_page_adapter.dart';
import 'eh_comments_page.dart';
import 'eh_gallery_page.dart' show RatingWidget, EhThumbnailLoader;
import 'eh_original_availability.dart';
import 'package:pica_comic/network/comic_source_services.dart';

// ============================================================================
// EhAdapter — E-Hentai
// ============================================================================

/// E-Hentai 评分弹窗。
class _RatingDialog extends StatefulWidget {
  const _RatingDialog({required this.data});

  final Gallery data;

  @override
  State<_RatingDialog> createState() => _RatingDialogState();
}

class _RatingDialogState extends State<_RatingDialog> {
  double _rating = 0;
  bool _running = false;

  Future<void> _submit() async {
    if (_running) return;
    setState(() => _running = true);
    try {
      final success = await appComicSourceServices.ehentai.rateGallery(
        widget.data.auth,
        _rating.toInt(),
      );
      if (!mounted) return;
      if (success) {
        Navigator.of(context).pop();
        showToast(message: "评分成功".tl);
      } else {
        setState(() => _running = false);
        showToast(message: "网络错误".tl);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _running = false);
      showToast(message: "网络错误".tl);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
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
                    onRatingUpdate: (value) => setState(() => _rating = value),
                    value: 0,
                    selectAble: true,
                    size: 40,
                  ),
                  const Spacer(),
                  Button.filled(
                    isLoading: _running,
                    onPressed: _submit,
                    child: Text("提交".tl),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class EhAdapter extends ComicPageAdapter<Gallery> {
  @override
  String get source => "EHentai";
  @override
  ComicType get comicType => ComicType.ehentai;
  @override
  String tag(String id) => comicPageTag(comicType, id);
  @override
  String downloadId(String id, DownloadManager manager) =>
      manager.getDownloadIdFromComicId(comicType, id);
  @override
  String url(Gallery data) => data.link ?? '';
  @override
  bool get enableTranslationToCN => App.locale.languageCode == "zh";

  // -------- B. 数据加载 --------
  @override
  Future<Res<Gallery>> loadData(String id) async {
    var res = await appComicSourceServices.ehentai.getGalleryInfo(
      id,
      appdata.getSetting(AppSettingKeys.ehIgnoreWarnings) == "1",
    );
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
        return await appComicSourceServices.ehentai.getGalleryInfo(id, true);
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
  ThumbnailsData? createThumbnails(Gallery data, WidgetRef ref) {
    if (data.auth["thumbnailKey"] != null &&
        data.auth["thumbnailKey"]!.startsWith("large thumbnail")) {
      return ThumbnailsData(
        data.thumbnails,
        (page) => appComicSourceServices.ehentai.getThumbnails(data, page),
        int.tryParse(data.auth["thumbnailKey"]!.nums) ?? 1,
      );
    }
    return ThumbnailsData(
      List.generate(
        min(data.pageSize, int.tryParse(data.maxPage) ?? 1),
        (_) => data.auth["thumbnailKey"]!.split(" ")[0],
      ),
      (page) => appComicSourceServices.ehentai.getThumbnails(data, page),
      int.tryParse(data.auth["thumbnailKey"]!.split(" ")[1]) ?? 1,
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
    if (data.auth["thumbnailKey"] != null &&
        data.auth["thumbnailKey"]!.startsWith("large thumbnail")) {
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
    "Cookie": appComicSourceServices.ehentai.cookiesStr,
    "User-Agent": webUA,
    "Referer": appComicSourceServices.ehentai.ehBaseUrl,
  };

  // -------- D. 操作 --------
  @override
  void read(Gallery data, History? history, BuildContext context) async {
    final h = await History.createIfNull(history, data);
    App.globalTo(() => ComicReadingPage.ehentai(data, initialPage: h!.page));
  }

  @override
  void download(Gallery data, BuildContext context, DownloadManager manager) {
    _showDownloadDialog(data, context, manager);
  }

  @override
  void openFavoritePanel(
    Gallery data,
    ComicPageBridge bridge,
    BuildContext context,
    DownloadManager manager,
  ) {
    final widget = FavoriteComicWidget(
      havePlatformFavorite: ehentai.isLogin,
      needLoadFolderData: false,
      folders: Map<String, String>.fromIterable(
        appComicSourceServices.ehentai.folderNames,
      ),
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
          var res = await appComicSourceServices.ehentai.favorite(
            data.auth["gid"]!,
            data.auth["token"]!,
            id: appComicSourceServices.ehentai.folderNames
                .indexOf(folder)
                .toString(),
          );
          if (res) {
            data = data.copyWith(favorite: true);
            bridge.updateData(data);
            bridge.updateState();
            return const Res(true);
          }
          return Res.error("网络错误".tl);
        }
        LocalFavoritesManager().addComic(
          folder,
          FavoriteItem.fromEhentai(data.toBrief()),
          null,
          manager,
        );
        return const Res(true);
      },
      cancelPlatformFavorite: () async {
        var res = await appComicSourceServices.ehentai.unfavorite(
          data.auth["gid"]!,
          data.auth["token"]!,
        );
        if (res) {
          data = data.copyWith(favorite: false);
          bridge.updateData(data);
          bridge.updateState();
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
    showComments(App.globalContext!, data.link ?? '', data.uploader, data.auth);
  };

  @override
  ActionFunc? onLike(
    Gallery data,
    ComicPageBridge bridge,
    BuildContext context,
  ) => null;
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
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        MouseRegion(
          cursor: appClickableMouseCursor,
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
                    const Icon(
                      Icons.star_half,
                      size: 30,
                      color: Color(0xffffbf00),
                    ),
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
        ),
        if (data.fileSize.isNotEmpty)
          Text(
            "${"文件大小".tl}: ${data.fileSize}",
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        EhOriginalAvailabilityBadge(gallery: data),
      ],
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
      builder: (_) => _RatingDialog(data: data),
    );
  }

  // -------- 下载弹窗 --------
  void _showDownloadDialog(
    Gallery data,
    BuildContext context,
    DownloadManager manager,
  ) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text("下载".tl),
        content: Text("普通下载".tl),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text("取消".tl),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _startDownload(data, context, manager);
            },
            child: Text("确认".tl),
          ),
        ],
      ),
    );
  }

  Future<void> _startDownload(
    Gallery data,
    BuildContext context,
    DownloadManager manager,
  ) async {
    final id = manager.getDownloadIdFromComicId(comicType, data.link ?? '');
    if (await manager.isExists(id)) {
      showToast(message: "已下载".tl);
      return;
    }
    for (var i in manager.downloading) {
      if (i.id == id) {
        showToast(message: "下载中".tl);
        return;
      }
    }
    manager.addEhDownload(data);
    showToast(message: "已加入下载队列".tl);
  }
}
