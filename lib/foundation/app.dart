import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pica_comic/foundation/app_page_route.dart';
import 'package:pica_comic/foundation/log.dart';
import '../base.dart';

export 'state_controller.dart';
export 'widget_utils.dart';

/// 标记需要打开在根 Navigator 上的页面。
abstract class RootNavigatorPage {}

class App {
  // platform
  static bool get isAndroid => Platform.isAndroid;
  static bool get isIOS => Platform.isIOS;
  static bool get isWindows => Platform.isWindows;
  static bool get isLinux => Platform.isLinux;
  static bool get isMacOS => Platform.isMacOS;
  static bool get isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  static bool get isMobile => Platform.isAndroid || Platform.isIOS;

  static BuildContext? get globalContext => navigatorKey.currentContext;

  static final navigatorKey = GlobalKey<NavigatorState>();

  static GlobalKey<NavigatorState>? mainNavigatorKey;

  /// get ui mode
  static UiModes uiMode([BuildContext? context]) {
    context ??= globalContext;
    if (MediaQuery.of(context!).size.shortestSide < 600) {
      return UiModes.m1;
    } else if (!(MediaQuery.of(context).size.shortestSide < 600) &&
        !(MediaQuery.of(context).size.width > 1400)) {
      return UiModes.m2;
    } else {
      return UiModes.m3;
    }
  }

  /// Path to store app cache.
  ///
  /// **Warning: The end of String is not '/'**
  static late final String cachePath;

  /// Path to store app data.
  ///
  /// **Warning: The end of String is not '/'**
  static late final String dataPath;

  static Future<void> init() async {
    cachePath = (await getApplicationCacheDirectory()).path;
    dataPath = (await getApplicationSupportDirectory()).path;
  }

  static back(BuildContext context) {
    if (Navigator.canPop(context)) {
      Navigator.of(context).pop();
    }
  }

  static globalBack() {
    final rootNavigator = navigatorKey.currentState;
    if (rootNavigator != null && rootNavigator.canPop()) {
      rootNavigator.maybePop();
      return;
    }

    final mainNavigator = mainNavigatorKey?.currentState;
    if (mainNavigator != null && mainNavigator.canPop()) {
      mainNavigator.maybePop();
    }
  }

  static off(BuildContext context, Widget Function() page) {
    final targetPage = page();
    Log.i("App Status Going to Page /${targetPage.runtimeType}");
    _navigatorForPage(
      context,
      targetPage,
    ).pushReplacement(AppPageRoute(builder: (context) => targetPage));
  }

  static globalOff(Widget Function() page) {
    final targetPage = page();
    Log.i("App Status Going to Page /${targetPage.runtimeType}");
    _navigatorForPage(
      globalContext!,
      targetPage,
    ).pushReplacement(AppPageRoute(builder: (context) => targetPage));
  }

  static offAll(Widget Function() page) {
    Navigator.of(globalContext!).pushAndRemoveUntil(
      AppPageRoute(builder: (context) => page()),
      (route) => false,
    );
  }

  static Future<T?> to<T extends Object?>(
    BuildContext context,
    Widget Function() page, {
    bool enableIOSGesture = true,
  }) {
    final targetPage = page();
    Log.i("App Status Going to Page /${targetPage.runtimeType}");
    return _navigatorForPage(context, targetPage).push<T>(
      AppPageRoute(
        builder: (context) => targetPage,
        enableIOSGesture: enableIOSGesture,
      ),
    );
  }

  static Future<T?> globalTo<T extends Object?>(
    Widget Function() page, {
    bool preventDuplicates = false,
  }) {
    final targetPage = page();
    final navigator = _navigatorForPage(globalContext!, targetPage);
    return navigator.push<T>(AppPageRoute(builder: (context) => targetPage));
  }

  /// Windows 使用左侧导航栏 + 右侧内容区，普通页面应进入右侧的内部
  /// Navigator。阅读器和认证页需要覆盖整个窗口，因此保留根 Navigator。
  static NavigatorState _navigatorForPage(
    BuildContext context,
    Widget targetPage,
  ) {
    if (_shouldUseRootNavigator(targetPage)) {
      final rootNavigator = navigatorKey.currentState;
      if (rootNavigator != null) {
        return rootNavigator;
      }
    }

    final nearestNavigator = Navigator.of(context);
    if (App.isWindows && nearestNavigator == navigatorKey.currentState) {
      final mainNavigator = mainNavigatorKey?.currentState;
      if (mainNavigator != null) {
        return mainNavigator;
      }
    }
    return nearestNavigator;
  }

  static bool _shouldUseRootNavigator(Widget targetPage) {
    return targetPage is RootNavigatorPage;
  }

  static bool get enablePopGesture => isIOS;

  static String? _currentRoute() {
    return ModalRoute.of(globalContext!)?.toString();
  }

  static String? get currentRoute => _currentRoute();

  static bool get canPop =>
      (navigatorKey.currentState?.canPop() ?? false) ||
      (mainNavigatorKey?.currentState?.canPop() ?? false);

  static bool temporaryDisablePopGesture = false;

  static Locale get locale {
    Locale deviceLocale = PlatformDispatcher.instance.locale;
    if (deviceLocale.languageCode == "zh" &&
        deviceLocale.scriptCode == "Hant") {
      deviceLocale = const Locale("zh", "TW");
    }
    return switch (appdata.settings[50]) {
      "cn" => const Locale("zh", "CN"),
      "tw" => const Locale("zh", "TW"),
      "en" => const Locale("en", "US"),
      _ => deviceLocale,
    };
  }

  /// size of screen
  static Size screenSize(BuildContext context) => MediaQuery.of(context).size;

  static ColorScheme colors(BuildContext context) =>
      Theme.of(context).colorScheme;
}

enum UiModes {
  /// The screen have a short width. Usually the device is phone.
  m1,

  /// The screen's width is medium size. Usually the device is tablet.
  m2,

  /// The screen's width is long. Usually the device is PC.
  m3,
}
