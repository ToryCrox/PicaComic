import 'dart:async';
import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/comic_source/comic_source.dart';
import 'package:pica_comic/foundation/app_settings_provider.dart';
import 'package:pica_comic/foundation/def.dart';
import 'package:pica_comic/foundation/window_frame_provider.dart';
import 'package:pica_comic/network/res.dart';
import 'package:pica_comic/pages/explore_providers.dart';
import 'package:pica_comic/pages/pre_search_providers.dart';

void main() {
  test('搜索页的筛选按实例隔离，旧快照不可修改，退出后释放', () async {
    final previous = ComicSource.sources;
    ComicSource.sources = [
      ComicSource.named(
        name: '测试来源',
        key: ComicType.picacg,
        filePath: '',
        searchPageData: SearchPageData.named(
          searchOptions: [
            SearchOptions(LinkedHashMap.of({'a': '选项一', 'b': '选项二'}), '排序'),
          ],
        ),
      ),
      ComicSource.named(
        name: '无筛选来源',
        key: ComicType.jm,
        filePath: '',
        searchPageData: const SearchPageData.named(),
      ),
    ];
    addTearDown(() => ComicSource.sources = previous);
    final container = ProviderContainer(
      overrides: [
        appSettingsRepositoryProvider.overrideWithValue(
          AppSettingsRepository(
            readValues: () => defaultAppSettings,
            changes: const Stream.empty(),
            notifyChanges: () {},
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    final first = preSearchProvider(Object());
    final second = preSearchProvider(Object());
    final subscription = container.listen(first, (_, _) {});
    container.listen(second, (_, _) {});
    final original = container.read(first);
    final actions = container.read(first.notifier);
    actions.setOption(0, 'b');
    expect(container.read(first).options, ['b']);
    expect(container.read(second).options, ['a']);
    expect(original.options, ['a']);
    expect(() => original.options.add('c'), throwsUnsupportedError);
    actions.updateTarget(ComicType.jm);
    expect(container.read(first).options, isEmpty);
    expect(container.read(second).target, ComicType.picacg);
    subscription.close();
    await container.pump();
    expect(container.exists(first), isFalse);
  });

  test('窗口主题和全屏独立更新，容器之间互不影响', () {
    final first = ProviderContainer();
    final second = ProviderContainer();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    final actions = first.read(windowFrameProvider.notifier);
    actions.hideWindowFrame();
    actions.setDarkTheme();
    actions.resetTheme();
    expect(first.read(windowFrameProvider).hidden, isTrue);
    expect(first.read(windowFrameProvider).useDarkTheme, isFalse);
    actions.showWindowFrame();
    expect(first.read(windowFrameProvider).hidden, isFalse);
    expect(second.read(windowFrameProvider).hidden, isFalse);
    expect(second.read(windowFrameProvider).useDarkTheme, isFalse);
  });

  test('探索页先显示缓存，刷新后的迟到请求不覆盖最新结果', () async {
    final requests = <Completer<Res<List<ExplorePagePart>>>>[];
    final data = ExplorePageData.named(
      title: '主页',
      type: ExplorePageType.singlePageWithMultiPart,
      loadMultiPartCache: () async => [const ExplorePagePart('缓存', [], null)],
      loadMultiPart: (_) {
        final request = Completer<Res<List<ExplorePagePart>>>();
        requests.add(request);
        return request.future;
      },
    );
    final session = Object();
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final provider = explorePartsProvider(session, 'picacg', data);
    container.listen(provider, (_, _) {});
    await container.pump();
    expect(container.read(provider).requireValue.single.title, '缓存');
    expect(requests.length, 1);
    container
        .read(exploreRefreshProvider(session, 'picacg', data.title).notifier)
        .refresh();
    await container.pump();
    await Future<void>.delayed(Duration.zero);
    expect(requests.length, 2);
    requests[1].complete(Res([const ExplorePagePart('最新', [], null)]));
    await container.pump();
    requests[0].complete(Res([const ExplorePagePart('过期', [], null)]));
    await container.pump();
    expect(container.read(provider).requireValue.single.title, '最新');
  });

  test('探索页刷新按实例和来源隔离，卸载后缓存请求不再启动网络', () async {
    final session = Object();
    final cache = Completer<List<ExplorePagePart>>();
    var calls = 0;
    final data = ExplorePageData.named(
      title: '主页',
      type: ExplorePageType.singlePageWithMultiPart,
      loadMultiPartCache: () => cache.future,
      loadMultiPart: (_) async {
        calls++;
        return const Res([]);
      },
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final provider = explorePartsProvider(session, 'picacg', data);
    final subscription = container.listen(provider, (_, _) {});
    final otherSource = exploreRefreshProvider(session, 'jm', data.title);
    final otherPage = exploreRefreshProvider(Object(), 'picacg', data.title);
    container.listen(otherSource, (_, _) {});
    container.listen(otherPage, (_, _) {});
    container
        .read(exploreRefreshProvider(session, 'picacg', data.title).notifier)
        .refresh();
    expect(container.read(otherSource), 0);
    expect(container.read(otherPage), 0);
    subscription.close();
    await container.pump();
    cache.complete([]);
    await container.pump();
    expect(calls, 0);
  });
}
