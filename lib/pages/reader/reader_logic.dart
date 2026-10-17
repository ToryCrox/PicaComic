import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:photo_view/photo_view.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:window_manager/window_manager.dart';

import '../../components/scrollable_list/src/item_positions_listener.dart';
import '../../components/scrollable_list/src/scrollable_positioned_list.dart';
import '../../components/window_frame.dart';
import '../../foundation/app.dart';
import '../../foundation/app_settings_provider.dart';
import '../../foundation/log.dart';
import '../../foundation/state_controller.dart';
import '../../tools/image_size_getter.dart' as image_sizes;
import '../../tools/translations.dart';
import 'reading_data.dart';
import 'reading_type.dart';
import 'touch_control.dart';
import 'package:pica_comic/base.dart';
import '../../components/components.dart';
import '../../foundation/image_favorites.dart';
import '../../foundation/image_favorites_providers.dart';
import '../../foundation/local_history.dart';
import 'continuous_reader_data.dart';
import '../../tools/iterable_extension.dart';
import '../../tools/key_down_event.dart';

part 'reader_logic.g.dart';
part 'continuous_reader_logic.dart';

// ============================================================================
// ReaderPageState -- immutable UI state
// ============================================================================

class ReaderPageState {
  final bool isLoading;
  final String? errorMessage;
  final List<String> urls;
  final List<ReaderItem> readingItems;
  final bool continuousReading;
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
    this.readingItems = const [],
    this.continuousReading = false,
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
    List<ReaderItem>? readingItems,
    bool? continuousReading,
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
      readingItems: readingItems ?? this.readingItems,
      continuousReading: continuousReading ?? this.continuousReading,
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
        listEquals(readingItems, other.readingItems) &&
        continuousReading == other.continuousReading &&
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
    Object.hashAll(readingItems),
    continuousReading,
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
    String sessionId,
    ReadingData readingData,
    int initialPage,
    int initialEp,
  ) {
    _pendingParams[sessionId] = _ReaderInitParams(
      readingData,
      initialPage,
      initialEp,
    );
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
    animateToPage(
      page,
      duration: const Duration(milliseconds: 300),
      curve: Curves.ease,
    );
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
class ComicReaderLogic extends _$ComicReaderLogic with _ContinuousReaderLogic {
  // ---- Controllers (mutable, don't trigger rebuild) ----

  late PageController pageController;
  var itemScrollController = ItemScrollController();
  var itemScrollListener = ItemPositionsListener.create();
  var scrollController = ScrollController(keepScrollOffset: true);

  PhotoViewController get photoViewController =>
      photoViewControllers[state.currentPage] ?? photoViewControllers[0]!;

  var photoViewControllers = <int, PhotoViewController>{};
  final _retiredControllers = <ChangeNotifier>[];

  /// 在视图解绑旧控制器之后释放它。
  void retireController(ChangeNotifier controller) {
    _retiredControllers.add(controller);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_retiredControllers.remove(controller)) controller.dispose();
    });
  }

  /// 切换翻页控制器，避免章节切换累积旧控制器。
  void replacePageController(PageController controller) {
    retireController(pageController);
    pageController = controller;
  }

  void clearPhotoViewControllers() {
    photoViewControllers.forEach((key, value) => value.dispose());
    photoViewControllers.clear();
  }

  ListenVolumeController? listenVolume;
  ScrollManager? scrollManager;
  FocusNode focusNode = FocusNode();

  /// 当前连续视图的坐标投影，包含缩放和平移变换。
  BuildContext? readerViewportContext;

  // ---- Reading data (set once in build) ----
  late ReadingData readingData;

  // ---- Internal mutable state (don't trigger rebuild) ----

  final Map<String, Size?> _imageSize = {};
  Map<String, Size?> get imageSize => _imageSize;
  final _hasComputeImageSizes = <String>{};
  final List<StreamSubscription> _imageSizeSubscriptions = [];
  List<bool> requestedLoadingItems = [];
  final requestedImageKeys = <String>{};
  bool _loadingInfo = false;

  /// 供界面读取的会话快照，避免暴露 Notifier 的受保护 state。
  ReaderPageState get snapshot => state;
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

  /// 当前阅读会话读取最新的持久化阅读设置。
  ReaderSettingsState get readerSettings => ref.read(readerSettingsProvider);

  double get _animateNextPageDistance =>
      (_pageSize.height * 0.95).clamp(100, 2000);

  /// 当前章节的长度
  int get length => state.urls.length;

  static int _getIndex(int initPage, int readingMode) {
    if (readingMode == 5 || readingMode == 6) {
      return initPage % 2 == 1 ? initPage : initPage - 1;
    } else {
      return initPage;
    }
  }

  static int getPage(int initPage, {required int readingMode}) {
    if (readingMode == 5 || readingMode == 6) {
      return (initPage + 2) ~/ 2;
    } else {
      return initPage;
    }
  }

  // ---- Lifecycle ----

  @override
  ReaderPageState build(String sessionId) {
    final settings = readerSettings;
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
    if (readingData is LocalReadingData) order = readingData.initialEpisode;
    initializeContinuousReader(sessionId);
    pageController = PageController(
      initialPage: getPage(initialPage, readingMode: settings.readingMode),
    );

    final isShowOriginSize =
        !settings.limitImageWidth ||
        readingData is LocalReadingData ||
        readingData.isDownloaded;

    itemScrollListener.itemPositions.addListener(handleVisibleItems);

    return ReaderPageState(
      isLoading: true,
      currentPage: _getIndex(initialPage, settings.readingMode),
      currentEpisode: order,
      readingMethod: ReadingMethod.values[settings.readingMode - 1],
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

  void setCurrentPage(int page) {
    state = state.copyWith(currentPage: page);
    markCurrentEpisodeRead();
  }

  void setCurrentScale(double scale) =>
      state = state.copyWith(currentScale: scale);
  void setNoScroll(bool value) => state = state.copyWith(noScroll: value);
  void setFabValue(double value) => state = state.copyWith(fabValue: value);
  void hideSettings() => state = state.copyWith(showSettings: false);
  void setToolsVisible(bool value) =>
      state = state.copyWith(toolsVisible: value);
  void toggleTools() =>
      state = state.copyWith(toolsVisible: !state.toolsVisible);
  void setRotation(bool? value) => state = state.copyWith(rotation: value);
  void toggleShowOriginSize() =>
      state = state.copyWith(isShowOriginSize: !state.isShowOriginSize);

  /// 更新阅读模式，并在连续模式间保持当前位置。
  void setReadingMethod(ReadingMethod method) {
    if (state.readingMethod == method) return;
    readerViewportContext = null;
    final page = state.currentPage;
    if (state.runningAutoPageTurning) stopAutoPageTurning();
    replacePageController(
      PageController(initialPage: getPage(page, readingMode: method.index + 1)),
    );
    clearPhotoViewControllers();
    restoreTopToBottomContinuouslyPage = true;
    state = state.copyWith(readingMethod: method);
    syncContinuousMode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (isDispose || state.readingMethod != method) return;
      if (method == ReadingMethod.topToBottomContinuously) {
        if (itemScrollController.isAttached) jumpToPage(page);
      } else if (pageController.hasClients) {
        jumpToPage(page);
      }
    });
  }

  void hideToolsAndSettings() =>
      state = state.copyWith(toolsVisible: false, showSettings: false);

  void startAutoPageTurning() {
    state = state.copyWith(runningAutoPageTurning: true, toolsVisible: false);
    autoPageTurning();
  }

  /// 设置变化后刷新当前会话，保留页码、加载状态和控制器。
  void notifySettingsChanged() =>
      state = state.copyWith(rebuildCount: state.rebuildCount + 1);

  /// 通过统一设置入口切换图片宽度限制，并立即刷新当前阅读器。
  Future<void> toggleImageWidthLimit() async {
    final limited = readerSettings.limitImageWidth;
    await setImageWidthLimit(!limited);
  }

  /// 保存图片最大宽度设置并立即更新当前阅读会话。
  Future<void> setImageWidthLimit(bool limited) async {
    final saving = ref
        .read(appSettingsProvider.notifier)
        .setValue(AppSettingKeys.limitReaderImageWidth, limited ? '1' : '0');
    state = state.copyWith(
      isShowOriginSize:
          !limited ||
          readingData is LocalReadingData ||
          readingData.isDownloaded,
      rebuildCount: state.rebuildCount + 1,
    );
    try {
      await saving;
    } catch (error, stack) {
      Log.e('阅读设置保存失败', error: error, stackTrace: stack);
      showToast(message: '设置保存失败'.tl);
    }
  }

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
        readingData.adjacentEpisode(state.currentEpisode, -1) != null) {
      state = state.copyWith(showFloatingButtonValue: -1);
    }
  }

  void reload() {
    replacePageController(PageController(initialPage: 1));
    state = state.copyWith(currentPage: 1, isLoading: true);
  }

  void change() {
    state = state.copyWith(isLoading: !state.isLoading);
  }

  // ---- Navigation ----

  Future<void> jumpToNextPage({
    bool animate = false,
    bool resetAutoTurning = false,
  }) async {
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
          distance = (maxScrollExtent - scrollController.position.pixels).clamp(
            10,
            600,
          );
        }
        int sec = readerSettings.autoPageSeconds;
        final duration = Duration(
          milliseconds: (distance / 600 * 1200 * (sec / 5)).toInt(),
        );
        await scrollController.animateTo(
          scrollController.position.pixels + distance,
          duration: duration,
          curve: Curves.linear,
        );
      } else {
        final duration = Duration(
          milliseconds: (300 / 600 * _animateNextPageDistance).toInt(),
        );
        await scrollController.animateTo(
          scrollController.position.pixels + _animateNextPageDistance,
          duration: duration,
          curve: Curves.decelerate,
        );
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
        milliseconds: (300 / 600 * _animateNextPageDistance).toInt(),
      );
      await scrollController.animateTo(
        scrollController.position.pixels - _animateNextPageDistance,
        duration: duration,
        curve: Curves.decelerate,
      );

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
      final index = continuousReading
          ? continuousPageIndex(state.currentEpisode, i)
          : i - 1;
      if (index >= 0 && itemScrollController.isAttached) {
        itemScrollController.jumpTo(index: index);
      }
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
    final newOrder = readingData.adjacentEpisode(state.currentEpisode, 1);
    state = state.copyWith(showFloatingButtonValue: 0);
    if (newOrder == null) {
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
    if (continuousReading) {
      jumpContinuousChapter(newOrder);
      return;
    }
    saveLocalReadingHistory();
    _loadVersion++;
    _loadingInfo = false;
    final data = readingData;
    if (data is LocalReadingData) {
      data.goNext();
    }
    state = state.copyWith(
      urls: [],
      isLoading: true,
      toolsVisible: false,
      currentEpisode: newOrder,
      currentPage: 1,
    );
    replacePageController(PageController(initialPage: 1));
    clearPhotoViewControllers();
  }

  void jumpToChapter(int index) {
    if (continuousReading) {
      jumpContinuousChapter(index);
      return;
    }
    saveLocalReadingHistory();
    _loadVersion++;
    _loadingInfo = false;
    final data = readingData;
    if (data is LocalReadingData) {
      data.goTo(index - 1);
    }
    state = state.copyWith(
      urls: [],
      isLoading: true,
      toolsVisible: false,
      currentEpisode: index,
      currentPage: 1,
    );
    replacePageController(PageController(initialPage: 1));
    clearPhotoViewControllers();
  }

  void jumpToLastChapter() {
    final newOrder = readingData.adjacentEpisode(state.currentEpisode, -1);
    state = state.copyWith(showFloatingButtonValue: 0);
    if (newOrder == null) {
      final method = state.readingMethod;
      if (method != ReadingMethod.topToBottomContinuously) {
        jumpByDeviceType(1);
      } else {
        jumpToPage(1);
        state = state.copyWith(currentPage: 1);
      }
      return;
    }

    if (continuousReading) {
      jumpContinuousChapter(newOrder);
      return;
    }
    saveLocalReadingHistory();
    _loadVersion++;
    _loadingInfo = false;
    final data = readingData;
    if (data is LocalReadingData) {
      data.goPrev();
    }
    state = state.copyWith(
      urls: [],
      isLoading: true,
      toolsVisible: false,
      currentEpisode: newOrder,
      currentPage: 1,
    );
    replacePageController(PageController(initialPage: 1));
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

    await loadImageSizesForUrls(
      state.urls.sublist(startIndex, min(startIndex + 5, state.urls.length)),
    );
  }

  /// 读取指定图片尺寸，支持相邻章节的本地图片。
  Future<void> loadImageSizesForUrls(List<String> urls) async {
    if (isDispose) return;
    final localImageUrls = urls.where((e) => e.startsWith('file://')).toList();
    final needLoadUrls = localImageUrls
        .where((e) => !_hasComputeImageSizes.contains(e))
        .toList();
    if (needLoadUrls.isEmpty) {
      return;
    }
    _hasComputeImageSizes.addAll(needLoadUrls);

    debugPrint(
      "loadImageSizes ${needLoadUrls.map((e) => path.basename(e)).toList()}",
    );
    late final StreamSubscription<Map<String, image_sizes.ImageSizeInfo>>
    subscription;
    subscription = image_sizes
        .computeImageSizes(needLoadUrls)
        .listen(
          (result) {
            if (isDispose) return;
            for (final entry in result.entries) {
              _imageSize[entry.key] = entry.value.size;
            }
            state = state.copyWith(rebuildCount: state.rebuildCount + 1);
          },
          onError: (Object error, StackTrace stack) {
            _hasComputeImageSizes.removeAll(needLoadUrls);
            if (!isDispose)
              Log.e('读取阅读图片尺寸失败', error: error, stackTrace: stack);
          },
          onDone: () => _imageSizeSubscriptions.remove(subscription),
        );
    _imageSizeSubscriptions.add(subscription);
    debugPrint("loadImageSizes finish");
  }

  void disposeAll() {
    if (isDispose) return;
    isDispose = true;
    cancelTimers();
    disposeContinuousReader();
    itemScrollListener.itemPositions.removeListener(handleVisibleItems);
    pageController.dispose();
    scrollController.dispose();
    focusNode.dispose();
    readerViewportContext = null;
    for (final controller in _retiredControllers) {
      controller.dispose();
    }
    _retiredControllers.clear();
    _imageSize.clear();
    _hasComputeImageSizes.clear();
    requestedImageKeys.clear();
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
      final readingMode = readerSettings.readingMode;
      final reverse = readingMode == 2 || readingMode == 6;
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
    cancelTimers();
    _isKeyboardPageTurning = false;
    if (state.readingMethod == ReadingMethod.topToBottomContinuously &&
        scrollController.hasClients) {
      // Defer to next frame to avoid triggering re-entrant
      // ScrollEndNotification while the handler is still running.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scrollController.hasClients) {
          scrollController.jumpTo(scrollController.position.pixels + 1);
        }
      });
    }
  }

  /// Cancel all auto-page-turning timers without modifying [state].
  /// Safe to call during widget dispose.
  void cancelTimers() {
    _isAutoPageTurningPaused = true;
    _isKeyboardPageTurning = true;
    _autoPageTurningTimer?.cancel();
    _autoPageTurningTimer = null;
    _wheelDebounceTimer?.cancel();
    _wheelDebounceTimer = null;
    _keyboardPageTurnDebounceTimer?.cancel();
    _keyboardPageTurnDebounceTimer = null;
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
        if (continuousReading && waitForContinuousChapter()) return;
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
    final sec = readerSettings.autoPageSeconds;
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
    retireController(scrollController);
    itemScrollListener.itemPositions.removeListener(handleVisibleItems);
    readerViewIdentity = '$readerViewIdentity-refresh';
    disposeContinuousReader();
    _loadVersion++;
    _loadingInfo = false;
    requestedImageKeys.clear();
    replacePageController(PageController(initialPage: 1));
    itemScrollController = ItemScrollController();
    itemScrollListener = ItemPositionsListener.create();
    itemScrollListener.itemPositions.addListener(handleVisibleItems);
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

  /// 加载当前章，避免 build 重复发起同一请求。
  Future<void> loadInfo() async {
    if (_loadingInfo || isDispose) return;
    _loadingInfo = true;
    final episode = state.currentEpisode;
    final version = ++_loadVersion;
    try {
      if (wantsContinuousReading) {
        await loadContinuousInfo();
      } else {
        state = state.copyWith(urls: [], clearError: true);
        await for (var res in readingData.loadEp(episode)) {
          if (isDispose ||
              version != _loadVersion ||
              episode != state.currentEpisode) {
            return;
          }
          if (res.error) {
            if (state.urls.isEmpty) {
              state = state.copyWith(errorMessage: res.errorMessage);
            }
          } else {
            state = state.copyWith(
              urls: res.data,
              isShowOriginSize:
                  state.isShowOriginSize || readingData.isDownloaded,
            );
          }
          state = state.copyWith(isLoading: false);
        }
      }
      if (isDispose || version != _loadVersion) return;
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
    } catch (error, stack) {
      if (!isDispose && version == _loadVersion) {
        Log.e('加载阅读章节失败', error: error, stackTrace: stack);
        state = state.copyWith(
          isLoading: false,
          errorMessage: error.toString(),
        );
      }
    } finally {
      if (version == _loadVersion) _loadingInfo = false;
    }
  }

  // ---- Favorite current image ----

  /// 按实际阅读数据类型获取 EH 元数据，不使用强制转换。
  Map<String, dynamic> _galleryMetadata(ReadingData data) {
    if (data is EhReadingData) return data.gallery.toJson();
    throw StateError('阅读数据与漫画源不一致');
  }

  /// 按实际阅读数据类型获取 Hitomi 元数据。
  List<Map<String, dynamic>> _hitomiMetadata(ReadingData data) {
    if (data is HitomiReadingData) {
      return data.images.map((image) => image.toMap()).toList();
    }
    throw StateError('阅读数据与漫画源不一致');
  }

  bool _favoriteBusy = false;

  /// 根据右键位置定位图片，连续阅读保留实际章节，双页分别命中左右页。
  ReaderItem? imageAtPosition(Offset position) {
    final method = state.readingMethod;
    if (method == ReadingMethod.topToBottomContinuously) {
      final index = imageIndexAtPosition(position);
      return index == null ? null : imageAtListIndex(index);
    }
    var page = state.currentPage - 1;
    if (method.isTwoPage) {
      final width = MediaQuery.of(App.globalContext!).size.width;
      if (position.dx >= width / 2 && page + 1 < state.urls.length) {
        page++;
      }
    }
    if (page < 0 || page >= state.urls.length) return null;
    return ReaderItem.image(state.currentEpisode, page, state.urls[page]);
  }

  /// 共用收藏身份，保证菜单状态查询和收藏操作识别同一张图片。
  ImageFavorite _imageFavoriteDraft(ReaderItem image) {
    var comicId = readingData.idForEpisode(image.episode);
    if (readingData.type == ComicType.local) {
      comicId = sha256.convert(utf8.encode(comicId)).toString();
    }
    return ImageFavorite(
      sourceKey: readingData.sourceKey,
      comicId: comicId,
      title: readingData.titleForEpisode(image.episode),
      ep: image.episode,
      page: image.page + 1,
      imagePath: '',
      imageUrl: image.url,
    );
  }

  /// 每次打开菜单时查询持久化状态，避免收藏或取消后仍显示旧文案。
  Future<bool> isImageFavorited(ReaderItem image) async {
    final repository = ref.read(imageFavoritesRepositoryProvider);
    return await repository.find(_imageFavoriteDraft(image).recordId) != null;
  }

  /// 收藏或取消当前图片，操作成功后才通知用户。
  Future<void> favoriteCurrentImage({ReaderItem? image}) async {
    if (_favoriteBusy) return;
    _favoriteBusy = true;
    try {
      final readingData = this.readingData;

      var pageIndex = state.currentPage - 1;
      ReaderItem? pickedImage = image;
      final method = state.readingMethod;
      if (pickedImage == null &&
          method == ReadingMethod.topToBottomContinuously) {
        var items = visibleImages;
        if (items.isEmpty) return;
        final choices = {
          for (final item in items) item.index: imageAtListIndex(item.index),
        };
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
                            title: Text(imageLabel(item.index)),
                            onTap: () {
                              res = item.index;
                              pickedImage = choices[item.index];
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
          isShowSelectImage = false;
          final selectedIndex = res;
          if (selectedIndex == null) return;
          pageIndex = selectedIndex;
        }
      }
      ReaderItem? selected = pickedImage;
      if (selected == null && method == ReadingMethod.topToBottomContinuously) {
        selected = imageAtListIndex(pageIndex);
      } else if (selected == null &&
          pageIndex >= 0 &&
          pageIndex < state.urls.length) {
        selected = ReaderItem.image(
          state.currentEpisode,
          pageIndex,
          state.urls[pageIndex],
        );
      }
      if (selected == null) return;
      final episode = selected.episode;
      pageIndex = selected.page;
      final imageUrl = selected.url;
      final draft = _imageFavoriteDraft(selected);
      final repository = ref.read(imageFavoritesRepositoryProvider);
      final existing = await repository.find(draft.recordId);
      if (existing != null) {
        await ref
            .read(imageFavoritesProvider.notifier)
            .delete(existing.recordId);
        showToast(message: "已取消图片收藏".tl);
        return;
      }

      File? file;
      try {
        final stream = readingData.loadImage(episode, pageIndex, imageUrl);
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

      var otherInfo = <String, dynamic>{
        'hasEp': readingData.hasEp,
        'chapterName': readingData.eps?.values.elementAtOrNull(episode - 1),
        'chapterStep': readingData.chapterStep,
      };
      if (readingData.type == ReadingType.ehentai) {
        otherInfo["gallery"] = _galleryMetadata(readingData);
      } else if (readingData.type == ReadingType.hitomi) {
        otherInfo["hitomi"] = _hitomiMetadata(readingData);
        otherInfo["galleryId"] = readingData.id;
      } else if (readingData.type == ReadingType.jm) {
        Log.d("TooBar ${readingData.eps}, ${state.currentEpisode}");
        otherInfo["eps"] = readingData.eps!.keys.toList();
        otherInfo["jmEpNames"] = readingData.eps!.values.toList();
        otherInfo["epsId"] = readingData.eps!.keys.getOrNull(episode - 1);
        otherInfo["bookId"] = readingData.id;
      } else if (readingData.type == ComicType.manhuagui) {
        otherInfo['eps'] = readingData.eps;
        otherInfo['chapterGroups'] = readingData.chapterGroups
            .map((group) => group.toMap())
            .toList();
      } else if (readingData.type != ComicType.other &&
          readingData.type != ComicType.hiperdex) {
        otherInfo["eps"] = readingData.eps?.keys.toList() ?? [];
      } else {
        otherInfo["eps"] = readingData.eps;
      }
      final favorite = ImageFavorite(
        sourceKey: draft.sourceKey,
        comicId: draft.comicId,
        imagePath: '',
        title: draft.title,
        ep: episode,
        page: pageIndex + 1,
        imageUrl: imageUrl,
        otherInfo: otherInfo,
      );
      await ref
          .read(imageFavoritesProvider.notifier)
          .add(favorite, file, downloadId: readingData.downloadId);
      showToast(message: "已添加至图片收藏".tl);
    } catch (e, s) {
      Log.e('图片收藏失败：$e', stackTrace: s);
      showToast(message: "图片收藏操作失败".tl);
    } finally {
      _favoriteBusy = false;
    }
  }

  /// 将屏幕坐标映射到图片条目，连续阅读的章节分隔不参与命中。
  int? imageIndexAtPosition(Offset position) {
    final items = visibleImages;
    if (items.isEmpty) return null;
    if (!continuousReading && items.length == 1) return items[0].index;

    double fractionY;
    if (continuousReading) {
      if (!scrollController.hasClients) return null;
      final box = readerViewportContext?.findRenderObject();
      final local = box is RenderBox ? box.globalToLocal(position) : position;
      final height = scrollController.position.viewportDimension;
      if (height <= 0) return null;
      fractionY = local.dy / height;
    } else {
      final size = MediaQuery.of(App.globalContext!).size;
      final padding = MediaQuery.of(App.globalContext!).padding;
      final availableHeight = size.height - padding.top - padding.bottom;
      fractionY = (position.dy - padding.top) / availableHeight;
    }

    if (continuousReading) {
      for (final item in itemScrollListener.itemPositions.value) {
        if (fractionY >= item.itemLeadingEdge &&
            fractionY <= item.itemTrailingEdge) {
          return imageAtListIndex(item.index) == null ? null : item.index;
        }
      }
      return null;
    }

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
