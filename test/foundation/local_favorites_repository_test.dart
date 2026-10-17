import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/foundation/app_settings_repository.dart';
import 'package:pica_comic/foundation/local_favorites.dart';
import 'package:pica_comic/foundation/repository_change.dart';
import 'package:pica_comic/pages/favorites/local_favorites_providers.dart';
import 'package:pica_comic/pages/favorites/favorites_session.dart';
import 'package:pica_comic/network/comic_source_services.dart';
import 'package:pica_comic/comic_source/comic_source.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 创建测试作品，允许验证不同来源使用相同标识。
FavoriteItem item(String target, {int type = 0, String? name}) => FavoriteItem(
  target: target,
  name: name ?? target,
  coverPath: 'https://example.com/$target.jpg',
  author: '',
  type: FavoriteType(type),
  tags: const ['测试'],
);

/// 使用内存保存导航，测试不写入用户设置。
class _Navigation extends FavoritesNavigationStore {
  String value = '1;;';
  @override
  String read() => value;
  @override
  Future<void> write(FavoritesSessionState state) async {
    value =
        '${state.selectingFolder ? 1 : 0};${state.isNetwork == true ? 1 : 0};${state.current ?? ''}';
  }
}

/// 避免会话测试初始化真实漫画源和账户。
class _Registry extends ComicSourceRegistry {
  @override
  Future<List<ComicSource>> build() async => const [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Database db;
  late LocalFavoritesManager repository;
  late ProviderContainer container;
  late StreamSubscription<RepositoryChange<FavoriteIdentity>> subscription;
  late List<RepositoryChange<FavoriteIdentity>> events;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute(
      'CREATE TABLE $kTableFolderSync ($kFolderSyncName TEXT PRIMARY KEY, '
      '$kFolderSyncTime TEXT, $kFolderSyncKey TEXT, $kFolderSyncData TEXT)',
    );
    await db.execute(
      'CREATE TABLE $kTableFolderOrder ($kFolderOrderName TEXT PRIMARY KEY, $kFolderOrderValue INT)',
    );
    repository = LocalFavoritesManager.forTesting(
      db,
      settings: AppSettingsRepository(
        readValues: () => {
          AppSettingKeys.localFavoriteInsertPosition: '0',
          AppSettingKeys.localFavoriteMoveAfterReading: '1',
        },
      ),
      save: () async {},
    );
    container = ProviderContainer(
      overrides: [
        localFavoritesRepositoryProvider.overrideWithValue(repository),
        favoritesNavigationStoreProvider.overrideWithValue(_Navigation()),
        comicSourceRegistryProvider.overrideWith(_Registry.new),
      ],
    );
    events = [];
    subscription = repository.changes.listen(events.add);
  });

  tearDown(() async {
    container.dispose();
    await subscription.cancel();
    await db.close();
  });

  test('不同来源的同标识作品可并存，编辑与删除互不影响', () async {
    await repository.createFolder('收藏');
    await repository.addComic('收藏', item('same'));
    await repository.addComic('收藏', item('same', type: 2));
    expect(await repository.count('收藏'), 2);
    await repository.editTags('same', '收藏', ['新标签'], const FavoriteType(2));
    expect(
      (await repository.getComic('收藏', 'same', const FavoriteType(0))).tags,
      ['测试'],
    );
    expect(
      (await repository.getComic('收藏', 'same', const FavoriteType(2))).tags,
      ['新标签'],
    );
    await repository.deleteComicWithTarget('收藏', 'same', const FavoriteType(2));
    expect((await repository.getAllComics('收藏')).single.type.key, 0);
  });

  test('排序和重命名保留同步配置与收藏夹顺序', () async {
    await repository.createFolder('旧名称');
    await repository.addComic('旧名称', item('a'));
    await repository.addComic('旧名称', item('b'));
    await repository.insertFolderSync(
      FolderSync(folderName: '旧名称', key: 'picacg', syncData: '{}', time: '旧时间'),
    );
    await repository.updateOrder({'旧名称': 5});
    await repository.reorder([item('b'), item('a')], '旧名称');
    expect((await repository.getAllComics('旧名称')).map((e) => e.target), [
      'b',
      'a',
    ]);
    expect((await repository.folderSync).single.time, '旧时间');
    await repository.rename('旧名称', '新名称');
    expect((await repository.folderSync).single.folderName, '新名称');
    expect((await db.query(kTableFolderOrder)).single[kFolderOrderValue], 5);
    await repository.deleteFolder('新名称');
    expect(await repository.folderSync, isEmpty);
    expect(await db.query(kTableFolderOrder), isEmpty);
  });

  test('同步写入失败整体回滚，记录和同步时间保持原状', () async {
    await repository.createFolder('同步');
    await repository.addComic('同步', item('existing'));
    await repository.insertFolderSync(
      FolderSync(folderName: '同步', key: 'picacg', syncData: '{}', time: '旧时间'),
    );
    await db.execute(
      'CREATE TRIGGER fail_insert BEFORE INSERT ON "同步" '
      'WHEN NEW.$kFavoriteTarget = \'fail\' BEGIN SELECT RAISE(ABORT, \'模拟写入失败\'); END',
    );
    await expectLater(
      repository.importFavorites('同步', [
        item('new'),
        item('fail'),
      ], sync: FolderSync(folderName: '同步', key: 'picacg', syncData: '{}')),
      throwsA(isA<DatabaseException>()),
    );
    expect((await repository.getAllComics('同步')).map((e) => e.target), [
      'existing',
    ]);
    expect((await repository.folderSync).single.time, '旧时间');
  });

  test('批量导入仅通知一次，复合身份去重并保留远端顺序', () async {
    await repository.createFolder('同步');
    await repository.addComic('同步', item('existing'));
    await Future<void>.delayed(Duration.zero);
    events.clear();
    await repository.importFavorites('同步', [
      item('a'),
      item('same'),
      item('same', type: 2),
      item('a'),
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(events, hasLength(1));
    expect(
      (await repository.getAllComics('同步')).map((e) => (e.type.key, e.target)),
      [(0, 'a'), (0, 'same'), (2, 'same'), (0, 'existing')],
    );
  });

  test('多收藏夹归属失败整体回滚', () async {
    await repository.createFolder('存在');
    await expectLater(
      repository.setMembership(['存在', '不存在'], item('a'), adding: true),
      throwsA(isA<DatabaseException>()),
    );
    expect(await repository.count('存在'), 0);
  });

  test('收藏列表、数量和归属随元数据及删除更新', () async {
    await repository.createFolder('收藏');
    await repository.addComic('收藏', item('a'));
    final list = folderFavoritesProvider('收藏');
    final count = localFavoriteCountProvider('收藏');
    final membership = favoriteMembershipProvider(item('a').identity);
    container.listen(list, (_, __) {});
    container.listen(count, (_, __) {});
    container.listen(membership, (_, __) {});
    final before = await container.read(list.future);
    expect(await container.read(count.future), 1);
    expect(await container.read(membership.future), ['收藏']);
    await repository.updateInfo('收藏', item('a', name: '更新标题'));
    await Future<void>.delayed(Duration.zero);
    await container.pump();
    expect((await container.read(list.future)).single.name, '更新标题');
    expect(before.single.name, 'a');
    expect(() => before.single.tags.add('修改'), throwsUnsupportedError);
    await repository.deleteComicWithTarget('收藏', 'a', const FavoriteType(0));
    await Future<void>.delayed(Duration.zero);
    await container.pump();
    expect(await container.read(list.future), isEmpty);
    expect(await container.read(count.future), 0);
    expect(await container.read(membership.future), isEmpty);
  });
  test('多选使用稳定身份，信息更新不丢失，切夹清空选择', () async {
    await repository.createFolder('A');
    await repository.createFolder('B');
    await repository.addComic('A', item('a'));
    container.listen(favoritesSessionProvider, (_, __) {});
    await container.read(localFavoritesProvider.future);
    final session = container.read(favoritesSessionProvider.notifier);
    session.openLocal('A');
    session.toggle(item('a').identity);
    await repository.updateInfo('A', item('a', name: '新标题'));
    await Future<void>.delayed(Duration.zero);
    await container.pump();
    expect(container.read(favoritesSessionProvider).selected, {
      item('a').identity,
    });
    await repository.rename('A', '重命名');
    await Future<void>.delayed(Duration.zero);
    await container.pump();
    expect(container.read(favoritesSessionProvider).current, '重命名');
    session.openLocal('B');
    expect(container.read(favoritesSessionProvider).selected, isEmpty);
  });

  test('选中作品删除后清除选择，当前收藏夹删除后返回目录', () async {
    await repository.createFolder('A');
    await repository.addComic('A', item('a'));
    container.listen(favoritesSessionProvider, (_, __) {});
    await container.read(localFavoritesProvider.future);
    final session = container.read(favoritesSessionProvider.notifier);
    session.openLocal('A');
    session.toggle(item('a').identity);
    await repository.deleteComicWithTarget('A', 'a', const FavoriteType(0));
    await Future<void>.delayed(Duration.zero);
    await container.pump();
    expect(container.read(favoritesSessionProvider).selected, isEmpty);
    await repository.deleteFolder('A');
    await Future<void>.delayed(Duration.zero);
    await container.pump();
    expect(container.read(favoritesSessionProvider).current, isNull);
    expect(container.read(favoritesSessionProvider).selectingFolder, isTrue);
  });

  test('旧 JSON 恢复成功后全量发布，失败保留输入与原数据', () async {
    final directory = await Directory.systemTemp.createTemp(
      'favorite-restore-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final legacy = File('${directory.path}/localFavorite');
    final temporary = '${directory.path}/local_favorite_temp.db';
    await repository.createFolder('原夹');
    await repository.addComic('原夹', item('old'));
    await legacy.writeAsString(
      jsonEncode({
        '新夹': [item('new').toJson()],
      }),
    );
    final before = events.length;
    await repository.readData(
      legacyPath: legacy.path,
      temporaryPath: temporary,
    );
    expect(await legacy.exists(), isFalse);
    expect(await repository.folderNames, ['新夹']);
    expect((await repository.getAllComics('新夹')).single.target, 'new');
    expect(events.length, before + 1);
    expect(events.last.keys, isNull);
    await legacy.writeAsString(jsonEncode({kTableFolderSync: []}));
    await expectLater(
      repository.readData(legacyPath: legacy.path, temporaryPath: temporary),
      throwsArgumentError,
    );
    expect(await legacy.exists(), isTrue);
    expect((await repository.getAllComics('新夹')).single.target, 'new');
  });

  test('临时数据库合并恢复保留顺序及同步配置', () async {
    final directory = await Directory.systemTemp.createTemp(
      'favorite-database-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final temporary = '${directory.path}/local_favorite_temp.db';
    final source = await databaseFactoryFfi.openDatabase(temporary);
    final incoming = LocalFavoritesManager.forTesting(
      source,
      save: () async {},
    );
    await source.execute(
      'CREATE TABLE $kTableFolderSync ($kFolderSyncName TEXT PRIMARY KEY, '
      '$kFolderSyncTime TEXT, $kFolderSyncKey TEXT, $kFolderSyncData TEXT)',
    );
    await source.execute(
      'CREATE TABLE $kTableFolderOrder ($kFolderOrderName TEXT PRIMARY KEY, $kFolderOrderValue INT)',
    );
    await incoming.createFolder('导入夹');
    await incoming.importFavorites('导入夹', [item('b'), item('a')]);
    await incoming.updateOrder({'导入夹': 5});
    await incoming.insertFolderSync(
      FolderSync(folderName: '导入夹', key: 'jm', syncData: '{}', time: '原时间'),
    );
    await source.close();
    await repository.createFolder('已有夹');
    await repository.readData(
      legacyPath: '${directory.path}/absent',
      temporaryPath: temporary,
    );
    expect(await File(temporary).exists(), isFalse);
    expect(await repository.folderNames, ['已有夹', '导入夹']);
    expect((await repository.getAllComics('导入夹')).map((e) => e.target), [
      'b',
      'a',
    ]);
    expect((await repository.folderSync).single.time, '原时间');
  });
  test('逐条批任务保留结果并在结束时合并通知', () async {
    await repository.createFolder('批量');
    await repository.copyComics('批量', [item('a'), item('b')]);
    await Future<void>.delayed(Duration.zero);
    final before = events.length;
    final batch = repository.beginChangeBatch();
    await repository.updateInfo('批量', item('a', name: '更新 A'), batch: batch);
    await repository.addTagTo(
      '批量',
      'b',
      'Unavailable',
      const FavoriteType(0),
      batch: batch,
    );
    expect(events.length, before);
    expect(
      (await repository.getComic('批量', 'a', const FavoriteType(0))).name,
      '更新 A',
    );
    batch.finish();
    batch.finish();
    await Future<void>.delayed(Duration.zero);
    expect(events.length, before + 1);
    expect(events.last.keys, {item('a').identity, item('b').identity});
  });
}
