import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/network/eh_network/eh_models.dart';
import 'package:pica_comic/network/res.dart';
import 'package:pica_comic/pages/favorites/network_favorites_providers.dart';

void main() {
  test('E-Hentai 不同收藏夹持有独立游标与缓存', () async {
    final calls = <String>[];
    NetworkFavoritePageLoader loader(String folder) =>
        NetworkFavoritePageLoader(
          loadPage: (_) async => const Res([]),
          loadGallery: (next) async {
            calls.add('$folder:${next ?? "first"}');
            return Res(Galleries(next: next == null ? '$folder-next' : null));
          },
        );
    final first = loader('A');
    final second = loader('B');
    await first.load(1);
    await second.load(1);
    await first.load(2);
    await second.load(2);
    expect(calls, ['A:first', 'B:first', 'A:A-next', 'B:B-next']);
    final end = await first.load(3);
    expect(end.data, isEmpty);
    expect(end.subData, 2);
  });

  test('刷新后忽略旧游标响应', () async {
    final response = Completer<Res<Galleries>>();
    final loader = NetworkFavoritePageLoader(
      loadPage: (_) async => const Res([]),
      loadGallery: (_) => response.future,
    );
    final pending = loader.load(1);
    await Future<void>.delayed(Duration.zero);
    loader.reset();
    response.complete(const Res(Galleries(next: '旧游标')));
    expect((await pending).error, isTrue);
  });

  test('远端操作重复提交复用请求，成功后更新统一状态', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final actions = container.read(networkFavoriteActionsProvider.notifier);
    final response = Completer<Res<bool>>();
    var calls = 0;
    Future<Res<bool>> action() {
      calls++;
      return response.future;
    }

    final first = actions.run('test', action, comicId: 'a', favorite: true);
    final duplicate = actions.run('test', action, comicId: 'a', favorite: true);
    expect(identical(first, duplicate), isTrue);
    response.complete(const Res(true));
    expect((await first).success, isTrue);
    expect(calls, 1);
    expect(
      container.read(networkFavoriteRevisionProvider('test')).statuses['a'],
      isTrue,
    );
  });

  test('账户切换后旧操作结果不得污染新会话', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final response = Completer<Res<bool>>();
    final pending = container
        .read(networkFavoriteActionsProvider.notifier)
        .run('test', () => response.future, comicId: 'a', favorite: true);
    container
        .read(networkFavoriteRevisionProvider('test').notifier)
        .sessionChanged();
    response.complete(const Res(true));
    expect((await pending).error, isTrue);
    expect(
      container.read(networkFavoriteRevisionProvider('test')).statuses,
      isEmpty,
    );
  });

  test('返回false的网络操作不会被视为收藏成功', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final response = await container
        .read(networkFavoriteActionsProvider.notifier)
        .run(
          'test',
          () async => const Res(false),
          comicId: 'a',
          favorite: true,
        );
    expect(response.error, isTrue);
    expect(container.read(networkFavoriteRevisionProvider('test')).revision, 0);
  });
}
