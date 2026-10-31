import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:pica_comic/components/windows_glass_app_bar.dart';
import 'package:pica_comic/components/windows_glass_panel.dart';
import 'package:pica_comic/foundation/app_settings_provider.dart';

void main() {
  testWidgets('普通标题栏覆盖顶部安全区并响应开关', (tester) async {
    final values = Map<String, String>.from(defaultAppSettings);
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
          home: Scaffold(
            appBar: WindowsGlassAppBar(
              child: AppBar(
                title: const Text('标题'),
                actions: [
                  IconButton(onPressed: () {}, icon: const Icon(Icons.search)),
                ],
              ),
            ),
            body: const Text('正文'),
          ),
        ),
      ),
    );
    final appBar = tester.getRect(find.byType(WindowsGlassAppBar));
    final glass = tester.getRect(find.byType(GlassContainer));
    expect(appBar.top, 0);
    expect(glass.top, lessThanOrEqualTo(appBar.top));
    expect(glass.bottom, greaterThanOrEqualTo(appBar.bottom));
    expect(find.text('标题'), findsOneWidget);
    expect(find.byIcon(Icons.search), findsOneWidget);
    await container
        .read(appSettingsProvider.notifier)
        .setValue(AppSettingKeys.liquidGlassEnabled, '0');
    await tester.pumpAndSettle();
    expect(find.byType(GlassContainer), findsNothing);
    expect(find.text('标题'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, skip: !Platform.isWindows);

  testWidgets('固定标题栏滚动后保留标题和背景', (tester) async {
    final repository = AppSettingsRepository(
      readValues: () => <String, String>{},
    );
    windowsGlassAvailable = true;
    addTearDown(() => windowsGlassAvailable = false);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSettingsRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                WindowsGlassSliverAppBar(
                  child: SliverAppBar(
                    pinned: true,
                    title: const Text('滚动标题'),
                    actions: [
                      IconButton(
                        onPressed: () {},
                        icon: const Icon(Icons.search),
                      ),
                    ],
                  ),
                ),
                SliverList.builder(
                  itemCount: 30,
                  itemBuilder: (_, i) =>
                      SizedBox(height: 80, child: Text('内容$i')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(find.text('滚动标题'), findsOneWidget);
    expect(find.byIcon(Icons.search), findsOneWidget);
    expect(find.byType(GlassContainer), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, skip: !Platform.isWindows);

  testWidgets('纵向布局中的标题栏可正常布局', (tester) async {
    final repository = AppSettingsRepository(
      readValues: () => <String, String>{},
    );
    windowsGlassAvailable = true;
    addTearDown(() => windowsGlassAvailable = false);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSettingsRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                WindowsGlassAppBar(child: AppBar(title: const Text('详情标题'))),
                const Expanded(child: Text('详情正文')),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.text('详情标题'), findsOneWidget);
    expect(find.text('详情正文'), findsOneWidget);
    expect(find.byType(GlassContainer), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, skip: !Platform.isWindows);
}
