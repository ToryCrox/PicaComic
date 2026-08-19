import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/foundation/theme/theme_provider.dart';
import 'package:pica_comic/tools/prefs_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PrefsHelper.init();
  });

  test('默认主题状态符合 PixEz 配置', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final state = container.read(themeSettingsProvider);
    expect(state.themeMode, ThemeMode.system);
    expect(state.useDynamicColor, isTrue);
    expect(state.seedColor, Colors.blue[400]);
    expect(state.isAmoled, isFalse);
  });

  test('主题状态可以保存并从独立 SharedPreferences 恢复', () async {
    final first = ProviderContainer();
    final notifier = first.read(themeSettingsProvider.notifier);
    await notifier.setThemeMode(ThemeMode.dark);
    await notifier.setUseDynamicColor(false);
    await notifier.setSeedColor(const Color(0xff42a5f5));
    await notifier.setAmoled(true);
    first.dispose();

    final restored = ProviderContainer();
    addTearDown(restored.dispose);
    final state = restored.read(themeSettingsProvider);
    expect(state.themeMode, ThemeMode.dark);
    expect(state.useDynamicColor, isFalse);
    expect(state.seedColor.toARGB32(), const Color(0xff42a5f5).toARGB32());
    expect(state.isAmoled, isTrue);
  });

  test('动态颜色可用时直接使用动态 ColorScheme', () {
    final dynamicLight = ColorScheme.fromSeed(
      seedColor: Colors.purple,
      brightness: Brightness.light,
    );
    final dynamicDark = ColorScheme.fromSeed(
      seedColor: Colors.purple,
      brightness: Brightness.dark,
    );
    final container = ProviderContainer(
      overrides: [
        dynamicColorSchemesProvider.overrideWithValue(
          DynamicColorSchemes(light: dynamicLight, dark: dynamicDark),
        ),
      ],
    );
    addTearDown(container.dispose);

    final bundle = container.read(themeBundleProvider);
    expect(bundle.lightColorScheme.primary, dynamicLight.primary);
    expect(bundle.darkColorScheme.primary, dynamicDark.primary);
  });

  test('动态颜色关闭或缺失时回退到固定种子色', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(themeSettingsProvider.notifier);
    await notifier.setUseDynamicColor(false);
    await notifier.setSeedColor(Colors.orange);

    final bundle = container.read(themeBundleProvider);
    expect(
      bundle.lightColorScheme.primary,
      ColorScheme.fromSeed(seedColor: Colors.orange).primary,
    );
    expect(
      bundle.darkColorScheme.primary,
      ColorScheme.fromSeed(
        seedColor: Colors.orange,
        brightness: Brightness.dark,
      ).primary,
    );
  });

  test('系统没有动态颜色方案时使用默认种子色', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final bundle = container.read(themeBundleProvider);
    expect(
      bundle.lightColorScheme.primary,
      ColorScheme.fromSeed(seedColor: Colors.blue[400]!).primary,
    );
    expect(
      bundle.darkColorScheme.primary,
      ColorScheme.fromSeed(
        seedColor: Colors.blue[400]!,
        brightness: Brightness.dark,
      ).primary,
    );
  });

  test('AMOLED 只改变深色主题的 scaffold 背景', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(themeSettingsProvider.notifier).setAmoled(true);

    final bundle = container.read(themeBundleProvider);
    expect(bundle.darkTheme.scaffoldBackgroundColor, Colors.black);
    expect(bundle.darkColorScheme.surface, isNot(Colors.black));
    expect(
      bundle.lightTheme.scaffoldBackgroundColor,
      bundle.lightColorScheme.surface,
    );
  });
}
