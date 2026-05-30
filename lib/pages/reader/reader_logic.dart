import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:photo_view/photo_view.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:window_manager/window_manager.dart';

import '../../components/scrollable_list/src/item_positions_listener.dart';
import '../../components/scrollable_list/src/scrollable_positioned_list.dart';
import '../../components/window_frame.dart';
import '../../foundation/app.dart';
import '../../foundation/image_manager.dart';
import '../../foundation/local_favorites.dart';
import '../../foundation/log.dart';
import '../../foundation/state_controller.dart';
import '../../network/eh_network/eh_models.dart';
import '../../network/hitomi_network/hitomi_models.dart';
import '../../network/jm_network/jm_image.dart';
import '../../network/jm_network/jm_network.dart';
import '../../network/res.dart';
import '../../tools/image_size_getter.dart';
import '../../tools/save_image.dart';
import '../../tools/translations.dart';
import '../../tools/type_util.dart';
import '../jm/jm_comments_page.dart';
import 'eps_view.dart';
import 'image.dart';
import 'image_view.dart';
import 'reading_data.dart';
import 'reading_settings.dart';
import 'reading_type.dart';
import 'tool_bar.dart';
import 'touch_control.dart';
import 'package:pica_comic/base.dart';
import '../../components/components.dart';
import '../../foundation/history.dart';
import '../../tools/iterable_extension.dart';
import '../../tools/key_down_event.dart';

part 'reader_logic.g.dart';

// ============================================================================
// ReaderPageState -- immutable UI state
// ============================================================================

class ReaderPageState {
  final bool isLoading;
  final String? errorMessage;
  final List<String> urls;
  final int currentPage; // 1-based
  final int currentEpisode; // 1-based
  final bool toolsVisible;
  final bool showSettings;
  final ReadingMethod readingMethod;
  final int showFloatingButtonValue; // -1=prev, 0=none, 1=next
  final double fabValue;
  final double currentScale;
  final bool noScroll;
  final bool mouseScroll;
  final bool runningAutoPageTurning;
  final bool isFullScreen;
  final bool isShowOriginSize;
  final bool? rotation; // null=跟随系统, false=竖向, true=横向
  final bool isShowSelectImage;
  final int rebuildCount;

  const ReaderPageState({
    this.isLoading = true,
    this.errorMessage,
    this.urls = const [],
    this.currentPage = 1,
    this.currentEpisode = 1,
    this.toolsVisible = false,
    this.showSettings = false,
    this.readingMethod = ReadingMethod.leftToRight,
    this.showFloatingButtonValue = 0,
    this.fabValue = 0,
    this.currentScale = 1.0,
    this.noScroll = false,
    this.mouseScroll = false,
    this.runningAutoPageTurning = false,
    this.isFullScreen = false,
    this.isShowOriginSize = false,
    this.rotation,
    this.isShowSelectImage = false,
    this.rebuildCount = 0,
  });

  ReaderPageState copyWith({
    bool? isLoading,
    String? errorMessage,
    List<String>? urls,
    int? currentPage,
    int? currentEpisode,
    bool? toolsVisible,
    bool? showSettings,
    ReadingMethod? readingMethod,
    int? showFloatingButtonValue,
    double? fabValue,
    double? currentScale,
    bool? noScroll,
    bool? mouseScroll,
    bool? runningAutoPageTurning,
    bool? isFullScreen,
    bool? isShowOriginSize,
    bool? rotation,
    bool? isShowSelectImage,
    int? rebuildCount,
    bool clearError = false,
  }) {
    return ReaderPageState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      urls: urls ?? this.urls,
      currentPage: currentPage ?? this.currentPage,
      currentEpisode: currentEpisode ?? this.currentEpisode,
      toolsVisible: toolsVisible ?? this.toolsVisible,
      showSettings: showSettings ?? this.showSettings,
      readingMethod: readingMethod ?? this.readingMethod,
      showFloatingButtonValue:
          showFloatingButtonValue ?? this.showFloatingButtonValue,
      fabValue: fabValue ?? this.fabValue,
      currentScale: currentScale ?? this.currentScale,
      noScroll: noScroll ?? this.noScroll,
      mouseScroll: mouseScroll ?? this.mouseScroll,
      runningAutoPageTurning:
          runningAutoPageTurning ?? this.runningAutoPageTurning,
      isFullScreen: isFullScreen ?? this.isFullScreen,
      isShowOriginSize: isShowOriginSize ?? this.isShowOriginSize,
      rotation: rotation ?? this.rotation,
      isShowSelectImage: isShowSelectImage ?? this.isShowSelectImage,
      rebuildCount: rebuildCount ?? this.rebuildCount,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ReaderPageState) return false;
    return isLoading == other.isLoading &&
        errorMessage == other.errorMessage &&
        listEquals(urls, other.urls) &&
        currentPage == other.currentPage &&
        currentEpisode == other.currentEpisode &&
        toolsVisible == other.toolsVisible &&
        showSettings == other.showSettings &&
        readingMethod == other.readingMethod &&
        showFloatingButtonValue == other.showFloatingButtonValue &&
        fabValue == other.fabValue &&
        currentScale == other.currentScale &&
        noScroll == other.noScroll &&
        mouseScroll == other.mouseScroll &&
        runningAutoPageTurning == other.runningAutoPageTurning &&
        isFullScreen == other.isFullScreen &&
        isShowOriginSize == other.isShowOriginSize &&
        rotation == other.rotation &&
        isShowSelectImage == other.isShowSelectImage &&
        rebuildCount == other.rebuildCount;
  }

  @override
  int get hashCode => Object.hashAll([
        isLoading,
        errorMessage,
        Object.hashAll(urls),
        currentPage,
        currentEpisode,
        toolsVisible,
        showSettings,
        readingMethod,
        showFloatingButtonValue,
        fabValue,
        currentScale,
        noScroll,
        mouseScroll,
        runningAutoPageTurning,
        isFullScreen,
        isShowOriginSize,
        rotation,
        isShowSelectImage,
        rebuildCount,
      ]);
}

// ============================================================================
// Session initialization
// ============================================================================

class _ReaderInitParams {
  final ReadingData readingData;
  final int initialPage;
  final int initialEp;

  _ReaderInitParams(this.readingData, this.initialPage, this.initialEp);
}

abstract class ReaderSession {
  static final Map<String, _ReaderInitParams> _pendingParams = {};

  static void prepare(
      String sessionId, ReadingData readingData, int initialPage, int initialEp) {
    _pendingParams[sessionId] =
        _ReaderInitParams(readingData, initialPage, initialEp);
  }
}

// ============================================================================
// ScrollRecord
// ============================================================================

class PageScrollRecord {
  final double position;
  final int timestamp;

  PageScrollRecord(this.position, this.timestamp);
}

// ============================================================================
// PageControllerExtension
// ============================================================================

extension PageControllerExtension on PageController {
  void animatedJumpToPage(int page) {
    final current = this.page?.round() ?? 0;
    if ((current - page).abs() > 1) {
      jumpToPage(page > current ? page - 1 : page + 1);
    }
    animateToPage(page,
        duration: const Duration(milliseconds: 300), curve: Curves.ease);
  }

  void jumpByDeviceType(int page, ComicReaderLogic logic) {
    if (logic.internalMouseScroll) {
      jumpToPage(page);
    } else {
      animatedJumpToPage(page);
    }
  }
}

// ============================================================================
// ComicReaderLogic -- Riverpod Notifier
// ============================================================================

@Riverpod(keepAlive: false, name: 'comicReaderLogicProvider')
class ComicReaderLogic extends _$ComicReaderLogic {
  // ---- Controllers (mutable, don't trigger rebuild) ----

  late PageController pageController;
  var itemScrollController = ItemScrollController();
  var itemScrollListener = ItemPositionsListener.create();
  var scrollController = ScrollController(keepScrollOffset: true);

  PhotoViewController get photoViewController =>
      photoViewControllers[state.currentPage] ?? photoViewControllers[0]!;

  var photoViewControllers = <int, PhotoViewController>{};

  void clearPhotoViewControllers() {
    photoViewControllers.forEach((key, value) => value.dispose());
    photoViewControllers.clear();
  }

  ListenVolumeController? listenVolume;
  ScrollManager? scrollManager;
  FocusNode focusNode = FocusNode();

  // ---- Reading data (set once in build) ----
  late ReadingData readingData;

  // ---- Internal mutable state (don't trigger rebuild) ----

  final Map<String, Size?> _imageSize = {};
  Map<String, Size?> get imageSize => _imageSize;
  final _hasComputeImageSizes = <String>{};
  final List<StreamSubscription> _imageSizeSubscriptions = [];
  List<bool> requestedLoadingItems = [];
  bool haveUsedInitialPage = false;
  bool restoreTopToBottomContinuouslyPage = false;
  bool isDispose = false;
  final _indexChangeCallbacks = <void Function(int)>[];
  void Function() openEpsView = () {};
  bool isAutoFullscreenAndScroll = false;
  Size _pageSize = Size.zero;
  bool _isShowSelectImage = false;
  bool get isShowSelectImage => _isShowSelectImage;
  set isShowSelectImage(bool show) {
    _isShowSelectImage = show;
    state = state.copyWith(isShowSelectImage: show);
  }

  // ---- Auto page turning state ----
  Timer? _autoPageTurningTimer;
  Timer? _wheelDebounceTimer;
  Timer? _keyboardPageTurnDebounceTimer;
  bool _isAutoPageTurningPaused = false;
  bool _isWheelScrolling = false;
  bool _isKeyboardPageTurning = false;
  int _lastKeyboardTime = 0;
  final List<PageScrollRecord> scrollRecords = [];
  double? releaseVelocity;
  bool internalMouseScroll = false;

  bool get mouseScroll => internalMouseScroll;
  bool userInteracting = false;
  bool get isCtrlPressed => HardwareKeyboard.instance.isControlPressed;

  /// 双页模式下是否在第一页时显示单页
  bool get singlePageForFirstScreen => appdata.implicitData[1] == '1';

  double get _animateNextPageDistance =>
      (_pageSize.height * 0.95).clamp(100, 2000);

  /// 当前章节的长度
  int get length => state.urls.length;

  static int _getIndex(int initPage) {
    if (appdata.settings[9] == "5" || appdata.settings[9] == "6") {
      return initPage % 2 == 1 ? initPage : initPage - 1;
    } else {
      return initPage;
    }
  }

  static int getPage(int initPage) {
    if (appdata.settings[9] == "5" || appdata.settings[9] == "6") {
      return (initPage + 2) ~/ 2;
    } else {
      return initPage;
    }
  }

  // ---- Lifecycle ----

  @override
  ReaderPageState build(String sessionId) {
    final params = ReaderSession._pendingParams.remove(sessionId)!;
    final readingData = params.readingData;
    var initialPage = params.initialPage;
    var order = params.initialEp;

    if (initialPage <= 0) {
      initialPage = 1;
    }
    if (order <= 0) {
      order = 1;
    }

    this.readingData = readingData;
    pageController = PageController(initialPage: getPage(initialPage));

    final isShowOriginSize = appdata.settings[43] == '0' ||
        readingData is LocalReadingData ||
        readingData.isDownloaded;

    // Set up itemScrollListener
    itemScrollListener.itemPositions.addListener(() {
      if (itemScrollListener.itemPositions.value.isNotEmpty) {
        var newIndex =
            itemScrollListener.itemPositions.value.first.index + 1;
        if (newIndex != state.currentPage) {
          state = state.copyWith(currentPage: newIndex);
        }
      }
    });

    return ReaderPageState(
      isLoading: true,
      currentPage: _getIndex(initialPage),
      currentEpisode: order,
      readingMethod:
          ReadingMethod.values[int.parse(appdata.settings[9]) - 1],
      isShowOriginSize: isShowOriginSize,
    );
  }

  // ---- Index management ----

  void addIndexChangeCallback(void Function(int) callback) {
    _indexChangeCallbacks.add(callback);
  }

  void removeIndexChangeCallback(void Function(int) callback) {
    _indexChangeCallbacks.remove(callback);
  }

  // ---- Public state mutation methods ----

  void setCurrentPage(int page) => state = state.copyWith(currentPage: page);
  void setCurrentScale(double scale) => state = state.copyWith(currentScale: scale);
  void setNoScroll(bool value) => state = state.copyWith(noScroll: value);
  void setFabValue(double value) => state = state.copyWith(fabValue: value);
  void hideSettings() => state = state.copyWith(showSettings: false);
  void setToolsVisible(bool value) => state = state.copyWith(toolsVisible: value);
  void toggleTools() => state = state.copyWith(toolsVisible: !state.toolsVisible);
  void setRotation(bool? value) => state = state.copyWith(rotation: value);
  void toggleShowOriginSize() =>
      state = state.copyWith(isShowOriginSize: !state.isShowOriginSize);
  void setReadingMethod(ReadingMethod method) =>
      state = state.copyWith(readingMethod: method);
  void hideToolsAndSettings() =>
      state = state.copyWith(toolsVisible: false, showSettings: false);

  void startAutoPageTurning() {
    state = state.copyWith(runningAutoPageTurning: true, toolsVisible: false);
    autoPageTurning();
  }

  /// Force a rebuild when external settings change (e.g. appdata).
  void notifySettingsChanged() =>
      state = state.copyWith(rebuildCount: state.rebuildCount + 1);

  void notifyIndexChange(int value) {
    for (var element in _indexChangeCallbacks) {
      element(value);
    }
  }

  // ---- Core operations ----

  void updatePageSize(Size size) {
    _pageSize = size;
  }

  void showFloatingButton(int value) {
    if (value == 0) {
      if (state.showFloatingButtonValue != 0) {
        state = state.copyWith(showFloatingButtonValue: 0, fabValue: 0);
      }
    }
    if (value == 1 && state.showFloatingButtonValue == 0) {
      state = state.copyWith(showFloatingButtonValue: 1);
    } else if (value == -1 &&
        state.showFloatingButtonValue == 0 &&
        state.currentEpisode != 1) {
      state = state.copyWith(showFloatingButtonValue: -1);
    }
  }

  void reload() {
    pageController = PageController(initialPage: 1);
    state = state.copyWith(currentPage: 1, isLoading: true);
  }

  void change() {
    state = state.copyWith(isLoading: !state.isLoading);
  }

  // ---- Navigation ----

  Future<void> jumpToNextPage(
      {bool animate = false, bool resetAutoTurning = false}) async {
    final method = state.readingMethod;
    if (method.index < 3) {
      pageController.jumpToPage(state.currentPage + 1);
      if (resetAutoTurning && state.runningAutoPageTurning) {
        autoPageTurning();
      }
    } else if (method == ReadingMethod.topToBottomContinuously) {
      if (resetAutoTurning && state.runningAutoPageTurning) {
        _isKeyboardPageTurning = true;
        pauseAutoPageTurning();
      }

      final maxScrollExtent = scrollController.position.maxScrollExtent;
      if (animate) {
        double distance = 600;
        if (maxScrollExtent - scrollController.position.pixels < 600) {
          distance = (maxScrollExtent - scrollController.position.pixels)
              .clamp(10, 600);
        }
        int sec = int.parse(appdata.settings[33]);
        final duration = Duration(
            milliseconds: (distance / 600 * 1200 * (sec / 5)).toInt());
        await scrollController.animateTo(
            scrollController.position.pixels + distance,
            duration: duration,
            curve: Curves.linear);
      } else {
        final duration = Duration(
            milliseconds: (300 / 600 * _animateNextPageDistance).toInt());
        await scrollController.animateTo(
            scrollController.position.pixels + _animateNextPageDistance,
            duration: duration,
            curve: Curves.decelerate);
      }

      if (resetAutoTurning && state.runningAutoPageTurning) {
        _isKeyboardPageTurning = false;
        resumeAutoPageTurning();
      }
    } else {
      pageController.jumpToPage(pageController.page!.round() + 1);
    }
  }

  Future<void> jumpToLastPage({bool resetAutoTurning = false}) async {
    final method = state.readingMethod;
    if (method.index < 3) {
      pageController.jumpToPage(state.currentPage - 1);
      if (resetAutoTurning && state.runningAutoPageTurning) {
        autoPageTurning();
      }
    } else if (method == ReadingMethod.topToBottomContinuously) {
      if (resetAutoTurning && state.runningAutoPageTurning) {
        _isKeyboardPageTurning = true;
        pauseAutoPageTurning();
      }

      final duration = Duration(
          milliseconds: (300 / 600 * _animateNextPageDistance).toInt());
      await scrollController.animateTo(
          scrollController.position.pixels - _animateNextPageDistance,
          duration: duration,
          curve: Curves.decelerate);

      if (resetAutoTurning && state.runningAutoPageTurning) {
        _isKeyboardPageTurning = false;
        resumeAutoPageTurning();
      }
    } else {
      pageController.jumpToPage(pageController.page!.round() - 1);
    }
  }

  void jumpToPage(int i, [bool updateWidget = false]) {
    i = i.clamp(1, length);
    final method = state.readingMethod;
    if (method == ReadingMethod.topToBottomContinuously) {
      itemScrollController.jumpTo(index: i - 1);
    } else if (!method.isTwoPage) {
      pageController.jumpToPage(i);
    } else {
      var index = singlePageForFirstScreen ? i ~/ 2 + 1 : (i + 1) ~/ 2;
      pageController.jumpToPage(index);
    }
    if (state.currentPage != i) {
      state = state.copyWith(currentPage: i);
      notifyIndexChange(i);
    }
  }

  void jumpByDeviceType(int page) {
    Future.microtask(() {
      if (internalMouseScroll) {
        pageController.jumpToPage(page);
      } else {
        pageController.animatedJumpToPage(page);
      }
    });
  }

  void jumpToNextChapter() {
    var eps = readingData.eps;
    state = state.copyWith(showFloatingButtonValue: 0);
    if (!readingData.hasEp || state.currentEpisode == eps?.length) {
      final method = state.readingMethod;
      if (method != ReadingMethod.topToBottomContinuously) {
        if (method.index < 3) {
          jumpByDeviceType(state.urls.length);
        } else if (method == ReadingMethod.twoPage) {
          jumpByDeviceType((state.urls.length % 2 + state.urls.length) ~/ 2);
        }
      } else {
        jumpToPage(state.urls.length);
        state = state.copyWith(currentPage: state.urls.length);
      }
      return;
    }
    final newOrder = state.currentEpisode + 1;
    if (readingData is LocalReadingData) {
      (readingData as LocalReadingData).goNext();
    }
    state = state.copyWith(
      urls: [],
      isLoading: true,
      toolsVisible: false,
      currentEpisode: newOrder,
      currentPage: 1,
    );
    pageController = PageController(initialPage: 1);
    clearPhotoViewControllers();
  }

  void jumpToChapter(int index) {
    if (readingData is LocalReadingData) {
      (readingData as LocalReadingData).goTo(index - 1);
    }
    state = state.copyWith(
      urls: [],
      isLoading: true,
      toolsVisible: false,
      currentEpisode: index,
      currentPage: 1,
    );
    pageController = PageController(initialPage: 1);
    clearPhotoViewControllers();
  }

  void jumpToLastChapter() {
    state = state.copyWith(showFloatingButtonValue: 0);
    if (state.currentEpisode == 1 || !readingData.hasEp) {
      final method = state.readingMethod;
      if (method != ReadingMethod.topToBottomContinuously) {
        jumpByDeviceType(1);
      } else {
        jumpToPage(1);
        state = state.copyWith(currentPage: 1);
      }
      return;
    }

    final newOrder = state.currentEpisode - 1;
    if (readingData is LocalReadingData) {
      (readingData as LocalReadingData).goPrev();
    }
    state = state.copyWith(
      urls: [],
      isLoading: true,
      toolsVisible: false,
      currentEpisode: newOrder,
      currentPage: 1,
    );
    pageController = PageController(initialPage: 1);
    clearPhotoViewControllers();
  }

  // ---- Image size loading ----

  Future<void> loadImageSizes([int? fromIndex]) async {
    int startIndex = state.currentPage - 1;
    if (startIndex < 0) {
      startIndex = 0;
    }
    if (fromIndex != null) {
      startIndex = fromIndex;
    }
    if (startIndex >= state.urls.length) {
      return;
    }

    final localImageUrls = state.urls
        .sublist(startIndex, min(startIndex + 5, state.urls.length))
        .where((e) => e.startsWith('file://'))
        .toList();
    final needLoadUrls = localImageUrls
        .where((e) => !_hasComputeImageSizes.contains(e))
        .toList();
    if (needLoadUrls.isEmpty) {
      return;
    }
    _hasComputeImageSizes.addAll(needLoadUrls);

    debugPrint(
        "loadImageSizes start $startIndex, ${needLoadUrls.map((e) => path.basename(e)).toList()}");
    _imageSizeSubscriptions.add(computeImageSizes(needLoadUrls).listen((e) {
      for (var url in e.keys) {
        final sizeInfo = e[url]!;
        _imageSize[url] = sizeInfo.size;
      }
      state = state.copyWith();
    }));
    debugPrint("loadImageSizes finish");
  }

  void disposeAll() {
    for (var element in _imageSizeSubscriptions) {
      element.cancel();
    }
    _imageSizeSubscriptions.clear();
    isDispose = true;
  }

  // ---- Fullscreen ----

  void fullscreen() {
    WindowManager.instance.setFullScreen(!state.isFullScreen);
    final newFullScreen = !state.isFullScreen;
    state = state.copyWith(isFullScreen: newFullScreen);
    focusNode.requestFocus();

    if (newFullScreen) {
      StateController.find<WindowFrameController>().hideWindowFrame();
    } else {
      StateController.find<WindowFrameController>().showWindowFrame();
    }
  }

  // ---- Keyboard handling ----

  void handleKeyboard(KeyEvent event) {
    bool hasEvent = false;
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      Log.d('handleKeyboard key: $event');
      bool reverse =
          appdata.settings[9] == "2" || appdata.settings[9] == "6";
      switch (event.logicalKey) {
        case LogicalKeyboardKey.arrowDown:
        case LogicalKeyboardKey.arrowRight:
          reverse
              ? jumpToLastPage(resetAutoTurning: true)
              : jumpToNextPage(resetAutoTurning: true);
          hasEvent = true;
          break;
        case LogicalKeyboardKey.arrowUp:
        case LogicalKeyboardKey.arrowLeft:
          reverse
              ? jumpToNextPage(resetAutoTurning: true)
              : jumpToLastPage(resetAutoTurning: true);
          hasEvent = true;
          break;
        case LogicalKeyboardKey.f12:
          hasEvent = true;
          fullscreen();
          break;
      }
    } else if (event is KeyUpEvent) {
      Log.d('handleKeyboard key: $event');
      if ((DateTime.now().millisecondsSinceEpoch - _lastKeyboardTime).abs() <
          1000) {
        Log.i('handleKeyboard Keyboard repeat event ignored $event');
        return;
      }
      switch (event.logicalKey) {
        case LogicalKeyboardKey.f3:
          jumpToLastChapter();
          hasEvent = true;
          break;
        case LogicalKeyboardKey.f4:
          jumpToNextChapter();
          hasEvent = true;
          break;
        case LogicalKeyboardKey.f5:
          hasEvent = true;
          final newAutoTurning = !state.runningAutoPageTurning;
          state = state.copyWith(
            runningAutoPageTurning: newAutoTurning,
            toolsVisible: newAutoTurning ? false : state.toolsVisible,
          );
          autoPageTurning();
          break;
      }
    }
    if (hasEvent) {
      _lastKeyboardTime = DateTime.now().millisecondsSinceEpoch;
    }
  }

  // ---- Auto page turning ----

  void stopAutoPageTurning() {
    state = state.copyWith(runningAutoPageTurning: false);
    _isAutoPageTurningPaused = false;
    _autoPageTurningTimer?.cancel();
    _autoPageTurningTimer = null;
    _wheelDebounceTimer?.cancel();
    _wheelDebounceTimer = null;
    _keyboardPageTurnDebounceTimer?.cancel();
    _keyboardPageTurnDebounceTimer = null;
    _isKeyboardPageTurning = false;
    if (state.readingMethod == ReadingMethod.topToBottomContinuously &&
        scrollController.hasClients) {
      scrollController.jumpTo(scrollController.position.pixels + 1);
    }
  }

  void pauseAutoPageTurning() {
    if (state.runningAutoPageTurning && !_isAutoPageTurningPaused) {
      _isAutoPageTurningPaused = true;
      if (state.readingMethod == ReadingMethod.topToBottomContinuously &&
          scrollController.hasClients) {
        scrollController.jumpTo(scrollController.position.pixels);
      }
    }
  }

  void wheelScroll() {
    if (!state.runningAutoPageTurning) return;

    _isWheelScrolling = true;
    pauseAutoPageTurning();

    _wheelDebounceTimer?.cancel();
    _wheelDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      _isWheelScrolling = false;
      resumeAutoPageTurning();
    });
  }

  void resumeAutoPageTurning() {
    if (state.runningAutoPageTurning &&
        _isAutoPageTurningPaused &&
        !userInteracting &&
        !_isWheelScrolling &&
        !_isKeyboardPageTurning) {
      _isAutoPageTurningPaused = false;
      autoPageTurning();
    }
  }

  Future<void> autoPageTurning() async {
    if (state.readingMethod == ReadingMethod.topToBottomContinuously) {
      if (!state.runningAutoPageTurning) {
        stopAutoPageTurning();
        return;
      }
      if (_isAutoPageTurningPaused) {
        return;
      }
      final pixels = scrollController.position.pixels;
      final maxScrollExtent = scrollController.position.maxScrollExtent;
      Log.d('ReadingLogic autoPageTurning $pixels $maxScrollExtent');
      if (scrollController.position.pixels >=
          scrollController.position.maxScrollExtent) {
        stopAutoPageTurning();
        return;
      }
      await jumpToNextPage(animate: true);
      if (state.runningAutoPageTurning) {
        autoPageTurning();
      }
      return;
    }
    if (state.currentPage == state.urls.length - 1) {
      stopAutoPageTurning();
      return;
    }
    int sec = int.parse(appdata.settings[33]);
    _autoPageTurningTimer?.cancel();
    if (state.runningAutoPageTurning) {
      _autoPageTurningTimer = Timer.periodic(Duration(seconds: sec), (timer) {
        if (!state.runningAutoPageTurning) {
          timer.cancel();
          return;
        }
        jumpToNextPage();
      });
    }
  }

  // ---- Refresh ----

  void refresh_() {
    pageController = PageController(initialPage: 1);
    itemScrollController = ItemScrollController();
    itemScrollListener = ItemPositionsListener.create();
    scrollController = ScrollController(keepScrollOffset: true);
    clearPhotoViewControllers();
    state = ReaderPageState(
      isLoading: true,
      currentPage: 1,
      currentEpisode: state.currentEpisode,
      readingMethod: state.readingMethod,
    );
  }

  // ---- Load info ----

  Future<void> loadInfo() async {
    state = state.copyWith(urls: []);
    await for (var res in readingData.loadEp(state.currentEpisode)) {
      if (res.error) {
        if (state.urls.isEmpty) {
          state = state.copyWith(errorMessage: res.errorMessage);
        }
      } else {
        state = state.copyWith(urls: res.data);
      }
      state = state.copyWith(isLoading: false);
    }
    loadImageSizes();
    if (isAutoFullscreenAndScroll) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (isDispose) return;
      fullscreen();
      state = state.copyWith(
        runningAutoPageTurning: true,
        toolsVisible: false,
      );
      autoPageTurning();
    }
  }

  // ---- Favorite current image ----

  Future<void> favoriteCurrentImage({Offset? position}) async {
    try {
      final readingData = this.readingData;
      final id = "${readingData.sourceKey}-${readingData.id}";
      int? pageIndex = state.currentPage - 1;
      final method = state.readingMethod;
      if (method == ReadingMethod.topToBottomContinuously) {
        if (position != null) {
          pageIndex = _getImageIndexAtPosition(position);
        } else {
          var items = itemScrollListener.itemPositions.value.toList();
          if (items.length == 1) {
            pageIndex = items[0].index;
          } else {
            isShowSelectImage = true;
            int? res;
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
              },
            );
            isShowSelectImage = false;
            if (res == null) return;
            pageIndex = res;
          }
        }
      } else if (method.isTwoPage && position != null) {
        final screenWidth =
            MediaQuery.of(App.globalContext!).size.width;
        final leftPageIndex = state.currentPage - 1;
        final rightPageIndex = leftPageIndex + 1;
        if (position.dx < screenWidth / 2) {
          pageIndex = leftPageIndex;
        } else {
          pageIndex = rightPageIndex < state.urls.length
              ? rightPageIndex
              : leftPageIndex;
        }
      }
      if (pageIndex == null || pageIndex >= state.urls.length) return;

      File? file;
      try {
        final stream = readingData.loadImage(
            state.currentEpisode, pageIndex, state.urls[pageIndex]);
        await for (var event in stream) {
          if (event.finished) {
            file = event.getFile();
            break;
          }
        }
      } catch (_) {
        showToast(message: "加载图片失败".tl);
        return;
      }
      if (file == null) {
        showToast(message: "加载图片失败".tl);
        return;
      }

      var image = await persistentCurrentImage(file);
      image = image.split("/").last;

      var otherInfo = <String, dynamic>{};
      if (readingData.type == ReadingType.ehentai) {
        otherInfo["gallery"] =
            (readingData as EhReadingData).gallery.toJson();
      } else if (readingData.type == ReadingType.hitomi) {
        otherInfo["hitomi"] = (readingData as HitomiReadingData)
            .images
            .map((e) => e.toMap())
            .toList();
        otherInfo["galleryId"] = readingData.id;
      } else if (readingData.type == ReadingType.jm) {
        Log.d("TooBar ${readingData.eps}, ${state.currentEpisode}");
        otherInfo["jmEpNames"] = readingData.eps!.values.toList();
        otherInfo["epsId"] =
            readingData.eps!.keys.getOrNull(state.currentEpisode - 1);
        otherInfo["bookId"] = readingData.id;
      } else if (readingData.type != ComicType.other) {
        otherInfo["eps"] = readingData.eps?.keys.toList() ?? [];
      } else {
        otherInfo["eps"] = readingData.eps;
      }
      otherInfo["url"] = state.urls[pageIndex];

      var favorite = ImageFavorite(
        id,
        image,
        readingData.title,
        state.currentEpisode,
        pageIndex + 1,
        otherInfo,
      );
      if (!(await ImageFavoriteManager.exist(
          id, state.currentEpisode, pageIndex + 1))) {
        ImageFavoriteManager.add(favorite);
        showToast(message: "已添加至图片收藏".tl);
      } else {
        ImageFavoriteManager.delete(favorite);
        showToast(message: "已取消图片收藏".tl);
      }
      showToast(message: "成功收藏图片".tl);
    } catch (e, s) {
      Log.e('TooBar $e', stackTrace: s);
      showToast(message: e.toString());
    }
  }

  int? _getImageIndexAtPosition(Offset position) {
    final items = itemScrollListener.itemPositions.value.toList();
    if (items.isEmpty) return null;
    if (items.length == 1) return items[0].index;

    final size = MediaQuery.of(App.globalContext!).size;
    final padding = MediaQuery.of(App.globalContext!).padding;
    final availableHeight = size.height - padding.top - padding.bottom;
    final topOffset = padding.top;
    final fractionY = (position.dy - topOffset) / availableHeight;

    for (final item in items) {
      if (fractionY >= item.itemLeadingEdge &&
          fractionY <= item.itemTrailingEdge) {
        return item.index;
      }
    }

    double minDist = double.infinity;
    int? closestIndex;
    for (final item in items) {
      final mid = (item.itemLeadingEdge + item.itemTrailingEdge) / 2;
      final dist = (fractionY - mid).abs();
      if (dist < minDist) {
        minDist = dist;
        closestIndex = item.index;
      }
    }
    return closestIndex;
  }
}
