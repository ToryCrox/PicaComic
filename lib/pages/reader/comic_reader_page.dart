import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:pica_comic/base.dart';

import '../../components/components.dart';
import '../../components/window_frame.dart';
import '../../foundation/app.dart';
import '../../foundation/app_page_route.dart';
import '../../foundation/history.dart';
import '../../foundation/image_loader/base_image_provider.dart';
import '../../foundation/image_manager.dart';
import '../../foundation/local_favorites.dart';
import '../../foundation/local_history.dart';
import '../../foundation/log.dart';
import '../../foundation/state_controller.dart';
import '../../foundation/ui_mode.dart';
import '../../tools/key_down_event.dart';
import '../../tools/save_image.dart';
import '../../tools/time.dart';
import '../../tools/translations.dart';
import '../comic_page.dart';
import 'eps_view.dart';
import 'image.dart';
import 'image_view.dart';
import 'reader_logic.dart';
import 'reading_data.dart';
import 'reading_type.dart';
import 'tool_bar.dart';
import 'touch_control.dart';

/// 阅读器 - ConsumerStatefulWidget
class ComicReaderPage extends ConsumerStatefulWidget {
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
  static Future<void> open(BuildContext context, {
    required ReadingData readingData,
    int initialPage = 1,
    int initialEp = 1,
  }) {
    return Navigator.of(context).push(
      AppPageRoute(
        builder: (context) => ComicReaderPage(
          readingData: readingData,
          initialPage: initialPage,
          initialEp: initialEp,
        ),
      ),
    );
  }

  /// 通知当前激活的漫画详情页更新阅读历史。
  static void updateActiveComicPageHistory(History? history) {
    if (BaseComicPage.tagsStack.isNotEmpty) {
      BaseComicPage.tagsStack.last.updateHistory(history);
    }
  }

  @override
  ConsumerState<ComicReaderPage> createState() => _ComicReaderPageState();
}

class _ComicReaderPageState extends ConsumerState<ComicReaderPage> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  late final String _sessionId;

  ReadingData get readingData => widget.readingData;
  ReadingType get type => readingData.type;
  bool get useDarkBackground => appdata.appSettings.useDarkBackground;

  ComicReaderLogic _logic() =>
      ref.read(comicReaderLogicProvider(_sessionId).notifier);

  @override
  void initState() {
    super.initState();
    _sessionId =
        '${widget.readingData.type.name}-${widget.readingData.id}-'
        '${DateTime.now().microsecondsSinceEpoch}';

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
    WakelockPlus.enable();
    if (appdata.settings[76] == "1") {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight
      ]);
    } else if (appdata.settings[76] == "2") {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown
      ]);
    }
    BaseImageProvider.clearCache();
    BaseImageProvider.setCacheSizeLimit(500 * 1024 * 1024);
    PaintingBinding.instance.imageCache.maximumSizeBytes = 800 * 1024 * 1024;

    if (useDarkBackground) {
      Future.microtask(() =>
          StateController.findOrNull<WindowFrameController>()
              ?.setDarkTheme());
    }

    ReaderSession.prepare(
        _sessionId, widget.readingData, widget.initialPage, widget.initialEp);
  }

  @override
  void dispose() {
    final logic = _logic();

    PaintingBinding.instance.imageCache.maximumSizeBytes = 400 * 1024 * 1024;
    BaseImageProvider.clearCache();
    BaseImageProvider.setCacheSizeLimit(50 * 1024 * 1024);
    logic.clearPhotoViewControllers();
    logic.disposeAll();

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    if (logic.listenVolume != null) {
      logic.listenVolume!.stop();
    }
    WakelockPlus.disable();
    logic.stopAutoPageTurning();
    ComicImage.clear();
    TapController.detach();

    LocalFavoritesManager()
        .onReadEnd(readingData.favoriteId, readingData.favoriteType);

    _updateHistory(logic, true);

    if (logic.state.isFullScreen) {
      logic.fullscreen();
    }
    if (!downloadManager.isDownloading) {
      ImageManager.clearTasks();
    }

    Future.microtask(() {
      ComicReaderPage.updateActiveComicPageHistory(readingData.history);
    });

    if (appdata.settings[76] != "0") {
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    }
    if (useDarkBackground) {
      Future.microtask(() =>
          StateController.findOrNull<WindowFrameController>()?.resetTheme());
    }

    super.dispose();
  }

  void _updateHistory(ComicReaderLogic logic, bool updateMePage) {
    final history = readingData.history;
    if (history == null) return;
    if (readingData.hasEp) {
      if (logic.state.currentEpisode == 1 && logic.state.currentPage == 1) {
        history.ep = 0;
        history.page = 0;
      } else {
        if (logic.state.currentEpisode == readingData.eps?.length &&
            logic.state.currentPage == logic.length) {
          history.ep = 0;
          history.page = 0;
        } else {
          history.ep = logic.state.currentEpisode;
          history.page = logic.state.currentPage;
        }
      }
    } else {
      if (logic.state.currentPage == 1) {
        history.ep = 0;
        history.page = 0;
      } else {
        history.ep = 1;
        history.page = logic.state.currentPage;
      }
    }
    history.maxPage = logic.length;
    HistoryManager().saveReadHistory(history, updateMePage);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(comicReaderLogicProvider(_sessionId));
    final logic = _logic();

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
        endDrawer: Drawer(
          child: EpsView(readingData, _sessionId),
        ),
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
                    BackButton(
                      onPressed: () => App.globalBack(),
                    ),
                    const Expanded(
                      child: Center(
                        child: CircularProgressIndicator(),
                      ),
                    ),
                  ],
                ),
              );
            } else if (state.urls.isNotEmpty) {
              if (state.readingMethod ==
                      ReadingMethod.topToBottomContinuously &&
                  !logic.haveUsedInitialPage &&
                  widget.initialPage != 0) {
                Future.microtask(() {
                  logic.jumpToPage(widget.initialPage);
                  logic.haveUsedInitialPage = true;
                });
              }

              if (appdata.settings[7] == "1") {
                if (logic.listenVolume == null) {
                  logic.listenVolume = ListenVolumeController(
                      () => logic.jumpToLastPage(),
                      () => logic.jumpToNextPage());
                  logic.listenVolume!.listenVolumeChange();
                }
              } else if (logic.listenVolume != null) {
                logic.listenVolume!.stop();
                logic.listenVolume = null;
              }

              if (appdata.settings[9] == "4") {
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
                        appdata.appSettings.reduceBrightnessInDarkMode)
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

                    if (appdata.appSettings.showPageInfoInReader)
                      buildPageInfoText(state, context,
                          readingData: readingData,
                          useDarkBackground: useDarkBackground),

                    buildBottomToolBar(state, logic, context,
                        showEps: readingData.hasEp,
                        useDarkBackground: useDarkBackground,
                        openEpsDrawer: openEpsDrawer,
                        onShare: () => _share(logic),
                        onSaveCurrentImage: () => _saveCurrentImage(logic)),

                    ...buildButtons(state, logic, context),

                    buildTopToolBar(state, _sessionId, context,
                        readingData: readingData,
                        useDarkBackground: useDarkBackground),
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
            child: Icon(
              Icons.error_outline,
              size: 60,
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: MediaQuery.of(App.globalContext!).size.height / 2 - 10,
          child: Align(
            alignment: Alignment.topCenter,
            child: Text(
              state.errorMessage ?? "未知错误".tl,
            ),
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
                  const SizedBox(
                    width: 8,
                  ),
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
                  )),
                ],
              ),
            ),
          ),
        ),
      ],
    ));
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

  Future<int?> selectImage(ComicReaderLogic logic) async {
    var items = logic.itemScrollListener.itemPositions.value.toList();
    if (items.length == 1) {
      return items[0].index;
    }
    logic.isShowSelectImage = true;
    int? res;
    await showDialog(
        context: App.globalContext!,
        builder: (context) {
          return SimpleDialog(
            title: Text("选择屏幕上的图片".tl),
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 400,
                ),
                child: Column(
                  children: [
                    for (var item in items)
                      ListTile(
                        title: Text((item.index + 1).toString()),
                        onTap: () {
                          res = item.index;
                          App.globalBack();
                        },
                        trailing: const Icon(Icons.arrow_right),
                      )
                  ],
                ),
              )
            ],
          );
        });
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

  void _share(ComicReaderLogic logic) async {
    int? index = logic.state.currentPage - 1;
    if (logic.state.readingMethod == ReadingMethod.topToBottomContinuously) {
      index = await selectImage(logic);
    }
    if (index == null) {
      return;
    }

    var file = await _getFileFromStream(readingData.loadImage(
        logic.state.currentEpisode, index, logic.state.urls[index]));

    shareImage(file);
  }

  void _saveCurrentImage(ComicReaderLogic logic) async {
    int? index = logic.state.currentPage - 1;
    if (logic.state.readingMethod == ReadingMethod.topToBottomContinuously) {
      index = await selectImage(logic);
    }
    if (index == null) {
      return;
    }

    var file = await _getFileFromStream(readingData.loadImage(
        logic.state.currentEpisode, index, logic.state.urls[index]));

    saveImage(file);
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
                  color: Theme.of(App.globalContext!)
                      .colorScheme
                      .primaryContainer,
                  borderRadius: BorderRadius.circular(16)),
              child: Stack(
                children: [
                  Positioned.fill(
                      child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => logic.jumpToNextChapter(),
                      borderRadius: BorderRadius.circular(16),
                      child: Center(
                          child: Icon(
                        Icons.arrow_forward_ios,
                        size: 24,
                        color: Theme.of(App.globalContext!)
                            .colorScheme
                            .onPrimaryContainer,
                      )),
                    ),
                  )),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    height: state.fabValue,
                    child: ColoredBox(
                      color: Theme.of(App.globalContext!)
                          .colorScheme
                          .surfaceTint
                          .withOpacity(0.2),
                      child: const SizedBox.expand(),
                    ),
                  )
                ],
              ),
            ));
    }
    return null;
  }
}
