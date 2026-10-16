import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/components/window_frame.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/foundation/app_settings_provider.dart';
import 'package:pica_comic/foundation/image_manager.dart';
import 'package:pica_comic/foundation/local_favorites.dart';
import 'package:pica_comic/foundation/local_history.dart';
import 'package:pica_comic/network/download/download_manager.dart';
import 'package:pica_comic/network/res.dart';
import 'package:pica_comic/pages/reader/comic_reader_page.dart';
import 'package:pica_comic/pages/reader/reader_logic.dart';
import 'package:pica_comic/pages/reader/reading_data.dart';
import 'package:pica_comic/pages/reader/reading_type.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const wakelockChannel =
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle';
  final platformCalls = <MethodCall>[];
  late LocalFavoritesManager? previousFavorites;
  late _ReaderFavorites favorites;
  late _ReaderWindowFrame windowFrame;

  setUp(() {
    previousFavorites = LocalFavoritesManager.cache;
    favorites = _ReaderFavorites();
    LocalFavoritesManager.cache = favorites;
    windowFrame = _ReaderWindowFrame();
    StateController.put<WindowFrameController>(windowFrame);
    platformCalls.clear();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        platformCalls.add(call);
        return null;
      },
    );
    binding.defaultBinaryMessenger.setMockMessageHandler(
      wakelockChannel,
      (_) async => const StandardMessageCodec().encodeMessage([null]),
    );
  });

  tearDown(() {
    LocalFavoritesManager.cache = previousFavorites;
    windowFrame.dispose();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
    binding.defaultBinaryMessenger.setMockMessageHandler(wakelockChannel, null);
  });

  for (final orientation in ['0', '1', '2']) {
    testWidgets('屏幕方向 $orientation 下退出阅读页安全释放资源并读取最新设置', (tester) async {
      final values = {
        ...defaultAppSettings,
        AppSettingKeys.readerOrientation: orientation,
        AppSettingKeys.readerDarkBackground: '0',
      };
      final repository = AppSettingsRepository(
        readValues: () => values,
        changes: const Stream.empty(),
        notifyChanges: () {},
      );
      final manager = _ReaderDownloadManager();
      final logic = ComicReaderLogic();
      final data = _PendingReadingData();
      final container = ProviderContainer(
        overrides: [
          appSettingsRepositoryProvider.overrideWithValue(repository),
          downloadManagerProvider.overrideWith(() => manager),
          comicReaderLogicProvider.overrideWith(() => logic),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: ComicReaderPage(
              readingData: data,
              initialPage: 1,
              initialEp: 1,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(tester.takeException(), isNull);

      // 不等待页面重建，确保卸载使用监听缓存的最新设置及下载状态。
      await container
          .read(appSettingsProvider.notifier)
          .setValue(AppSettingKeys.readerDarkBackground, '1', persist: false);
      manager.downloadingActive = orientation == '1';
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(logic.isDispose, isTrue);
      expect(manager.exitDownloadStates, [manager.downloadingActive]);
      expect(favorites.finishedIds, [data.favoriteId]);
      expect(windowFrame.resetCount, 1);
      expect(
        PaintingBinding.instance.imageCache.maximumSizeBytes,
        400 * 1024 * 1024,
      );
      expect(
        platformCalls
            .where(
              (call) => call.method == 'SystemChrome.setPreferredOrientations',
            )
            .last
            .arguments,
        DeviceOrientation.values.map((value) => value.toString()).toList(),
      );

      // 加载结果晚于退出时也不能继续更新已释放的阅读会话。
      data.chapters.add(const Res(['late-image']));
      final closed = data.chapters.close();
      await tester.pump();
      await closed;
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('本地漫画翻页后立即退出仍保存最新页码', (tester) async {
    final values = {...defaultAppSettings, AppSettingKeys.readingMode: '1'};
    final repository = AppSettingsRepository(
      readValues: () => values,
      changes: const Stream.empty(),
      notifyChanges: () {},
    );
    final logic = ComicReaderLogic();
    final data = _PendingLocalReadingData();
    final saved = <LocalHistory>[];
    final container = ProviderContainer(
      overrides: [
        appSettingsRepositoryProvider.overrideWithValue(repository),
        downloadManagerProvider.overrideWith(_ReaderDownloadManager.new),
        comicReaderLogicProvider.overrideWith(() => logic),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: ComicReaderPage(
            readingData: data,
            initialPage: 1,
            initialEp: 1,
          ),
        ),
      ),
    );
    logic.saveLocalHistoryOverride = (history) async => saved.add(history);
    data.chapters.add(const Res(['page-1', 'page-2', 'page-3']));
    await tester.idle();
    expect(logic.snapshot.urls.length, 3);
    logic.setCurrentPage(2);
    await container
        .read(appSettingsProvider.notifier)
        .setValue(AppSettingKeys.readerDarkBackground, '1', persist: false);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(logic.isDispose, isTrue);
    expect(saved, isNotEmpty);
    expect(saved.last.path, data.dirPath);
    expect(saved.last.pageIndex, 2);
    expect(saved.last.totalPages, 3);
    final closed = data.chapters.close();
    await tester.pump();
    await closed;
  });
}

/// 保持章节加载中，验证页面卸载和迟到响应的真实生命周期。
class _PendingReadingData extends ReadingData {
  final chapters = StreamController<Res<List<String>>>();

  @override
  String get id => 'reader-dispose-test';
  @override
  String get title => '退出阅读测试';
  @override
  String get downloadId => id;
  @override
  ReadingType get type => ReadingType.picacg;
  @override
  bool get hasEp => false;
  @override
  Map<String, String>? get eps => null;
  @override
  FavoriteType get favoriteType => FavoriteType.picacg;

  @override
  Stream<Res<List<String>>> loadEp(int ep, {bool markRead = true}) =>
      chapters.stream;

  @override
  Future<Res<List<String>>> loadEpNetwork(int ep) async => const Res([]);

  @override
  Stream<DownloadProgress> loadImageNetwork(int ep, int page, String url) =>
      const Stream.empty();
}

/// 提供可控的本地章节，不读取真实漫画目录。
class _PendingLocalReadingData extends LocalReadingData {
  _PendingLocalReadingData() : super('C:/reader-test/comic', '本地退出测试');

  final chapters = StreamController<Res<List<String>>>();

  @override
  Stream<Res<List<String>>> loadEp(int ep, {bool markRead = true}) =>
      chapters.stream;
}

/// 不启动真实下载服务，并记录退出时读取的即时下载状态。
class _ReaderDownloadManager extends DownloadManager {
  bool downloadingActive = false;
  final exitDownloadStates = <bool>[];

  @override
  DownloadQueueSnapshot build() => const DownloadQueueSnapshot(
    tasks: [],
    runningTaskIds: {},
    waitingTaskIds: {},
    isDownloading: false,
    hasError: false,
  );

  @override
  bool get isDownloading {
    exitDownloadStates.add(downloadingActive);
    return downloadingActive;
  }
}

/// 记录收藏阅读结束通知，避免访问用户数据库。
class _ReaderFavorites extends Fake implements LocalFavoritesManager {
  final finishedIds = <String>[];

  @override
  void onReadEnd(String target, FavoriteType type) => finishedIds.add(target);
}

/// 记录退出后的窗口主题恢复。
class _ReaderWindowFrame extends WindowFrameController {
  int resetCount = 0;

  @override
  void resetTheme() {
    resetCount++;
    super.resetTheme();
  }
}
