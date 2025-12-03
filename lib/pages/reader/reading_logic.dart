part of pica_reader;

extension PageControllerExtension on PageController {
  void animatedJumpToPage(int page) {
    final current = this.page?.round() ?? 0;
    if ((current - page).abs() > 1) {
      jumpToPage(page > current ? page - 1 : page + 1);
    }
    animateToPage(page,
        duration: const Duration(milliseconds: 300), curve: Curves.ease);
  }

  void jumpByDeviceType(int page) {
    if (StateController.find<ComicReadingPageLogic>().mouseScroll) {
      jumpToPage(page);
    } else {
      animatedJumpToPage(page);
    }
  }
}

class ComicReadingPageLogic extends StateController {
  ///控制页面, 用于非从上至下(连续)阅读方式
  late PageController pageController;

  ///用于从上至下(连续)阅读方式, 跳转至指定项目
  var itemScrollController = ItemScrollController();

  ///用于从上至下(连续)阅读方式, 获取当前滚动到的元素的序号
  var itemScrollListener = ItemPositionsListener.create();

  ///用于从上至下(连续)阅读方式, 控制滚动
  var scrollController = ScrollController(keepScrollOffset: true);

  ///用于从上至下(连续)阅读方式, 获取放缩大小
  PhotoViewController get photoViewController =>
      photoViewControllers[index] ?? photoViewControllers[0]!;

  var photoViewControllers = <int, PhotoViewController>{};

  ListenVolumeController? listenVolume;

  ScrollManager? scrollManager;

  String? errorMessage;

  void clearPhotoViewControllers() {
    photoViewControllers.forEach((key, value) => value.dispose());
    photoViewControllers.clear();
  }

  bool noScroll = false;

  bool mouseScroll = false;

  double currentScale = 1.0;

  bool get isCtrlPressed => HardwareKeyboard.instance.isControlPressed;

  List<bool> requestedLoadingItems = [];

  bool haveUsedInitialPage = false;

  bool restoreTopToBottomContinuouslyPage = false;

  /// 双页模式下是否在第一页时显示单页
  bool get singlePageForFirstScreen => appdata.implicitData[1] == '1';

  var focusNode = FocusNode();

  /// 正在选择图片
  bool _isShowSelectImage = false;

  bool get isShowSelectImage => _isShowSelectImage;

  set isShowSelectImage(bool show) {
    _isShowSelectImage = show;
    update();
  }

  /// 是否显示原图大小，默认是不限制宽度或者是本地模式时
  late bool _isShowOriginSize = appdata.settings[43] == '0' ||
      data is LocalReadingData ||
      data._isDownloaded;
  bool get isShowOriginSize => _isShowOriginSize;
  set isShowOriginSize(bool show) {
    _isShowOriginSize = show;
    update();
  }

  final Map<String, Size?> _imageSize = {};
  Map<String, Size?> get imageSize => _imageSize;
  final _hasComputeImageSizes = <String>{};

  List<StreamSubscription> _imageSizeSubscriptions = [];

  Future<void> loadImageSizes([int? fromIndex]) async {
    int startIndex = index - 1;
    if (startIndex < 0) {
      startIndex = 0;
    }
    if (fromIndex != null) {
      startIndex = fromIndex;
    }
    if (startIndex >= urls.length) {
      return;
    }

    final localImageUrls = urls
        .sublist(startIndex, min(startIndex + 5, urls.length))
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
      update();
    }));
    debugPrint("loadImageSizes finish");
  }

  // Future<void> loadImageSizes([int? fromIndex]) async {
  //   final localImageUrls = urls.where((e) => e.startsWith('file://')).toList();
  //   int startIndex = index - 1;
  //   if (startIndex < 0) {
  //     startIndex = 0;
  //   }
  //   if (fromIndex != null) {
  //     startIndex = fromIndex;
  //   }
  //   final requestedUrls = <String>[];
  //   if (startIndex > 0) {
  //     requestedUrls.addAll(localImageUrls);
  //   } else {
  //     requestedUrls.addAll(localImageUrls.sublist(startIndex));
  //     if (startIndex > 0) {
  //       requestedUrls.addAll(localImageUrls.sublist(0, startIndex));
  //     }
  //   }
  //   final resultUrs = requestedUrls.where((e) => !_imageSize.containsKey(e)).toList();
  //   if (resultUrs.isEmpty) {
  //     return;
  //   }
  //   debugPrint("loadImageSizes start $startIndex");
  //   _imageSizeSubscription = computeImageSizes(resultUrs).listen((e){
  //     for(var url in e.keys) {
  //       final sizeInfo = e[url]!;
  //       _imageSize[url] = sizeInfo.size;
  //     }
  //     update();
  //   });
  //   debugPrint("loadImageSizes finish");
  // }

  bool isDispose = false;

  void disposeAll() {
    _imageSizeSubscriptions.forEach((element) {
      element.cancel();
    });
    _imageSizeSubscriptions.clear();
    isDispose = true;
  }

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

  ComicReadingPageLogic(
      this.order, this.data, int initialPage, this.updateHistory,
      {this.isAutoFullscreenAndScroll = false}) {
    if (initialPage <= 0) {
      initialPage = 1;
    }
    pageController = PageController(initialPage: getPage(initialPage));
    _index = _getIndex(initialPage);
    order <= 0 ? order = 1 : order;
    itemScrollListener.itemPositions.addListener(() {
      var newIndex = itemScrollListener.itemPositions.value.first.index + 1;
      if (newIndex != index) {
        index = newIndex;
        update(["ToolBar"]);
      }
    });
  }

  final void Function() updateHistory;

  ReadingData data;

  bool isLoading = true;

  ///旋转方向: null-跟随系统, false-竖向, true-横向
  bool? rotation;

  ///是否应该显示悬浮按钮, 为-1表示显示上一章, 为0表示不显示, 为1表示显示下一章
  int showFloatingButtonValue = 0;

  double fABValue = 0;

  void showFloatingButton(int value) {
    if (value == 0) {
      if (showFloatingButtonValue != 0) {
        showFloatingButtonValue = 0;
        fABValue = 0;
        update();
      }
    }
    if (value == 1 && showFloatingButtonValue == 0) {
      showFloatingButtonValue = 1;
      update();
    } else if (value == -1 && showFloatingButtonValue == 0 && order != 1) {
      showFloatingButtonValue = -1;
      update();
    }
  }

  ///当前的页面, 0和最后一个为空白页, 用于进行章节跳转
  late int _index;

  ///当前的页面, 0和最后一个为空白页, 用于进行章节跳转
  int get index => _index;

  ///当前的页面, 0和最后一个为空白页, 用于进行章节跳转
  set index(int value) {
    _index = value;
    for (var element in _indexChangeCallbacks) {
      element(value);
    }
    updateHistory();
  }

  final _indexChangeCallbacks = <void Function(int)>[];

  void addIndexChangeCallback(void Function(int) callback) {
    _indexChangeCallbacks.add(callback);
  }

  void removeIndexChangeCallback(void Function(int) callback) {
    _indexChangeCallbacks.remove(callback);
  }

  ///当前的章节位置, 从1开始
  int order;

  ///工具栏是否打开
  bool tools = false;

  ///是否显示设置窗口
  bool showSettings = false;

  ///所有的图片链接
  var urls = <String>[];

  void reload() {
    index = 1;
    pageController = PageController(initialPage: 1);
    isLoading = true;
    update();
  }

  void change() {
    isLoading = !isLoading;
    update();
  }

  ReadingMethod get readingMethod =>
      ReadingMethod.values[int.parse(appdata.settings[9]) - 1];

  Size _pageSize = Size.zero;

  void updatePageSize(Size size) {
    _pageSize = size;
  }

  double get _animateNextPageDistance =>
      (_pageSize.height * 0.95).clamp(100, 2000);

  Future<void> jumpToNextPage(
      {bool animate = false, bool resetAutoTurning = false}) async {
    if (readingMethod.index < 3) {
      pageController.jumpToPage(index + 1);
      if (resetAutoTurning && runningAutoPageTurning) {
        autoPageTurning();
      }
    } else if (readingMethod == ReadingMethod.topToBottomContinuously) {
      // 键盘翻页时的处理
      if (resetAutoTurning && runningAutoPageTurning) {
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
        final duration =
            Duration(milliseconds: (distance / 600 * 1200 * (sec / 5)).toInt());
        await scrollController.animateTo(
            scrollController.position.pixels + distance,
            duration: duration,
            curve: Curves.linear);
      } else {
        print(
            "_animateNextPageDistance: $_animateNextPageDistance, height: ${_pageSize.height}");
        //scrollController.jumpTo(scrollController.position.pixels + 600);
        final duration = Duration(
            milliseconds: (300 / 600 * _animateNextPageDistance).toInt());
        await scrollController.animateTo(
            scrollController.position.pixels + _animateNextPageDistance,
            duration: duration,
            curve: Curves.decelerate);
      }

      // 键盘翻页后立即恢复自动滚动
      if (resetAutoTurning && runningAutoPageTurning) {
        _isKeyboardPageTurning = false;
        resumeAutoPageTurning();
      }
    } else {
      pageController.jumpToPage(pageController.page!.round() + 1);
    }
  }

  Future<void> jumpToLastPage({bool resetAutoTurning = false}) async {
    if (readingMethod.index < 3) {
      pageController.jumpToPage(index - 1);
      if (resetAutoTurning && runningAutoPageTurning) {
        autoPageTurning();
      }
    } else if (readingMethod == ReadingMethod.topToBottomContinuously) {
      // 键盘翻页时的处理
      if (resetAutoTurning && runningAutoPageTurning) {
        _isKeyboardPageTurning = true;
        pauseAutoPageTurning();
      }

      //scrollController.jumpTo(scrollController.position.pixels - 600);
      final duration = Duration(
          milliseconds: (300 / 600 * _animateNextPageDistance).toInt());
      await scrollController.animateTo(
          scrollController.position.pixels - _animateNextPageDistance,
          duration: duration,
          curve: Curves.decelerate);

      // 键盘翻页后立即恢复自动滚动
      if (resetAutoTurning && runningAutoPageTurning) {
        _isKeyboardPageTurning = false;
        resumeAutoPageTurning();
      }
    } else {
      pageController.jumpToPage(pageController.page!.round() - 1);
    }
  }

  void jumpToPage(int i, [bool updateWidget = false]) {
    i = i.clamp(1, length);
    if (readingMethod == ReadingMethod.topToBottomContinuously) {
      itemScrollController.jumpTo(index: i - 1);
    } else if (!readingMethod.isTwoPage) {
      pageController.jumpToPage(i);
    } else {
      var index = singlePageForFirstScreen ? i ~/ 2 + 1 : (i + 1) ~/ 2;
      pageController.jumpToPage(index);
    }
    if (index != i) {
      index = i;
    }
    if (updateWidget) {
      update(["ToolBar"]);
    }
  }

  void jumpByDeviceType(int page) {
    Future.microtask(() {
      if (mouseScroll) {
        pageController.jumpToPage(page);
      } else {
        pageController.animatedJumpToPage(page);
      }
    });
  }

  void jumpToNextChapter() {
    var eps = data.eps;
    showFloatingButtonValue = 0;
    if (!data.hasEp || order == eps?.length) {
      if (readingMethod != ReadingMethod.topToBottomContinuously) {
        if (readingMethod.index < 3) {
          jumpByDeviceType(urls.length);
        } else if (readingMethod == ReadingMethod.twoPage) {
          jumpByDeviceType((urls.length % 2 + urls.length) ~/ 2);
        }
      } else {
        jumpToPage(urls.length);
        index = urls.length;
        update(["ToolBar"]);
      }
      return;
    }
    order += 1;
    if (data is LocalReadingData) {
      (data as LocalReadingData).goNext();
    }
    urls = [];
    isLoading = true;
    tools = false;
    index = 1;
    pageController = PageController(initialPage: 1);
    clearPhotoViewControllers();
    update();
  }

  void jumpToChapter(int index) {
    order = index;
    if (data is LocalReadingData) {
      (data as LocalReadingData).goTo(index - 1);
    }
    urls = [];
    isLoading = true;
    tools = false;
    this.index = 1;
    pageController = PageController(initialPage: 1);
    clearPhotoViewControllers();
    update();
  }

  void jumpToLastChapter() {
    showFloatingButtonValue = 0;
    if (order == 1 || !data.hasEp) {
      if (readingMethod != ReadingMethod.topToBottomContinuously) {
        jumpByDeviceType(1);
      } else {
        jumpToPage(1);
        index = 1;
        update(["ToolBar"]);
      }
      return;
    }

    order -= 1;
    if (data is LocalReadingData) {
      (data as LocalReadingData).goPrev();
    }
    urls = [];
    isLoading = true;
    tools = false;
    pageController = PageController(initialPage: 1);
    index = 1;
    clearPhotoViewControllers();
    update();
  }

  ///当前章节的长度
  int get length => urls.length;

  /// 是否处于自动翻页状态
  bool runningAutoPageTurning = false;

  /// 是否暂停自动翻页
  ///
  /// 当用户进行交互(拖动/滚轮)时, 会临时暂停自动翻页
  bool _isAutoPageTurningPaused = false;

  /// 用户是否正在交互(按下鼠标/触摸)
  ///
  /// 用于判断是否应该恢复自动翻页
  bool userInteracting = false;

  /// 是否正在使用滚轮滚动
  ///
  /// 滚轮滚动时会触发多次事件, 使用此标志位配合定时器进行防抖
  bool _isWheelScrolling = false;

  /// 是否正在进行键盘翻页
  ///
  /// 键盘翻页时会触发动画, 使用此标志位配合定时器进行防抖
  bool _isKeyboardPageTurning = false;

  Timer? _autoPageTurningTimer;

  /// 滚轮防抖定时器
  Timer? _wheelDebounceTimer;

  /// 键盘翻页后恢复自动翻页的定时器
  Timer? _keyboardPageTurnDebounceTimer;

  void stopAutoPageTurning() {
    runningAutoPageTurning = false;
    _isAutoPageTurningPaused = false;
    _autoPageTurningTimer?.cancel();
    _autoPageTurningTimer = null;
    _wheelDebounceTimer?.cancel();
    _wheelDebounceTimer = null;
    _keyboardPageTurnDebounceTimer?.cancel();
    _keyboardPageTurnDebounceTimer = null;
    _isKeyboardPageTurning = false;
    if (readingMethod == ReadingMethod.topToBottomContinuously &&
        scrollController.hasClients) {
      scrollController.jumpTo(scrollController.position.pixels + 1);
    }
  }

  /// 暂停自动翻页
  ///
  /// 仅在自动翻页开启且未暂停时生效
  void pauseAutoPageTurning() {
    if (runningAutoPageTurning && !_isAutoPageTurningPaused) {
      _isAutoPageTurningPaused = true;
      if (readingMethod == ReadingMethod.topToBottomContinuously &&
          scrollController.hasClients) {
        // Stop current animation
        scrollController.jumpTo(scrollController.position.pixels);
      }
    }
  }

  /// 处理滚轮滚动
  ///
  /// 滚轮滚动时暂停自动翻页, 并设置300ms防抖, 停止滚动后恢复
  void wheelScroll() {
    if (!runningAutoPageTurning) return;

    _isWheelScrolling = true;
    pauseAutoPageTurning();

    _wheelDebounceTimer?.cancel();
    _wheelDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      _isWheelScrolling = false;
      resumeAutoPageTurning();
    });
  }

  /// 恢复自动翻页
  ///
  /// 仅在:
  /// 1. 自动翻页开启中
  /// 2. 当前处于暂停状态
  /// 3. 用户未在交互(未按下)
  /// 4. 未在滚轮滚动中
  /// 5. 未在键盘翻页中
  /// 时恢复
  void resumeAutoPageTurning() {
    if (runningAutoPageTurning &&
        _isAutoPageTurningPaused &&
        !userInteracting &&
        !_isWheelScrolling &&
        !_isKeyboardPageTurning) {
      _isAutoPageTurningPaused = false;
      autoPageTurning();
    }
  }

  Future<void> autoPageTurning() async {
    if (readingMethod == ReadingMethod.topToBottomContinuously) {
      if (!runningAutoPageTurning) {
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
      if (runningAutoPageTurning) {
        autoPageTurning();
      }
      return;
    }
    if (index == urls.length - 1) {
      stopAutoPageTurning();
      update();
      return;
    }
    int sec = int.parse(appdata.settings[33]);
    _autoPageTurningTimer?.cancel();
    if (runningAutoPageTurning) {
      _autoPageTurningTimer = Timer.periodic(Duration(seconds: sec), (timer) {
        if (!runningAutoPageTurning) {
          timer.cancel();
          return;
        }
        jumpToNextPage();
      });
    }
    // for (int i = 0; i < sec * 10; i++) {
    //   await Future.delayed(const Duration(milliseconds: 100));
    //   if (!runningAutoPageTurning) {
    //     return;
    //   }
    // }
    // jumpToNextPage();
    // autoPageTurning();
  }

  void refresh_() {
    pageController = PageController(initialPage: 1);
    itemScrollController = ItemScrollController();
    itemScrollListener = ItemPositionsListener.create();
    scrollController = ScrollController(keepScrollOffset: true);
    clearPhotoViewControllers();
    noScroll = false;
    currentScale = 1.0;
    showFloatingButtonValue = 0;
    index = 1;
    urls.clear();
    isLoading = true;
    tools = false;
    showSettings = false;
    update();
  }

  bool isFullScreen = false;

  void fullscreen() {
    // const channel = MethodChannel("pica_comic/full_screen");
    // channel.invokeMethod("set", !isFullScreen);
    WindowManager.instance.setFullScreen(!isFullScreen);
    isFullScreen = !isFullScreen;
    focusNode.requestFocus();

    if (isFullScreen) {
      StateController.find<WindowFrameController>().hideWindowFrame();
    } else {
      StateController.find<WindowFrameController>().showWindowFrame();
    }
  }

  int _lastKeyboardTime = 0;
  void handleKeyboard(KeyEvent event) {
    bool hasEvent = false;
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      Log.d('handleKeyboard key: ${event}');
      bool reverse = appdata.settings[9] == "2" || appdata.settings[9] == "6";
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
      Log.d('handleKeyboard key: ${event}');
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
          runningAutoPageTurning = !runningAutoPageTurning;
          autoPageTurning();
          if (runningAutoPageTurning) {
            tools = false;
          }
          update();
          break;
      }
    }
    if (hasEvent) {
      _lastKeyboardTime = DateTime.now().millisecondsSinceEpoch;
    }
  }

  late final void Function() openEpsView;

  final bool isAutoFullscreenAndScroll;
}
