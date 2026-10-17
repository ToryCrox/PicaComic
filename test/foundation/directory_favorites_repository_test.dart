import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/foundation/database/download_database.dart';
import 'package:pica_comic/foundation/directory_favorites_providers.dart';
import 'package:pica_comic/foundation/directory_favorites_repository.dart';
import 'package:pica_comic/foundation/local_history.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Directory root;
  late DownloadDatabase database;
  late DirectoryFavoritesRepository repository;
  late ProviderContainer container;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('pica_directory_favorite_');
    database = DownloadDatabase();
    await database.init(dbPath: '${root.path}/download.db');
    repository = DirectoryFavoritesRepository(database: database);
    container = ProviderContainer(
      overrides: [
        directoryFavoritesRepositoryProvider.overrideWithValue(repository),
      ],
    );
  });
  tearDown(() async {
    container.dispose();
    await repository.dispose();
    await database.close();
    await root.delete(recursive: true);
  });

  test('目录收藏添加取消与权重修改同步至卡片和列表', () async {
    final first = await Directory('${root.path}/first').create();
    final second = await Directory('${root.path}/second').create();
    final entry = directoryFavoriteProvider(first.path);
    container.listen(entry, (_, __) {});
    container.listen(directoryFavoritesProvider, (_, __) {});
    expect(await container.read(entry.future), isNull);
    await repository.add(first.path, sortOrder: 1);
    await repository.add(second.path, sortOrder: 2);
    await Future<void>.delayed(Duration.zero);
    await container.pump();
    expect((await container.read(entry.future))?.sortOrder, 1);
    expect(
      (await container.read(
        directoryFavoritesProvider.future,
      )).map((e) => e.path),
      [second.path, first.path],
    );
    await repository.reorder(first.path, 3);
    await Future<void>.delayed(Duration.zero);
    await container.pump();
    expect(
      (await container.read(directoryFavoritesProvider.future)).first.path,
      first.path,
    );
    await repository.remove(first.path);
    await Future<void>.delayed(Duration.zero);
    await container.pump();
    expect(await container.read(entry.future), isNull);
    expect(
      (await container.read(directoryFavoritesProvider.future)).single.path,
      second.path,
    );
  });

  test('收藏页隐藏失效目录，持久化收藏仍保留', () async {
    await repository.add('${root.path}/missing');
    container.listen(directoryFavoritesProvider, (_, __) {});
    expect(await container.read(directoryFavoritesProvider.future), isEmpty);
    expect(await repository.getAll(), hasLength(1));
  });

  test('本地历史清空真正删除数据库记录，并更新单条查询', () async {
    final history = LocalHistoryManager();
    history.bindDatabaseReady(() async {});
    final path = '${root.path}/comic';
    await history.saveReadHistory(
      LocalHistory(
        path: path,
        isReversed: 0,
        pageIndex: 5,
        time: 1,
        totalPages: 10,
      ),
    );
    expect((await history.find(path))?.pageIndex, 5);
    await history.clearHistory();
    expect(await history.find(path), isNull);
    expect(await history.getAll(), isEmpty);
  });
}
