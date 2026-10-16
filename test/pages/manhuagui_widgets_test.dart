import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pica_comic/pages/manhuagui/manhuagui_adapter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/comic_source/comic_source.dart';
import 'package:pica_comic/components/grouped_chapters.dart';
import 'package:pica_comic/network/manhuagui/manhuagui_network.dart';
import 'package:pica_comic/network/manhuagui/manhuagui_parser.dart';
import 'package:pica_comic/network/res.dart';
import 'package:pica_comic/pages/manhuagui/manhuagui_comments_page.dart';
import 'package:pica_comic/pages/manhuagui/manhuagui_category_page.dart';
import 'package:pica_comic/comic_source/built_in/manhuagui.dart';
import 'package:pica_comic/pages/category_page.dart';
import 'package:pica_comic/tools/translations.dart';

import '../fixtures/manhuagui/sample.dart';

/// 使用可手动完成的响应验证切换排序时的竞态。
class _CommentsNetwork extends ManhuaguiNetwork {
  _CommentsNetwork() : super(Dio(), cacheEnabled: false);
  final requests =
      <
        ({int page, ManhuaguiCommentSort sort}),
        Completer<Res<List<ManhuaguiCommentThread>>>
      >{};
  @override
  Future<Res<List<ManhuaguiCommentThread>>> comments(
    String id,
    int page,
    ManhuaguiCommentSort sort,
  ) => (requests[(page: page, sort: sort)] = Completer()).future;
}

Res<List<ManhuaguiCommentThread>> response(String content, {int pages = 2}) =>
    Res([
      ManhuaguiCommentThread(
        Comment('用户', null, content, '2026-10-16', null, content),
        const [],
      ),
    ], subData: pages);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(AppTranslation.init);
  setUp(
    () =>
        TestWidgetsFlutterBinding.instance.platformDispatcher.localeTestValue =
            const Locale('zh', 'CN'),
  );
  tearDown(
    () => TestWidgetsFlutterBinding.instance.platformDispatcher
        .clearLocaleTestValue(),
  );

  testWidgets('手机尺寸下分组选章和操作按钮没有布局溢出', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GroupedDownloadChapters(
            chapters: sample.chapters!,
            groups: sample.chapterGroups,
            onDownload: (_) {},
          ),
        ),
      ),
    );
    await tester.tap(find.text('第01卷'));
    await tester.pumpAndSettle();
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(find.byIcon(Icons.download_outlined), findsNWidgets(3));
    expect(find.text('${'下载选择'.tl} (1)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('下载选章切组保留选择，仅下载当前分组的未下载章节', (tester) async {
    List<String>? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GroupedDownloadChapters(
            chapters: sample.chapters!,
            groups: sample.chapterGroups,
            downloadedIds: const {'11'},
            onDownload: (ids) => result = ids,
          ),
        ),
      ),
    );
    await tester.tap(find.text('第01卷'));
    await tester.tap(find.text('第01话'));
    await tester.pump();
    await tester.tap(find.text('${'下载选择'.tl} (2)'));
    expect(result, ['10', '20']);
    await tester.tap(find.byKey(const ValueKey('download-chapters')));
    expect(result, ['20', '21']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('详情并列展示所有分组，排序不改变点击章节 ID', (tester) async {
    String? tapped;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GroupedChapters(
            chapters: sample.chapters!,
            groups: sample.chapterGroups,
            currentId: '21',
            onTap: (id) => tapped = id,
          ),
        ),
      ),
    );
    expect(find.text('第01话'), findsOneWidget);
    expect(find.text('第01卷'), findsOneWidget);
    expect(find.text('番外篇'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('sort-chapters')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('第02话'));
    expect(tapped, '21');
  });

  testWidgets('各模块默认二十章，独立展开和倒序', (tester) async {
    tester.view.physicalSize = const Size(1000, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final chapters = {for (var i = 1; i <= 50; i++) '$i': '章节$i'};
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GroupedChapters(
            chapters: chapters,
            onTap: (_) {},
            groups: [
              ComicChapterGroup(
                id: 'a',
                title: '单话',
                chapterIds: chapters.keys.take(25).toList(),
              ),
              ComicChapterGroup(
                id: 'b',
                title: '番外',
                chapterIds: chapters.keys.skip(25).toList(),
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('章节21'), findsNothing);
    expect(find.text('章节46'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('expand-a')));
    await tester.pumpAndSettle();
    expect(find.text('章节25'), findsOneWidget);
    expect(find.text('章节46'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('sort-a')));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('章节25')).dy,
      lessThan(tester.getTopLeft(find.text('章节1')).dy),
    );
    await tester.tap(find.byKey(const ValueKey('expand-a')));
    await tester.pumpAndSettle();
    expect(find.text('章节1'), findsNothing);
  });

  testWidgets('排序与标题同行，快速切换时旧响应不会覆盖当前评论', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final network = _CommentsNetwork();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [manhuaguiNetworkProvider.overrideWithValue(network)],
        child: const MaterialApp(
          home: Scaffold(body: ManhuaguiCommentsPage(comicId: '4125')),
        ),
      ),
    );
    await tester.pump();
    expect(
      (tester.getCenter(find.text('热门评论'.tl)).dy -
              tester.getCenter(find.text('评论'.tl)).dy)
          .abs(),
      lessThan(5),
    );
    await tester.tap(find.text('热门评论'.tl));
    await tester.pump();
    network.requests[(page: 1, sort: ManhuaguiCommentSort.hot)]!.complete(
      response('热门内容', pages: 1),
    );
    await tester.pumpAndSettle();
    network.requests[(page: 1, sort: ManhuaguiCommentSort.latest)]!.complete(
      response('过期最新内容'),
    );
    await tester.pumpAndSettle();
    expect(find.text('热门内容'), findsOneWidget);
    expect(find.text('过期最新内容'), findsNothing);
    await tester.tap(find.text('最新评论'.tl));
    await tester.pump();
    network.requests[(page: 1, sort: ManhuaguiCommentSort.latest)]!.complete(
      response('新的最新内容', pages: 1),
    );
    await tester.pumpAndSettle();
    expect(find.text('热门内容'), findsNothing);
    expect(find.text('新的最新内容'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('评论滚动自动追加下一页，失败重试且保留已有内容', (tester) async {
    final network = _CommentsNetwork();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [manhuaguiNetworkProvider.overrideWithValue(network)],
        child: const MaterialApp(
          home: Scaffold(body: ManhuaguiCommentsPage(comicId: '4125')),
        ),
      ),
    );
    await tester.pump();
    network.requests[(page: 1, sort: ManhuaguiCommentSort.latest)]!.complete(
      Res([
        for (var i = 0; i < 30; i++) response('第一页$i').data.single,
      ], subData: 2),
    );
    await tester.pumpAndSettle();
    expect(network.requests.length, 1);
    final list = tester.widget<ListView>(find.byType(ListView));
    list.controller!.jumpTo(list.controller!.position.maxScrollExtent);
    await tester.pump();
    expect(network.requests.length, 2);
    network.requests[(page: 2, sort: ManhuaguiCommentSort.latest)]!.complete(
      const Res.error('网络失败'),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('重试'.tl),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('重试'.tl));
    await tester.pump();
    network.requests[(page: 2, sort: ManhuaguiCommentSort.latest)]!.complete(
      Res([
        response('第一页29').data.single,
        response('第二页内容').data.single,
      ], subData: 2),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('第二页内容'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('第二页内容'), findsOneWidget);
    expect(find.text('第一页29'), findsOneWidget);
    expect(network.requests.length, 2);
    list.controller!.jumpTo(0);
    await tester.pumpAndSettle();
    expect(find.text('第一页0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('短评论列表自动补页，空结果停止加载', (tester) async {
    final network = _CommentsNetwork();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [manhuaguiNetworkProvider.overrideWithValue(network)],
        child: const MaterialApp(
          home: Scaffold(body: ManhuaguiCommentsPage(comicId: '4125')),
        ),
      ),
    );
    await tester.pump();
    network.requests[(page: 1, sort: ManhuaguiCommentSort.latest)]!.complete(
      response('短列表', pages: 3),
    );
    await tester.pump();
    await tester.pump();
    expect(
      network.requests.keys,
      contains((page: 2, sort: ManhuaguiCommentSort.latest)),
    );
    network.requests[(page: 2, sort: ManhuaguiCommentSort.latest)]!.complete(
      const Res([], subData: 3),
    );
    await tester.pumpAndSettle();
    expect(network.requests.length, 2);
    expect(find.text('短列表'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('首页分类注册漫画柜，动态显示网站分类模块', (tester) async {
    final previous = ComicSource.sources;
    ComicSource.sources = [manhuagui];
    addTearDown(() => ComicSource.sources = previous);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          manhuaguiFiltersProvider.overrideWith(
            (_) async => const Res({
              'area': {'': '全部', 'japan': '日本'},
              'genre': {'rexue': '热血'},
            }),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: CategoryPage('manhuagui')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('地区'.tl), findsOneWidget);
    expect(find.text('日本'.tl), findsOneWidget);
    expect(find.text('剧情'.tl), findsOneWidget);
    expect(find.text('热血'.tl), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('打开链接按钮通过系统浏览器打开当前漫画', (tester) async {
    MethodCall? launched;
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      launched = call;
      return true;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return Row(
                children: ManhuaguiAdapter().buildExtraActionButtons(
                  sample,
                  context,
                  (context, label, icon, onTap, [onLongPress]) =>
                      TextButton.icon(
                        onPressed: onTap,
                        icon: Icon(icon),
                        label: Text(label),
                      ),
                )!,
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开链接'.tl));
    await tester.pumpAndSettle();
    expect(launched?.method, 'launch');
    final arguments = launched!.arguments as Map;
    expect(arguments['url'], 'https://www.manhuagui.com/comic/4125/');
    expect(arguments['useWebView'], false);
    expect(arguments['useSafariVC'], false);
  });
}
