import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:path/path.dart' as path;
import 'package:pica_comic/foundation/app_settings_provider.dart';
import 'package:pica_comic/foundation/image_favorites.dart';
import 'package:pica_comic/foundation/image_favorites_providers.dart';
import 'package:pica_comic/foundation/image_favorites_repository.dart';
import 'package:pica_comic/pages/image_favorites.dart';
import 'package:pica_comic/pages/local_image_viewer_page.dart';
import 'package:pica_comic/tools/translations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Directory temporary;
  late ImageFavoritesRepository repository;

  setUpAll(() async {
    await AppTranslation.init();
  });
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('pica_favorites_widget_');
    repository = ImageFavoritesRepository(
      rootPath: () => temporary.path,
      comicDirectory: (_) async => '',
      ensureReady: () async {},
    );
  });
  tearDown(() async {
    await repository.dispose();
    await temporary.delete(recursive: true);
  });

  /// 测试中隔离全局设置存储。
  AppSettingsRepository settings() => AppSettingsRepository(
    readValues: () => const {},
    changes: const Stream.empty(),
    notifyChanges: () {},
    saveSettings: (_) async {},
    saveData: (_) async {},
  );

  /// 建立包含同名不同来源作品和乱序页码的真实收藏。
  Future<(File, List<ImageFavorite>)> seed() async {
    final file = File(path.join(temporary.path, 'sample.png'));
    await file.writeAsBytes(image.encodePng(image.Image(width: 8, height: 8)));
    final records = <ImageFavorite>[];
    for (final (source, id, ep, page) in [
      ('test', 'a', 2, 10),
      ('test', 'b', 1, 3),
      ('test', 'a', 1, 2),
      ('other', 'a', 1, 4),
    ]) {
      records.add(
        await repository.add(
          ImageFavorite(
            sourceKey: source,
            comicId: id,
            title: '同名漫画',
            ep: ep,
            page: page,
            imagePath: '',
            otherInfo: {
              'hasEp': source == 'test',
              if (source == 'test') 'chapterName': '章节 $ep',
            },
          ),
          file,
        ),
      );
    }
    return (file, records);
  }

  /// 在挂载收藏页前完成磁盘和解码操作，避免测试时钟阻塞真实 I/O。
  Future<void> prepare(
    WidgetTester tester,
    ProviderContainer container,
    File file,
    List<ImageFavorite> records,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.runAsync(() async {
      final subscription = container.listen(
        filteredImageFavoritesProvider(''),
        (_, _) {},
      );
      addTearDown(subscription.close);
      await container.read(filteredImageFavoritesProvider('').future);
      final context = tester.element(find.byType(SizedBox).first);
      await precacheImage(FileImage(file), context);
      for (final record in records) {
        await precacheImage(
          FileImage(await repository.originalFile(record)),
          context,
        );
      }
    });
  }

  /// 交替推进真实磁盘回调和测试微任务，完成仓库访问及图片解码。
  Future<void> flushIO(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
  }

  testWidgets('卡片显示章节、排序切换，原图按当前列表快照跨作品切换', (tester) async {
    final (file, records) = (await tester.runAsync(seed))!;
    final container = ProviderContainer(
      overrides: [
        imageFavoritesRepositoryProvider.overrideWithValue(repository),
        appSettingsRepositoryProvider.overrideWithValue(settings()),
        for (final record in records)
          imageFavoriteThumbnailProvider(
            record,
          ).overrideWith((ref) async => file),
      ],
    );
    addTearDown(container.dispose);
    await prepare(tester, container, file, records);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ImageFavoritesPage()),
      ),
    );
    await tester.pumpAndSettle();
    List<String> tileIds() => tester
        .widgetList<FavoriteImageTile>(find.byType(FavoriteImageTile))
        .map((tile) => tile.image.recordId)
        .toList();
    final order = [records[3], records[2], records[0], records[1]];
    expect(tileIds(), order.map((record) => record.recordId));
    expect(
      find.text('章节 2 · ${'第 @page 页'.tlParams({'page': '10'})}'),
      findsOneWidget,
    );
    expect(find.text('第 @page 页'.tlParams({'page': '4'})), findsOneWidget);
    await tester.tap(find.byTooltip('切换为倒序'.tl));
    await tester.pumpAndSettle();
    expect(tileIds(), order.reversed.map((record) => record.recordId));
    await tester.tap(find.byIcon(Icons.grid_view));
    await tester.pumpAndSettle();
    expect(
      container
          .read(imageFavoriteGroupsProvider)
          .requireValue
          .map((record) => (record.sourceKey, record.comicId)),
      [('other', 'a'), ('test', 'a'), ('test', 'b')],
    );
    await tester.tap(find.byIcon(Icons.list));
    await tester.pumpAndSettle();
    expect(tileIds(), order.reversed.map((record) => record.recordId));
    final selected = find.byKey(ValueKey(records[0].recordId));
    await tester.tap(
      find.descendant(of: selected, matching: find.byTooltip('查看原图'.tl)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    final viewer = tester.widget<LocalImageViewerPage>(
      find.byType(LocalImageViewerPage),
    );
    expect(viewer.initialIndex, 1);
    expect(viewer.gallery.length, 4);
    expect(
      viewer.gallery[1].subtitle,
      '章节 2 · ${'第 @page 页'.tlParams({'page': '10'})}',
    );
    await flushIO(tester);
    await tester.runAsync(() async {
      await repository.delete(records[2].recordId);
    });
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    expect(find.text('读取图片失败'.tl), findsOneWidget);
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    await flushIO(tester);
    expect(
      find.descendant(
        of: find.byType(LocalImageViewerPage),
        matching: find.text('第 @page 页'.tlParams({'page': '4'})),
      ),
      findsOneWidget,
    );
    expect(viewer.gallery.length, 4);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('作品筛选隔离同名不同来源，原图图集只包含当前作品', (tester) async {
    final (file, records) = (await tester.runAsync(seed))!;
    final container = ProviderContainer(
      overrides: [
        imageFavoritesRepositoryProvider.overrideWithValue(repository),
        appSettingsRepositoryProvider.overrideWithValue(settings()),
        for (final record in records)
          imageFavoriteThumbnailProvider(
            record,
          ).overrideWith((ref) async => file),
      ],
    );
    addTearDown(container.dispose);
    await prepare(tester, container, file, records);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: ImageFavoritesPage(
            filterTitle: '同名漫画',
            filterSourceKey: 'test',
            filterComicId: 'a',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<FavoriteImageTile>(find.byType(FavoriteImageTile))
          .map((tile) => tile.image.recordId),
      [records[2].recordId, records[0].recordId],
    );
    await tester.tap(find.byTooltip('查看原图'.tl).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    final viewer = tester.widget<LocalImageViewerPage>(
      find.byType(LocalImageViewerPage),
    );
    expect(viewer.initialIndex, 0);
    expect(viewer.gallery.length, 2);
    expect(viewer.gallery.map((item) => item.subtitle), [
      '章节 1 · ${'第 @page 页'.tlParams({'page': '2'})}',
      '章节 2 · ${'第 @page 页'.tlParams({'page': '10'})}',
    ]);
    await flushIO(tester);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  test('Provider 自动刷新列表、标题和数量，删除后无需页面回调', () async {
    final container = ProviderContainer(
      overrides: [
        imageFavoritesRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    final count = container.listen(imageFavoriteCountProvider, (_, _) {});
    addTearDown(count.close);
    expect(await container.read(imageFavoriteCountProvider.future), 0);
    final source = File(path.join(temporary.path, 'original.jpg'));
    await source.writeAsBytes([1]);
    const draft = ImageFavorite(
      sourceKey: 'test',
      comicId: 'comic',
      title: '漫画',
      ep: 1,
      page: 1,
      imagePath: '',
    );
    final favorite = await repository.add(draft, source);
    await container.pump();
    expect(await container.read(imageFavoriteCountProvider.future), 1);
    expect(await container.read(imageFavoriteTitlesProvider.future), ['漫画']);
    expect(
      (await container.read(
        filteredImageFavoritesProvider('漫画').future,
      )).length,
      1,
    );
    await container
        .read(imageFavoritesProvider.notifier)
        .delete(favorite.recordId);
    await container.pump();
    expect(await container.read(imageFavoriteCountProvider.future), 0);
  });

  testWidgets('空列表与标题分组切换不丢失状态', (tester) async {
    final container = ProviderContainer(
      overrides: [
        imageFavoritesRepositoryProvider.overrideWithValue(repository),
        filteredImageFavoritesProvider('').overrideWith((ref) async => []),
        imageFavoriteTitlesProvider.overrideWith((ref) async => []),
        appSettingsRepositoryProvider.overrideWithValue(
          AppSettingsRepository(
            readValues: () => const {},
            changes: const Stream.empty(),
            notifyChanges: () {},
            saveSettings: (_) async {},
            saveData: (_) async {},
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.runAsync(() => container.read(imageFavoritesProvider.future));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ImageFavoritesPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('暂无图片收藏'.tl), findsOneWidget);
    expect(find.byType(Scaffold), findsOneWidget);
    await tester.tap(find.byIcon(Icons.grid_view));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.list), findsOneWidget);
    expect(find.text('暂无图片收藏'.tl), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
