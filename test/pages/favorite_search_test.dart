import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/foundation/local_favorites.dart';
import 'package:pica_comic/foundation/repository_change.dart';
import 'package:pica_comic/pages/favorites/local_favorites_providers.dart';

/// 独立控制搜索返回顺序，不访问实际数据库。
class _Repository extends Fake implements LocalFavoritesManager {
  final responses = <String, Completer<List<FavoriteItemWithFolderInfo>>>{};

  @override
  Stream<RepositoryChange<FavoriteIdentity>> get changes =>
      const Stream.empty();

  @override
  Future<List<FavoriteItemWithFolderInfo>> search(String keyword) =>
      (responses[keyword] ??= Completer()).future;
}

void main() {
  testWidgets('搜索输入防抖 300 毫秒，提交取消尚未触发的输入', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.listen(favoriteSearchInputProvider, (_, __) {});
    final actions = container.read(favoriteSearchInputProvider.notifier);
    actions.change('旧词');
    await tester.pump(const Duration(milliseconds: 299));
    expect(container.read(favoriteSearchInputProvider), '');
    actions.change('新词');
    await tester.pump(const Duration(milliseconds: 300));
    expect(container.read(favoriteSearchInputProvider), '新词');
    actions.change('待触发');
    actions.submit('立即提交');
    expect(container.read(favoriteSearchInputProvider), '立即提交');
    await tester.pump(const Duration(milliseconds: 301));
    expect(container.read(favoriteSearchInputProvider), '立即提交');
  });

  test('迟到的旧关键词查询不能覆盖新查询', () async {
    final repository = _Repository();
    final container = ProviderContainer(
      overrides: [
        localFavoritesRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    final old = favoriteSearchProvider('旧词');
    final current = favoriteSearchProvider('新词');
    final subscription = container.listen(old, (_, __) {});
    final pending = container.read(old.future);
    subscription.close();
    container.listen(current, (_, __) {});
    repository.responses['新词']!.complete([]);
    expect(await container.read(current.future), isEmpty);
    repository.responses['旧词']!.complete([]);
    await pending;
    expect(container.read(current).asData?.value, isEmpty);
  });
}
