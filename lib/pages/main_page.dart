import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/foundation/app_page_route.dart';
import 'package:pica_comic/foundation/startup_metrics.dart';
import 'package:pica_comic/network/update.dart';
import 'package:pica_comic/pages/download/download_page.dart';
import 'package:pica_comic/pages/local/local_comic_page.dart';
import 'package:pica_comic/tools/app_links.dart';
import 'package:pica_comic/tools/translations.dart';
import 'package:pica_comic/network/download/download_manager.dart';
import 'download/download_providers.dart';
import 'update_providers.dart';
import 'category_page.dart';
import 'explore_page.dart';
import 'favorites/main_favorites_page.dart';
import 'pre_search_page.dart';
import 'settings/settings_page.dart';
import 'settings/theme_page.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:pica_comic/foundation/app.dart';
import 'me_page.dart';

bool _haveClipboardDialog = false;

void checkClipboard() async {
  if (appdata.settings[61] == "0") {
    return;
  }
  var data = await Clipboard.getData(Clipboard.kTextPlain);
  if (data?.text != null && canHandle(data!.text!)) {
    await Future.delayed(const Duration(milliseconds: 200));
    if (_haveClipboardDialog) {
      return;
    }
    _haveClipboardDialog = true;
    await showDialog(
      context: App.globalContext!,
      builder: (context) => ContentDialog(
        title: "发现剪切板中的链接".tl,
        content: Text(data.text!),
        actions: [
          TextButton(
            onPressed: () {
              App.globalContext!.pop();
              handleAppLinks(Uri.parse(data.text!));
            },
            child: Text("打开".tl),
          ),
        ],
      ),
    );
    _haveClipboardDialog = false;
  }
}

class MainPage extends ConsumerStatefulWidget {
  const MainPage({Key? key}) : super(key: key);

  static MainPageState of(BuildContext context) {
    return context.findAncestorStateOfType<MainPageState>()!;
  }

  @override
  ConsumerState<MainPage> createState() => MainPageState();
}

class MainPageState extends ConsumerState<MainPage> {
  GlobalKey<NavigatorState>? _navigatorKey;

  late final NaviObserver _observer;
  late final HeroController _heroController;

  void to(Widget Function() widget, {bool preventDuplicate = false}) async {
    if (preventDuplicate) {
      var page = widget();
      if ("/${page.runtimeType}" == _observer.routes.last.toString()) return;
    }
    App.to(_navigatorKey!.currentContext!, widget);
  }

  void back() {
    _navigatorKey!.currentContext!.pop();
  }

  List<Widget> get _pages => [
    const MePage(),
    FavoritesPage(),
    ExplorePage(key: Key(appdata.appSettings.explorePages.length.toString())),
    const AllCategoryPage(),
    const DownloadPage(showBack: false),
    const LocalComicPage(),
  ];

  void _showUpdateDialog(String info) {
    if (!mounted) return;
    showDialog(
      context: App.globalContext!,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text("有可用更新".tl),
          content: Text(info),
          actions: [
            TextButton(
              onPressed: () {
                dialogContext.pop();
                appdata.settings[2] = "0";
                appdata.writeData();
              },
              child: const Text("关闭更新检查"),
            ),
            TextButton(onPressed: dialogContext.pop, child: Text("取消".tl)),
            TextButton(
              onPressed: () {
                getDownloadUrl().then((s) {
                  launchUrlString(s, mode: LaunchMode.externalApplication);
                });
              },
              child: Text("下载".tl),
            ),
          ],
        );
      },
    );
  }

  bool _downloadPromptShown = false;

  void _showDownloadPrompt() {
    if (!mounted || _downloadPromptShown) return;
    _downloadPromptShown = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text("下载管理器".tl),
          content: Text("继续未完成的下载?".tl),
          actions: [
            TextButton(onPressed: dialogContext.pop, child: Text("否".tl)),
            TextButton(
              onPressed: () {
                downloadManager.start();
                dialogContext.pop();
              },
              child: Text("是".tl),
            ),
          ],
        );
      },
    );
  }

  Future<void> _initializeNotifications() async {
    try {
      await notifications.init();
      await notifications.requestPermission();
      await notifications.cancelAll();
    } catch (_) {
      // 通知权限失败不应影响页面交互。
    }
  }

  @override
  void initState() {
    _navigatorKey = GlobalKey();
    App.mainNavigatorKey = _navigatorKey;
    if (appdata.firstUse[3] == "0") {
      appdata.firstUse[3] = "1";
      appdata.writeData();
    }

    Future.delayed(const Duration(milliseconds: 300), checkClipboard);
    _observer = NaviObserver();
    _heroController = HeroController();
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      startupMetrics.mark('Home interactive');
      unawaited(_initializeNotifications());
      ref.read(updateCheckProvider);
      ref.read(pendingDownloadsProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(updateCheckProvider, (previous, next) {
      next.when(
        data: (info) {
          if (info != null) _showUpdateDialog(info);
        },
        loading: () {},
        error: (_, __) {},
      );
    });
    ref.listen(pendingDownloadsProvider, (previous, next) {
      next.when(
        data: (pending) {
          if (pending) _showDownloadPrompt();
        },
        loading: () {},
        error: (_, __) {},
      );
    });
    return NaviPane(
      initialPage: int.parse(appdata.settings[23]),
      observer: _observer,
      paneItems: [
        PaneItemEntry(
          label: '我'.tl,
          icon: Icons.person_outline,
          activeIcon: Icons.person,
        ),
        PaneItemEntry(
          label: '收藏'.tl,
          icon: Icons.local_activity_outlined,
          activeIcon: Icons.local_activity,
        ),
        PaneItemEntry(
          label: '探索'.tl,
          icon: Icons.explore_outlined,
          activeIcon: Icons.explore,
        ),
        PaneItemEntry(
          label: '分类'.tl,
          icon: Icons.account_tree_outlined,
          activeIcon: Icons.account_tree,
        ),
        PaneItemEntry(
          label: '下载'.tl,
          icon: Icons.download_outlined,
          activeIcon: Icons.download,
        ),
        PaneItemEntry(
          label: '本地'.tl,
          icon: Icons.local_library_outlined,
          activeIcon: Icons.local_library,
        ),
      ],
      paneActions: [
        PaneActionEntry(
          icon: Icons.search,
          label: "搜索".tl,
          onTap: () => to(() => PreSearchPage(), preventDuplicate: true),
        ),
        PaneActionEntry(
          icon: Icons.palette_outlined,
          label: "主题设置".tl,
          onTap: () =>
              ThemePage.open(context: _navigatorKey?.currentContext ?? context),
        ),
        PaneActionEntry(
          icon: Icons.settings,
          label: "设置".tl,
          onTap: () => SettingsPage.open(
            context: _navigatorKey?.currentContext ?? context,
          ),
        ),
      ],
      pageBuilder: (index) {
        return Navigator(
          observers: [_heroController, _observer],
          key: _navigatorKey,
          onGenerateRoute: (settings) => AppPageRoute(
            preventRebuild: false,
            isRootRoute: true,
            builder: (context) {
              return NaviPaddingWidget(child: _pages[index]);
            },
          ),
        );
      },
      onPageChange: (index) {
        HapticFeedback.selectionClick();
        _navigatorKey!.currentState?.pushAndRemoveUntil(
          AppPageRoute(
            preventRebuild: false,
            isRootRoute: true,
            builder: (context) {
              return NaviPaddingWidget(child: _pages[index]);
            },
          ),
          (route) => false,
        );
      },
    );
  }
}
