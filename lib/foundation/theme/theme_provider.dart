import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/foundation/theme/app_mouse_cursor.dart';
import 'package:pica_comic/tools/prefs_helper.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'theme_provider.g.dart';

/// 主题设置的持久化状态。
class ThemeSettingsState {
  const ThemeSettingsState({
    required this.themeMode,
    required this.useDynamicColor,
    required this.seedColor,
    required this.isAmoled,
  });

  final ThemeMode themeMode;
  final bool useDynamicColor;
  final Color seedColor;
  final bool isAmoled;

  ThemeSettingsState copyWith({
    ThemeMode? themeMode,
    bool? useDynamicColor,
    Color? seedColor,
    bool? isAmoled,
  }) {
    return ThemeSettingsState(
      themeMode: themeMode ?? this.themeMode,
      useDynamicColor: useDynamicColor ?? this.useDynamicColor,
      seedColor: seedColor ?? this.seedColor,
      isAmoled: isAmoled ?? this.isAmoled,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ThemeSettingsState &&
        other.themeMode == themeMode &&
        other.useDynamicColor == useDynamicColor &&
        other.seedColor.toARGB32() == seedColor.toARGB32() &&
        other.isAmoled == isAmoled;
  }

  @override
  int get hashCode =>
      Object.hash(themeMode, useDynamicColor, seedColor.toARGB32(), isAmoled);
}

/// 系统动态颜色方案，由 [DynamicColorBuilder] 在应用入口处注入。
class DynamicColorSchemes {
  const DynamicColorSchemes({this.light, this.dark});

  final ColorScheme? light;
  final ColorScheme? dark;
}

/// 当前可用的动态颜色方案。
final dynamicColorSchemesProvider = Provider<DynamicColorSchemes>(
  (ref) => const DynamicColorSchemes(),
);

/// 应用主题的完整数据。
class ThemeBundle {
  const ThemeBundle({
    required this.themeMode,
    required this.lightTheme,
    required this.darkTheme,
    required this.lightColorScheme,
    required this.darkColorScheme,
  });

  final ThemeMode themeMode;
  final ThemeData lightTheme;
  final ThemeData darkTheme;
  final ColorScheme lightColorScheme;
  final ColorScheme darkColorScheme;
}

/// 主题设置 Provider。
@Riverpod(keepAlive: true)
class ThemeSettings extends _$ThemeSettings {
  static const _themeModeKey = 'pica_theme_mode';
  static const _dynamicColorKey = 'pica_theme_use_dynamic_color';
  static const _seedColorKey = 'pica_theme_seed_color';
  static const _amoledKey = 'pica_theme_amoled';

  static final _defaultSeedColor = Colors.blue[400]!;

  @override
  ThemeSettingsState build() {
    final modeIndex = PrefsHelper.getInt(_themeModeKey);
    final mode = modeIndex >= 0 && modeIndex < ThemeMode.values.length
        ? ThemeMode.values[modeIndex]
        : ThemeMode.system;
    final colorValue = PrefsHelper.getInt(
      _seedColorKey,
      _defaultSeedColor.toARGB32(),
    );

    return ThemeSettingsState(
      themeMode: mode,
      useDynamicColor: PrefsHelper.getBool(_dynamicColorKey, true),
      seedColor: Color(0xff000000 | (colorValue & 0x00ffffff)),
      isAmoled: PrefsHelper.getBool(_amoledKey),
    );
  }

  /// 设置主题模式。
  Future<void> setThemeMode(ThemeMode value) async {
    state = state.copyWith(themeMode: value);
    await PrefsHelper.setInt(_themeModeKey, value.index);
  }

  /// 设置是否使用系统动态颜色。
  Future<void> setUseDynamicColor(bool value) async {
    state = state.copyWith(useDynamicColor: value);
    await PrefsHelper.setBool(_dynamicColorKey, value);
  }

  /// 设置固定种子颜色。
  Future<void> setSeedColor(Color value) async {
    final rgb = value.toARGB32() & 0x00ffffff;
    state = state.copyWith(seedColor: Color(0xff000000 | rgb));
    await PrefsHelper.setInt(_seedColorKey, 0xff000000 | rgb);
  }

  /// 设置 AMOLED 深色背景。
  Future<void> setAmoled(bool value) async {
    state = state.copyWith(isAmoled: value);
    await PrefsHelper.setBool(_amoledKey, value);
  }
}

/// 根据主题设置生成 Material 主题数据。
@Riverpod(keepAlive: true)
ThemeBundle themeBundle(Ref ref) {
  final settings = ref.watch(themeSettingsProvider);
  final dynamicSchemes = ref.watch(dynamicColorSchemesProvider);

  final hasDynamicSchemes =
      settings.useDynamicColor &&
      dynamicSchemes.light != null &&
      dynamicSchemes.dark != null;
  final lightScheme = hasDynamicSchemes
      ? dynamicSchemes.light!.harmonized()
      : ColorScheme.fromSeed(seedColor: settings.seedColor);
  final darkScheme = hasDynamicSchemes
      ? dynamicSchemes.dark!.harmonized()
      : ColorScheme.fromSeed(
          seedColor: settings.seedColor,
          brightness: Brightness.dark,
        );

  return ThemeBundle(
    themeMode: settings.themeMode,
    lightColorScheme: lightScheme,
    darkColorScheme: darkScheme,
    lightTheme: _buildTheme(lightScheme, Brightness.light),
    darkTheme: _buildTheme(
      darkScheme,
      Brightness.dark,
      isAmoled: settings.isAmoled,
    ),
  );
}

ThemeData _buildTheme(
  ColorScheme colorScheme,
  Brightness brightness, {
  bool isAmoled = false,
}) {
  final fontFamily = App.isDesktop && appdata.appSettings.font.isNotEmpty
      ? appdata.appSettings.font
      : null;
  final isDark = brightness == Brightness.dark;
  final surfaceContainer = colorScheme.surfaceContainer;

  return ThemeData(
    brightness: brightness,
    useMaterial3: true,
    fontFamily: fontFamily,
    colorScheme: colorScheme,
    primaryColor: colorScheme.primary,
    scaffoldBackgroundColor: isDark && isAmoled
        ? Colors.black
        : colorScheme.surface,
    cardColor: surfaceContainer,
    canvasColor: surfaceContainer,
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      mouseCursor: appClickableMouseCursor,
    ),
    chipTheme: ChipThemeData(backgroundColor: surfaceContainer),
    checkboxTheme: const CheckboxThemeData(
      mouseCursor: appClickableMouseCursor,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surfaceContainer,
      titleTextStyle: TextStyle(
        fontFamily: fontFamily,
        fontSize: 22,
        color: colorScheme.onSurface,
      ),
      contentTextStyle: TextStyle(
        fontFamily: fontFamily,
        fontSize: 16,
        color: colorScheme.onSurfaceVariant,
      ),
    ),
    elevatedButtonTheme: const ElevatedButtonThemeData(
      style: ButtonStyle(mouseCursor: appClickableMouseCursor),
    ),
    filledButtonTheme: const FilledButtonThemeData(
      style: ButtonStyle(mouseCursor: appClickableMouseCursor),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      mouseCursor: appClickableMouseCursor,
    ),
    iconButtonTheme: const IconButtonThemeData(
      style: ButtonStyle(mouseCursor: appClickableMouseCursor),
    ),
    listTileTheme: const ListTileThemeData(
      mouseCursor: appClickableMouseCursor,
    ),
    menuButtonTheme: const MenuButtonThemeData(
      style: ButtonStyle(mouseCursor: appClickableMouseCursor),
    ),
    outlinedButtonTheme: const OutlinedButtonThemeData(
      style: ButtonStyle(mouseCursor: appClickableMouseCursor),
    ),
    popupMenuTheme: const PopupMenuThemeData(
      mouseCursor: appClickableMouseCursor,
    ),
    radioTheme: const RadioThemeData(mouseCursor: appClickableMouseCursor),
    sliderTheme: const SliderThemeData(mouseCursor: appClickableMouseCursor),
    switchTheme: const SwitchThemeData(mouseCursor: appClickableMouseCursor),
    tabBarTheme: const TabBarThemeData(
      dividerColor: Colors.transparent,
      mouseCursor: appClickableMouseCursor,
    ),
    textButtonTheme: const TextButtonThemeData(
      style: ButtonStyle(mouseCursor: appClickableMouseCursor),
    ),
  );
}
