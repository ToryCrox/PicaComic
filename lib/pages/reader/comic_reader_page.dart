import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:window_manager/window_manager.dart';
import 'package:pica_comic/base.dart';

import '../../components/components.dart';
import '../../components/window_frame.dart';
import '../../foundation/app.dart';
import '../../foundation/app_settings_provider.dart';
import '../../network/comic_source_services.dart';
import '../../network/download/download_manager.dart';
import '../../foundation/history.dart';
import '../../foundation/log.dart';
import '../../foundation/image_loader/base_image_provider.dart';
import '../../foundation/image_manager.dart';
import '../../foundation/local_favorites.dart';
import '../../tools/key_down_event.dart';
import '../../tools/save_image.dart';
import '../../tools/translations.dart';
import '../comic_page/comic_page_widget.dart';
import 'eps_view.dart';
import 'continuous_reader_data.dart';
import 'image.dart';
import 'image_view.dart';
import 'reader_logic.dart';
import 'reading_data.dart';
import 'reading_type.dart';
import 'tool_bar.dart';
import 'touch_control.dart';

/// 阅读器 - ConsumerStatefulWidget
class ComicReaderPage extends ConsumerStatefulWidget
    implements RootNavigatorPage {
  const ComicReaderPage({
    required this.readingData,
    required this.initialPage,
    required this.initialEp,
    super.key,
  });

  final ReadingData readingData;
  final int initialPage;
  final int initialEp;

  /// 统一入口，替代所有命名构造函数。
  static Future<void> open(
    BuildContext context, {
    required ReadingData readingData,
    int initialPage = 1,
    int initialEp = 1,
  }) {
    return App.to(
      context,
      () => ComicReaderPage(
        readingData: readingData,
        initialPage: initialPage,
        initialEp: initialEp,
      ),
    );
  }

  /// 通知当前激活的漫画详情页更新阅读历史。
  static void updateActiveComicPageHistory(History? history) {
    ComicPageWidget.updateActivePageHistory(history);
  }

  @override
  ConsumerState<ComicReaderPage> createState() => _ComicReaderPageState();
}

class _ComicReaderPageState extends ConsumerState<ComicReaderPage>
    with WidgetsBindingObserver {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  late final String _sessionId;
  // 卸载时不能访问 WidgetRef，提前保存清理所需的依赖和最新设置。
  late final ComicReaderLogic _readerLogic;
  late final DownloadManager _downloadManager;
  late ReaderPageState _readerState;
  late bool _useDarkBackground;

  ReadingData get readingData => widget.readingData;
  ReadingType get type => readingData.type;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _downloadManager = ref.read(downloadManagerProvider.notifier);
    ref.listenManual(
      appSettingsProvider.select(
        (settings) => settings.enabled(AppSettingKeys.readerDarkBackground),
      ),
      (_, value) => _useDarkBackground = value,
      fireImmediately: true,
    );
    readingData.bindDependencies(
      downloadManager: _downloadManager,
      sourceServices: ref.read(comicSourceServicesProvider),
      sourceCallbacks: ref.read(comicSourceCallbackRunnerProvider),
    );
    _sessionId =
        '${widget.readingData.type.name}-${widget.readingData.id}-'
        '${DateTime.now().microsecondsSinceEpoch}';

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
    WakelockPlus.enable();
    final orientation = ref.read(readerSettingsProvider).screenOrientation;
    if (orientation == 1) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else if (orientation == 2) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    }
    BaseImageProvider.clearCache();
    BaseImageProvider.setCacheSizeLimit(500 * 1024 * 1024);
    PaintingBinding.instance.imageCache.maximumSizeBytes = 800 * 1024 * 1024;

    if (_useDarkBackground) {
      Future.microtask(
        () =>
            StateController.findOrNull<WindowFrameController>()?.setDarkTheme(),
      );
    }

    ReaderSession.prepare(
      _sessionId,
      widget.readingData,
      widget.initialPage,
      widget.initialEp,
    );
    _readerLogic = ref.read(comicReaderLogicProvider(_sessionId).notifier);
    ref.listenManual(
      comicReaderLogicProvider(_sessionId),
      (_, value) => _readerState = value,
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    final logic = _readerLogic;
    WidgetsBinding.instance.removeObserver(this);
    logic.saveLocalReadingHistory(snapshot: _readerState);

    PaintingBinding.instance.imageCache.maximumSizeBytes = 400 * 1024 * 1024;
    BaseImageProvider.clearCache();
    BaseImageProvider.setCacheSizeLimit(50 * 1024 * 1024);

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    if (logic.listenVolume != null) {
      logic.listenVolume!.stop();
    }
    WakelockPlus.disable();

    // Cleanup without modifying provider state.
    logic.cancelTimers();
    logic.clearPhotoViewControllers();
    logic.disposeAll();
    ComicImage.clear();
    TapController.detach();

    LocalFavoritesManager().onReadEnd(
      readingData.favoriteId,
      readingData.favoriteType,
    );

    _updateHistory(logic, true, snapshot: _readerState);

    // Exit fullscreen if active — only touch the window manager, not state.
    if (_readerState.isFullScreen) {
      WindowManager.instance.setFullScreen(false);
      StateController.findOrNull<WindowFrameController>()?.showWindowFrame();
    }
    if (!_downloadManager.isDownloading) {
      ImageManager.clearTasks();
    }

    Future.microtask(() {
      ComicReaderPage.updateActiveComicPageHistory(readingData.history);
    });

    if (_useDarkBackground) {
      Future.microtask(
        () => StateController.findOrNull<WindowFrameController>()?.resetTheme(),
      );
    }

    super.dispose();
  }

  /// 进入后台及时保存当前阅读位置。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _updateHistory(_readerLogic, false);
    }
  }

  /// 使用退出前缓存的快照保存进度，避免卸载时触发 Provider 刷新。
  void _updateHistory(
    ComicReaderLogic logic,
    bool updateMePage, {
    ReaderPageState? snapshot,
  }) {
    final state = snapshot ?? logic.snapshot;
    if (readingData is LocalReadingData) {
      logic.saveLocalReadingHistory(snapshot: state);
      return;
    }
    final history = readingData.history;
    if (history == null) return;
    if (readingData.hasEp) {
      if (readingData.adjacentEpisode(state.currentEpisode, -1) == null &&
          state.currentPage == 1) {
        history.ep = 0;
        history.page = 0;
      } else {
        if (readingData.adjacentEpisode(state.currentEpisode, 1) == null &&
            state.currentPage == state.urls.length) {
          history.ep = 0;
          history.page = 0;
        } else {
          history.ep = state.currentEpisode;
          history.page = state.currentPage;
        }
      }
    } else {
      if (state.currentPage == 1) {
        history.ep = 0;
        history.page = 0;
      } else {
        history.ep = 1;
        history.page = state.currentPage;
      }
    }
    readingData.saveChapterPosition(state.currentEpisode, state.currentPage);
    history.maxPage = state.urls.length;
    HistoryManager().saveReadHistory(history, updateMePage);
  }

  @override
  Widget build(BuildContext context) {
    final toolbarSettings = ref.watch(
      readerSettingsProvider.select(
        (settings) => (
          readingMode: settings.readingMode,
          orientation: settings.screenOrientation,
          showButtons: settings.showButtonsInReader,
          flipPageWithClick: settings.flipWithTap,
        ),
      ),
    );
    final screenSettings = ref.watch(
      readerSettingsProvider.select(
        (settings) => (
          useVolumeKeys: settings.useVolumeKeys,
          reduceBrightness: settings.reduceBrightness,
          showPageInfo: settings.showPageInfo,
        ),
      ),
    );
    final useDarkBackground = ref.watch(
      readerSettingsProvider.select(
        (settings) => settings.readerDarkBackground,
      ),
    );
    final state = ref.watch(comicReaderLogicProvider(_sessionId));
    final logic = _readerLogic;

    TapController.attach(logic, _sessionId);
    logic.openEpsView = openEpsDrawer;
    logic.updatePageSize(MediaQuery.of(context).size);

    return DefaultTextStyle.merge(
      style: TextStyle(
        color: useDarkBackground ? Colors.white : null,
        fontSize: 16,
      ),
      child: Scaffold(
        backgroundColor: useDarkBackground ? Colors.black : null,
        extendBody: true,
        extendBodyBehindAppBar: true,
        endDrawerEnableOpenDragGesture: false,
        key: _scaffoldKey,
        endDrawer: Drawer(child: EpsView(readingData, _sessionId)),
        floatingActionButton: buildEpChangeButton(state, logic),
        body: Builder(
          builder: (context) {
            if (state.isLoading) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) logic.loadInfo();
              });
              return SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    BackButton(onPressed: () => App.globalBack()),
                    const Expanded(
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ],
                ),
              );
            } else if (state.urls.isNotEmpty || state.readingItems.isNotEmpty) {
              if (!state.continuousReading && state.urls.isNotEmpty) {
                logic.markCurrentEpisodeRead();
              }
              if (state.readingMethod ==
                      ReadingMethod.topToBottomContinuously &&
                  !logic.haveUsedInitialPage &&
                  widget.initialPage != 0 &&
                  state.urls.isNotEmpty) {
                Future.microtask(() {
                  logic.jumpToPage(widget.initialPage);
                  logic.haveUsedInitialPage = true;
                });
              }

              if (screenSettings.useVolumeKeys) {
                if (logic.listenVolume == null) {
                  logic.listenVolume = ListenVolumeController(
                    () => logic.jumpToLastPage(),
                    () => logic.jumpToNextPage(),
                  );
                  logic.listenVolume!.listenVolumeChange();
                }
              } else if (logic.listenVolume != null) {
                logic.listenVolume!.stop();
                logic.listenVolume = null;
              }

              if (toolbarSettings.readingMode == 4) {
                logic.scrollManager ??= ScrollManager(logic);
              }

              var body = Listener(
                onPointerMove: TapController.onPointerMove,
                onPointerUp: TapController.onTapUp,
                onPointerDown: TapController.onTapDown,
                behavior: HitTestBehavior.translucent,
                onPointerCancel: TapController.onTapCancel,
                child: Stack(
                  children: [
                    buildComicView(
                      state,
                      logic,
                      context,
                      readingData.id,
                      readingData,
                      useDarkBackground,
                      isShowSelectImage: logic.isShowSelectImage,
                    ),
                    if (MediaQuery.of(context).platformBrightness ==
                            Brightness.dark &&
                        screenSettings.reduceBrightness)
                      Positioned(
                        top: 0,
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: IgnorePointer(
                          child: ColoredBox(
                            color: Colors.black.withOpacity(0.2),
                          ),
                        ),
                      ),

                    if (screenSettings.showPageInfo)
                      buildPageInfoText(
                        state,
                        context,
                        readingData: readingData,
                        useDarkBackground: useDarkBackground,
                      ),

                    buildBottomToolBar(
                      state,
                      logic,
                      context,
                      settings: toolbarSettings,
                      showEps: readingData.hasEp,
                      useDarkBackground: useDarkBackground,
                      openEpsDrawer: openEpsDrawer,
                      onShare: () => _share(logic),
                      onSaveCurrentImage: () => _saveCurrentImage(logic),
                    ),

                    ...buildButtons(state, logic, context, toolbarSettings),

                    buildTopToolBar(
                      state,
                      _sessionId,
                      context,
                      readingData: readingData,
                      useDarkBackground: useDarkBackground,
                    ),
                  ],
                ),
              );

              return KeyboardListener(
                focusNode: logic.focusNode,
                autofocus: true,
                onKeyEvent: (event) {
                  logic.handleKeyboard(event);
                  if (event is KeyUpEvent) {
                    if (event.logicalKey == LogicalKeyboardKey.f6) {
                      logic.favoriteCurrentImage();
                    }
                  }
                },
                child: body,
              );
            } else {
              return buildErrorView(state, logic);
            }
          },
        ),
      ),
    );
  }

  Widget buildErrorView(ReaderPageState state, ComicReaderLogic logic) {
    return SafeArea(
      child: Stack(
        children: [
          Positioned(
            left: 8,
            top: 12,
            child: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => App.globalBack(),
            ),
          ),
          Positioned(
            top: MediaQuery.of(App.globalContext!).size.height / 2 - 80,
            left: 0,
            right: 0,
            child: const Align(
              alignment: Alignment.topCenter,
              child: Icon(Icons.error_outline, size: 60),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: MediaQuery.of(App.globalContext!).size.height / 2 - 10,
            child: Align(
              alignment: Alignment.topCenter,
              child: Text(state.errorMessage ?? "未知错误".tl),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: MediaQuery.of(App.globalContext!).size.height / 2 + 30,
            child: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: 250,
                height: 40,
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          logic.change();
                        },
                        child: Text("重试".tl),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          if (!readingData.hasEp) {
                            showToast(message: "没有其它章节".tl);
                            return;
                          }
                          if (MediaQuery.of(context).size.width > 600) {
                            showSideBar(
                              context,
                              EpsView(readingData, _sessionId),
                              title: null,
                              useSurfaceTintColor: true,
                              addTopPadding: true,
                              width: 400,
                            );
                          } else {
                            showModalBottomSheet(
                              context: context,
                              useSafeArea: false,
                              builder: (context) {
                                return EpsView(readingData, _sessionId);
                              },
                            );
                          }
                        },
                        child: Text("切换章节".tl),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void openEpsDrawer() {
    var context = App.globalContext!;
    if (MediaQuery.of(context).size.width > 600) {
      showSideBar(
        context,
        EpsView(readingData, _sessionId),
        title: null,
        useSurfaceTintColor: true,
        width: 400,
        addTopPadding: true,
      );
    } else {
      showModalBottomSheet(
        context: context,
        useSafeArea: false,
        builder: (context) {
          return EpsView(readingData, _sessionId);
        },
      );
    }
  }

  Future<ReaderItem?> selectImage(ComicReaderLogic logic) async {
    var items = logic.visibleImages;
    if (items.isEmpty) return null;
    if (items.length == 1) {
      return logic.imageAtListIndex(items[0].index);
    }
    final images = {
      for (final item in items) item.index: logic.imageAtListIndex(item.index),
    };
    logic.isShowSelectImage = true;
    ReaderItem? res;
    await showDialog(
      context: App.globalContext!,
      builder: (context) {
        return SimpleDialog(
          title: Text("选择屏幕上的图片".tl),
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                children: [
                  for (var item in items)
                    ListTile(
                      title: Text(logic.imageLabel(item.index)),
                      onTap: () {
                        res = images[item.index];
                        App.globalBack();
                      },
                      trailing: const Icon(Icons.arrow_right),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
    logic.isShowSelectImage = false;
    return res;
  }

  Future<File> _getFileFromStream(Stream<DownloadProgress> stream) async {
    await for (var event in stream) {
      if (event.finished) {
        return event.getFile();
      }
    }
    throw "failed";
  }

  /// 解析目标图片时保存章节身份，避免弹窗期间列表刷新改变索引。
  Future<ReaderItem?> _selectCurrentImage(ComicReaderLogic logic) async {
    if (logic.snapshot.readingMethod == ReadingMethod.topToBottomContinuously) {
      return selectImage(logic);
    }
    return logic.imageAtListIndex(logic.snapshot.currentPage - 1);
  }

  void _share(ComicReaderLogic logic) async {
    final image = await _selectCurrentImage(logic);
    if (image == null) return;
    try {
      final file = await _getFileFromStream(
        readingData.loadImage(image.episode, image.page, image.url),
      );
      if (mounted) shareImage(file);
    } catch (error, stack) {
      Log.e('分享阅读图片失败', error: error, stackTrace: stack);
      if (mounted) showToast(message: '加载图片失败'.tl);
    }
  }

  void _saveCurrentImage(ComicReaderLogic logic) async {
    final image = await _selectCurrentImage(logic);
    if (image == null) return;
    try {
      final file = await _getFileFromStream(
        readingData.loadImage(image.episode, image.page, image.url),
      );
      if (mounted) saveImage(file);
    } catch (error, stack) {
      Log.e('保存阅读图片失败', error: error, stackTrace: stack);
      if (mounted) showToast(message: '加载图片失败'.tl);
    }
  }

  Widget? buildEpChangeButton(ReaderPageState state, ComicReaderLogic logic) {
    if (!readingData.hasEp) return null;
    switch (state.showFloatingButtonValue) {
      case -1:
        return FloatingActionButton(
          onPressed: () => logic.jumpToLastChapter(),
          child: const Icon(Icons.arrow_back_ios_outlined),
        );
      case 0:
        return null;
      case 1:
        return Hero(
          tag: "FAB",
          child: Container(
            width: 58,
            height: 58,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Theme.of(App.globalContext!).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      mouseCursor: appClickableMouseCursor,
                      onTap: () => logic.jumpToNextChapter(),
                      borderRadius: BorderRadius.circular(16),
                      child: Center(
                        child: Icon(
                          Icons.arrow_forward_ios,
                          size: 24,
                          color: Theme.of(
                            App.globalContext!,
                          ).colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  height: state.fabValue,
                  child: ColoredBox(
                    color: Theme.of(
                      App.globalContext!,
                    ).colorScheme.surfaceTint.withOpacity(0.2),
                    child: const SizedBox.expand(),
                  ),
                ),
              ],
            ),
          ),
        );
    }
    return null;
  }
}
