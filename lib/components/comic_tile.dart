part of 'components.dart';

/// 仅在存在译文时创建提示框，避免 Tooltip 接收空消息触发断言。
Widget _withTranslationTooltip(String? translation, Widget child) {
  if (translation == null || translation.isEmpty) return child;
  return Tooltip(message: translation, child: child);
}

class ComicTileMenuOption {
  final String title;
  final IconData icon;
  final void Function(String? comicId) onTap;

  const ComicTileMenuOption(this.title, this.icon, this.onTap);
}

abstract class ComicTile extends StatelessWidget {
  /// Show a comic brief information. Usually displayed in comic list page.
  const ComicTile({Key? key}) : super(key: key);

  static final ValueNotifier<ComicTile?> _activeCoverHeroOwner = ValueNotifier(
    null,
  );

  Widget get image;

  Widget? buildSubDescription(BuildContext context) => null;

  String get title;

  /// 已缓存的 AI 标题译文；为空时不显示。
  String? get translatedTitle => null;

  String get subTitle;

  String get description;

  /// 简介文本允许显示的最大行数。
  int get descriptionMaxLines => 2;

  Widget? get badge => null;

  List<String> get primaryTags => [];

  List<String>? get tags => null;

  int get maxLines => 2;

  FavoriteItem? get favoriteItem => null;

  ActionFunc? get read => null;

  bool get enableLongPressed => true;

  int? get pages => null;

  List<ComicTileMenuOption>? get addonMenuOptions => null;

  /// Callback when download button is tapped
  Future<void> Function()? get onDownloadTap => null;

  /// Callback when a tag is tapped
  void Function(String tag)? get onTagTap => null;

  /// Callback when a primary tag is tapped
  void Function(String tag)? get onPrimaryTagTap => null;

  /// Callback when a tag is secondary tapped
  void Function(String tag, TapDownDetails details)? get onTagSecondaryTap =>
      null;

  /// Callback when a primary tag is secondary tapped
  void Function(String tag, TapDownDetails details)?
  get onPrimaryTagSecondaryTap => null;

  /// Comic ID, used to identify a comic.
  String? get comicID => null;

  /// Source type, used to generate download ID.
  ComicType? get comicType => null;

  String? get coverHeroTag {
    final id = comicID;
    final type = comicType;
    if (id == null || type == null || type == ComicType.local) {
      return null;
    }
    return comicCoverHeroTag(type, id);
  }

  bool get showFavorite => true;
  bool get showDownload => true;
  bool get showRead => true;

  void showBlockPane() {
    showDialog(
      context: App.globalContext!,
      builder: (context) => _BlockingPane(comic: this),
    );
  }

  void onLongTap_() {
    bool favorite = false;
    showDialog(
      context: App.globalContext!,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            Widget child;
            if (!favorite) {
              child = Dialog(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Column(
                    key: const Key("1"),
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
                          context.pop();
                          _openDetailWithHero();
                        },
                      ),
                      if (favoriteItem != null)
                        ListTile(
                          leading: const Icon(Icons.bookmark_rounded),
                          title: Text("本地收藏".tl),
                          onTap: () {
                            setState(() {
                              favorite = true;
                            });
                          },
                        ),
                      if (read != null)
                        ListTile(
                          leading: const Icon(Icons.chrome_reader_mode),
                          title: Text("阅读".tl),
                          onTap: () {
                            context.pop();
                            read!();
                          },
                        ),
                      ListTile(
                        leading: const Icon(Icons.search),
                        title: Text("搜索".tl),
                        onTap: () {
                          context.pop();
                          context.to(() => PreSearchPage(initialValue: title));
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.block),
                        title: Text("屏蔽".tl),
                        onTap: () {
                          context.pop();
                          showBlockPane();
                        },
                      ),
                      if (comicID != null && comicType != null)
                        ListTile(
                          leading: const Icon(Icons.folder_open),
                          title: Text("打开下载目录".tl),
                          onTap: () async {
                            context.pop();
                            final downloadId = downloadManager
                                .getDownloadIdFromComicId(comicType, comicID);
                            if (downloadId.isEmpty) {
                              showToast(message: "无法生成下载ID".tl);
                              return;
                            }
                            final isDownloaded = await downloadManager.isExists(
                              downloadId,
                            );
                            if (isDownloaded) {
                              final path = await downloadManager
                                  .getFullDirectory(downloadId);
                              if (path.isNotEmpty) {
                                FileUtils.openFileOrDirectory(path);
                              } else {
                                showToast(message: "目录不存在".tl);
                              }
                            } else {
                              showToast(message: "未下载".tl);
                            }
                          },
                        ),
                      if (addonMenuOptions != null)
                        for (var option in addonMenuOptions!)
                          ListTile(
                            leading: Icon(option.icon),
                            title: Text(option.title),
                            onTap: () => option.onTap(comicID),
                          ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              );
            } else {
              child = buildFavoriteDialog(context);
            }
            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: child,
            );
          },
        );
      },
    );
  }

  Widget buildFavoriteDialog(BuildContext context) {
    return FutureBuilder<List<String>>(
      future: LocalFavoritesManager().folderNames,
      builder: (context, snapshot) {
        String? folder = appdata.settings[51];
        int? initialFolderIndex;
        List<String> folderNames = [];
        if (snapshot.hasData) {
          folderNames = snapshot.data!;
          initialFolderIndex = folderNames.indexOf(appdata.settings[51]);
          if (initialFolderIndex == -1) {
            folder = null;
            initialFolderIndex = null;
          }
        }
        return SimpleDialog(
          title: Text("添加收藏".tl),
          children: [
            if (folderNames.isNotEmpty)
              ListTile(
                title: Text("收藏夹".tl),
                trailing: Select(
                  outline: true,
                  width: 156,
                  values: folderNames,
                  initialValue: initialFolderIndex,
                  onChange: (i) => folder = folderNames[i],
                ),
              ),
            const SizedBox(height: 16),
            Center(
              child: FilledButton(
                child: const Text("确认"),
                onPressed: () {
                  if (folder == null) {
                    showToast(message: '请选择一个文件夹');
                    return;
                  }
                  LocalFavoritesManager().addComic(folder!, favoriteItem!);
                  context.pop();
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }

  void onTap_();

  void _openDetailWithHero() {
    if (coverHeroTag == null) {
      onTap_();
      return;
    }
    _activeCoverHeroOwner.value = this;
    WidgetsBinding.instance.addPostFrameCallback((_) => onTap_());
  }

  /// 构建收藏图标 Widget
  Widget _buildFavoriteIcon(bool detailedMode) {
    return Positioned(
      left: detailedMode ? 16 : 6,
      top: 8,
      child: Container(
        height: 24,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(4)),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            Container(
              height: 24,
              width: 24,
              color: Colors.green,
              child: const Icon(
                Icons.bookmark_rounded,
                size: 16,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建网络阅读图标 Widget
  Widget _buildReadIcon(bool detailedMode) {
    if (comicID == null || comicType == null) {
      return const SizedBox.shrink();
    }
    final downloadId = downloadManager.getDownloadIdFromComicId(
      comicType,
      comicID,
    );
    return Consumer(
      builder: (context, ref, child) {
        final isDownloaded = ref.watch(
          downloadedIdsProvider.select((ids) => ids.contains(downloadId)),
        );

        if (isDownloaded) {
          return Positioned(
            right: detailedMode ? 54 : 44, // 放置在下载按钮的左侧
            bottom: 8,
            child: _buildIcon(Icons.menu_book, () async {
              if (downloadId.isEmpty) {
                return;
              }
              final downloadedItem = await downloadManager.getComicOrNull(
                downloadId,
              );
              if (downloadedItem != null) {
                downloadedItem.read();
              } else {
                showToast(message: "无法获取离线漫画".tl);
              }
            }, color: Theme.of(context).colorScheme.primary),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }

  /// 构建下载图标按钮
  Widget _buildDownloadIcon(bool detailedMode) {
    if (comicID == null || comicType == null) {
      return const SizedBox.shrink();
    }
    final downloadId = downloadManager.getDownloadIdFromComicId(
      comicType,
      comicID,
    );
    return Consumer(
      builder: (context, ref, child) {
        final isDownloaded = ref.watch(
          downloadedIdsProvider.select((ids) => ids.contains(downloadId)),
        );
        final downloadStatus = ref.watch(
          downloadingItemsProvider.select((items) => items[downloadId]),
        );

        if (isDownloaded) {
          return Positioned(
            right: detailedMode ? 16 : 6,
            bottom: 8,
            child: _buildIcon(Icons.folder_open, () async {
              if (downloadId.isEmpty) {
                showToast(message: "无法生成下载ID".tl);
                return;
              }
              final path = await downloadManager.getFullDirectory(downloadId);
              if (path.isNotEmpty) {
                FileUtils.openFileOrDirectory(path);
              } else {
                showToast(message: "目录不存在".tl);
              }
            }, color: Colors.blue),
          );
        }

        if (downloadStatus != null) {
          if (downloadStatus == DownloadStatus.downloading) {
            return Positioned(
              right: detailedMode ? 16 : 6,
              bottom: 8,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    context.to(() => const DownloadPage());
                  },
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.8),
                      shape: BoxShape.circle,
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      child: const CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 3,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }

          IconData icon;
          switch (downloadStatus) {
            case DownloadStatus.waiting:
              icon = Icons.schedule;
              break;
            case DownloadStatus.paused:
              icon = Icons.pause_circle_outline;
              break;
            default:
              icon = Icons.error;
          }

          return Positioned(
            right: detailedMode ? 16 : 6,
            bottom: 8,
            child: _buildIcon(icon, () {
              // 点击跳转下载页面
              context.to(() => const DownloadPage());
            }, color: Colors.green),
          );
        }

        if (onDownloadTap != null) {
          return _DownloadButton(
            onTap: onDownloadTap!,
            detailedMode: detailedMode,
            id: comicID,
          );
        }

        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildIcon(IconData icon, VoidCallback onTap, {Color? color}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: (color ?? Colors.black).withValues(alpha: 0.5),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 18, color: Colors.white),
        ),
      ),
    );
  }

  void onSecondaryTap_(TapDownDetails details) {
    showDesktopMenu(
      App.globalContext!,
      Offset(details.globalPosition.dx, details.globalPosition.dy),
      [
        DesktopMenuEntry(
          text: "查看".tl,
          onClick: () => Future.microtask(_openDetailWithHero),
        ),
        if (read != null)
          DesktopMenuEntry(
            text: "阅读".tl,
            onClick: () => Future.microtask(read!),
          ),
        DesktopMenuEntry(
          text: "搜索".tl,
          onClick: () => Future.microtask(() {
            App.mainNavigatorKey!.currentContext!.to(
              () => PreSearchPage(initialValue: title),
            );
          }),
        ),
        DesktopMenuEntry(
          text: "本地收藏".tl,
          onClick: () => Future.microtask(
            () => showDialog(
              context: App.globalContext!,
              builder: (context) => buildFavoriteDialog(context),
            ),
          ),
        ),
        DesktopMenuEntry(
          text: "屏蔽".tl,
          onClick: () => Future.microtask(showBlockPane),
        ),
        if (comicID != null && comicType != null)
          DesktopMenuEntry(
            text: "打开下载目录".tl,
            onClick: () async {
              final downloadId = downloadManager.getDownloadIdFromComicId(
                comicType,
                comicID,
              );
              if (downloadId.isEmpty) {
                showToast(message: "无法生成下载ID".tl);
                return;
              }
              final isDownloaded = await downloadManager.isExists(downloadId);
              if (isDownloaded) {
                final path = await downloadManager.getFullDirectory(downloadId);
                if (path.isNotEmpty) {
                  FileUtils.openFileOrDirectory(path);
                } else {
                  showToast(message: "目录不存在".tl);
                }
              } else {
                showToast(message: "未下载".tl);
              }
            },
          ),
        if (addonMenuOptions != null)
          for (var option in addonMenuOptions!)
            DesktopMenuEntry(
              text: option.title,
              onClick: () => option.onTap(comicID),
            ),
      ],
    );
  }

  Widget _buildHeroImage() {
    final tag = coverHeroTag;
    if (tag == null) {
      return image;
    }
    final coverImage = image;
    return ValueListenableBuilder<ComicTile?>(
      valueListenable: _activeCoverHeroOwner,
      builder: (context, activeOwner, child) {
        if (!identical(activeOwner, this)) {
          return child!;
        }
        return Hero(tag: tag, child: child!);
      },
      child: coverImage,
    );
  }

  @override
  Widget build(BuildContext context) {
    var type = appdata.settings[44].split(',').first;
    Widget child;
    bool detailedMode;
    if (type == "0" || type == "3") {
      detailedMode = true;
      child = _buildDetailedMode(context);
    } else {
      detailedMode = false;
      child = _buildBriefMode(context);
    }
    final id = comicID;
    if (id != null) {
      final isFavorite = appdata.settings[72] == '1'
          ? LocalFavoritesManager().isExist(id)
          : false;
      child = Stack(
        children: [
          Positioned.fill(child: child),
          if (isFavorite && showFavorite) _buildFavoriteIcon(detailedMode),
          // 下载完成后显示的阅读图标
          if (showRead) _buildReadIcon(detailedMode),
          // 打开下载说明图标或者下载状态图标
          if (showDownload) _buildDownloadIcon(detailedMode),
        ],
      );
    }

    return HoverScaleCard(
      enabled: App.isDesktop,
      scale: detailedMode ? 1.012 : 1.02,
      margin: EdgeInsets.all(App.isDesktop ? 4 : 1),
      borderRadius: BorderRadius.circular(detailedMode ? 12 : 10),
      child: child,
    );
  }

  Widget _buildHistoryTime(BuildContext context) {
    if (comicID == null || appdata.settings[73] != '1') {
      return const SizedBox.shrink();
    }

    return Watch.builder(
      builder: (context) {
        final history = HistoryManager().findInCache(comicID!);
        if (history == null) return const SizedBox.shrink();

        if (history.ep == 0 && history.page == 0) {
          return const SizedBox.shrink();
        }

        final now = DateTime.now();
        final diff = now.difference(history.time);
        String timeStr;
        if (diff.inMinutes < 1) {
          timeStr = "刚刚".tl;
        } else if (diff.inHours < 1) {
          timeStr = "${diff.inMinutes}分钟以前".tl;
        } else if (diff.inDays < 1) {
          timeStr = "${diff.inHours}小时以前".tl;
        } else if (diff.inDays < 30) {
          timeStr = "${diff.inDays}天以前".tl;
        } else {
          timeStr =
              "${history.time.year}-${history.time.month.toString().padLeft(2, '0')}-${history.time.day.toString().padLeft(2, '0')}";
        }

        return Positioned(
          left: 0,
          bottom: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            margin: const EdgeInsets.only(left: 4, bottom: 4),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              timeStr,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHistoryProgressBar(BuildContext context) {
    if (comicID == null || appdata.settings[73] != '1') {
      return const SizedBox.shrink();
    }

    return Watch.builder(
      builder: (context) {
        final history = HistoryManager().findInCache(comicID!);
        if (history == null) return const SizedBox.shrink();

        if (history.ep == 0 && history.page == 0) {
          return const SizedBox.shrink();
        }

        final currentPage = math.max(1, history.page);
        final maxPage = history.maxPage ?? currentPage;
        if (maxPage == 0) return const SizedBox.shrink();

        final progress = (currentPage / maxPage).clamp(0.0, 1.0);

        return Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SizedBox(
            height: 3,
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.transparent,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailedMode(BuildContext context) {
    return _ComicTileInkWell(
      onTap: _openDetailWithHero,
      onLongPress: enableLongPressed ? onLongTap_ : null,
      onSecondaryTap: onSecondaryTap_,
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 24, 10),
            child: Row(
              children: [
                AspectRatio(
                  aspectRatio: 0.68,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: _buildHeroImage(),
                      ),
                      _buildHistoryTime(context),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _ComicDescription(
                    // 标题中不应出现换行符，爬虫可能多爬取换行符。
                    title: pages == null
                        ? title.replaceAll("\n", "")
                        : "[${pages}P]${title.replaceAll("\n", "")}",
                    translatedTitle: translatedTitle,
                    user: subTitle,
                    description: description,
                    descriptionMaxLines: descriptionMaxLines,
                    subDescription: buildSubDescription(context),
                    badge: badge,
                    primaryTags: primaryTags,
                    tags: tags,
                    maxLines: maxLines,
                    onTagTap: onTagTap,
                    onPrimaryTagTap: onPrimaryTagTap,
                    onTagSecondaryTap: onTagSecondaryTap,
                    onPrimaryTagSecondaryTap: onPrimaryTagSecondaryTap,
                  ),
                ),
              ],
            ),
          ),
          _buildHistoryProgressBar(context),
        ],
      ),
    );
  }

  Widget _buildBriefMode(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: Stack(
            fit: StackFit.expand,
            children: [_buildHeroImage(), _buildHistoryTime(context)],
          ),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.4),
                  Colors.black.withValues(alpha: 0.72),
                ],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 20, 10, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _withTranslationTooltip(
                    translatedTitle,
                    Text(
                      title.replaceAll("\n", ""),
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14.0,
                        height: 1.25,
                        color: Colors.white,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: Material(
            color: Colors.transparent,
            child: _ComicTileInkWell(
              onTap: _openDetailWithHero,
              onLongPress: enableLongPressed ? onLongTap_ : null,
              onSecondaryTap: onSecondaryTap_,
              borderRadius: BorderRadius.circular(10),
              child: const SizedBox.expand(),
            ),
          ),
        ),
        _buildHistoryProgressBar(context),
      ],
    );
  }
}

class _ComicDescription extends StatefulWidget {
  const _ComicDescription({
    required this.title,
    this.translatedTitle,
    required this.user,
    required this.description,
    required this.descriptionMaxLines,
    this.subDescription,
    this.badge,
    this.maxLines = 2,
    this.tags,
    this.primaryTags = const [],
    this.onTagTap,
    this.onPrimaryTagTap,
    this.onTagSecondaryTap,
    this.onPrimaryTagSecondaryTap,
  });

  final String title;
  final String? translatedTitle;
  final String user;
  final String description;
  final int descriptionMaxLines;
  final Widget? subDescription;
  final Widget? badge;
  final List<String> primaryTags;
  final List<String>? tags;
  final int maxLines;
  final void Function(String tag)? onTagTap;
  final void Function(String tag)? onPrimaryTagTap;
  final void Function(String tag, TapDownDetails details)? onTagSecondaryTap;
  final void Function(String tag, TapDownDetails details)?
  onPrimaryTagSecondaryTap;

  @override
  State<_ComicDescription> createState() => _ComicDescriptionState();
}

class _ComicDescriptionState extends State<_ComicDescription> {
  TapDownDetails? _details;

  @override
  Widget build(BuildContext context) {
    final tags = (widget.tags ?? const <String>[])
        .where((tag) => tag.removeAllBlank.isNotEmpty)
        .toList(growable: false);
    final primaryTags = widget.primaryTags
        .where((tag) => tag.removeAllBlank.isNotEmpty)
        .toList(growable: false);
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _withTranslationTooltip(
          widget.translatedTitle,
          Text(
            widget.title,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 15,
              height: 1.2,
            ),
            maxLines: widget.maxLines,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (widget.user != "")
          Text(
            widget.user,
            style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        const SizedBox(height: 4),
        if (tags.isNotEmpty || primaryTags.isNotEmpty)
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                double padding = constraints.maxHeight % 23;
                if (constraints.maxHeight < 23) padding = 0;
                return Padding(
                  padding: EdgeInsets.only(bottom: padding),
                  child: Wrap(
                    runAlignment: WrapAlignment.start,
                    clipBehavior: Clip.antiAlias,
                    runSpacing: 4,
                    spacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.end,
                    children: [
                      for (var s in primaryTags)
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onSecondaryTapDown: (details) => _details = details,
                          onSecondaryTap: () {
                            if (_details != null) {
                              widget.onPrimaryTagSecondaryTap?.call(
                                s,
                                _details!,
                              );
                            }
                          },
                          child: InkWell(
                            onTap: () => widget.onPrimaryTagTap?.call(s),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(3, 1, 3, 3),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary,
                                borderRadius: const BorderRadius.all(
                                  Radius.circular(8),
                                ),
                              ),
                              child: Text(
                                s,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onPrimary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      for (var s in tags)
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onSecondaryTapDown: (details) => _details = details,
                          onSecondaryTap: () {
                            if (_details != null) {
                              widget.onTagSecondaryTap?.call(s, _details!);
                            }
                          },
                          child: InkWell(
                            onTap: () => widget.onTagTap?.call(s),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(3, 1, 3, 3),
                              decoration: BoxDecoration(
                                color: s == "Unavailable"
                                    ? colorScheme.errorContainer
                                    : colorScheme.secondaryContainer,
                                borderRadius: const BorderRadius.all(
                                  Radius.circular(8),
                                ),
                              ),
                              child: Text(
                                s,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        const SizedBox(height: 2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.subDescription != null) widget.subDescription!,
                  Text(
                    widget.description,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    maxLines: widget.descriptionMaxLines,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (widget.badge != null)
              Container(
                padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.tertiaryContainer,
                  borderRadius: const BorderRadius.all(Radius.circular(8)),
                ),
                child: DefaultTextStyle(
                  style: const TextStyle(fontSize: 12),
                  child: widget.badge!,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class NormalComicTile extends ComicTile {
  const NormalComicTile({
    required this.description_,
    required this.coverPath,
    required this.name,
    required this.subTitle_,
    required this.onTap,
    this.onLongTap,
    this.badgeName,
    this.headers,
    this.tags,
    ComicType? comicType,
    super.key,
  }) : _comicType = comicType;

  final String description_;
  final String coverPath;
  final void Function() onTap;
  final String subTitle_;
  final String name;
  final void Function()? onLongTap;
  final String? badgeName;
  final Map<String, String>? headers;
  final ComicType? _comicType;

  @override
  final List<String>? tags;

  @override
  String get description => description_;

  @override
  void onLongTap_() => onLongTap?.call();

  @override
  Widget? get badge => badgeName != null ? Text(badgeName!) : null;

  @override
  Widget get image => PicaImage(
    url: coverPath,
    sourceKey: _comicType?.name,
    isThumbnail: true,
    headers: headers,
    fit: BoxFit.cover,
    width: double.infinity,
    height: double.infinity,
  );

  @override
  void onTap_() => onTap();

  @override
  String get subTitle => subTitle_;

  @override
  String get title => name;

  @override
  ComicType? get comicType => _comicType;
}

class ComicTilePlaceholder extends StatelessWidget {
  const ComicTilePlaceholder({super.key, this.type = 'full'});

  final String type;

  @override
  Widget build(BuildContext context) {
    var type = appdata.settings[44].split(',').first;
    Widget child;
    if (type == "0" || type == "3") {
      child = _buildDetailedMode(context);
    } else {
      child = _buildBriefMode(context);
    }
    return child;
  }

  Widget _buildDetailedMode(BuildContext context) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.all(App.isDesktop ? 4 : 1),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Colors.transparent,
      child: LayoutBuilder(
        builder: (context, constrains) {
          final height = constrains.maxHeight - 16;
          return Container(
            padding: const EdgeInsets.fromLTRB(8, 8, 24, 8),
            child: Row(
              children: [
                Container(
                  width: height * 0.68,
                  height: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: context.colorScheme.secondaryContainer.withAlpha(
                      140,
                    ),
                  ),
                ),
                SizedBox.fromSize(size: const Size(16, 5)),
                if (type != 'full')
                  const Spacer()
                else
                  Expanded(
                    child: Column(
                      children: [
                        const SizedBox(height: 3),
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            color: context.colorScheme.tertiaryContainer
                                .withAlpha(140),
                          ),
                          height: 26,
                        ),
                        const SizedBox(height: 4),
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            color: context.colorScheme.tertiaryContainer
                                .withAlpha(140),
                          ),
                          height: 18,
                        ),
                        const Spacer(),
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            color: context.colorScheme.tertiaryContainer
                                .withAlpha(140),
                          ),
                          height: 18,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildBriefMode(BuildContext context) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.all(App.isDesktop ? 4 : 1),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      color: context.colorScheme.secondaryContainer.withAlpha(80),
      child: const SizedBox.expand(),
    );
  }
}

class _ComicTileInkWell extends StatefulWidget {
  const _ComicTileInkWell({
    required this.onTap,
    required this.onLongPress,
    required this.onSecondaryTap,
    required this.child,
    this.borderRadius,
  });

  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final void Function(TapDownDetails) onSecondaryTap;
  final Widget child;
  final BorderRadius? borderRadius;

  @override
  State<_ComicTileInkWell> createState() => _ComicTileInkWellState();
}

class _ComicTileInkWellState extends State<_ComicTileInkWell> {
  TapDownDetails? _details;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: widget.borderRadius,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      onSecondaryTapDown: (details) => _details = details,
      onSecondaryTap: () {
        if (_details != null) {
          widget.onSecondaryTap(_details!);
        }
      },
      child: widget.child,
    );
  }
}

class CustomComicTile extends ComicTile {
  const CustomComicTile(this.comic, {super.key, this.addonMenuOptions});

  final CustomComic comic;

  @override
  String get description => comic.description;

  @override
  Widget get image => PicaImage(
    url: comic.cover,
    sourceKey: comic.sourceKey,
    isThumbnail: true,
    fit: BoxFit.cover,
    width: double.infinity,
    height: double.infinity,
  );

  @override
  void onTap_() {
    App.mainNavigatorKey!.currentContext!.to(
      () => ComicPage(
        comicType: ComicType.fromString(comic.sourceKey),
        id: comic.id,
        cover: comic.cover,
      ),
    );
  }

  @override
  String get subTitle => comic.subTitle;

  @override
  String get title => comic.title;

  @override
  FavoriteItem? get favoriteItem => FavoriteItem.custom(comic);

  @override
  List<String>? get tags => comic.tags;

  @override
  final List<ComicTileMenuOption>? addonMenuOptions;

  @override
  String? get comicID => comic.id;

  @override
  ComicType? get comicType => ComicType.other;

  @override
  get read => () async {
    bool cancel = false;
    var dialog = showLoadingDialog(
      App.globalContext!,
      onCancel: () => cancel = true,
    );
    var comicSource = ComicSource.find(comic.sourceKey)!;
    var res = await comicSource.loadComicInfo!(comic.id);
    if (cancel) return;
    dialog.close();
    if (res.error) {
      showToast(message: res.errorMessage ?? "Error");
    } else {
      var history = await History.findOrCreate(res.data);
      App.globalTo(
        () => ComicReadingPage(
          CustomReadingData(
            res.data.target,
            res.data.title,
            comicSource,
            res.data.chapters,
          ),
          history.page,
          history.ep,
        ),
      );
    }
  };
}

Widget buildComicTile(
  BuildContext context,
  BaseComic item,
  ComicType comicType, {
  List<ComicTileMenuOption>? addonMenuOptions,
}) {
  var source = ComicSource.find(comicType.name);
  if (source == null) {
    throw "Comic Source $comicType Not Found";
  }
  if (!appdata.appSettings.fullyHideBlockedWorks ||
      comicType == ComicType.hitomi) {
    var blockWord = isBlocked(item);
    if (blockWord != null) {
      return Stack(
        children: [
          const Positioned.fill(child: ComicTilePlaceholder(type: '')),
          Positioned.fill(
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: context.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text("${"屏蔽".tl}: $blockWord"),
              ),
            ),
          ),
        ],
      );
    }
  }
  if (source.comicTileBuilderOverride != null) {
    return source.comicTileBuilderOverride!(context, item, addonMenuOptions);
  } else {
    return CustomComicTile(
      item as CustomComic,
      addonMenuOptions: addonMenuOptions,
    );
  }
}

/// return the first blocked keyword, or null if not blocked
String? isBlocked(BaseComic item) {
  for (var word in appdata.blockingKeyword) {
    if (item.title.contains(word)) {
      return word;
    }
    if (item.subTitle.contains(word)) {
      return word;
    }
    if (item.description.contains(word)) {
      return word;
    }
    for (var tag in item.tags) {
      if (tag == word) {
        return word;
      }
      if (tag.contains(':')) {
        tag = tag.split(':')[1];
        if (tag == word) {
          return word;
        }
      }
      if (item.enableTagsTranslation && tag.translateTagsToCN == word) {
        return word;
      }
    }
  }
  return null;
}

class _BlockingPane extends StatefulWidget {
  const _BlockingPane({required this.comic});

  final ComicTile comic;

  @override
  State<_BlockingPane> createState() => _BlockingPaneState();
}

class _BlockingPaneState extends State<_BlockingPane> {
  var controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    var content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Appbar(title: Text("屏蔽".tl), backgroundColor: Colors.transparent),
        SizedBox(
          width: double.infinity,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: buildTags().toList(),
          ).paddingVertical(8),
        ).paddingHorizontal(16),
        SizedBox(
          height: 42,
          child: TextField(
            controller: controller,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: "屏蔽关键词".tl,
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            ),
          ),
        ).paddingHorizontal(16),
        const SizedBox(height: 16),
        Button.filled(onPressed: onSubmit, child: Text("提交".tl)),
        const SizedBox(height: 16),
      ],
    );

    if (context.width > 400) {
      return Dialog(
        elevation: 0,
        backgroundColor: context.colorScheme.surface,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: content,
        ),
      );
    } else {
      return Dialog.fullscreen(
        backgroundColor: context.colorScheme.surface,
        child: content,
      );
    }
  }

  Iterable<Widget> buildTags() sync* {
    yield buildTag(widget.comic.title);
    yield buildTag(widget.comic.subTitle);
    for (var tag in widget.comic.tags ?? []) {
      yield buildTag(tag);
    }
  }

  bool _isExisted(String text) {
    if (text.contains(':')) {
      text = text.split(':')[1];
    }
    return controller.text.split(';').contains(text);
  }

  Widget buildTag(String text) {
    var isExisted = _isExisted(text);
    if (isExisted) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: context.colorScheme.primaryContainer.withValues(alpha: 0.4),
        ),
        child: Text(text),
      );
    }
    return GestureDetector(
      onTap: () => handleText(text),
      child: HoverBox(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          key: Key(text),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: context.colorScheme.primaryContainer,
          ),
          child: Text(text),
        ),
      ),
    );
  }

  void handleText(String text) {
    if (text.contains(':')) {
      text = text.split(':')[1];
    }
    controller.text += "$text;";
    setState(() {});
  }

  void onSubmit() {
    for (var word in controller.text.split(';')) {
      if (word.isNotEmpty && !appdata.blockingKeyword.contains(word)) {
        appdata.blockingKeyword.add(word);
      }
    }
    appdata.writeData();
    for (var c in StateController.findAll<ComicsPageLogic>()) {
      c.update();
    }
    for (var c in StateController.findAll<SliverGridComicsController>()) {
      c.update();
    }
    context.pop();
  }
}

class _DownloadButton extends StatefulWidget {
  final Future<void> Function() onTap;
  final bool detailedMode;
  final String? id;

  const _DownloadButton({
    required this.onTap,
    required this.detailedMode,
    this.id,
  });

  @override
  State<_DownloadButton> createState() => _DownloadButtonState();
}

class _DownloadButtonState extends State<_DownloadButton> {
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.id != null) {
      _isLoading = _loadingIds.contains(widget.id);
      _loadingIds.addListener(_onLoadingChanged);
    }
  }

  @override
  void dispose() {
    if (widget.id != null) {
      _loadingIds.removeListener(_onLoadingChanged);
    }
    super.dispose();
  }

  void _onLoadingChanged() {
    if (widget.id == null) return;
    final isLoading = _loadingIds.contains(widget.id);
    if (isLoading != _isLoading) {
      if (mounted) {
        setState(() {
          _isLoading = isLoading;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: widget.detailedMode ? 16 : 6,
      bottom: 8,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isLoading
              ? null
              : () async {
                  if (widget.id != null) {
                    _loadingIds.add(widget.id!);
                  } else {
                    setState(() {
                      _isLoading = true;
                    });
                  }

                  try {
                    await widget.onTap();
                  } finally {
                    if (widget.id != null) {
                      _loadingIds.remove(widget.id!);
                    } else if (mounted) {
                      setState(() {
                        _isLoading = false;
                      });
                    }
                  }
                },
          borderRadius: BorderRadius.circular(20),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: _isLoading
                ? Container(
                    padding: const EdgeInsets.all(6),
                    child: const CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 3,
                    ),
                  )
                : const Icon(
                    Icons.download_for_offline,
                    size: 24,
                    color: Colors.white,
                  ),
          ),
        ),
      ),
    );
  }
}

// Global loading state for download buttons
class _LoadingIds extends ChangeNotifier {
  final Set<String> _ids = {};

  bool contains(String? id) => id != null && _ids.contains(id);

  void add(String id) {
    _ids.add(id);
    notifyListeners();
  }

  void remove(String id) {
    _ids.remove(id);
    notifyListeners();
  }
}

final _LoadingIds _loadingIds = _LoadingIds();
