part of 'reader_logic.dart';

/// 连续阅读的会话状态、位置映射和历史管理。
mixin _ContinuousReaderLogic on _$ComicReaderLogic {
  ComicReaderLogic get _reader => this as ComicReaderLogic;
  ContinuousReaderData? _continuousData;
  int _loadVersion = 0;
  bool _positionUpdatePending = false;
  bool _scrollEndPending = false;
  bool _waitingForChapter = false;
  int _scrollDirection = 1;
  final _visitedLocalEpisodes = <int>{};

  /// 测试可以替换持久化回调，生产环境使用本地历史仓库。
  @visibleForTesting
  Future<void> Function(LocalHistory)? saveLocalHistoryOverride;
  String readerViewIdentity = '';

  bool get continuousReading => state.continuousReading;
  bool get wantsContinuousReading =>
      state.readingMethod == ReadingMethod.topToBottomContinuously &&
      _reader.readerSettings.continuousChapterReading &&
      (_reader.readingData.eps?.isNotEmpty ?? false);

  /// 安装针对性设置监听，不重新构建阅读会话。
  void initializeContinuousReader(String sessionId) {
    readerViewIdentity = sessionId;
    ref.listen(
      readerSettingsProvider.select((s) => s.continuousChapterReading),
      (_, _) => syncContinuousMode(),
    );
    ref.listen(readerSettingsProvider.select((s) => s.readingMode), (_, mode) {
      if (!_reader.isDispose) {
        _reader.setReadingMethod(ReadingMethod.values[mode - 1]);
      }
    });
    ref.onDispose(() {
      _reader.disposeAll();
      _reader.clearPhotoViewControllers();
    });
  }

  /// 新列表会话保留当前章内容，旧请求失效。
  ContinuousReaderData _createContinuousData() {
    _continuousData?.dispose();
    late final ContinuousReaderData data;
    data = ContinuousReaderData(
      episodeCount: _reader.readingData.eps!.length,
      loadEpisode: (episode) =>
          _reader.readingData.loadEp(episode, markRead: false),
      canPrepend: () =>
          !_reader.userInteracting &&
          !_reader.isShowSelectImage &&
          (!_reader.scrollController.hasClients ||
              !_reader.scrollController.position.isScrollingNotifier.value),
      onChanged: () {
        if (!_reader.isDispose && identical(_continuousData, data)) {
          _publishContinuousData();
        }
      },
    );
    _continuousData = data;
    return data;
  }

  /// 发布不可变列表快照，当前章页码含义保持不变。
  void _publishContinuousData() {
    final data = _continuousData;
    if (data == null || !continuousReading) return;
    final chapter = data.chapters[state.currentEpisode];
    final items = data.items;
    if (!listEquals(
      state.readingItems.map((item) => item.identity).toList(),
      items.map((item) => item.identity).toList(),
    )) {
      _resetPositionListener();
    }
    state = state.copyWith(
      readingItems: items,
      urls: chapter?.urls,
      isLoading: chapter == null,
      isShowOriginSize:
          state.isShowOriginSize || _reader.readingData.isDownloaded,
      rebuildCount: state.rebuildCount + 1,
    );
    if (_waitingForChapter && chapter != null) {
      _resumeAfterChapterLoad();
    }
  }

  /// 列表索引变更后等待新布局报告，禁止用旧索引标记另一章已读。
  void _resetPositionListener() {
    _reader.itemScrollListener.itemPositions.removeListener(handleVisibleItems);
    _reader.itemScrollListener = ItemPositionsListener.create();
    _reader.itemScrollListener.itemPositions.addListener(handleVisibleItems);
  }

  /// 切换开关或阅读模式时保留章节与章内页码。
  void syncContinuousMode() {
    if (_reader.isDispose || wantsContinuousReading == continuousReading) {
      return;
    }
    _loadVersion++;
    _waitingForChapter = false;
    final page = state.currentPage;
    _resetPositionListener();
    if (state.isLoading || state.urls.isEmpty) {
      _continuousData?.dispose();
      _continuousData = null;
      _reader._loadingInfo = false;
      state = state.copyWith(
        continuousReading: wantsContinuousReading,
        readingItems: const [],
        isLoading: true,
        clearError: true,
      );
      unawaited(_reader.loadInfo());
      return;
    }
    if (wantsContinuousReading) {
      final data = _createContinuousData();
      data.seed(state.currentEpisode, state.urls);
      state = state.copyWith(
        continuousReading: true,
        readingItems: data.items,
        showFloatingButtonValue: 0,
        fabValue: 0,
      );
    } else {
      _continuousData?.dispose();
      _continuousData = null;
      state = state.copyWith(continuousReading: false, readingItems: const []);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_reader.isDispose &&
          _reader.itemScrollController.isAttached &&
          state.readingMethod == ReadingMethod.topToBottomContinuously) {
        _reader.jumpToPage(page);
      }
    });
  }

  /// 初次加载连续阅读，当前章优先。
  Future<void> loadContinuousInfo() async {
    final version = _loadVersion;
    final data = _createContinuousData();
    state = state.copyWith(continuousReading: true, readingItems: const []);
    await data.load(state.currentEpisode, priority: true);
    if (_reader.isDispose || version != _loadVersion) return;
    _publishContinuousData();
  }

  /// 可见图片的列表位置映射回真实章节、章内页码。
  ReaderItem? imageAtListIndex(int index) {
    if (continuousReading) {
      if (index < 0 || index >= state.readingItems.length) return null;
      final item = state.readingItems[index];
      return item.isImage ? item : null;
    }
    if (index < 0 || index >= state.urls.length) return null;
    return ReaderItem.image(state.currentEpisode, index, state.urls[index]);
  }

  /// 图片选择排除分隔条和加载边界，按屏幕顺序排列。
  List<ItemPosition> get visibleImages {
    final items = _reader.itemScrollListener.itemPositions.value
        .where(
          (item) =>
              item.itemTrailingEdge > 0 &&
              item.itemLeadingEdge < 1 &&
              imageAtListIndex(item.index) != null,
        )
        .toList();
    items.sort((a, b) => a.itemLeadingEdge.compareTo(b.itemLeadingEdge));
    return items;
  }

  /// 显示目标图片所属的章节和页码。
  String imageLabel(int index) {
    final item = imageAtListIndex(index);
    if (item == null) return '';
    if (!continuousReading) return '${item.page + 1}';
    return '${_reader.readingData.eps?.values.elementAtOrNull(item.episode - 1) ?? item.episode} · ${item.page + 1}';
  }

  /// 延迟到布局结束更新业务状态，防止重入 build。
  void handleVisibleItems() {
    if (_positionUpdatePending || _reader.isDispose) return;
    _positionUpdatePending = true;
    Future.microtask(() {
      _positionUpdatePending = false;
      if (_reader.isDispose) return;
      final images = visibleImages;
      if (images.isEmpty) return;
      var selected = images.first;
      var nearest = double.infinity;
      for (final image in images) {
        double distance = 0;
        if (image.itemLeadingEdge > 0.25) {
          distance = image.itemLeadingEdge - 0.25;
        } else if (image.itemTrailingEdge < 0.25) {
          distance = 0.25 - image.itemTrailingEdge;
        }
        if (distance < nearest) {
          nearest = distance;
          selected = image;
        }
      }
      final item = imageAtListIndex(selected.index)!;
      _setReadingPosition(item);
      if (continuousReading) {
        checkChapterBoundaries();
        _resumeAfterChapterLoad();
      }
    });
  }

  /// 实际进入章节时才更新历史和本地目录。
  void _setReadingPosition(ReaderItem item) {
    if (state.currentEpisode != item.episode) {
      saveLocalReadingHistory();
      if (_reader.readingData is LocalReadingData) {
        (_reader.readingData as LocalReadingData).goTo(item.episode - 1);
      }
    }
    if (state.currentEpisode != item.episode ||
        state.currentPage != item.page + 1) {
      final urls = _continuousData?.chapters[item.episode]?.urls ?? state.urls;
      state = state.copyWith(
        currentEpisode: item.episode,
        currentPage: item.page + 1,
        urls: urls,
      );
      _reader.notifyIndexChange(item.page + 1);
    }
    markCurrentEpisodeRead();
  }

  /// 只有实际展示的章节参与阅读记录，预加载不创建本地历史。
  void markCurrentEpisodeRead() {
    _reader.readingData.history?.addReadEpisode(state.currentEpisode);
    if (_reader.readingData is LocalReadingData) {
      _visitedLocalEpisodes.add(state.currentEpisode);
    }
  }

  /// 章内页码转换为连续列表索引。
  int continuousPageIndex(int episode, int page) =>
      state.readingItems.indexWhere(
        (item) =>
            item.isImage && item.episode == episode && item.page == page - 1,
      );

  /// 仅在两屏以内加载相邻章节，下一章先入队。
  void checkChapterBoundaries() {
    final data = _continuousData;
    if (data == null ||
        !continuousReading ||
        !_reader.scrollController.hasClients) {
      return;
    }
    final position = _reader.scrollController.position;
    final threshold = position.viewportDimension * 2;
    if (position.extentAfter <= threshold && data.canLoadNext) {
      unawaited(data.load(data.lastEpisode + 1));
    }
    if (position.extentBefore <= threshold && data.canLoadPrevious) {
      unawaited(data.load(data.firstEpisode - 1));
    }
  }

  /// 记录预加载方向并处理边界，滚动结束提交头部插入。
  void continuousScrollUpdate(double? delta) {
    if (delta != null && delta != 0) _scrollDirection = delta > 0 ? 1 : -1;
    checkChapterBoundaries();
  }

  void continuousScrollEnd() {
    if (_scrollEndPending || _reader.isDispose) return;
    _scrollEndPending = true;
    Future.microtask(() {
      _scrollEndPending = false;
      if (_reader.isDispose) return;
      _continuousData?.flushPrepend();
      checkChapterBoundaries();
      _resumeAfterChapterLoad();
    });
  }

  int get preloadDirection => _scrollDirection;

  /// 重试仅作用于指定章节。
  Future<void> retryContinuousChapter(int episode) async {
    await _continuousData?.load(episode, retry: true, priority: true);
    _resumeAfterChapterLoad();
  }

  /// 明确跳过异常章节并进入后续章节。
  void skipContinuousChapter(int episode, int direction) {
    unawaited(_continuousData?.skip(episode, direction) ?? Future.value());
  }

  /// 手动切章优先：失效旧列表请求，加载目标章节第一页。
  void jumpContinuousChapter(int episode) {
    saveLocalReadingHistory();
    _loadVersion++;
    _continuousData?.dispose();
    _continuousData = null;
    _waitingForChapter = false;
    if (_reader.readingData is LocalReadingData) {
      (_reader.readingData as LocalReadingData).goTo(episode - 1);
    }
    _reader.haveUsedInitialPage = true;
    state = state.copyWith(
      currentEpisode: episode,
      currentPage: 1,
      urls: const [],
      readingItems: const [],
      isLoading: true,
      toolsVisible: false,
      clearError: true,
    );
    _reader._loadingInfo = false;
    unawaited(_loadAndJumpContinuousChapter());
  }

  Future<void> _loadAndJumpContinuousChapter() async {
    final episode = state.currentEpisode;
    final loading = _reader.loadInfo();
    final version = _loadVersion;
    await loading;
    if (_reader.isDispose ||
        version != _loadVersion ||
        episode != state.currentEpisode)
      return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_reader.isDispose &&
          version == _loadVersion &&
          _reader.itemScrollController.isAttached) {
        final index = continuousPageIndex(state.currentEpisode, 1);
        _reader.itemScrollController.jumpTo(index: index < 0 ? 0 : index);
      }
    });
  }

  /// 自动滚动到列表末尾时等待相邻章，失败则停止。
  bool waitForContinuousChapter() {
    final data = _continuousData;
    if (data == null ||
        data.lastEpisode >= data.episodeCount ||
        !data.canLoadNext) {
      return false;
    }
    _waitingForChapter = true;
    unawaited(data.load(data.lastEpisode + 1));
    return true;
  }

  void _resumeAfterChapterLoad() {
    if (!_waitingForChapter || _reader.isDispose) return;
    final data = _continuousData;
    if (data == null) return;
    if (!data.canLoadNext) {
      _waitingForChapter = false;
      _reader.stopAutoPageTurning();
      return;
    }
    if (!_reader.scrollController.hasClients ||
        _reader.scrollController.position.extentAfter <= 0) {
      return;
    }
    _waitingForChapter = false;
    if (state.runningAutoPageTurning) unawaited(_reader.autoPageTurning());
  }

  /// 本地进度按目录保存，预加载目录不会创建记录。
  void saveLocalReadingHistory() {
    final reading = _reader.readingData;
    if (reading is! LocalReadingData ||
        state.urls.isEmpty ||
        !_visitedLocalEpisodes.contains(state.currentEpisode)) {
      return;
    }
    unawaited(
      (saveLocalHistoryOverride ?? LocalHistoryManager().saveReadHistory)(
        LocalHistory(
          path: reading.directoryForEpisode(state.currentEpisode),
          isReversed: reading.isReversed ? 1 : 0,
          pageIndex: state.currentPage,
          time: DateTime.now().millisecondsSinceEpoch,
          totalPages: state.urls.length,
        ),
      ).catchError((Object error, StackTrace stack) {
        Log.e('保存本地阅读进度失败', error: error, stackTrace: stack);
      }),
    );
  }

  /// 释放连续阅读请求并失效所有待执行操作。
  void disposeContinuousReader() {
    _loadVersion++;
    _continuousData?.dispose();
    _continuousData = null;
    _waitingForChapter = false;
  }
}
