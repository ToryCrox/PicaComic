import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/foundation/favorite_metadata_service.dart';
import 'package:pica_comic/foundation/local_favorites.dart';
import 'package:pica_comic/network/base_comic.dart';
import 'package:pica_comic/network/res.dart';
import 'package:pica_comic/pages/favorites/favorite_jobs.dart';
import 'package:pica_comic/pages/favorites/local_favorites_providers.dart';

/// 批任务测试作品。
class _Comic extends BaseComic {
  const _Comic(this.id);
  @override
  final String id;
  @override
  String get title => id;
  @override
  String get subTitle => '';
  @override
  String get cover => '';
  @override
  List<String> get tags => const [];
  @override
  String get description => '';
}

/// 创建不需要网络模型的收藏快照。
FavoriteItem _item(String id) => FavoriteItem(
  target: id,
  name: id,
  coverPath: '',
  author: '',
  type: const FavoriteType(0),
  tags: const [],
);

/// 记录批量提交，允许模拟事务提交等待。
class _Repository extends Fake implements LocalFavoritesManager {
  int commits = 0;
  final updates = <String>[];
  final unavailable = <String>[];
  Completer<(String, int)>? commit;
  @override
  FavoriteChangeBatch beginChangeBatch() => FavoriteChangeBatch((_) {});
  @override
  Future<(String, int)> importFavorites(
    String folder,
    List<FavoriteItem> comics, {
    bool create = false,
    FolderSync? sync,
  }) async {
    commits++;
    return commit == null ? (folder, comics.length) : commit!.future;
  }

  @override
  Future<void> updateInfo(
    String folder,
    FavoriteItem comic, {
    FavoriteChangeBatch? batch,
  }) async => updates.add(comic.target);
  @override
  Future<void> addTagTo(
    String folder,
    String target,
    String tag,
    FavoriteType type, {
    FavoriteChangeBatch? batch,
  }) async => unavailable.add(target);
}

/// 测试控制元数据响应和返回时机。
class _Metadata extends Fake implements FavoriteMetadataService {
  Future<Res<FavoriteItem>> Function(FavoriteItem) handler = (item) async =>
      Res(item);
  @override
  Future<Res<FavoriteItem>> load(FavoriteItem item) => handler(item);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProviderContainer container;
  late _Repository repository;
  late _Metadata metadata;
  late FavoriteJob job;
  final provider = favoriteJobProvider('目标');

  setUp(() {
    repository = _Repository();
    metadata = _Metadata();
    container = ProviderContainer(
      overrides: [
        localFavoritesRepositoryProvider.overrideWithValue(repository),
        favoriteMetadataServiceProvider.overrideWithValue(metadata),
      ],
    );
    container.listen(provider, (_, __) {});
    job = container.read(provider.notifier);
  });
  tearDown(() => container.dispose());

  test('取消抓取不提交部分收藏，重复启动复用当前任务', () async {
    final response = Completer<Res<List<BaseComic>>>();
    var calls = 0;
    Future<Res<List<BaseComic>>> load(int page) {
      calls++;
      return response.future;
    }

    final first = job.importNetwork(
      loadPage: load,
      convert: (comic) => _item(comic.id),
      targetFolder: '目标',
      create: true,
    );
    final duplicate = job.importNetwork(
      loadPage: load,
      convert: (comic) => _item(comic.id),
      targetFolder: '目标',
    );
    expect(identical(first, duplicate), isTrue);
    job.cancel();
    response.complete(const Res([_Comic('a')]));
    expect((await first).phase, FavoriteJobPhase.cancelled);
    expect(repository.commits, 0);
    expect(calls, 1);
  });

  test('中途抓取失败不会更新收藏或同步时间', () async {
    final result = await job.importNetwork(
      loadPage: (page) async => page == 1
          ? const Res([_Comic('a')], subData: 2)
          : const Res.error('网络错误'),
      convert: (comic) => _item(comic.id),
      targetFolder: '目标',
    );
    expect(result.phase, FavoriteJobPhase.failed);
    expect(repository.commits, 0);
  });

  test('按同步页数完整抓取后仅提交一次，提交阶段不可取消', () async {
    repository.commit = Completer();
    final result = job.importNetwork(
      loadPage: (_) async => const Res([_Comic('a')], subData: 8),
      convert: (comic) => _item(comic.id),
      targetFolder: '目标',
      pageLimit: 1,
    );
    await Future<void>.delayed(Duration.zero);
    expect(container.read(provider).phase, FavoriteJobPhase.committing);
    expect(container.read(provider).canCancel, isFalse);
    job.cancel();
    repository.commit!.complete(('目标', 1));
    expect((await result).phase, FavoriteJobPhase.completed);
    expect(repository.commits, 1);
  });

  test('抓取期间切换账号后不提交', () async {
    var current = true;
    final result = await job.importNetwork(
      loadPage: (_) async {
        current = false;
        return const Res([_Comic('a')], subData: 1);
      },
      convert: (comic) => _item(comic.id),
      targetFolder: '目标',
      isSessionCurrent: () => current,
    );
    expect(result.phase, FavoriteJobPhase.cancelled);
    expect(repository.commits, 0);
  });

  test('取消信息更新保留已完成条目，迟到响应不写入', () async {
    final response = Completer<Res<FavoriteItem>>();
    metadata.handler = (item) =>
        item.target == 'a' ? Future.value(Res(item)) : response.future;
    final result = job.updateItems([_item('a'), _item('b')]);
    await Future<void>.delayed(Duration.zero);
    expect(repository.updates, ['a']);
    job.cancel();
    response.complete(Res(_item('b')));
    expect((await result).phase, FavoriteJobPhase.cancelled);
    expect(repository.updates, ['a']);
  });

  test('普通网络错误不标记为失效，明确404才添加失效标签', () async {
    metadata.handler = (item) async =>
        Res.error(item.target == 'missing' ? '404 Not Found' : '连接超时');
    final result = await job.updateItems([
      _item('missing'),
      _item('timeout'),
    ], checkAvailability: true);
    expect(repository.unavailable, ['missing']);
    expect(result.unavailable, 1);
    expect(result.failures, 1);
    expect(result.completed, 2);
  });
  test('URL 中的 404 不是明确的失效状态', () {
    expect(
      isFavoriteUnavailable(const Res.error('连接 https://example.com/404/1 失败')),
      isFalse,
    );
    expect(isFavoriteUnavailable(const Res.error('404: not found')), isTrue);
    expect(
      isFavoriteUnavailable(const Res.error('response status code of 404')),
      isTrue,
    );
    expect(isFavoriteUnavailable(const Res.error('HTTP 404')), isTrue);
  });
}
