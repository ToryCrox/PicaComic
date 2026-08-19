import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/foundation/theme/theme_provider.dart';
import 'package:pica_comic/pages/settings/theme_page.dart';
import 'package:pica_comic/tools/prefs_helper.dart';
import 'package:pica_comic/tools/translations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await PrefsHelper.init();
    await AppTranslation.init();
  });

  setUp(() async {
    await PrefsHelper.remove('pica_theme_mode');
    await PrefsHelper.remove('pica_theme_use_dynamic_color');
    await PrefsHelper.remove('pica_theme_seed_color');
    await PrefsHelper.remove('pica_theme_amoled');
  });

  Future<ProviderContainer> pumpPage(WidgetTester tester) async {
    final container = ProviderContainer();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ThemePage()),
      ),
    );
    addTearDown(container.dispose);
    return container;
  }

  testWidgets('TabBar 可以切换主题模式', (tester) async {
    final container = await pumpPage(tester);
    await tester.tap(find.text('深色'));
    await tester.pump();
    expect(container.read(themeSettingsProvider).themeMode, ThemeMode.dark);
  });

  testWidgets('关闭动态颜色后显示种子颜色入口', (tester) async {
    final container = await pumpPage(tester);
    expect(find.text('种子颜色'), findsNothing);

    await tester.tap(find.byType(SwitchListTile).at(1));
    await tester.pump();
    expect(container.read(themeSettingsProvider).useDynamicColor, isFalse);
    expect(find.text('种子颜色'), findsOneWidget);
  });

  testWidgets('颜色选择器支持 HSV 调整、十六进制输入和取消', (tester) async {
    final container = await pumpPage(tester);
    await container
        .read(themeSettingsProvider.notifier)
        .setUseDynamicColor(false);
    await tester.pump();
    final original = container.read(themeSettingsProvider).seedColor;

    await tester.tap(find.text('种子颜色'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('theme-color-sv-picker')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('theme-color-hue-picker')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('theme-color-sv-picker')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('theme-color-hex-input')),
      '#ff0000',
    );
    await tester.pump();
    expect(find.text('#FF0000'), findsOneWidget);

    await tester.tap(find.byType(TextButton).at(1));
    await tester.pumpAndSettle();
    expect(
      container.read(themeSettingsProvider).seedColor.toARGB32(),
      original.toARGB32(),
    );
  });

  testWidgets('颜色选择器点击确定后保存颜色', (tester) async {
    final container = await pumpPage(tester);
    await container
        .read(themeSettingsProvider.notifier)
        .setUseDynamicColor(false);
    await tester.pump();
    await tester.tap(find.text('种子颜色'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('theme-color-hex-input')),
      '#123456',
    );
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(
      container.read(themeSettingsProvider).seedColor.toARGB32(),
      const Color(0xff123456).toARGB32(),
    );
  });
}
