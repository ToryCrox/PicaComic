import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/components/windows_glass_panel.dart';
import 'package:pica_comic/foundation/app_settings_provider.dart';

void main() {
  testWidgets('右键菜单保留禁用状态、返回值和关闭回调', (tester) async {
    final values = Map<String, String>.from(defaultAppSettings);
    final repository = AppSettingsRepository(
      readValues: () => values,
      saveSettings: (_) async {},
    );
    windowsGlassAvailable = true;
    addTearDown(() => windowsGlassAvailable = false);
    int? result;
    var tapped = false;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSettingsRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await showContextMenu<int>(
                    context: context,
                    globalPosition: const Offset(790, 590),
                    items: [
                      popupMenuItem<int>(text: '禁用项', value: 1, enabled: false),
                      popupMenuItem<int>(
                        text: '执行',
                        value: 2,
                        onTap: () => tapped = true,
                      ),
                    ],
                  );
                },
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.byType(GlassContainer), findsOneWidget);
    await tester.tap(find.text('禁用项'));
    await tester.pump();
    expect(find.text('执行'), findsOneWidget);
    await tester.tap(find.text('执行'));
    await tester.pumpAndSettle();
    expect(result, 2);
    expect(tapped, isTrue);
    expect(tester.takeException(), isNull);
  }, skip: !Platform.isWindows);

  testWidgets('关闭效果时按钮使用原生菜单', (tester) async {
    final values = Map<String, String>.from(defaultAppSettings)
      ..[AppSettingKeys.liquidGlassEnabled] = '0';
    final repository = AppSettingsRepository(readValues: () => values);
    windowsGlassAvailable = true;
    addTearDown(() => windowsGlassAvailable = false);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSettingsRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: WindowsGlassPopupMenuButton<int>(
              itemBuilder: (_) => [
                const PopupMenuItem(value: 1, child: Text('选项')),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.byType(PopupMenuButton<int>), findsOneWidget);
    await tester.tap(find.byType(PopupMenuButton<int>));
    await tester.pumpAndSettle();
    expect(find.text('选项'), findsOneWidget);
    expect(find.byType(GlassContainer), findsNothing);
  }, skip: !Platform.isWindows);

  testWidgets('排序筛选菜单能显示、选择和关闭', (tester) async {
    final repository = AppSettingsRepository(
      readValues: () => <String, String>{},
    );
    windowsGlassAvailable = true;
    addTearDown(() => windowsGlassAvailable = false);
    var selected = false;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSettingsRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: WindowsGlassMenuAnchor(
              menuChildren: [
                MenuItemButton(
                  onPressed: () => selected = true,
                  child: const Text('按时间排序'),
                ),
                const Divider(),
                MenuItemButton(onPressed: () {}, child: const Text('按名称排序')),
              ],
              builder: (context, controller, child) => TextButton(
                onPressed: controller.open,
                child: const Text('排序'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('排序'));
    await tester.pumpAndSettle();
    expect(find.byType(GlassContainer), findsOneWidget);
    await tester.tap(find.text('按时间排序'));
    await tester.pumpAndSettle();
    expect(selected, isTrue);
    expect(find.text('按时间排序'), findsNothing);
    expect(tester.takeException(), isNull);
  }, skip: !Platform.isWindows);

  testWidgets('玻璃菜单支持键盘移动焦点并选择', (tester) async {
    final repository = AppSettingsRepository(
      readValues: () => <String, String>{},
    );
    windowsGlassAvailable = true;
    addTearDown(() => windowsGlassAvailable = false);
    int? selected;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSettingsRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: WindowsGlassPopupMenuButton<int>(
              icon: const Icon(Icons.more_horiz),
              onSelected: (value) => selected = value,
              itemBuilder: (_) => [
                const PopupMenuItem(value: 1, child: Text('第一项')),
                const PopupMenuItem(value: 2, child: Text('第二项')),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(selected, 2);
    expect(tester.takeException(), isNull);
  }, skip: !Platform.isWindows);

  testWidgets('长右键菜单可滚动，Escape 可关闭', (tester) async {
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
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showContextMenu<void>(
                  context: context,
                  globalPosition: const Offset(795, 595),
                  items: List.generate(
                    30,
                    (i) => popupMenuItem<void>(text: '项目$i', onTap: () {}),
                  ),
                ),
                child: const Text('打开长菜单'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开长菜单'));
    await tester.pumpAndSettle();
    expect(find.byType(GlassContainer), findsOneWidget);
    final rect = tester.getRect(find.byType(GlassContainer));
    expect(rect.right, lessThanOrEqualTo(800));
    expect(rect.bottom, lessThanOrEqualTo(600));
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(find.text('项目20'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(GlassContainer), findsNothing);
    expect(tester.takeException(), isNull);
  }, skip: !Platform.isWindows);

  testWidgets('长菜单打开时显示当前选中项', (tester) async {
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
            body: WindowsGlassPopupMenuButton<int>(
              icon: const Icon(Icons.more_horiz),
              initialValue: 25,
              itemBuilder: (_) => List.generate(
                30,
                (i) => PopupMenuItem<int>(value: i, child: Text('选项$i')),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    final selected = tester.getRect(find.text('选项25'));
    final menu = tester.getRect(find.byType(GlassContainer));
    expect(selected.top, greaterThanOrEqualTo(menu.top));
    expect(selected.bottom, lessThanOrEqualTo(menu.bottom));
    expect(tester.takeException(), isNull);
  }, skip: !Platform.isWindows);
}
