import 'dart:async';
import 'dart:ui';

import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/components/window_frame.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/foundation/app_page_route.dart';
import 'package:pica_comic/foundation/log.dart';
import 'package:pica_comic/foundation/theme/theme_provider.dart';
import 'package:pica_comic/init.dart';
import 'package:pica_comic/network/network_client_manager.dart';
import 'package:pica_comic/network/http_client.dart';
import 'package:pica_comic/pages/auth_page.dart';
import 'package:pica_comic/pages/comic_page/adapters_register.dart';
import 'package:pica_comic/pages/main_page.dart';
import 'package:pica_comic/pages/welcome_page.dart';
import 'package:pica_comic/tools/block_screenshot.dart';
import 'package:pica_comic/tools/mouse_listener.dart';
import 'package:pica_comic/tools/tags_translation.dart';
import 'package:window_manager/window_manager.dart';
import 'package:worker_manager/worker_manager.dart';

import 'components/components.dart';
import 'network/webdav.dart';

bool notFirstUse = false;

void main(List<String> args) {
  if (runWebViewTitleBarWidget(args)) {
    return;
  }

  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      await initBase();
      registerAllComicPageAdapters();
      await workerManager.init(isolatesCount: 3, dynamicSpawning: false);
      FlutterError.onError = (details) {
        Log.e("Unhandled Exception ${details.exception}\n${details.stack}");
      };
      notFirstUse = appdata.firstUse[3] == "1";
      setNetworkProxy();
      runApp(const ProviderScope(child: AppBootstrap()));
      if (App.isDesktop) {
        await windowManager.ensureInitialized();
        windowManager.waitUntilReadyToShow().then((_) async {
          await windowManager.setTitleBarStyle(
            TitleBarStyle.hidden,
            windowButtonVisibility: App.isMacOS,
          );
          if (App.isLinux) {
            await windowManager.setBackgroundColor(Colors.transparent);
          }
          await windowManager.setMinimumSize(const Size(500, 600));
          if (!App.isLinux) {
            // https://github.com/leanflutter/window_manager/issues/460
            var placement = await WindowPlacement.loadFromFile();
            await placement.applyToWindow();
            await windowManager.show();
            WindowPlacement.loop();
          }
        });
      }
    },
    (error, stack) {
      Log.e("Unhandled Exception $error\n$stack");
    },
  );
}

/// 在 ProviderScope 内完成网络客户端和应用服务初始化。
class AppBootstrap extends ConsumerStatefulWidget {
  const AppBootstrap({super.key});

  @override
  ConsumerState<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends ConsumerState<AppBootstrap> {
  late final Future<void> _initialization;

  @override
  void initState() {
    super.initState();
    _initialization = _initialize();
  }

  Future<void> _initialize() async {
    await ref.read(networkClientManagerProvider).initialize();
    await initServices();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initialization,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const MaterialApp(
            home: Scaffold(body: Center(child: CircularProgressIndicator())),
          );
        }
        if (snapshot.hasError) {
          return MaterialApp(
            home: Scaffold(
              body: Center(child: Text('初始化失败: ${snapshot.error}')),
            ),
          );
        }
        return const MyApp();
      },
    );
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  static void Function()? updater;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  DateTime time = DateTime.fromMillisecondsSinceEpoch(0);

  bool forceRebuild = false;

  OverlayEntry? hideContentOverlay;

  void hideContent() {
    if (hideContentOverlay != null) return;
    hideContentOverlay = OverlayEntry(
      builder: (context) => Container(
        width: MediaQuery.of(context).size.width,
        height: MediaQuery.of(context).size.width,
        color: Theme.of(context).colorScheme.surface,
      ),
    );
    OverlayWidget.addOverlay(hideContentOverlay!);
  }

  void showContent() {
    hideContentOverlay = null;
    OverlayWidget.removeAll();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    bool enableAuth = appdata.settings[13] == "1";
    if (App.isAndroid && appdata.settings[38] == "1") {
      try {
        FlutterDisplayMode.setHighRefreshRate();
      } catch (e) {
        // ignore
      }
    }
    setNetworkProxy();
    unawaited(networkClientManager.applySettings());
    scheduleMicrotask(() {
      if (state == AppLifecycleState.hidden && enableAuth) {
        if (!AuthPage.lock && appdata.settings[13] == "1") {
          AuthPage.initial = false;
          AuthPage.lock = true;
          App.to(App.globalContext!, () => const AuthPage());
        }
      }

      if (state == AppLifecycleState.inactive && enableAuth) {
        hideContent();
      } else if (state == AppLifecycleState.resumed) {
        showContent();
        Future.delayed(const Duration(milliseconds: 200), checkClipboard);
      }

      if (DateTime.now().millisecondsSinceEpoch - time.millisecondsSinceEpoch >
          7200000) {
        Webdav.syncData();
        time = DateTime.now();
      }
    });
  }

  @override
  void initState() {
    MyApp.updater = () => setState(() => forceRebuild = true);
    time = DateTime.now();
    TagsTranslation.readData();
    if (App.isAndroid && appdata.settings[38] == "1") {
      try {
        FlutterDisplayMode.setHighRefreshRate();
      } finally {}
    }
    listenMouseSideButtonToBack();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    WidgetsBinding.instance.addObserver(this);
    notifications.init();
    if (appdata.settings[12] == "1") {
      blockScreenshot();
    }
    PaintingBinding.instance.imageCache.maximumSizeBytes = 400 * 1024 * 1024;
    PaintingBinding.instance.imageCache.maximumSize = 4000;
    super.initState();
  }

  @override
  void didChangePlatformBrightness() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (forceRebuild) {
      forceRebuild = false;
      void rebuild(Element el) {
        el.markNeedsBuild();
        el.visitChildren(rebuild);
      }

      (context as Element).visitChildren(rebuild);
    }
    return PopScope(
      canPop: false,
      child: DynamicColorBuilder(
        builder: (light, dark) {
          return ProviderScope(
            overrides: [
              dynamicColorSchemesProvider.overrideWithValue(
                DynamicColorSchemes(light: light, dark: dark),
              ),
            ],
            child: Consumer(
              builder: (context, ref, child) {
                final themeBundle = ref.watch(themeBundleProvider);
                return MaterialApp(
                  title: 'Pica Comic',
                  debugShowCheckedModeBanner: false,
                  navigatorKey: App.navigatorKey,
                  theme: themeBundle.lightTheme,
                  darkTheme: themeBundle.darkTheme,
                  themeMode: themeBundle.themeMode,
                  onGenerateRoute: (settings) => AppPageRoute(
                    builder: (context) => notFirstUse
                        ? (appdata.settings[13] == "1"
                              ? const AuthPage()
                              : const MainPage())
                        : const WelcomePage(),
                  ),
                  localizationsDelegates: const [
                    GlobalMaterialLocalizations.delegate,
                    GlobalWidgetsLocalizations.delegate,
                    GlobalCupertinoLocalizations.delegate,
                  ],
                  supportedLocales: const [
                    Locale('zh', 'CN'),
                    Locale('zh', 'TW'),
                    Locale('en', 'US'),
                  ],
                  scrollBehavior: fixScrollBehavior,
                  builder: (context, widget) {
                    ErrorWidget.builder = (details) {
                      Log.e(
                        "Unhandled Exception ${details.exception}\n${details.stack}",
                      );
                      return Material(
                        child: Center(
                          child: Text(details.exception.toString()),
                        ),
                      );
                    };
                    if (widget != null) {
                      widget = OverlayWidget(widget);
                      if (App.isDesktop) {
                        widget = Shortcuts(
                          shortcuts: {
                            LogicalKeySet(
                              LogicalKeyboardKey.escape,
                            ): VoidCallbackIntent(() {
                              if (App.canPop) {
                                App.globalBack();
                              } else {
                                App.mainNavigatorKey?.currentContext?.pop();
                              }
                            }),
                          },
                          child: WindowFrame(widget),
                        );
                      }
                      return _SystemUiProvider(widget);
                    }
                    throw ('widget is null');
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _SystemUiProvider extends StatelessWidget {
  const _SystemUiProvider(this.child);

  final Widget child;

  @override
  Widget build(BuildContext context) {
    var brightness = Theme.of(context).brightness;
    SystemUiOverlayStyle systemUiStyle;
    if (brightness == Brightness.light) {
      systemUiStyle = SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
      );
    } else {
      systemUiStyle = SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
      );
    }
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: systemUiStyle,
      child: child,
    );
  }
}

final fixScrollBehavior = const MaterialScrollBehavior().copyWith(
  scrollbars: true,
  //physics: MBouncingScrollPhysics(),
  dragDevices: {
    PointerDeviceKind.mouse,
    PointerDeviceKind.touch,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
    PointerDeviceKind.trackpad,
  },
);
