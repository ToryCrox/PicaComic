import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/components/windows_glass_panel.dart';
import 'package:pica_comic/foundation/app_settings_provider.dart';

void main() {
  test('玻璃设置默认启用标准强度', () {
    final snapshot = AppSettingsSnapshot({});
    expect(snapshot.value(AppSettingKeys.liquidGlassEnabled), '1');
    expect(snapshot.value(AppSettingKeys.liquidGlassStrength), '1');
  });

  testWidgets('着色器不可用时显示普通面板', (tester) async {
    windowsGlassAvailable = false;
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: WindowsGlassPanel(
              fallback: Text('普通面板'),
              child: Text('玻璃面板'),
            ),
          ),
        ),
      ),
    );
    expect(find.text('普通面板'), findsOneWidget);
    expect(find.text('玻璃面板'), findsNothing);
  });

  testWidgets('Windows 玻璃开关和强度即时生效，关闭后恢复普通界面', (tester) async {
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
        child: const MaterialApp(
          home: Scaffold(
            body: WindowsGlassPanel(
              fallback: Text('普通面板'),
              child: Text('玻璃面板'),
            ),
          ),
        ),
      ),
    );
    expect(find.text('玻璃面板'), findsOneWidget);
    expect(
      tester.widget<GlassContainer>(find.byType(GlassContainer)).settings!.blur,
      7,
    );
    await container
        .read(appSettingsProvider.notifier)
        .setValue(AppSettingKeys.liquidGlassStrength, '2');
    await tester.pump();
    expect(
      tester.widget<GlassContainer>(find.byType(GlassContainer)).settings!.blur,
      10,
    );
    await container
        .read(appSettingsProvider.notifier)
        .setValue(AppSettingKeys.liquidGlassEnabled, '0');
    await tester.pump();
    expect(find.text('普通面板'), findsOneWidget);
    expect(find.byType(GlassContainer), findsNothing);
    expect(tester.takeException(), isNull);
  }, skip: !Platform.isWindows);

  testWidgets('玻璃浮层支持固有宽度布局', (tester) async {
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
        child: const MaterialApp(
          home: Scaffold(
            body: Center(
              child: FlyoutContent(title: '浮层', actions: []),
            ),
          ),
        ),
      ),
    );
    expect(find.text('浮层'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, skip: !Platform.isWindows);
}
