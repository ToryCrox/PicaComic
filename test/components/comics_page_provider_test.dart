import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/network/base_comic.dart';
import 'package:pica_comic/network/res.dart';

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

class _TestComicsPage extends ComicsPage<BaseComic> {
  const _TestComicsPage({required this.pageKey, required this.loadPage});

  final String pageKey;
  final Future<Res<List<BaseComic>>> Function(int page) loadPage;

  @override
  ComicType get comicType => ComicType.picacg;

  @override
  Future<Res<List<BaseComic>>> getComics(int page) async {
    return loadPage(page);
  }

  @override
  String get tag => pageKey;

  @override
  String? get title => null;

  @override
  bool get showPageIndicator => false;

  @override
  Widget buildItem(
    BuildContext context,
    BaseComic item,
    ComicListPageLogic logic,
  ) {
    return const SizedBox(width: 120, height: 120);
  }
}

void main() {
  late String originalDisplayType;

  setUp(() {
    originalDisplayType = appdata.getSetting(
      AppSettingKeys.comicsListDisplayMode,
    );
  });

  tearDown(() {
    appdata.setSetting(
      AppSettingKeys.comicsListDisplayMode,
      originalDisplayType,
    );
  });

  testWidgets('分页模式不会在构建期间触发 Provider 写入', (tester) async {
    appdata.setSetting(AppSettingKeys.comicsListDisplayMode, '1');
    final calls = <int>[];

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: _TestComicsPage(
            pageKey: 'widget-paged-list',
            loadPage: (page) async {
              calls.add(page);
              return Res<List<BaseComic>>([
                _TestComic('page$page'),
              ], subData: 2);
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(calls, [1]);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('连续模式最后一项触发下一页不会在构建期间写 Provider', (tester) async {
    appdata.setSetting(AppSettingKeys.comicsListDisplayMode, '0');
    final calls = <int>[];

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: _TestComicsPage(
            pageKey: 'widget-continuous-list',
            loadPage: (page) async {
              calls.add(page);
              return Res<List<BaseComic>>([
                _TestComic('page$page'),
              ], subData: 2);
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(calls, [1, 2]);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
