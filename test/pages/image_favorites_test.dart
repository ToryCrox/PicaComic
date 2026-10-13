import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:pica_comic/foundation/app_settings_provider.dart';
import 'package:pica_comic/foundation/image_favorites.dart';
import 'package:pica_comic/foundation/image_favorites_providers.dart';
import 'package:pica_comic/foundation/image_favorites_repository.dart';
import 'package:pica_comic/pages/image_favorites.dart';
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
