import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/components/scrollable_list/src/item_positions_listener.dart';
import 'package:pica_comic/components/scrollable_list/src/item_positions_notifier.dart';
import 'package:pica_comic/components/scrollable_list/src/scrollable_positioned_list.dart';
import 'package:pica_comic/foundation/app_settings_provider.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/foundation/def.dart';
import 'package:pica_comic/foundation/history.dart';
import 'package:pica_comic/foundation/local_history.dart';
import 'package:pica_comic/foundation/image_manager.dart';
import 'package:pica_comic/foundation/image_favorites.dart';
import 'package:pica_comic/foundation/image_favorites_providers.dart';
import 'package:pica_comic/foundation/image_favorites_repository.dart';
import 'package:pica_comic/foundation/image_loader/stream_image_provider.dart';
import 'package:pica_comic/foundation/local_favorites.dart';
import 'package:pica_comic/network/res.dart';
import 'package:pica_comic/pages/reader/reader_logic.dart';
import 'package:pica_comic/pages/reader/image_view.dart';
import 'package:pica_comic/pages/reader/chapter_separator.dart';
import 'package:pica_comic/pages/reader/continuous_reader_data.dart';
import 'package:pica_comic/tools/translations.dart';
import 'package:pica_comic/pages/reader/reading_data.dart';
import 'package:pica_comic/pages/reader/reading_type.dart';
import 'package:pica_comic/pages/reader/touch_control.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(AppTranslation.init);

  testWidgets('右键菜单随收藏状态切换，取消操作固定命中的图片', (tester) async {
    final favorites = _ImageFavoritesRepository();
    final harness = _Harness(readingMode: '1', favorites: favorites);
    addTearDown(harness.dispose);
    addTearDown(TapController.detach);
    await harness.logic.loadInfo();
    TapController.attach(harness.logic, 'favorite-menu-test');
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: App.navigatorKey,
        home: const Scaffold(body: SizedBox.expand()),
      ),
    );
    Future<void> openMenu() async {
      unawaited(
        TapController.handleSecondaryTapUp(
          const PointerDownEvent(position: Offset(100, 100)),
        ),
      );
      await tester.pumpAndSettle();
    }

    await openMenu();
    expect(find.text('收藏图片'.tl), findsOneWidget);
    expect(find.text('取消收藏'.tl), findsNothing);
    App.navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();

    const favorite = ImageFavorite(
      sourceKey: 'picacg',
      comicId: 'test',
      title: 'test',
      ep: 2,
      page: 1,
      imagePath: '',
    );
    favorites.records[favorite.recordId] = favorite;
    await openMenu();
    expect(find.text('取消收藏'.tl), findsOneWidget);
    expect(find.byIcon(Icons.favorite), findsOneWidget);
    harness.logic.setCurrentPage(2);
    await tester.tap(find.text('取消收藏'.tl));
    await tester.pumpAndSettle();
    expect(favorites.records, isEmpty);
    // 取消后再次查看原图，菜单恢复为收藏。
    harness.logic.setCurrentPage(1);
    await openMenu();
    expect(find.text('收藏图片'.tl), findsOneWidget);
    expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    App.navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();

    harness.logic.setReadingMethod(ReadingMethod.twoPage);
    final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    expect(harness.logic.imageAtPosition(Offset.zero)!.page, 0);
    expect(harness.logic.imageAtPosition(Offset(width - 1, 0))!.page, 1);
    harness.logic.setCurrentPage(3);
    expect(harness.logic.imageAtPosition(Offset(width - 1, 0))!.page, 2);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpWidget(const SizedBox());
  });

  for (final mode in ['1', '4', '5']) {
    test('倒序目录在阅读模式 $mode 中正确手动翻章及识别首尾', () async {
      final harness = _Harness(readingMode: mode);
      addTearDown(harness.dispose);
      harness.data.chapterStep = -1;
      await harness.logic.loadInfo();
      harness.logic.jumpToNextChapter();
      await Future<void>.delayed(Duration.zero);
      expect(harness.logic.snapshot.currentEpisode, 1);
      expect(harness.logic.snapshot.currentPage, 1);
      await harness.logic.loadInfo();
      harness.logic.jumpToLastChapter();
      await Future<void>.delayed(Duration.zero);
      expect(harness.logic.snapshot.currentEpisode, 2);
      await harness.logic.loadInfo();
      harness.logic.jumpToLastChapter();
      await Future<void>.delayed(Duration.zero);
      expect(harness.logic.snapshot.currentEpisode, 3);
      await harness.logic.loadInfo();
      harness.logic.showFloatingButton(-1);
      expect(harness.logic.snapshot.showFloatingButtonValue, 0);
      if (harness.logic.continuousReading) {
        harness.logic.jumpToNextChapter();
        await Future<void>.delayed(Duration.zero);
        harness.logic.jumpToNextChapter();
        await Future<void>.delayed(Duration.zero);
        expect(harness.logic.snapshot.currentEpisode, 1);
        expect(harness.logic.waitForContinuousChapter(), isFalse);
      }
    });
  }

  test('默认开启，章节加载不标记已读，参考线经过图片才标记', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await harness.logic.loadInfo();
    expect(harness.logic.continuousReading, isTrue);
    expect(harness.data.markReadRequests, [false]);
    expect(harness.data.history!.readEpisode, isEmpty);
    final index = harness.logic.continuousPageIndex(2, 2);
    _positions(harness.logic, [
      ItemPosition(index: index, itemLeadingEdge: -0.2, itemTrailingEdge: 0.8),
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(harness.logic.snapshot.currentEpisode, 2);
    expect(harness.logic.snapshot.currentPage, 2);
    expect(harness.logic.length, 3);
    expect(harness.data.history!.readEpisode, {2});
    expect(harness.logic.imageAtListIndex(index)!.url, '2-1');
    expect(harness.logic.visibleImages.length, 1);
  });

  test('分隔条不修改阅读位置，不出现在图片选择中', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await harness.logic.loadInfo();
    harness.logic.setCurrentPage(3);
    harness.data.history!.readEpisode.clear();
    final header = harness.logic.snapshot.readingItems.indexWhere(
      (item) => !item.isImage && item.episode == 2,
    );
    _positions(harness.logic, [
      ItemPosition(index: header, itemLeadingEdge: 0, itemTrailingEdge: 1),
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(harness.logic.snapshot.currentPage, 3);
    expect(harness.logic.imageAtListIndex(header), isNull);
    expect(harness.logic.visibleImages, isEmpty);
    expect(harness.data.history!.readEpisode, isEmpty);
  });

  test('运行中关闭和开启开关保留当前章页码，不重新加载', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await harness.logic.loadInfo();
    harness.logic.setCurrentPage(2);
    final settings = harness.container.read(appSettingsProvider.notifier);
    await settings.setValue(
      AppSettingKeys.continuousChapterReading,
      '0',
      persist: false,
    );
    expect(harness.logic.continuousReading, isFalse);
    expect(harness.logic.snapshot.currentEpisode, 2);
    expect(harness.logic.snapshot.currentPage, 2);
    expect(harness.logic.snapshot.urls, ['2-0', '2-1', '2-2']);
    await settings.setValue(
      AppSettingKeys.continuousChapterReading,
      '1',
      persist: false,
    );
    expect(harness.logic.continuousReading, isTrue);
    expect(harness.logic.snapshot.currentPage, 2);
    expect(harness.logic.continuousPageIndex(2, 2), greaterThan(0));
    expect(harness.data.requestedEpisodes, [2]);
  });

  test('切换到分页及返回连续模式保留章内页码', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await harness.logic.loadInfo();
    harness.logic.setCurrentPage(3);
    harness.logic.setReadingMethod(ReadingMethod.twoPage);
    expect(harness.logic.continuousReading, isFalse);
    expect(harness.logic.snapshot.currentPage, 3);
    harness.logic.setReadingMethod(ReadingMethod.topToBottomContinuously);
    expect(harness.logic.continuousReading, isTrue);
    expect(harness.logic.snapshot.currentEpisode, 2);
    expect(harness.logic.snapshot.currentPage, 3);
    expect(harness.data.requestedEpisodes, [2]);
  });

  test('外部设置导入阅读模式时保留章节位置并同步会话', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await harness.logic.loadInfo();
    harness.logic.setCurrentPage(3);
    final settings = harness.container.read(appSettingsProvider.notifier);
    await settings.setValue(AppSettingKeys.readingMode, '2', persist: false);
    expect(harness.logic.snapshot.readingMethod, ReadingMethod.rightToLeft);
    expect(harness.logic.continuousReading, isFalse);
    expect(harness.logic.snapshot.currentEpisode, 2);
    expect(harness.logic.snapshot.currentPage, 3);
    await settings.setValue(AppSettingKeys.readingMode, '4', persist: false);
    expect(harness.logic.continuousReading, isTrue);
    expect(harness.logic.snapshot.currentPage, 3);
    expect(harness.data.requestedEpisodes, [2]);
  });

  test('初次加载期间关闭开关不会遗留加载锁或接收旧请求', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    final delayed = StreamController<Res<List<String>>>();
    harness.data.delayed[2] = delayed;
    final pending = harness.logic.loadInfo();
    await Future<void>.delayed(Duration.zero);
    harness.data.delayed.remove(2);
    await harness.container
        .read(appSettingsProvider.notifier)
        .setValue(AppSettingKeys.continuousChapterReading, '0', persist: false);
    await delayed.close();
    await pending;
    await Future<void>.delayed(Duration.zero);
    expect(harness.logic.snapshot.isLoading, isFalse);
    expect(harness.logic.continuousReading, isFalse);
    expect(harness.logic.snapshot.currentEpisode, 2);
    expect(harness.logic.snapshot.urls, ['2-0', '2-1', '2-2']);
  });

  test('快速手动切章丢弃旧结果，只发布最终目标章节', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await harness.logic.loadInfo();
    final old = StreamController<Res<List<String>>>();
    harness.data.delayed[3] = old;
    harness.logic.jumpToChapter(3);
    await Future<void>.delayed(Duration.zero);
    harness.logic.jumpToChapter(1);
    await Future<void>.delayed(Duration.zero);
    old.add(const Res(['late-chapter-3']));
    await old.close();
    await Future<void>.delayed(Duration.zero);
    expect(harness.logic.snapshot.currentEpisode, 1);
    expect(harness.logic.snapshot.currentPage, 1);
    expect(harness.logic.snapshot.urls, ['1-0', '1-1', '1-2']);
    expect(
      harness.logic.snapshot.readingItems
          .where((item) => item.isImage)
          .every((item) => item.episode == 1),
      isTrue,
    );
  });

  testWidgets('实际阅读视图双向跨章，分隔可见且图片操作使用目标章节', (tester) async {
    final harness = _Harness();
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      const Rect.fromLTWH(0, 0, 100, 100),
      Paint()..color = Colors.grey,
    );
    final picture = recorder.endRecording();
    final image = await tester.runAsync(() => picture.toImage(100, 100));
    picture.dispose();
    final bytes = await tester.runAsync(
      () => image!.toByteData(format: ui.ImageByteFormat.png),
    );
    image!.dispose();
    harness.data.imageProvider = MemoryImage(bytes!.buffer.asUint8List());
    await tester.runAsync(harness.logic.loadInfo);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: harness.container,
        child: MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(300, 400)),
            child: SizedBox(
              width: 300,
              height: 400,
              child: Consumer(
                builder: (context, ref, _) {
                  final state = ref.watch(harness.provider);
                  return Stack(
                    children: [
                      buildComicView(
                        state,
                        harness.logic,
                        context,
                        'test',
                        harness.data,
                        false,
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => precacheImage(
        harness.data.imageProvider!,
        tester.element(find.byType(Stack).first),
      ),
    );
    for (var frame = 0; frame < 12; frame++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
    expect(harness.data.history!.readEpisode, {2});
    // 桌面滚轮正常滚动即可进入下一章，无需在末尾额外拉动。
    for (
      var step = 0;
      step < 10 && harness.logic.snapshot.currentEpisode != 3;
      step++
    ) {
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(find.byType(Stack).first),
          kind: ui.PointerDeviceKind.mouse,
          scrollDelta: const Offset(0, 240),
        ),
      );
      await tester.pump();
      await tester.pump();
    }
    expect(harness.logic.snapshot.currentEpisode, 3);
    final next = harness.logic.continuousPageIndex(3, 1);
    expect(next, greaterThan(0));
    harness.logic.itemScrollController.jumpTo(index: next - 1);
    await tester.pump();
    await tester.pump();
    expect(find.byType(ChapterSeparator), findsWidgets);
    expect(
      harness.logic.imageIndexAtPosition(
        tester.getCenter(find.text('3 · 第三章')),
      ),
      isNull,
    );
    final hit = harness.logic.imageIndexAtPosition(
      tester.getCenter(find.byKey(const ValueKey('image:3:0'))),
    );
    expect(hit, isNotNull);
    expect(harness.logic.imageAtListIndex(hit!)!.episode, 3);
    expect(harness.logic.imageAtListIndex(hit)!.page, 0);
    final favoriteTarget = harness.logic.imageAtPosition(
      tester.getCenter(find.byKey(const ValueKey('image:3:0'))),
    );
    expect(favoriteTarget!.episode, 3);
    expect(favoriteTarget.page, 0);
    expect(
      harness.logic.imageAtPosition(tester.getCenter(find.text('3 · 第三章'))),
      isNull,
    );

    expect(harness.logic.snapshot.currentEpisode, 3);
    expect(harness.logic.snapshot.currentPage, 1);
    expect(harness.logic.length, 3);
    final visible = harness.logic.visibleImages.first;
    expect(harness.logic.imageAtListIndex(visible.index)!.episode, 3);
    expect(harness.logic.imageAtListIndex(visible.index)!.page, 0);
    final previous = harness.logic.continuousPageIndex(1, 3);
    expect(previous, greaterThan(0));
    harness.logic.itemScrollController.jumpTo(index: previous);
    await tester.pump();
    await tester.pump();
    expect(harness.logic.snapshot.currentEpisode, 1);
    expect(harness.logic.snapshot.currentPage, 3);
    expect(harness.data.history!.readEpisode, {1, 2, 3});
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    harness.dispose();
  });

  test('本地历史按实际阅读目录保存，预加载和未展示目录不创建记录', () async {
    final reading = _LocalReadingData();
    final values = {...defaultAppSettings, AppSettingKeys.readingMode: '4'};
    final container = ProviderContainer(
      overrides: [
        appSettingsRepositoryProvider.overrideWithValue(
          AppSettingsRepository(
            readValues: () => values,
            changes: const Stream.empty(),
          ),
        ),
      ],
    );
    ReaderSession.prepare('local-test', reading, 2, 1);
    final subscription = container.listen(
      comicReaderLogicProvider('local-test'),
      (_, _) {},
    );
    final logic = container.read(
      comicReaderLogicProvider('local-test').notifier,
    );
    final saved = <LocalHistory>[];
    logic.saveLocalHistoryOverride = (history) async => saved.add(history);
    addTearDown(() {
      subscription.close();
      container.dispose();
    });
    expect(logic.snapshot.currentEpisode, 2);
    await logic.loadInfo();
    logic.saveLocalReadingHistory();
    expect(saved, isEmpty);
    _positions(logic, [
      ItemPosition(
        index: logic.continuousPageIndex(2, 2),
        itemLeadingEdge: 0,
        itemTrailingEdge: 1,
      ),
    ]);
    await Future<void>.delayed(Duration.zero);
    logic.jumpToChapter(3);
    await Future<void>.delayed(Duration.zero);
    expect(saved.length, 1);
    expect(saved.single.path, 'C:/books/b');
    expect(saved.single.pageIndex, 2);
    expect(saved.single.isReversed, 1);
    expect(saved.single.totalPages, 3);
    logic.saveLocalReadingHistory();
    expect(saved.length, 1);
    _positions(logic, [
      ItemPosition(
        index: logic.continuousPageIndex(3, 3),
        itemLeadingEdge: -0.4,
        itemTrailingEdge: 0.6,
      ),
    ]);
    await Future<void>.delayed(Duration.zero);
    logic.saveLocalReadingHistory();
    expect(saved.last.path, 'C:/books/c');
    expect(saved.last.pageIndex, 3);
  });

  test('其他阅读模式不启用跨章列表，保留原章节加载行为', () async {
    final harness = _Harness(readingMode: '1');
    addTearDown(harness.dispose);
    await harness.logic.loadInfo();
    expect(harness.logic.continuousReading, isFalse);
    expect(harness.logic.snapshot.readingItems, isEmpty);
    expect(harness.data.markReadRequests, [true]);
  });

  test('下载图片与在线章节混排时图片加载使用自身章节和章内索引', () async {
    final reading = _ReadingData();
    final data = ContinuousReaderData(
      episodeCount: 3,
      onChanged: () {},
      canPrepend: () => true,
      loadEpisode: (ep) async* {
        if (ep == 2) {
          yield const Res(['file://C:/downloads/chapter-2/1.png']);
        } else {
          yield const Res(['https://example.test/chapter-3/1.png']);
        }
      },
    );
    await data.load(2);
    await data.load(3);
    final images = data.items.where((item) => item.isImage).toList();
    final downloaded = images.first;
    final online = images.last;
    final localProvider = reading.createImageProvider(
      downloaded.episode,
      downloaded.page,
      downloaded.url,
    );
    expect(localProvider, isA<FileImage>());
    expect(
      reading.createImageProvider(online.episode, online.page, online.url),
      isA<StreamImageProvider>(),
    );
    final local = await reading
        .loadImage(downloaded.episode, downloaded.page, downloaded.url)
        .single;
    expect(
      local.getFile().path.replaceAll('\\', '/'),
      'C:/downloads/chapter-2/1.png',
    );
    await reading.loadImage(online.episode, online.page, online.url).toList();
    expect(reading.networkImageCalls, [
      (3, 0, 'https://example.test/chapter-3/1.png'),
    ]);
    data.dispose();
  });

  for (final fail in [false, true]) {
    testWidgets('自动滚动等待相邻章${fail ? '失败后停止并可重试' : '成功后继续直到整本结束'}', (
      tester,
    ) async {
      final harness = _Harness();
      final stream = StreamController<Res<List<String>>>();
      harness.data.delayed[3] = stream;
      await tester.runAsync(harness.logic.loadInfo);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: harness.container,
          child: MaterialApp(
            home: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 300,
                height: 400,
                child: Consumer(
                  builder: (_, ref, _) {
                    final state = ref.watch(harness.provider);
                    final items = state.readingItems;
                    return ScrollablePositionedList.builder(
                      scrollController: harness.logic.scrollController,
                      itemScrollController: harness.logic.itemScrollController,
                      itemPositionsListener: harness.logic.itemScrollListener,
                      initialScrollIndex: harness.logic.continuousPageIndex(
                        2,
                        1,
                      ),
                      itemCount: items.length,
                      itemKeyBuilder: (i) => items[i].identity,
                      maintainVisibleContentPosition: true,
                      itemBuilder: (_, _) => const SizedBox(height: 200),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final scroll = harness.logic.scrollController;
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pump();
      harness.logic.startAutoPageTurning();
      await tester.pump();
      expect(harness.logic.snapshot.runningAutoPageTurning, isTrue);
      final boundary = scroll.offset;
      await tester.pump(const Duration(seconds: 1));
      expect(scroll.offset, closeTo(boundary, 1));
      stream.add(
        fail ? const Res.error('offline') : const Res(['3-0', '3-1', '3-2']),
      );
      await tester.runAsync(stream.close);
      await tester.pump();
      await tester.pump();
      if (fail) {
        expect(harness.logic.snapshot.runningAutoPageTurning, isFalse);
        expect(harness.data.history!.readEpisode.contains(3), isFalse);
        harness.data.delayed.remove(3);
        var completed = false;
        final retry = harness.logic
            .retryContinuousChapter(3)
            .whenComplete(() => completed = true);
        for (var step = 0; step < 20 && !completed; step++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(completed, isTrue);
        await retry;
        await tester.pump();
        expect(
          harness.logic.snapshot.readingItems
              .where((item) => item.isImage && item.episode == 3)
              .length,
          3,
        );
      } else {
        for (
          var step = 0;
          step < 10 && harness.logic.snapshot.runningAutoPageTurning;
          step++
        ) {
          await tester.pump(const Duration(seconds: 2));
        }
        expect(harness.logic.snapshot.currentEpisode, 3);
        expect(harness.logic.snapshot.runningAutoPageTurning, isFalse);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      harness.dispose();
    });
  }
}

/// 使用内存设置及伪章节，不连接真实网络或用户历史数据库。
class _Harness {
  _Harness({String readingMode = '4', ImageFavoritesRepository? favorites}) {
    final values = {
      ...defaultAppSettings,
      AppSettingKeys.readingMode: readingMode,
    };
    final repository = AppSettingsRepository(
      readValues: () => values,
      changes: const Stream.empty(),
      notifyChanges: () {},
    );
    container = ProviderContainer(
      overrides: [
        appSettingsRepositoryProvider.overrideWithValue(repository),
        if (favorites != null)
          imageFavoritesRepositoryProvider.overrideWithValue(favorites),
      ],
    );
    final session = 'test-${DateTime.now().microsecondsSinceEpoch}';
    ReaderSession.prepare(session, data, 1, 2);
    provider = comicReaderLogicProvider(session);
    subscription = container.listen(provider, (_, _) {});
    logic = container.read(comicReaderLogicProvider(session).notifier);
  }

  final data = _ReadingData();
  late final ProviderContainer container;
  late final ProviderSubscription<ReaderPageState> subscription;
  late final ComicReaderLogic logic;
  late final ComicReaderLogicProvider provider;

  void dispose() {
    logic.disposeAll();
    logic.clearPhotoViewControllers();
    subscription.close();
    container.dispose();
  }
}

/// 在内存中模拟收藏增删，避免菜单回归测试访问真实下载目录。
class _ImageFavoritesRepository extends Fake
    implements ImageFavoritesRepository {
  final records = <String, ImageFavorite>{};

  @override
  Stream<void> get changes => const Stream.empty();

  @override
  Future<List<ImageFavorite>> getAll() async => records.values.toList();

  @override
  Future<ImageFavorite?> find(String recordId) async => records[recordId];

  @override
  Future<void> delete(String recordId) async {
    records.remove(recordId);
  }
}

/// 将可见条目交给实际会话监听，验证章节与章内页码映射。
void _positions(ComicReaderLogic logic, List<ItemPosition> positions) {
  (logic.itemScrollListener as ItemPositionsNotifier).itemPositions.value =
      positions;
}

/// 可控加载顺序的漫画数据，记录是否要求标记已读。
class _ReadingData extends ReadingData {
  _ReadingData() {
    history = History(
      HistoryType.picacg,
      DateTime.now(),
      'test',
      '',
      '',
      0,
      0,
      'test',
    );
  }

  ImageProvider? imageProvider;

  @override
  int chapterStep = 1;

  @override
  ImageProvider createImageProvider(int ep, int page, String url) =>
      imageProvider ?? super.createImageProvider(ep, page, url);

  final requestedEpisodes = <int>[];
  final networkImageCalls = <(int, int, String)>[];
  final markReadRequests = <bool>[];
  final delayed = <int, StreamController<Res<List<String>>>>{};

  @override
  String get id => 'test';
  @override
  String get title => 'test';
  @override
  String get downloadId => 'test';
  @override
  ComicType get type => ComicType.picacg;
  @override
  bool get hasEp => true;
  @override
  Map<String, String> get eps => {'a': '第一章', 'b': '第二章', 'c': '第三章'};
  @override
  FavoriteType get favoriteType => FavoriteType.picacg;

  @override
  Stream<Res<List<String>>> loadEp(int ep, {bool markRead = true}) async* {
    requestedEpisodes.add(ep);
    markReadRequests.add(markRead);
    if (markRead) history!.addReadEpisode(ep);
    if (delayed.containsKey(ep)) {
      yield* delayed[ep]!.stream;
    } else {
      yield Res(List.generate(3, (page) => '$ep-$page'));
    }
  }

  @override
  Future<Res<List<String>>> loadEpNetwork(int ep) async => const Res([]);
  @override
  Stream<DownloadProgress> loadImageNetwork(int ep, int page, String url) {
    networkImageCalls.add((ep, page, url));
    return const Stream.empty();
  }
}

/// 不访问真实目录的本地章节数据，用于验证路径与历史归属。
class _LocalReadingData extends LocalReadingData {
  _LocalReadingData()
    : super(
        'C:/books/b',
        'b',
        allDirPaths: ['C:/books/a', 'C:/books/b', 'C:/books/c'],
        isReversed: true,
      );

  @override
  Stream<Res<List<String>>> loadEp(int ep, {bool markRead = true}) async* {
    yield Res(List.generate(3, (page) => 'local-$ep-$page'));
  }
}
