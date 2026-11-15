import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/foundation/history.dart';
import 'package:pica_comic/foundation/history_providers.dart';
import 'package:pica_comic/network/download/download_model.dart';
import 'package:pica_comic/network/eh_network/eh_download_model.dart';
import 'package:pica_comic/network/eh_network/eh_models.dart';
import 'package:pica_comic/pages/download/components/download_comic_card.dart';
import 'package:pica_comic/pages/download/download_providers.dart';
import 'package:pica_comic/tools/time.dart';
import 'package:pica_comic/tools/translations.dart';

void main() {
  late Map<String, String> originalSettings;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await AppTranslation.init();
  });

  setUp(() {
    originalSettings = Map<String, String>.from(appdata.settings);
    appdata.setSetting(AppSettingKeys.language, 'cn');
  });

  tearDown(() {
    appdata.settings = originalSettings;
  });

  group('下载页网格自适应', () {
    const delegate = SliverGridDelegateWithDownloadComics(infoHeight: 66);

    test('手机宽度为两列，卡片宽度落在 140-240', () {
      final resolved = delegate.resolve(360);
      expect(resolved.columns, 2);
      expect(resolved.childWidth, closeTo(172, 0.01));
      expect(resolved.childWidth, inInclusiveRange(140, 240));
      // 卡片之间的间距不小于 16
      expect(resolved.crossAxisSpacing, greaterThanOrEqualTo(16));
    });

    test('列数随宽度增长，卡片宽度始终受最大宽度约束', () {
      const widths = [320.0, 600.0, 900.0, 1200.0, 1400.0, 2000.0, 2560.0];
      var previousColumns = 1;
      for (final width in widths) {
        final resolved = delegate.resolve(width);
        expect(resolved.columns, greaterThanOrEqualTo(previousColumns));
        expect(
          resolved.childWidth,
          inInclusiveRange(140, 240),
          reason: 'width=$width',
        );
        // 列宽 + 间距应完整铺满可用宽度
        final total =
            resolved.childWidth * resolved.columns +
            resolved.crossAxisSpacing * (resolved.columns - 1);
        expect(total, closeTo(width, 0.01), reason: 'width=$width');
        previousColumns = resolved.columns;
      }
    });

    test('卡片高度按封面宽高比与信息区高度计算', () {
      final resolved = delegate.resolve(360);
      final layout = delegate.getLayout(
        const SliverConstraints(
          axisDirection: AxisDirection.down,
          growthDirection: GrowthDirection.forward,
          userScrollDirection: ScrollDirection.idle,
          scrollOffset: 0,
          precedingScrollExtent: 0,
          overlap: 0,
          remainingPaintExtent: 400,
          crossAxisExtent: 360,
          crossAxisDirection: AxisDirection.right,
          viewportMainAxisExtent: 800,
          remainingCacheExtent: 800,
          cacheOrigin: 0,
        ),
      );
      expect(
        layout.getGeometryForChildIndex(0).mainAxisExtent,
        closeTo(
          resolved.childWidth / downloadComicCardCoverAspectRatio + 66,
          0.01,
        ),
      );
    });

    test('放大系数让卡片变宽同时减少列数', () {
      const larger = SliverGridDelegateWithDownloadComics(
        infoHeight: 66,
        scale: 1.5,
      );
      final normalResolved = delegate.resolve(900);
      final largerResolved = larger.resolve(900);
      expect(largerResolved.childWidth, greaterThan(normalResolved.childWidth));
      expect(largerResolved.columns, lessThan(normalResolved.columns));
      expect(
        largerResolved.childWidth,
        inInclusiveRange(
          SliverGridDelegateWithDownloadComics.defaultMinChildWidth * 1.5,
          SliverGridDelegateWithDownloadComics.defaultMaxChildWidth * 1.5,
        ),
      );
    });

    test('缩小系数让卡片变窄同时增加列数', () {
      const smaller = SliverGridDelegateWithDownloadComics(
        infoHeight: 66,
        scale: 0.75,
      );
      final normalResolved = delegate.resolve(900);
      final smallerResolved = smaller.resolve(900);
      expect(smallerResolved.childWidth, lessThan(normalResolved.childWidth));
      expect(smallerResolved.columns, greaterThan(normalResolved.columns));
      expect(
        smallerResolved.childWidth,
        inInclusiveRange(
          SliverGridDelegateWithDownloadComics.defaultMinChildWidth * 0.75,
          SliverGridDelegateWithDownloadComics.defaultMaxChildWidth * 0.75,
        ),
      );
      // 放大 / 缩小后列宽与间距仍需铺满可用宽度。
      final total =
          smallerResolved.childWidth * smallerResolved.columns +
          smallerResolved.crossAxisSpacing * (smallerResolved.columns - 1);
      expect(total, closeTo(900, 0.01));
    });

    test('损坏的缩放系数回落到默认宽度', () {
      for (final scale in [0.0, -1.0, double.nan]) {
        final broken = SliverGridDelegateWithDownloadComics(
          infoHeight: 66,
          scale: scale,
        );
        expect(
          broken.resolve(360).childWidth,
          closeTo(delegate.resolve(360).childWidth, 0.01),
          reason: 'scale=$scale',
        );
      }
    });
  });

  group('下载漫画卡片', () {
    testWidgets('展示标题 Tooltip、作者、大小与来源，操作为无文字图标', (tester) async {
      await _pumpCard(tester);

      expect(find.text('Test Comic'), findsOneWidget);
      expect(find.textContaining('Test Comic'), findsOneWidget);
      expect(find.text('KuruFapJikan'), findsOneWidget);
      expect(find.text('7.73MB'), findsOneWidget);
      expect(find.text('本地'), findsOneWidget);
      expect(find.text('阅读'), findsNothing);
      expect(find.text('目录'), findsNothing);
      expect(find.text('标签'), findsNothing);
      expect(find.text('标记'), findsNothing);
      expect(find.byIcon(Icons.menu_book), findsOneWidget);
      expect(find.byIcon(Icons.folder_open), findsOneWidget);
      expect(find.byIcon(Icons.label_outline), findsOneWidget);
      expect(find.byIcon(Icons.circle_outlined), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('自定义标签使用主题色与下划线，来源标签使用次要色', (tester) async {
      await _pumpCard(tester, userTags: const ['我的分类']);

      final custom = tester.widget<Text>(find.text('我的分类'));
      expect(custom.style!.color, _scheme.primary);
      expect(custom.style!.fontWeight, FontWeight.w500);
      expect(custom.style!.decoration, TextDecoration.underline);

      final source = tester.widget<Text>(find.text('学生'));
      expect(source.style!.color, _scheme.onSurfaceVariant);
      expect(source.style!.decoration, TextDecoration.underline);
      expect(tester.takeException(), isNull);
    });

    testWidgets('选中态显示描边与对勾', (tester) async {
      await _pumpCard(tester, isSelected: true);

      expect(find.byIcon(Icons.check), findsOneWidget);
      final borders = tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .map((e) => e.decoration)
          .whereType<BoxDecoration>()
          .where(
            (d) =>
                d.border is Border &&
                (d.border as Border).top.width == 2 &&
                (d.border as Border).top.color == _scheme.primary,
          );
      expect(borders, isNotEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('页数从标题挪到文件大小旁边', (tester) async {
      await _pumpCard(tester, item: _galleryItem, width: 260);

      expect(find.textContaining('(123P)'), findsNothing);
      expect(find.text('123P · 12.50MB'), findsOneWidget);
      expect(find.textContaining('Test Comic'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('有历史记录时显示最后阅读时间', (tester) async {
      final lastRead = DateTime.now().subtract(const Duration(hours: 3));
      await _pumpCard(
        tester,
        item: _galleryItem,
        historyTime: lastRead,
        width: 260,
      );

      expect(find.text('3 小时前'), findsOneWidget);
      expect(
        find.byTooltip(
          '最后阅读 ${timeToDateString(lastRead)} '
          '${lastRead.hour.toString().padLeft(2, '0')}:'
          '${lastRead.minute.toString().padLeft(2, '0')}',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });
}

final ColorScheme _scheme = ColorScheme.fromSeed(seedColor: Colors.indigo);

class _FakeComicUserTags extends ComicUserTags {
  _FakeComicUserTags(this.tags);

  final Map<String, List<String>> tags;

  @override
  Future<Map<String, List<String>>> build() async => tags;
}

Future<void> _pumpCard(
  WidgetTester tester, {
  List<String> userTags = const [],
  bool isSelected = false,
  DownloadedItem? item,
  DateTime? historyTime,
  double width = 176,
}) async {
  final target = item ?? _item;
  final infoHeight = downloadComicCardInfoHeight(TextScaler.noScaling);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        comicUserTagsProvider.overrideWith(
          () => _FakeComicUserTags(
            userTags.isEmpty ? const {} : {target.id: userTags},
          ),
        ),
        if (historyTime != null && target is DownloadedGallery)
          historyEntryProvider(target.gallery.link).overrideWith(
            (ref) async => HistoryRecord(
              type: HistoryType.ehentai,
              time: historyTime,
              title: target.gallery.title,
              subtitle: target.gallery.uploader,
              cover: '',
              ep: 0,
              page: 60,
              target: target.gallery.link,
              maxPage: 123,
            ),
          ),
      ],
      child: MaterialApp(
        theme: ThemeData(colorScheme: _scheme),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              height: width / downloadComicCardCoverAspectRatio + infoHeight,
              child: DownloadComicCard(
                item: target,
                pageId: 'test',
                isSelected: isSelected,
                isDragDisabled: true,
                onTap: () {},
                onLongTap: () {},
                onSecondaryTap: (_) {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  if (historyTime != null) {
    // 等异步 provider 覆写返回历史记录。
    await tester.pump();
  }
}

final DownloadedGallery _galleryItem = DownloadedGallery(
  Gallery(
    title: 'Test Comic',
    uploader: 'Artist',
    link: 'https://e-hentai.org/g/1/abcdef/',
    maxPage: '123',
  ),
  12.5,
)..bindDownloadManager(DownloadManager());

final LocalDownloadedItem _item = LocalDownloadedItem(
  comicSize: 7.73,
  downloadedEps: const [],
  id: 'local-test',
  name: 'Test Comic',
  subTitle: 'KuruFapJikan',
  tags: const ['学生'],
  repositoryName: 'test',
);
