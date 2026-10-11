import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/foundation/app_settings_provider.dart';
import 'package:pica_comic/network/network_config.dart';
import 'package:pica_comic/network/network_settings_provider.dart';
import 'package:pica_comic/pages/settings/settings_page.dart';
import 'package:pica_comic/tools/translations.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await AppTranslation.init();
  });

  for (final width in [300.0, 600.0]) {
    testWidgets('通用开关和选择器在宽度 $width 下响应仓库重载', (tester) async {
      final values = Map<String, String>.from(defaultAppSettings);
      final changes = StreamController<void>.broadcast();
      final saves = <bool>[];
      final repository = AppSettingsRepository(
        readValues: () => values,
        changes: changes.stream,
        notifyChanges: () => changes.add(null),
        saveSettings: (sync) async => saves.add(sync),
      );
      final container = ProviderContainer(
        overrides: [
          appSettingsRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(changes.close);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: width,
                  child: const Column(
                    children: [
                      SwitchSetting(
                        title: '翻页',
                        icon: Icon(Icons.touch_app),
                        settingKey: AppSettingKeys.readerTapToTurnPage,
                      ),
                      SelectSettingWithAppdata(
                        title: '列表',
                        icon: Icon(Icons.list),
                        settingKey: AppSettingKeys.comicsListDisplayMode,
                        options: ['连续', '分页'],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('连续'), findsOneWidget);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      values[AppSettingKeys.comicsListDisplayMode] = '1';
      values[AppSettingKeys.readerTapToTurnPage] = '0';
      changes.add(null);
      await tester.pump();
      expect(find.text('分页'), findsOneWidget);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(values[AppSettingKeys.readerTapToTurnPage], '1');
      expect(saves, [true]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('阅读面板响应导入值，并通过统一入口保存阅读模式', (tester) async {
    final values = Map<String, String>.from(defaultAppSettings);
    final changes = StreamController<void>.broadcast();
    final saves = <bool>[];
    final repository = AppSettingsRepository(
      readValues: () => values,
      changes: changes.stream,
      notifyChanges: () => changes.add(null),
      saveSettings: (sync) async => saves.add(sync),
    );
    final container = ProviderContainer(
      overrides: [appSettingsRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    addTearDown(changes.close);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: ReadingSettings(false)),
          ),
        ),
      ),
    );
    values[AppSettingKeys.readingMode] = '6';
    values[AppSettingKeys.autoPageInterval] = '20';
    changes.add(null);
    await tester.pump();
    final modeFinder = find.byWidgetPredicate(
      (widget) => widget is SelectSetting && widget.title == '阅读模式'.tl,
    );
    final mode = tester.widget<SelectSetting>(modeFinder);
    expect(mode.initialValue, 5);
    expect(tester.widget<Slider>(find.byType(Slider)).value, 20);
    mode.onChanged(0);
    await tester.pumpAndSettle();
    expect(values[AppSettingKeys.readingMode], '1');
    expect(saves, [true]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('网络页面显示 Provider 重载的协议和后端，代理弹窗保存后关闭', (tester) async {
    final values = Map<String, String>.from(defaultAppSettings);
    final changes = StreamController<void>.broadcast();
    final calls = <String>[];
    final repository = AppSettingsRepository(
      readValues: () => values,
      changes: changes.stream,
      notifyChanges: () => changes.add(null),
      saveSettings: (_) async => calls.add('settings'),
      saveData: (_) async => calls.add('data'),
    );
    final container = ProviderContainer(
      overrides: [
        appSettingsRepositoryProvider.overrideWithValue(repository),
        networkSettingsRuntimeProvider.overrideWithValue(
          NetworkSettingsRuntime(
            applyProxy: () async => calls.add('proxy'),
            applyClient: () async => calls.add('client'),
            reloadHosts: () => calls.add('hosts'),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(changes.close);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: NetworkSettings())),
        ),
      ),
    );
    values[AppSettingKeys.networkBackend] = 'dio';
    values[AppSettingKeys.networkProtocol] = 'http2';
    changes.add(null);
    await tester.pump();
    expect(
      tester
          .widget<DropdownButton<NetworkBackend>>(
            find.byType(DropdownButton<NetworkBackend>),
          )
          .value,
      NetworkBackend.dio,
    );
    expect(
      tester
          .widget<DropdownButton<NetworkProtocol>>(
            find.byType(DropdownButton<NetworkProtocol>),
          )
          .value,
      NetworkProtocol.http2,
    );
    await tester.tap(find.text('设置代理'.tl));
    await tester.pumpAndSettle();
    expect(find.byType(SimpleDialog), findsOneWidget);
    await tester.tap(find.text('确认'.tl));
    await tester.pumpAndSettle();
    expect(find.byType(SimpleDialog), findsNothing);
    expect(calls, ['data', 'proxy', 'client']);
    expect(values[AppSettingKeys.proxy], '0');
    expect(tester.takeException(), isNull);
  });
}
