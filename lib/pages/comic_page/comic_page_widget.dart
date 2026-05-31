import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shimmer_animation/shimmer_animation.dart';

import '../../base.dart';
import '../../components/components.dart';
import '../../comic_source/comic_source.dart';
import '../../foundation/app.dart';
import '../../foundation/app_page_route.dart';
import '../../foundation/def.dart';
import '../../foundation/file_utils.dart';
import '../../foundation/history.dart';
import '../../foundation/local_favorites.dart';
import '../../foundation/ui_mode.dart';
import '../../tools/tags_translation.dart';
import '../../tools/translations.dart';
import '../download/tag_assignment_dialog.dart';
import '../favorites/local_favorites.dart';
import '../image_favorites.dart';
import '../reader/comic_reading_page.dart';
import '../show_image_page.dart';
import 'comic_page_adapter.dart';
import 'comic_page_logic.dart';

// ============================================================================
// ComicPageWidget — 漫画详情页UI
// ============================================================================

/// 漫画详情页，所有漫画来源公用此组件。
///
/// 通过 [ComicPageWidget.open] 静态方法统一打开页面。
/// UI渲染完全依赖 [ComicPageAdapter] 获取数据，不关心具体来源类型。
class ComicPageWidget extends ConsumerStatefulWidget {
  const ComicPageWidget({
    required this.comicType,
    required this.id,
    this.cover,
    super.key,
  });

  final ComicType comicType;
  final String id;
  final String? cover;

  /// 统一的页面入口 -- 替代所有直接子类构造
  static Future<T?> open<T extends Object?>(BuildContext context, {
    required ComicType comicType,
    required String id,
    String? cover,
  }) {
    return Navigator.of(context).push<T>(
      AppPageRoute<T>(
        builder: (context) => ComicPageWidget(
          comicType: comicType,
          id: id,
          cover: cover,
        ),
      ),
    );
  }

  @override
  ConsumerState<ComicPageWidget> createState() => _ComicPageWidgetState();
}

class _ComicPageWidgetState extends ConsumerState<ComicPageWidget> {
  static final List<ComicPageLogic> _activePages = [];
  ComicPageLogic? _notifier;

  @override
  void initState() {
    super.initState();
    _notifier = ref.read(
      comicPageLogicProvider((widget.comicType, widget.id)).notifier,
    );
    _activePages.add(_notifier!);
  }

  @override
  void dispose() {
    _activePages.remove(_notifier);
    super.dispose();
  }

  /// 阅读器页面关闭后，通过此方法更新最后活跃页面的历史记录
  static void updateActivePageHistory(History? history) {
    if (_activePages.isNotEmpty) {
      _activePages.last.updateHistory(history);
    }
  }

  @override
  Widget build(BuildContext context) {
    final logic = ref.watch(
      comicPageLogicProvider((widget.comicType, widget.id)),
    );
    final notifier = ref.read(
      comicPageLogicProvider((widget.comicType, widget.id)).notifier,
    );
    final adapter = notifier.adapter;
    final data = notifier.data;
    final coverUrl = widget.cover ?? (data != null ? adapter.cover(data) : null);

    // 数据首次到达后初始化缩略图
    if (data != null && notifier.thumbnailsData == null) {
      notifier.initThumbnails(adapter.createThumbnails(data));
    }

    return LayoutBuilder(builder: (context, constraints) {
      return Scaffold(
        body: _buildBody(context, logic, notifier, adapter, data, coverUrl),
      );
    });
  }

  // ========================================================================
  // 主体切换：加载中 / 错误 / 内容
  // ========================================================================

  Widget _buildBody(BuildContext context, ComicPageState state,
      ComicPageLogic notifier, ComicPageAdapter adapter, Object? data,
      String? coverUrl) {
    if (state.loading) {
      return _buildLoadingShimmer(context, adapter, coverUrl);
    }

    if (state.message != null && data == null) {
      return NetworkError(
        message: state.message!,
        retry: notifier.refresh_,
      );
    }

    return _buildContent(context, state, notifier, adapter, data!, coverUrl);
  }

  // ========================================================================
  // 加载中 — Shimmer骨架屏
  // ========================================================================

  Widget _buildLoadingShimmer(
      BuildContext context, ComicPageAdapter adapter, String? coverUrl) {
    return SingleChildScrollView(
      child: Shimmer(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        colorOpacity: 0.5,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 56,
              child: const BackButton().toAlign(Alignment.centerLeft),
            ).paddingLeft(8),
            SizedBox(
              width: double.infinity,
              child: _buildComicInfo(context, null, null, adapter, null, coverUrl,
                  sliver: false),
            ),
            const Divider(),
            _buildSectionHeader(context, "信息"),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: List.generate(
                8,
                (index) => Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                  child: Container(
                    width: double.infinity,
                    height: 32,
                    constraints: const BoxConstraints(maxWidth: 400),
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withOpacity(0.4),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ).paddingTop(MediaQuery.of(context).padding.top),
    );
  }

  // ========================================================================
  // 完整内容
  // ========================================================================

  Widget _buildContent(BuildContext context, ComicPageState state,
      ComicPageLogic notifier, ComicPageAdapter adapter, Object data,
      String? coverUrl) {
    return SmoothCustomScrollView(
      controller: notifier.controller,
      slivers: [
        _buildSliverAppBar(context, state, adapter, data),
        _buildComicInfo(context, state, notifier, adapter, data, coverUrl),
        _buildTagsSection(context, state, adapter, data),
        ..._buildEpisodeSection(context, state, adapter, data),
        ..._buildIntroductionSection(context, adapter, data),
        ..._buildThumbnailsSection(context, state, notifier, adapter, data),
        ..._buildRecommendationSection(context, adapter, data),
        SliverPadding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).padding.bottom,
          ),
        ),
      ],
    );
  }

  // ========================================================================
  // SliverAppBar
  // ========================================================================

  Widget _buildSliverAppBar(BuildContext context, ComicPageState state,
      ComicPageAdapter adapter, Object data) {
    final titleText = adapter.title(data) ?? '';
    return SliverAppbar(
      title: AnimatedOpacity(
        opacity: state.showAppbarTitle ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: Text(titleText),
      ),
      actions: [
        IconButton(
          onPressed: () => _showMoreActions(context, adapter, data, titleText),
          icon: const Icon(Icons.more_horiz),
        ),
      ],
    );
  }

  // ========================================================================
  // 更多操作菜单
  // ========================================================================

  void _showMoreActions(BuildContext context, ComicPageAdapter adapter,
      Object data, String title) {
    final width = MediaQuery.of(context).size.width;
    final url = adapter.url(data);

    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(width, 0, 0, 0),
      items: [
        PopupMenuItem(
          child: Text("复制标题".tl),
          onTap: () {
            var text = title;
            if (url != null) text += ":$url";
            Clipboard.setData(ClipboardData(text: text));
            showToast(message: "已复制".tl, icon: const Icon(Icons.check));
          },
        ),
        if (url != null)
          PopupMenuItem(
            child: Text("复制链接".tl),
            onTap: () {
              Clipboard.setData(ClipboardData(text: url));
              showToast(message: "已复制".tl, icon: const Icon(Icons.check));
            },
          ),
        PopupMenuItem(
          child: Text("分享".tl),
          onTap: () {
            var text = title;
            if (url != null) text += ":$url";
            Share.share(text);
          },
        ),
      ],
    );
  }

  // ========================================================================
  // 漫画信息区（封面 + 标题 + 操作按钮）
  // ========================================================================

  Widget _buildComicInfo(BuildContext context, ComicPageState? state,
      ComicPageLogic? notifier, ComicPageAdapter adapter, Object? data,
      String? coverUrl, {bool sliver = true}) {
    final body = LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      final sourceText = adapter.source;
      final titleText = data != null ? adapter.title(data) : '';
      final subTitleText = data != null ? adapter.subTitle(data) : null;
      final pagesCount = data != null ? adapter.pages(data) : null;

      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(width: 8),
                _buildCover(context, notifier, adapter, coverUrl, 136, 102),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText(titleText?.trim() ?? "",
                          style: const TextStyle(fontSize: 18)),
                      if (subTitleText != null) ...[
                        const SizedBox(height: 8),
                        SelectableText(subTitleText,
                            style: const TextStyle(fontSize: 14)),
                      ],
                      const SizedBox(height: 8),
                      Text(sourceText, style: const TextStyle(fontSize: 12)),
                      if (pagesCount != null) ...[
                        const SizedBox(height: 8),
                        Text("${pagesCount}P",
                            style: const TextStyle(fontSize: 12)),
                      ],
                      if (width >= 500)
                        _buildActions(context, state, notifier, adapter, data,
                                center: false)
                            .paddingTop(12),
                    ],
                  ),
                ),
              ],
            ),
          ).paddingHorizontal(10).paddingBottom(12),
          if (width < 500)
            _buildActions(context, state, notifier, adapter, data, center: true)
                .paddingHorizontal(12),
        ],
      );
    });

    if (!sliver) return body;
    return SliverToBoxAdapter(child: body);
  }

  // ========================================================================
  // 封面
  // ========================================================================

  Widget _buildCover(BuildContext context, ComicPageLogic? notifier,
      ComicPageAdapter adapter, String? coverUrl,
      double height, double width) {
    if (coverUrl == null) {
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
      );
    }

    final tag = adapter.tag(widget.id);
    final displayUrl = (notifier?.state.coverPath != null)
        ? Uri.file(notifier!.state.coverPath!).toString()
        : coverUrl;

    return GestureDetector(
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: Hero(
          tag: "image$tag",
          child: PicaImage(
            url: displayUrl,
            fit: BoxFit.cover,
            sourceKey: adapter.comicType.name,
            isThumbnail: true,
          ),
        ),
      ),
      onTap: () =>
          App.globalTo(() => ShowImagePageWithHero(coverUrl, "image$tag")),
    );
  }

  // ========================================================================
  // 操作按钮行
  // ========================================================================

  Widget _buildActions(BuildContext context, ComicPageState? state,
      ComicPageLogic? notifier, ComicPageAdapter adapter, Object? data,
      {required bool center}) {
    if (state == null || notifier == null || data == null) {
      return Container(
        decoration: BoxDecoration(
          color: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest
              .withOpacity(0.4),
          borderRadius: BorderRadius.circular(12),
        ),
        height: 72,
        width: double.infinity,
      );
    }

    final screenWidth = MediaQuery.of(context).size.width;

    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: UiMode.m1(context)
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: center ? WrapAlignment.center : WrapAlignment.start,
            children: [
              if (state.history != null && screenWidth >= 500)
                _buildActionItem(context, "继续阅读".tl, Icons.menu_book,
                    () => adapter.read(data, state.history, context)),
              if (screenWidth >= 500 ||
                  (screenWidth < 500 && state.history != null))
                _buildActionItem(context, "从头开始".tl,
                    Icons.not_started_outlined, () => adapter.read(data, null, context)),
              _buildActionItem(context, "分享".tl, Icons.share, () {
                var text = adapter.title(data) ?? '';
                final url = adapter.url(data);
                if (url != null) text += ":$url";
                Share.share(text);
              }),
              _buildActionItem(
                context,
                state.favorite ? "已收藏".tl : "收藏".tl,
                state.favorite
                    ? Icons.collections_bookmark
                    : Icons.collections_bookmark_outlined,
                () => adapter.openFavoritePanel(data, notifier, context),
                () async {
                  // 长按直接收藏到默认本地文件夹
                  var folder = appdata.settings[51];
                  if ((await LocalFavoritesManager().folderNames)
                      .contains(folder)) {
                    LocalFavoritesManager()
                        .addComic(folder, adapter.toLocalFavoriteItem(data));
                    showToast(message: "已收藏".tl);
                  }
                },
              ),
              if (screenWidth >= 500)
                _buildActionItem(context, "下载".tl, Icons.download,
                    () => adapter.download(data, context)),
              ..._buildExtraActions(adapter, data, state, screenWidth),
              ..._buildLikeAction(adapter, data),
              ..._buildCommentsAction(adapter, data),
              ..._buildSearchSimilarAction(adapter, data),
              ..._buildAutoPageTurnAction(adapter, notifier, data, state,
                  screenWidth),
              ..._buildDeleteDownloadAction(adapter, notifier),
              _buildActionItem(context, "图片收藏".tl, Icons.image, () {
                Navigator.of(context).push(AppPageRoute(
                  builder: (_) => ImageFavoritesPage(
                    filterTitle: adapter.title(data) ?? '',
                  ),
                ));
              }),
            ],
          ),
          if (screenWidth < 500)
            _buildMobileButtons(context, adapter, notifier, data, state),
        ],
      ),
    );
  }

  // ========================================================================
  // 额外操作按钮（来自adapter）
  // ========================================================================

  List<Widget> _buildExtraActions(ComicPageAdapter adapter, Object data,
      ComicPageState state, double screenWidth) {
    final extraButtons = adapter.buildExtraActionButtons(
      data, context,
      (ctx, title, icon, onTap, [onLongPress]) =>
          _buildActionItem(ctx, title, icon, onTap, onLongPress),
    );
    return extraButtons ?? [];
  }

  // ========================================================================
  // 点赞按钮
  // ========================================================================

  List<Widget> _buildLikeAction(ComicPageAdapter adapter, Object data) {
    final onLike = adapter.onLike(data, context);
    if (onLike == null) return [];
    return [
      _buildActionItem(
        context,
        adapter.likeCount(data) ?? "喜欢".tl,
        adapter.isLiked(data) ? Icons.favorite : Icons.favorite_border,
        onLike,
      ),
    ];
  }

  // ========================================================================
  // 评论按钮
  // ========================================================================

  List<Widget> _buildCommentsAction(ComicPageAdapter adapter, Object data) {
    final openComments = adapter.openComments(data, context);
    if (openComments == null) return [];
    return [
      _buildActionItem(
        context,
        adapter.commentsCount(data) ?? "评论".tl,
        Icons.comment_outlined,
        openComments,
      ),
    ];
  }

  // ========================================================================
  // 相似搜索按钮
  // ========================================================================

  List<Widget> _buildSearchSimilarAction(
      ComicPageAdapter adapter, Object data) {
    final searchSimilar = adapter.searchSimilar(data, context);
    if (searchSimilar == null) return [];
    return [
      _buildActionItem(
          context, "相关推荐".tl, Icons.account_tree, searchSimilar),
    ];
  }

  // ========================================================================
  // 自动翻页按钮
  // ========================================================================

  List<Widget> _buildAutoPageTurnAction(ComicPageAdapter adapter,
      ComicPageLogic notifier, Object data, ComicPageState state,
      double screenWidth) {
    if (state.history == null ||
        screenWidth < 500 ||
        screenWidth >= 600) return [];
    return [
      _buildActionItem(context, "auto_page_turning".tl, Icons.timer_outlined,
          () {
        final cs = ComicSource.find(widget.comicType);
        App.globalTo(
          () => ComicReadingPage(
            CustomReadingData(
              widget.id,
              adapter.title(data) ?? '',
              cs!,
              {},
            ),
            1,
            1,
          )..readingData.history = state.history,
        );
      }),
    ];
  }

  // ========================================================================
  // 删除下载按钮
  // ========================================================================

  List<Widget> _buildDeleteDownloadAction(
      ComicPageAdapter adapter, ComicPageLogic notifier) {
    final downloadId = adapter.downloadId(widget.id);
    return [
      FutureBuilder<bool>(
        future: downloadManager.isExists(downloadId),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done ||
              !snapshot.hasData ||
              snapshot.data != true) {
            return const SizedBox.shrink();
          }
          return Flyout(
            enableTap: true,
            navigator: App.navigatorKey.currentState!,
            withInkWell: true,
            borderRadius: 8,
            flyoutBuilder: (ctx) => FlyoutContent(
              title: "从本地下载中删除?".tl,
              actions: [
                TextButton(
                  onPressed: () async {
                    Navigator.of(ctx).pop();
                    await downloadManager.delete([downloadId]);
                    showToast(message: "已删除".tl);
                    notifier.updateState();
                  },
                  child: Text("删除".tl),
                ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text("取消".tl),
                ),
              ],
            ),
            child: SizedBox(
              height: 72,
              width: 64,
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Icon(Icons.delete_outline,
                      size: 24,
                      color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 8),
                  Text("删除下载".tl, style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
          );
        },
      ),
    ];
  }

  // ========================================================================
  // 移动端底部按钮
  // ========================================================================

  Widget _buildMobileButtons(BuildContext context, ComicPageAdapter adapter,
      ComicPageLogic notifier, Object data, ComicPageState state) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          Expanded(
            child: FilledButton.tonal(
              onPressed: () => adapter.download(data, context),
              child: Text("下载".tl),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: FilledButton.tonal(
              onPressed: () => adapter.read(data, state.history, context),
              child: Text("阅读".tl),
            ),
          ),
        ],
      ),
    ).paddingHorizontal(8);
  }

  // ========================================================================
  // 单个操作按钮
  // ========================================================================

  Widget _buildActionItem(BuildContext context, String title, IconData icon,
      VoidCallback onTap, [VoidCallback? onLongPress]) {
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: const BorderRadius.all(Radius.circular(8)),
      child: SizedBox(
        height: 72,
        width: 64,
        child: Column(
          children: [
            const SizedBox(height: 12),
            Icon(icon, size: 24, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // ========================================================================
  // 标签区
  // ========================================================================

  Widget _buildTagsSection(BuildContext context, ComicPageState state,
      ComicPageAdapter adapter, Object data) {
    return SliverToBoxAdapter(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                _buildSectionHeader(context, "信息"),
                if (state.message != null)
                  Tooltip(
                    message: state.message!,
                    child: IconButton(
                      icon: const Icon(Icons.offline_bolt,
                          color: Colors.orange),
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: Text("网络错误".tl),
                            content: Text(state.message!),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: Text("确认".tl),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ..._buildInfoCards(context, state, adapter, data),
        ],
      ),
    );
  }

  // ========================================================================
  // 信息卡片列表
  // ========================================================================

  Iterable<Widget> _buildInfoCards(BuildContext context, ComicPageState state,
      ComicPageAdapter adapter, Object data) sync* {
    final notifier = ref.read(
      comicPageLogicProvider((widget.comicType, widget.id)).notifier,
    );
    // 本地标签（已下载的漫画）
    if (state.isDownloaded) {
      yield Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
        child: Wrap(
          children: [
            _buildInfoCard(context, adapter, "本地标签", state.colorIndex % colors.length, title: true, key: ""),
            for (var tag in state.localTags)
              _buildLocalTagCard(context, tag.name),
            _buildOpenFolderButton(context, adapter.downloadId(widget.id)),
            _buildAddTagButton(context, adapter),
          ],
        ),
      );
    }

    // 自定义更多信息
    final moreInfo = adapter.buildMoreInfo(data, context);
    if (moreInfo != null) {
      yield Padding(
        padding: const EdgeInsets.fromLTRB(18, 8, 30, 8),
        child: moreInfo,
      );
    }

    // 网络标签
    final tags = adapter.tags(data);
    if (tags != null) {
      var colorIndex = 0;
      for (var key in tags.keys) {
        colorIndex++;
        yield Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
          child: Wrap(
            children: [
              _buildInfoCard(context, adapter, key, colorIndex, title: true, key: key),
              for (var tag in tags[key]!)
                _buildInfoCard(context, adapter, tag, colorIndex, key: key),
            ],
          ),
        );
      }
    }

    // 上传者信息
    final uploaderInfo = adapter.buildUploaderInfo(data, context);
    if (uploaderInfo != null) {
      yield Padding(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: uploaderInfo,
          ),
        ),
      );
    }
  }

  // ========================================================================
  // 单个信息卡片（标签芯片）
  // ========================================================================

  Widget _buildInfoCard(BuildContext context, ComicPageAdapter adapter,
      String text, int colorIndex, {bool title = false, String key = "key"}) {
    final colorScheme = Theme.of(context).colorScheme;
    final displayText = text.isEmpty ? "未知".tl : text;

    final labelText = adapter.enableTranslationToCN
        ? (title
            ? displayText.translateTagsCategoryToCN
            : TagsTranslation.translationTagWithNamespace(displayText, key))
        : displayText;

    return GestureDetector(
      onLongPressStart: (details) {
        showMenu(
          context: App.globalContext!,
          position: RelativeRect.fromLTRB(
            details.globalPosition.dx,
            details.globalPosition.dy,
            details.globalPosition.dx,
            details.globalPosition.dy,
          ),
          items: _buildInfoCardPopMenus(text, labelText, title, key, adapter),
        );
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(4, 4, 4, 4),
        child: InkWell(
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          onTap: title ? null : () {
            final data = ref.read(
              comicPageLogicProvider((widget.comicType, widget.id)).notifier,
            ).data;
            if (data != null) {
              adapter.onTagTapped(text, key, data, context);
            }
          },
          onSecondaryTapDown: (details) {
            showMenu(
              context: App.globalContext!,
              position: RelativeRect.fromLTRB(
                details.globalPosition.dx,
                details.globalPosition.dy,
                details.globalPosition.dx,
                details.globalPosition.dy,
              ),
              items: _buildInfoCardPopMenus(text, labelText, title, key, adapter),
            );
          },
          child: Card(
            margin: EdgeInsets.zero,
            color: title
                ? colors[colorIndex % colors.length].shade100.withOpacity(0.6)
                : ElevationOverlay.applySurfaceTint(
                    colorScheme.surface, colorScheme.surfaceTint, 3),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
              child: Text(labelText, style: const TextStyle(fontSize: 13)),
            ),
          ),
        ),
      ),
    );
  }

  List<PopupMenuEntry> _buildInfoCardPopMenus(
      String text, String labelText, bool title, String key,
      ComicPageAdapter adapter) {
    return [
      PopupMenuItem(
        child: Text("复制".tl),
        onTap: () {
          Clipboard.setData(ClipboardData(text: text));
          showToast(message: "已复制".tl);
        },
      ),
      PopupMenuItem(
        child: Text("复制中文".tl),
        onTap: () {
          Clipboard.setData(ClipboardData(text: labelText));
          showToast(message: "已复制".tl);
        },
      ),
      if (!title)
        PopupMenuItem(
          child: Text("屏蔽".tl),
          onTap: () {
            appdata.blockingKeyword.add(text);
            appdata.writeData();
          },
        ),
      if (!title)
        PopupMenuItem(
          child: Text("收藏".tl),
          onTap: () {
            var res = adapter.source;
            if (adapter.source == "EHentai") res += ":$key";
            if (adapter.source == "Nhentai" && key == "Artists") {
              res += ":Artist";
            }
            if (text.contains(" ")) {
              res += ":\"$text\"";
            } else {
              res += ":$text";
            }
            appdata.favoriteTags.add(res);
            appdata.writeHistory();
          },
        ),
    ];
  }

  // ========================================================================
  // 本地标签卡片
  // ========================================================================

  Widget _buildLocalTagCard(BuildContext context, String text) {
    return GestureDetector(
      onLongPressStart: (details) {
        showMenu(
          context: App.globalContext!,
          position: RelativeRect.fromLTRB(
            details.globalPosition.dx,
            details.globalPosition.dy,
            details.globalPosition.dx,
            details.globalPosition.dy,
          ),
          items: [
            PopupMenuItem(
              child: Text("复制".tl),
              onTap: () {
                Clipboard.setData(ClipboardData(text: text));
                showToast(message: "已复制".tl);
              },
            ),
          ],
        );
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(4, 4, 4, 4),
        child: InkWell(
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          onTap: () {
            final notifier = ref.read(
              comicPageLogicProvider((widget.comicType, widget.id)).notifier,
            );
            final data = notifier.data;
            if (data != null) {
              notifier.adapter.onTagTapped(text, "本地标签", data, context);
            }
          },
          child: Card(
            margin: EdgeInsets.zero,
            color: ElevationOverlay.applySurfaceTint(
              Theme.of(context).colorScheme.surface,
              Theme.of(context).colorScheme.surfaceTint,
              3,
            ),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
              child: Text(text, style: const TextStyle(fontSize: 13)),
            ),
          ),
        ),
      ),
    );
  }

  // ========================================================================
  // 打开文件夹 & 打标签按钮
  // ========================================================================

  Widget _buildOpenFolderButton(BuildContext context, String downloadId) {
    return Container(
      margin: const EdgeInsets.fromLTRB(4, 4, 4, 4),
      child: InkWell(
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        onTap: () async {
          final folderPath =
              await downloadManager.getFullDirectory(downloadId);
          if (folderPath.isNotEmpty) {
            FileUtils.openFileOrDirectory(folderPath);
          } else {
            showToast(message: "无法获取文件夹路径".tl);
          }
        },
        child: Card(
          margin: EdgeInsets.zero,
          color: Theme.of(context).colorScheme.secondaryContainer,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.folder_open, size: 16,
                    color: Theme.of(context).colorScheme.onSecondaryContainer),
                const SizedBox(width: 4),
                Text("打开文件夹",
                    style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context)
                            .colorScheme
                            .onSecondaryContainer)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAddTagButton(BuildContext context, ComicPageAdapter adapter) {
    return Container(
      margin: const EdgeInsets.fromLTRB(4, 4, 4, 4),
      child: InkWell(
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        onTap: () => _openTagAssignmentDialog(context, adapter),
        child: Card(
          margin: EdgeInsets.zero,
          color: Theme.of(context).colorScheme.primaryContainer,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add, size: 16,
                    color: Theme.of(context).colorScheme.onPrimaryContainer),
                const SizedBox(width: 4),
                Text("打标签",
                    style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context)
                            .colorScheme
                            .onPrimaryContainer)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openTagAssignmentDialog(
      BuildContext context, ComicPageAdapter adapter) async {
    final notifier = ref.read(
      comicPageLogicProvider((widget.comicType, widget.id)).notifier,
    );
    final currentTags = <String>[];
    final data = notifier.data;
    if (data == null) return;

    final titleText = adapter.title(data);
    if (titleText != null && titleText.isNotEmpty) {
      currentTags.add(titleText.translateTagsToCN);
    }

    final tags = adapter.tags(data);
    if (tags != null) {
      for (var tagList in tags.values) {
        currentTags.addAll(tagList.map((tag) => tag.translateTagsToCN));
      }
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => TagAssignmentDialog(
        comicIds: [adapter.downloadId(widget.id)],
        suggestedTags: currentTags,
      ),
    );

    if (result == true) {
      notifier.refresh_();
    }
  }

  // ========================================================================
  // 章节区
  // ========================================================================

  Iterable<Widget> _buildEpisodeSection(BuildContext context,
      ComicPageState state, ComicPageAdapter adapter, Object data) sync* {
    final eps = adapter.eps(data, context);
    if (eps == null) return;
    final hasCurrentEpisode = state.history != null &&
        state.history!.ep > 0 &&
        state.history!.ep <= eps.eps.length &&
        eps.eps.length > 1;

    yield const SliverToBoxAdapter(child: Divider());

    yield SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Text("章节".tl,
                style: const TextStyle(
                    fontWeight: FontWeight.w500, fontSize: 18)),
            if (hasCurrentEpisode) ...[
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  "· ${eps.eps[state.history!.ep - 1]}",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ] else
              const Spacer(),
            Tooltip(
              message: "排序".tl,
              child: IconButton(
                icon: const Icon(Icons.swap_vert),
                onPressed: () {
                  final notifier = ref.read(
                    comicPageLogicProvider(
                            (widget.comicType, widget.id))
                        .notifier,
                  );
                  notifier.state = notifier.state.copyWith(
                    reverseEpsOrder: !state.reverseEpsOrder,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );

    yield const SliverPadding(padding: EdgeInsets.all(6));

    int length = eps.eps.length;
    if (!state.showFullEps) length = math.min(length, 20);

    yield SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      sliver: SliverGrid(
        delegate: SliverChildBuilderDelegate(
          childCount: length,
          (context, i) {
            var index = i;
            if (state.reverseEpsOrder) {
              index = eps.eps.length - i - 1;
            }
            final isLastRead = state.history?.ep == index + 1;
            final visited =
                (state.history?.readEpisode ?? const {}).contains(index + 1) || isLastRead;
            final hasMultipleEps = eps.eps.length > 1;
            return Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
              child: InkWell(
                borderRadius: const BorderRadius.all(Radius.circular(16)),
                onTap: () => eps.onTap(index),
                child: Material(
                  elevation: 5,
                  color: isLastRead && hasMultipleEps
                      ? Theme.of(context).colorScheme.primaryContainer
                      : Theme.of(context).colorScheme.surface,
                  surfaceTintColor:
                      Theme.of(context).colorScheme.surfaceTint,
                  borderRadius:
                      const BorderRadius.all(Radius.circular(12)),
                  shadowColor: Colors.transparent,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    child: Center(
                      child: Text(
                        eps.eps[index],
                        maxLines: 1,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isLastRead && hasMultipleEps
                              ? Theme.of(context).colorScheme.onPrimaryContainer
                              : visited
                                  ? Theme.of(context).colorScheme.outline
                                  : null,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        gridDelegate: const SliverGridDelegateWithFixedHeight(
            maxCrossAxisExtent: 200, itemHeight: 48),
      ),
    );

    if (eps.eps.length > 20 && !state.showFullEps) {
      yield SliverToBoxAdapter(
        child: Align(
          alignment: Alignment.center,
          child: FilledButton.tonal(
            style: ButtonStyle(
              shape: WidgetStateProperty.all(const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(8)))),
            ),
            onPressed: () {
              final notifier = ref.read(
                comicPageLogicProvider((widget.comicType, widget.id)).notifier,
              );
              notifier.state = notifier.state.copyWith(showFullEps: true);
            },
            child: Text("${"显示全部".tl} (${eps.eps.length})"),
          ).paddingTop(12),
        ),
      );
    }
  }

  // ========================================================================
  // 简介区
  // ========================================================================

  Iterable<Widget> _buildIntroductionSection(
      BuildContext context, ComicPageAdapter adapter, Object data) sync* {
    final introduction = adapter.introduction(data);
    if (introduction == null) return;

    yield const SliverPadding(padding: EdgeInsets.all(5));
    yield const SliverToBoxAdapter(child: Divider());
    yield SliverToBoxAdapter(
      child: _buildSectionHeader(context, "简介"),
    );
    yield SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
        child: SelectableText(introduction),
      ),
    );
    yield const SliverPadding(padding: EdgeInsets.all(5));
  }

  // ========================================================================
  // 缩略图区
  // ========================================================================

  Iterable<Widget> _buildThumbnailsSection(BuildContext context,
      ComicPageState state, ComicPageLogic notifier,
      ComicPageAdapter adapter, Object data) sync* {
    if (!adapter.supportThumbnails) return;

    final localImages = state.localImages;
    final thumbnailsData = notifier.thumbnailsData;

    if (localImages == null) {
      if (thumbnailsData == null) return;
      if (thumbnailsData.thumbnails.isEmpty &&
          !adapter.tag(widget.id).contains("Hitomi") &&
          !adapter.tag(widget.id).contains("Eh")) {
        return;
      }
      if (thumbnailsData.thumbnails.isEmpty) {
        // 延迟加载缩略图
        Future.microtask(() {
          thumbnailsData.get(() {
            if (mounted) setState(() {});
          });
        });
      }
    }

    final childCount = localImages?.length ?? thumbnailsData!.thumbnails.length;

    yield const SliverPadding(padding: EdgeInsets.all(5));
    yield const SliverToBoxAdapter(child: Divider());
    yield SliverToBoxAdapter(child: _buildSectionHeader(context, "预览"));
    yield const SliverPadding(padding: EdgeInsets.all(5));

    yield SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      sliver: SliverGrid(
        delegate: SliverChildBuilderDelegate(
          childCount: childCount,
          (context, index) {
            if (localImages == null &&
                thumbnailsData != null &&
                index == thumbnailsData.thumbnails.length - 1) {
              thumbnailsData.get(() {
                if (mounted) setState(() {});
              });
            }
            return Padding(
              padding: UiMode.m1(context)
                  ? const EdgeInsets.all(4)
                  : const EdgeInsets.all(8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () =>
                          adapter.onThumbnailTapped(index, data, context),
                      borderRadius:
                          const BorderRadius.all(Radius.circular(16)),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius:
                              const BorderRadius.all(Radius.circular(16)),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                        width: double.infinity,
                        height: double.infinity,
                        child: ClipRRect(
                          borderRadius:
                              const BorderRadius.all(Radius.circular(16)),
                          child: adapter.buildThumbnailImage(
                            index,
                            localImages != null ? "" : thumbnailsData!.thumbnails[index],
                            context,
                            data: data,
                            localImages: localImages,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text((index + 1).toString()),
                ],
              ),
            );
          },
        ),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 200,
          childAspectRatio: 0.65,
        ),
      ),
    );

    if (localImages == null &&
        thumbnailsData != null &&
        thumbnailsData.current < thumbnailsData.maxPage) {
      yield const SliverToBoxAdapter(child: ListLoadingIndicator());
    }
  }

  // ========================================================================
  // 推荐区
  // ========================================================================

  Iterable<Widget> _buildRecommendationSection(
      BuildContext context, ComicPageAdapter adapter, Object data) sync* {
    final recommendation = adapter.buildRecommendation(data, context);
    if (recommendation == null) return;

    yield const SliverToBoxAdapter(child: Divider());
    yield SliverToBoxAdapter(child: _buildSectionHeader(context, "相关推荐"));
    yield const SliverPadding(padding: EdgeInsets.all(5));
    yield recommendation;
  }

  // ========================================================================
  // 通用区标题
  // ========================================================================

  static Widget _buildSectionHeader(BuildContext context, String text) {
    return SizedBox(
      width: 100,
      child: Row(
        children: [
          const SizedBox(width: 18),
          Text(
            text.tl,
            style: const TextStyle(
                fontWeight: FontWeight.w500, fontSize: 18),
          ),
        ],
      ),
    );
  }
}
