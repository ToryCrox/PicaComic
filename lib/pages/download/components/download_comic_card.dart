import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

import 'package:pica_comic/base.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/components/hover_scale_card.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/foundation/def.dart';
import 'package:pica_comic/foundation/file_utils.dart';
import 'package:pica_comic/foundation/history_providers.dart';
import 'package:pica_comic/foundation/theme/app_mouse_cursor.dart';
import 'package:pica_comic/network/download/custom_download_model.dart';
import 'package:pica_comic/network/download/download_manager.dart';
import 'package:pica_comic/network/download/download_model.dart';
import 'package:pica_comic/network/download/models/download_color_tag.dart';
import 'package:pica_comic/network/eh_network/eh_download_model.dart';
import 'package:pica_comic/pages/download/download_helper.dart';
import 'package:pica_comic/pages/download/tag_assignment_dialog.dart';
import 'package:pica_comic/pages/search_result_page.dart';
import 'package:pica_comic/tools/extensions.dart';
import 'package:pica_comic/tools/tags_translation.dart';
import 'package:pica_comic/tools/time.dart';
import 'package:pica_comic/tools/translations.dart';

import '../download_providers.dart';
import '../translation_result_replace_dialog.dart';
import '../translation_result_replacer.dart';
import 'download_tile.dart';

/// 下载页专用的已下载漫画卡片。
///
/// 独立实现，不继承公用 `ComicTile`：封面在上、信息区三行；操作入口以图标
/// 叠在封面左侧；翻译结果徽标与 AI 标记在封面右上；标签为带下划线的纯文字，
/// 自定义标签使用主题色；卡片底部叠 3px 阅读进度条。
///
/// 卡片自身的展示数据（标题、作者、大小、来源、标签、翻译结果、阅读进度）
/// 全部由 [item] 与对应 provider 推导；点击/长按/右键涉及页面级选择状态，
/// 仍由下载页回调接管。
class DownloadComicCard extends ConsumerWidget {
  const DownloadComicCard({
    super.key,
    required this.item,
    required this.pageId,
    required this.onTap,
    required this.onLongTap,
    required this.onSecondaryTap,
    this.translatedName,
    this.isSelected = false,
    this.isDragDisabled = false,
    this.draggedItems,
  });

  final DownloadedItem item;

  /// 下载页实例 id，用于标签筛选与本地搜索。
  final String pageId;

  /// AI 翻译后的标题，由外部缓存构建器提供。
  final String? translatedName;

  final VoidCallback onTap;
  final VoidCallback onLongTap;
  final void Function(TapDownDetails details) onSecondaryTap;

  final bool isSelected;
  final bool isDragDisabled;
  final List<DownloadedItem>? draggedItems;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyTarget = _historyTarget(ref);
    final card = _buildCard(context, ref, historyTarget);
    if (isDragDisabled) return card;
    return _DownloadComicCardDragWrapper(
      downloadedItems: draggedItems == null || draggedItems!.isEmpty
          ? [item]
          : draggedItems!,
      child: card,
    );
  }

  // ---------------------------------------------------------------------------
  // 派生数据
  // ---------------------------------------------------------------------------

  /// 页数文本（如 `123P`），页数会从标题前缀挪到文件大小旁边展示。
  String? get _pageCountText {
    if (item is DownloadedGallery) {
      final maxPage = (item as DownloadedGallery).gallery.maxPage;
      if (maxPage.isNotEmpty && maxPage != '0') return '${maxPage}P';
    }
    return null;
  }

  /// 标题：去掉 [getComicDisplayName] 拼接的页数前缀，保留下载 ID。
  String get _displayName {
    final name = getComicDisplayName(item);
    final pageCount = _pageCountText;
    if (pageCount == null) return name;
    final prefix = '($pageCount)';
    return name.startsWith(prefix) ? name.substring(prefix.length) : name;
  }

  String get _sizeText {
    final size = getComicSizeText(item);
    return double.tryParse(size) == null ? size : '${size}MB';
  }

  /// 信息区右侧的元信息：页数（若有）紧挨文件大小。
  String get _metaTrailingText {
    final pageCount = _pageCountText;
    return pageCount == null ? _sizeText : '$pageCount · $_sizeText';
  }

  ComicType? get _comicType => item is CustomDownloadedItem
      ? ComicType.fromString((item as CustomDownloadedItem).sourceKey)
      : item.type.toComicType();

  /// 在线漫画的历史记录键；本地漫画为 null。
  String? _historyTarget(WidgetRef ref) {
    if (item.type == DownloadType.local) return null;
    // EH 的历史以画廊链接为键，其他源与漫画详情页共用漫画 ID。
    final comic = item;
    if (comic is DownloadedGallery) return comic.gallery.link;
    final target = ref
        .read(downloadManagerProvider.notifier)
        .getComicIdFromDownloadId(item.type.toComicType(), item.id);
    return target.isEmpty ? null : target;
  }

  /// 漫画目录绝对路径，本地历史与翻译结果都以它为键。
  String? get _directoryKey {
    try {
      final directory = item.directoryPath;
      return directory.isEmpty ? null : directory;
    } on StateError {
      return null;
    }
  }

  /// 本地漫画以目录绝对路径作为历史键。
  String? get _localHistoryPath =>
      item.type == DownloadType.local ? _directoryKey : null;

  String? _heroTag(String? historyTarget) {
    final type = _comicType;
    if (type == null || type == ComicType.local) return null;
    if (historyTarget == null || historyTarget.isEmpty) return null;
    return comicCoverHeroTag(type, historyTarget);
  }

  // ---------------------------------------------------------------------------
  // 卡片骨架
  // ---------------------------------------------------------------------------

  Widget _buildCard(
    BuildContext context,
    WidgetRef ref,
    String? historyTarget,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return HoverScaleCard(
      enabled: App.isDesktop,
      scale: 1.06,
      borderRadius: const BorderRadius.all(Radius.circular(16)),
      child: InkWell(
        mouseCursor: appClickableMouseCursor,
        onTap: onTap,
        onLongPress: onLongTap,
        onSecondaryTapDown: onSecondaryTap,
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(child: _buildCover(context, ref, historyTarget)),
                _buildInfo(context, ref),
              ],
            ),
            _buildProgressBar(context, ref, historyTarget),
            if (isSelected)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: colorScheme.primary, width: 2),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 封面
  // ---------------------------------------------------------------------------

  Widget _buildCover(
    BuildContext context,
    WidgetRef ref,
    String? historyTarget,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cover = item.coverPath;

    Widget image;
    if (cover == null || cover.isEmpty) {
      image = ColoredBox(color: colorScheme.surfaceContainerHighest);
    } else {
      image = LayoutBuilder(
        builder: (context, constraints) => Image.file(
          File(cover),
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          cacheWidth: (constraints.maxWidth * dpr).round().clamp(1, 4096),
          errorBuilder: (context, error, stackTrace) =>
              ColoredBox(color: colorScheme.surfaceContainerHighest),
        ),
      );
    }

    final heroTag = _heroTag(historyTarget);
    if (heroTag != null) {
      image = Hero(tag: heroTag, child: image);
    }

    final lastReadAt = _resolveLastReadAt(ref, historyTarget);

    return Stack(
      fit: StackFit.expand,
      children: [
        image,
        Positioned(top: 6, left: 6, child: _buildActions(context, ref)),
        Positioned(top: 6, right: 6, child: _buildTopRightBadges(context, ref)),
        Positioned(
          left: 6,
          bottom: 6,
          child: _CoverBadge(text: getComicTypeName(item)),
        ),
        if (lastReadAt != null)
          Positioned(
            right: 6,
            bottom: 6,
            child: Tooltip(
              message: '最后阅读 @time'.tlParams({
                'time': _absoluteTimeText(lastReadAt),
              }),
              child: _CoverBadge(text: timeToString(lastReadAt), dense: true),
            ),
          ),
      ],
    );
  }

  /// 历史记录的绝对时间，作为相对时间的补充提示。
  String _absoluteTimeText(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '${timeToDateString(time)} $hour:$minute';
  }

  Widget _buildActions(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CoverOverlayAction(
          tooltip: '阅读'.tl,
          icon: Icons.menu_book,
          background: colorScheme.primary.withValues(alpha: 0.9),
          onTap: () => item.read(),
        ),
        const SizedBox(height: 6),
        _CoverOverlayAction(
          tooltip: '目录'.tl,
          icon: Icons.folder_open,
          onTap: () => _openFolder(ref),
        ),
        const SizedBox(height: 6),
        _CoverOverlayAction(
          tooltip: '标签'.tl,
          icon: Icons.label_outline,
          onTap: () => _manageTags(context, ref),
        ),
        const SizedBox(height: 6),
        _CoverOverlayAction(
          tooltip: '标记'.tl,
          icon: item.color?.color == null
              ? Icons.circle_outlined
              : Icons.circle,
          iconColor: item.color?.color ?? Colors.white,
          onTapDown: (details) => _showColorTagMenu(context, ref, details),
        ),
      ],
    );
  }

  Widget _buildTopRightBadges(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final directoryKey = _directoryKey;
    final translationResult = directoryKey == null
        ? null
        : ref
              .watch(translationResultAvailabilityProvider)
              .asData
              ?.value[directoryKey];

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isSelected)
          Tooltip(
            message: '已选择'.tl,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: colorScheme.primary,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check, size: 13, color: Colors.white),
            ),
          )
        else
          Tooltip(
            message: item.aiTranslationCompletedAt == null
                ? '标记为 AI 翻译完成'.tl
                : '取消 AI 翻译完成标记'.tl,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _toggleAiTranslationMarker(context, ref),
              child: MouseRegion(
                cursor: appClickableMouseCursor,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.black38,
                    shape: BoxShape.circle,
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: item.aiTranslationCompletedAt == null
                          ? Colors.grey
                          : Colors.green,
                    ),
                    child: const SizedBox(width: 8, height: 8),
                  ),
                ),
              ),
            ),
          ),
        if (translationResult != null) ...[
          const SizedBox(width: 4),
          Tooltip(
            message: '发现 @num 张翻译结果，分布在 @dirs 个目录'.tlParams({
              'num': translationResult.pairCount.toString(),
              'dirs': translationResult.resultDirectoryCount.toString(),
            }),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _replaceTranslationResults(context, ref),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.red.shade300, width: 1),
                ),
                child: Text(
                  '翻译结果 @num'.tlParams({
                    'num': translationResult.pairCount.toString(),
                  }),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 信息区
  // ---------------------------------------------------------------------------

  Widget _buildInfo(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final scaler = MediaQuery.textScalerOf(context);
    final titleTooltip = (translatedName == null || translatedName!.isEmpty)
        ? _displayName
        : '$_displayName\n${'译文'.tl}：$translatedName';

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: downloadComicCardTitleHeight(scaler),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Tooltip(
                message: titleTooltip,
                waitDuration: const Duration(milliseconds: 500),
                child: Text(
                  _displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 2),
          SizedBox(
            height: downloadComicCardMetaHeight(scaler),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    item.subTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.primary.withValues(alpha: 0.7),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _metaTrailingText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 3),
          SizedBox(
            height: downloadComicCardTagHeight(scaler),
            child: _buildTags(context, ref),
          ),
        ],
      ),
    );
  }

  Widget _buildTags(BuildContext context, WidgetRef ref) {
    final userTagsMap = ref.watch(comicUserTagsProvider).asData?.value;
    final userTags = userTagsMap == null
        ? const <String>[]
        : getUserTags(item, userTagsMap);
    final sourceTags = userTagsMap == null
        ? item.tags
        : getRawTags(item, userTagsMap);
    final isZh = App.locale.languageCode == 'zh';

    final tags = <Widget>[
      for (final tag in userTags)
        if (tag.trim().isNotEmpty)
          _UnderlineTag(
            text: tag,
            isCustom: true,
            onTap: () => _onUserTagTap(ref, tag),
            onSecondaryTap: (details) =>
                _showTagMenu(context, ref, tag, details: details),
          ),
      for (final tag in sourceTags)
        if (tag.trim().isNotEmpty)
          _UnderlineTag(
            text: isZh ? tag.translateTagsToCN : tag,
            isCustom: false,
            onTap: () => updateKeyword(ref, pageId, tag),
            onSecondaryTap: (details) => _showTagMenu(
              context,
              ref,
              isZh ? tag.translateTagsToCN : tag,
              details: details,
            ),
          ),
    ];

    if (tags.isEmpty) return const SizedBox.shrink();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var index = 0; index < tags.length; index++) ...[
            if (index > 0) const SizedBox(width: 8),
            tags[index],
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 阅读进度
  // ---------------------------------------------------------------------------

  Widget _buildProgressBar(
    BuildContext context,
    WidgetRef ref,
    String? historyTarget,
  ) {
    final progress = _resolveProgress(ref, historyTarget);
    if (progress == null || progress <= 0) return const SizedBox.shrink();
    final colorScheme = Theme.of(context).colorScheme;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Tooltip(
        message: '已读 @percent%'.tlParams({
          'percent': (progress * 100).round().toString(),
        }),
        child: SizedBox(
          height: 3,
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 3,
            backgroundColor: colorScheme.onSurface.withValues(alpha: 0.12),
            color: colorScheme.primary,
          ),
        ),
      ),
    );
  }

  /// 最近一次阅读的时间；没有历史记录时返回 null。
  DateTime? _resolveLastReadAt(WidgetRef ref, String? historyTarget) {
    final localPath = _localHistoryPath;
    if (localPath != null) {
      final history = ref
          .watch(localHistoryEntryProvider(localPath))
          .asData
          ?.value;
      if (history == null || history.time <= 0) return null;
      return DateTime.fromMillisecondsSinceEpoch(history.time);
    }

    if (historyTarget == null) return null;
    final record = ref.watch(historyEntryProvider(historyTarget)).asData?.value;
    if (record == null || record.time.millisecondsSinceEpoch <= 0) return null;
    return record.time;
  }

  double? _resolveProgress(WidgetRef ref, String? historyTarget) {
    final localPath = _localHistoryPath;
    if (localPath != null) {
      final history = ref
          .watch(localHistoryEntryProvider(localPath))
          .asData
          ?.value;
      if (history == null || history.totalPages <= 1) return null;
      return (history.pageIndex / history.totalPages).clamp(0.0, 1.0);
    }

    if (historyTarget == null) return null;
    final record = ref.watch(historyEntryProvider(historyTarget)).asData?.value;
    if (record == null || (record.ep == 0 && record.page == 0)) return null;
    final currentPage = math.max(1, record.page);
    final maxPage = record.maxPage ?? currentPage;
    if (maxPage <= 1) return null;
    return (currentPage / maxPage).clamp(0.0, 1.0);
  }

  // ---------------------------------------------------------------------------
  // 交互
  // ---------------------------------------------------------------------------

  /// 刷新下载列表与翻译结果标记；标签由 provider 流通知自动更新。
  void _refresh(WidgetRef ref) {
    ref.invalidate(allDownloadedComicsProvider);
    ref.invalidate(translationResultAvailabilityProvider);
  }

  Future<void> _openFolder(WidgetRef ref) async {
    final directory = await ref
        .read(downloadManagerProvider.notifier)
        .getFullDirectory(item.id);
    await FileUtils.openFileOrDirectory(directory);
  }

  Future<void> _manageTags(BuildContext context, WidgetRef ref) async {
    final userTagsMap =
        ref.read(comicUserTagsProvider).asData?.value ??
        const <String, List<String>>{};
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => TagAssignmentDialog(
        comicIds: [item.id],
        suggestedTags: [
          item.name,
          item.subTitle,
          ...getOriginalTags(item, userTagsMap),
        ],
      ),
    );
    if (result == true) {
      ref.invalidate(downloadTagsProvider);
    }
  }

  Future<void> _showColorTagMenu(
    BuildContext context,
    WidgetRef ref,
    TapDownDetails details,
  ) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final targetPosition = overlay.globalToLocal(details.globalPosition);
    final position = RelativeRect.fromRect(
      Rect.fromPoints(targetPosition, targetPosition),
      Offset.zero & overlay.size,
    );
    final color = await showMenu<DownloadColorTag>(
      context: context,
      position: position,
      items: [
        for (final tag in DownloadColorTag.values)
          PopupMenuItem(
            value: tag,
            child: Row(
              children: [
                if (tag.color != null)
                  Icon(Icons.circle, color: tag.color!, size: 18)
                else
                  const Icon(Icons.circle_outlined, size: 18),
                const SizedBox(width: 8),
                Text(tag.label),
              ],
            ),
          ),
      ],
    );
    if (color != null) {
      ref.read(downloadManagerProvider.notifier).updateColor(item.id, color);
    }
  }

  Future<void> _toggleAiTranslationMarker(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final translations =
        ref.read(translationResultAvailabilityProvider).asData?.value ??
        const <String, TranslationResultInfo>{};
    final directoryKey = _directoryKey;
    if (item.aiTranslationCompletedAt == null &&
        directoryKey != null &&
        translations[directoryKey] != null) {
      showToast(message: '存在未处理或替换失败的翻译结果，暂不能标记完成'.tl);
      return;
    }
    final manager = ref.read(downloadManagerProvider.notifier);
    if (item.aiTranslationCompletedAt == null) {
      await manager.markAiTranslationCompleted(item.id);
    } else {
      await manager.clearAiTranslationCompleted(item.id);
    }
    _refresh(ref);
  }

  Future<void> _replaceTranslationResults(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final result = await TranslationResultReplaceDialog.show(
      context,
      comics: [item],
      translationResultRootDirectory:
          appdata.appSettings.translationResultDirectory,
      onComplete: () => _refresh(ref),
    );
    if (result == false && context.mounted) {
      showToast(message: '没有可应用的翻译图片'.tl);
    }
  }

  /// 自定义标签点击 → 按标签筛选下载列表。
  Future<void> _onUserTagTap(WidgetRef ref, String tag) async {
    final allTags = ref.read(downloadTagsProvider).asData?.value;
    final tagInfo = allTags?.firstWhereOrNull((e) => e.name == tag);
    if (tagInfo != null) {
      updateTagFilter(ref, pageId, tagInfo.id);
    }
  }

  void _showTagMenu(
    BuildContext context,
    WidgetRef ref,
    String tag, {
    required TapDownDetails details,
  }) {
    showContextMenu(
      context: App.globalContext!,
      globalPosition: details.globalPosition,
      items: [
        popupMenuItem<void>(
          text: '管理标签'.tl,
          icon: Icons.label_outline,
          onTap: () async {
            await Future.delayed(const Duration(milliseconds: 300));
            if (context.mounted) {
              await _manageTags(context, ref);
            }
          },
        ),
        popupMenuItem<void>(
          text: '复制'.tl,
          icon: Icons.content_copy,
          onTap: () {
            Clipboard.setData(ClipboardData(text: tag));
            showToast(message: '已复制'.tl);
          },
        ),
        popupMenuItem<void>(
          text: '本地搜索'.tl,
          icon: Icons.search,
          onTap: () => updateKeyword(ref, pageId, tag),
        ),
        popupMenuItem<void>(
          text: '搜索漫画'.tl,
          icon: Icons.travel_explore,
          onTap: () => _searchComic(tag),
        ),
      ],
    );
  }

  /// 按标签在对应漫画源搜索。
  void _searchComic(String tag) {
    var searchTag = tag;
    final originalTag = item.tags.firstWhereOrNull(
      (e) => e.translateTagsToCN == tag || e == tag,
    );
    if (originalTag != null) {
      searchTag = originalTag;
    }

    var sourceKey = item.type.name;
    if (item.type == DownloadType.other) {
      sourceKey = (item as CustomDownloadedItem).sourceKey;
    }
    App.mainNavigatorKey!.currentContext!.to(
      () => SearchResultPage(
        keyword: searchTag,
        comicType: ComicType.fromString(sourceKey),
      ),
    );
  }
}

/// 标题行高度，随系统字号缩放。
double downloadComicCardTitleHeight(TextScaler scaler) =>
    math.max(18, scaler.scale(14) * 1.25);

/// 作者 / 大小行高度。
double downloadComicCardMetaHeight(TextScaler scaler) =>
    math.max(15, scaler.scale(11) * 1.3);

/// 标签行高度。
double downloadComicCardTagHeight(TextScaler scaler) =>
    math.max(16, scaler.scale(11) * 1.3);

/// 卡片信息区总高度（含上下内边距与行间距）。
double downloadComicCardInfoHeight(TextScaler scaler) =>
    6 +
    downloadComicCardTitleHeight(scaler) +
    2 +
    downloadComicCardMetaHeight(scaler) +
    3 +
    downloadComicCardTagHeight(scaler) +
    6;

/// 封面宽高比（宽 / 高）。
///
/// 对齐 PixEz 已下载页：它的网格 `childAspectRatio: 0.7` 作用于「封面 +
/// 信息区」的整体卡片，信息区约 64px，折算到封面本身约为 0.85；这里取
/// 0.85 后，整卡比例同样落在 0.68–0.70。
const double downloadComicCardCoverAspectRatio = 0.85;

/// 下载页专用网格：按可用宽度自适应列数，卡片宽度限制在
/// [minChildWidth] 与 [maxChildWidth] 之间。
class SliverGridDelegateWithDownloadComics extends SliverGridDelegate {
  const SliverGridDelegateWithDownloadComics({
    required this.infoHeight,
    this.minChildWidth = 140,
    this.maxChildWidth = 240,
    this.spacing = 16,
    this.coverAspectRatio = downloadComicCardCoverAspectRatio,
    this.maxColumns = 12,
  });

  /// 卡片信息区高度，由 [downloadComicCardInfoHeight] 计算。
  final double infoHeight;

  final double minChildWidth;
  final double maxChildWidth;

  /// 主 / 交叉轴间距。
  final double spacing;

  /// 封面宽高比（宽 / 高）。
  final double coverAspectRatio;

  final int maxColumns;

  /// 依据可用宽度计算列数、卡片宽度与实际交叉轴间距（余量均分到间距），
  /// 供测试与布局复用。
  ({int columns, double childWidth, double crossAxisSpacing}) resolve(
    double available,
  ) {
    if (available <= 0) {
      return (columns: 1, childWidth: 0, crossAxisSpacing: 0);
    }
    // 以「卡片宽度不超过 maxChildWidth」为起点取列数，使卡片尽量宽，
    // 而不是把列数塞到卡片贴着最小宽度。
    var columns = (available / (maxChildWidth + spacing))
        .ceil()
        .clamp(1, maxColumns)
        .toInt();
    var childWidth = (available - spacing * (columns - 1)) / columns;
    // 卡片被压到最小宽度以下时减少列数，保证可读性。
    while (childWidth < minChildWidth && columns > 1) {
      columns -= 1;
      childWidth = (available - spacing * (columns - 1)) / columns;
    }
    if (childWidth > maxChildWidth) {
      // 列数已达上限或只能单列：锁死最大宽度，把余量均分到间距。
      childWidth = maxChildWidth;
    }
    final crossAxisSpacing = columns > 1
        ? (available - childWidth * columns) / (columns - 1)
        : 0.0;
    return (
      columns: columns,
      childWidth: childWidth,
      crossAxisSpacing: math.max(spacing, crossAxisSpacing),
    );
  }

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) {
    final resolved = resolve(constraints.crossAxisExtent);
    final columns = resolved.columns;
    final childWidth = resolved.childWidth;
    final childHeight = childWidth / coverAspectRatio + infoHeight;
    return SliverGridRegularTileLayout(
      crossAxisCount: columns,
      mainAxisStride: childHeight + spacing,
      crossAxisStride: childWidth + resolved.crossAxisSpacing,
      childMainAxisExtent: childHeight,
      childCrossAxisExtent: childWidth,
      reverseCrossAxis: false,
    );
  }

  @override
  bool shouldRelayout(
    covariant SliverGridDelegateWithDownloadComics oldDelegate,
  ) {
    return oldDelegate.infoHeight != infoHeight ||
        oldDelegate.minChildWidth != minChildWidth ||
        oldDelegate.maxChildWidth != maxChildWidth ||
        oldDelegate.spacing != spacing ||
        oldDelegate.coverAspectRatio != coverAspectRatio ||
        oldDelegate.maxColumns != maxColumns;
  }
}

/// 封面左上角的圆形操作按钮，无文字，仅 Tooltip。
class _CoverOverlayAction extends StatelessWidget {
  const _CoverOverlayAction({
    required this.tooltip,
    required this.icon,
    this.onTap,
    this.onTapDown,
    this.background,
    this.iconColor,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onTap;
  final void Function(TapDownDetails details)? onTapDown;
  final Color? background;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        cursor: appClickableMouseCursor,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          onTapDown: onTapDown,
          child: Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: background ?? Colors.black54,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 18, color: iconColor ?? Colors.white),
          ),
        ),
      ),
    );
  }
}

/// 封面上的小角标（来源、阅读时间）。
class _CoverBadge extends StatelessWidget {
  const _CoverBadge({required this.text, this.dense = false});

  final String text;

  /// 更紧凑的尺寸，用于阅读时间等次要信息。
  final bool dense;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: dense
          ? const EdgeInsets.symmetric(horizontal: 5, vertical: 2)
          : const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        maxLines: 1,
        style: TextStyle(
          color: Colors.white,
          fontSize: dense ? 10 : 11,
          fontWeight: FontWeight.w500,
          height: 1.2,
        ),
      ),
    );
  }
}

/// 带下划线的纯文字标签：自定义标签使用主题色。
class _UnderlineTag extends StatelessWidget {
  const _UnderlineTag({
    required this.text,
    required this.isCustom,
    this.onTap,
    this.onSecondaryTap,
  });

  final String text;
  final bool isCustom;
  final VoidCallback? onTap;
  final void Function(TapDownDetails details)? onSecondaryTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = isCustom ? colorScheme.primary : colorScheme.onSurfaceVariant;
    final decorationColor = isCustom
        ? colorScheme.primary.withValues(alpha: 0.7)
        : colorScheme.onSurfaceVariant.withValues(alpha: 0.35);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onSecondaryTapDown: onSecondaryTap,
      child: MouseRegion(
        cursor: onTap == null && onSecondaryTap == null
            ? MouseCursor.defer
            : appClickableMouseCursor,
        child: Text(
          text,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            height: 1.2,
            fontWeight: isCustom ? FontWeight.w500 : FontWeight.w400,
            color: color,
            decoration: TextDecoration.underline,
            decorationColor: decorationColor,
            decorationThickness: 1,
          ),
        ),
      ),
    );
  }
}

/// 拖动卡片导出漫画目录。
class _DownloadComicCardDragWrapper extends StatelessWidget {
  const _DownloadComicCardDragWrapper({
    required this.downloadedItems,
    required this.child,
  });

  final List<DownloadedItem> downloadedItems;
  final Widget child;

  /// 构造一个代表漫画目录的拖拽项。
  DragItem _createDragItem(DownloadedItem item) {
    final directoryPath = item.directoryPath;
    final dragItem = DragItem(suggestedName: path.basename(directoryPath));
    dragItem.add(Formats.fileUri(Uri.file(directoryPath)));
    return dragItem;
  }

  /// 获取当前仍然存在的漫画目录。
  Future<List<DownloadedItem>> _getExistingItems() async {
    final result = <DownloadedItem>[];
    for (final item in downloadedItems) {
      final directoryPath = item.directoryPath;
      if (directoryPath.isEmpty) continue;
      if (await Directory(directoryPath).exists()) {
        result.add(item);
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return DragItemWidget(
      allowedOperations: () => [DropOperation.copy],
      canAddItemToExistingSession: true,
      dragItemProvider: (request) async {
        final items = await _getExistingItems();
        if (items.isEmpty) return null;
        return _createDragItem(items.first);
      },
      child: DraggableWidget(
        hitTestBehavior: HitTestBehavior.opaque,
        isLocationDraggable: (location) => true,
        onDragConfiguration: (configuration, session) async {
          final items = await _getExistingItems();
          if (items.length <= 1 || configuration.items.isEmpty) {
            return configuration;
          }

          final snapshot = configuration.items.first.image;
          final sharedSnapshot = _RefCountingSnapshot(
            snapshot.snapshot,
            snapshot.rect,
            items.length,
          );
          return DragConfiguration(
            items: [
              for (final item in items)
                DragConfigurationItem(
                  item: _createDragItem(item),
                  image: sharedSnapshot,
                ),
            ],
            allowedOperations: configuration.allowedOperations,
            options: configuration.options,
          );
        },
        child: child,
      ),
    );
  }
}

/// 引用计数镜像包装器，用于批量拖拽时共享镜像。
class _RefCountingSnapshot extends TargetedWidgetSnapshot {
  int _count;

  _RefCountingSnapshot(WidgetSnapshot snapshot, Rect rect, this._count)
    : super(snapshot, rect);

  @override
  void dispose() {
    _count--;
    if (_count <= 0) {
      super.dispose();
    }
  }
}
