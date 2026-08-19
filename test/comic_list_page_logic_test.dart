import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pica_comic/components/comic_list_page_logic.dart';
import 'package:pica_comic/network/base_comic.dart';
import 'package:pica_comic/network/res.dart';
import 'package:test/test.dart';

class _TestComic extends BaseComic {
  const _TestComic(this.id);

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

Future<void> _settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

ComicListPageConfig _config(
  Future<Res<List<BaseComic>>> Function(int page) loadPage,
) {
  return ComicListPageConfig(pageKey: 'test-list', loadPage: loadPage);
}

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
  });

  tearDown(() {
    container.dispose();
  });

  test('首次加载保存第1页和最大页数', () async {
    final calls = <int>[];
    final config = _config((page) async {
      calls.add(page);
      return Res<List<BaseComic>>([_TestComic('page$page')], subData: 3);
    });

    final provider = comicListPageLogicProvider(config);
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    await _settle();

    final state = container.read(provider);
    expect(calls, [1]);
    expect(state.loading, isFalse);
    expect(state.current, 1);
    expect(state.maxPage, 3);
    expect(state.comics!.single.id, 'page1');
    expect(state.dividedComics[1]!.single.id, 'page1');
  });

  test('连续模式加载下一页并追加数据', () async {
    final config = _config((page) async {
      return Res<List<BaseComic>>([_TestComic('page$page')], subData: 2);
    });

    final provider = comicListPageLogicProvider(config);
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    await _settle();

    final logic = container.read(provider.notifier);
    logic.loadNextPage();
    await _settle();

    final state = container.read(provider);
    expect(state.current, 2);
    expect(state.comics!.map((comic) => comic.id), ['page1', 'page2']);
    expect(state.loadingData, isFalse);
  });

  test('分页模式切换到未加载页面', () async {
    final calls = <int>[];
    final config = _config((page) async {
      calls.add(page);
      return Res<List<BaseComic>>([_TestComic('page$page')], subData: 3);
    });

    final provider = comicListPageLogicProvider(config);
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    await _settle();

    final logic = container.read(provider.notifier);
    logic.selectPage(2);
    await _settle();

    final state = container.read(provider);
    expect(calls, [1, 2]);
    expect(state.current, 2);
    expect(state.dividedComics[2]!.single.id, 'page2');
  });

  test('刷新会清空旧分页状态并从第1页重新加载', () async {
    var request = 0;
    final config = _config((page) async {
      request++;
      return Res<List<BaseComic>>([
        _TestComic('request$request-page$page'),
      ], subData: 3);
    });

    final provider = comicListPageLogicProvider(config);
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    await _settle();

    final logic = container.read(provider.notifier);
    logic.selectPage(2);
    await _settle();
    expect(container.read(provider).current, 2);

    logic.refresh();
    final refreshing = container.read(provider);
    expect(refreshing.current, 1);
    expect(refreshing.dividedComics, isEmpty);
    expect(refreshing.comics, isNull);

    await _settle();
    final state = container.read(provider);
    expect(state.current, 1);
    expect(state.dividedComics.keys, [1]);
    expect(state.comics!.single.id, 'request3-page1');
  });
}
