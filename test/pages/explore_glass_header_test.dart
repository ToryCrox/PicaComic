import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:pica_comic/comic_source/comic_source.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/components/windows_glass_panel.dart';
import 'package:pica_comic/foundation/app_settings_provider.dart';
import 'package:pica_comic/foundation/def.dart';
import 'package:pica_comic/network/res.dart';
import 'package:pica_comic/pages/explore_page.dart';
import 'package:pica_comic/tools/translations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(AppTranslation.init);

  testWidgets('探索标签栏切换玻璃效果时保留当前页面', (tester) async {
    final previousSources = ComicSource.sources;
    ComicSource.sources = [
      ComicSource.named(
        name: '测试来源',
        key: ComicType.picacg,
        filePath: '',
        explorePages: [
          ExplorePageData.named(
            title: '探索一',
            type: ExplorePageType.override,
            overridePageBuilder: (_) => const Center(child: Text('第一页内容')),
          ),
          ExplorePageData.named(
            title: '探索二',
            type: ExplorePageType.override,
            overridePageBuilder: (_) => const Center(child: Text('第二页内容')),
          ),
        ],
      ),
    ];
    addTearDown(() => ComicSource.sources = previousSources);
    final values = Map<String, String>.from(defaultAppSettings)
      ..[AppSettingKeys.explorePages] = '探索一,探索二';
    final repository = AppSettingsRepository(
      readValues: () => values,
      saveSettings: (_) async {},
    );
    final container = ProviderContainer(
      overrides: [appSettingsRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    windowsGlassAvailable = true;
    addTearDown(() => windowsGlassAvailable = false);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(padding: const EdgeInsets.only(top: 32)),
            child: child!,
          ),
          home: const ExplorePage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(GlassContainer), findsNWidgets(2));
    expect(
      find.byWidgetPredicate(
        (widget) => widget is WindowsGlassPanel && widget.tintColor != null,
      ),
      findsOneWidget,
    );
    expect(
      tester.widget<FilledTabBar>(find.byType(FilledTabBar)).showBottomBorder,
      isFalse,
    );
    expect(find.text('第一页内容'), findsOneWidget);
    await tester.tap(find.text('探索二'));
    await tester.pumpAndSettle();
    expect(find.text('第二页内容'), findsOneWidget);
    await container
        .read(appSettingsProvider.notifier)
        .setValue(AppSettingKeys.liquidGlassEnabled, '0');
    await tester.pumpAndSettle();
    expect(find.byType(GlassContainer), findsNothing);
    expect(
      tester.widget<FilledTabBar>(find.byType(FilledTabBar)).showBottomBorder,
      isTrue,
    );
    expect(find.text('第二页内容'), findsOneWidget);
    await container
        .read(appSettingsProvider.notifier)
        .setValue(AppSettingKeys.liquidGlassEnabled, '1');
    await tester.pumpAndSettle();
    expect(find.byType(GlassContainer), findsNWidgets(2));
    expect(find.text('第二页内容'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, skip: !Platform.isWindows);

  testWidgets('探索内容滚动时会经过玻璃标签栏后方', (tester) async {
    final previousSources = ComicSource.sources;
    final parts = List.generate(
      25,
      (i) => ExplorePagePart('分区$i', const [], null),
    );
    ComicSource.sources = [
      ComicSource.named(
        name: '测试来源',
        key: ComicType.picacg,
        filePath: '',
        explorePages: [
          ExplorePageData.named(
            title: '测试探索',
            type: ExplorePageType.singlePageWithMultiPart,
            loadMultiPart: (_) async => Res(parts),
          ),
        ],
      ),
    ];
    addTearDown(() => ComicSource.sources = previousSources);
    final values = Map<String, String>.from(defaultAppSettings)
      ..[AppSettingKeys.explorePages] = '测试探索';
    final repository = AppSettingsRepository(
      readValues: () => values,
      saveSettings: (_) async {},
    );
    final container = ProviderContainer(
      overrides: [appSettingsRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    windowsGlassAvailable = true;
    addTearDown(() => windowsGlassAvailable = false);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(padding: const EdgeInsets.only(top: 32)),
            child: child!,
          ),
          home: const ExplorePage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final header = tester.getRect(find.byType(WindowsGlassHeader));
    final before = tester.getTopLeft(find.text('分区0')).dy;
    expect(before, greaterThanOrEqualTo(header.bottom));
    final scroll = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    scroll.position.jumpTo(65);
    await tester.pump();
    final after = tester.getTopLeft(find.text('分区0')).dy;
    expect(after, lessThan(header.bottom));
    expect(find.byType(GlassContainer), findsNWidgets(2));
    await container
        .read(appSettingsProvider.notifier)
        .setValue(AppSettingKeys.liquidGlassEnabled, '0');
    await tester.pumpAndSettle();
    expect(find.byType(GlassContainer), findsNothing);
    final scrollAfterSwitch = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(scrollAfterSwitch.position.pixels, closeTo(65, 0.01));
    expect(tester.takeException(), isNull);
  }, skip: !Platform.isWindows);
}
