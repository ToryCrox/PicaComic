import 'dart:async';
import 'dart:io' as io;

import 'package:app_links/app_links.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:pica_comic/comic_source/comic_source.dart';
import 'package:pica_comic/foundation/cache_manager.dart';
import 'package:pica_comic/foundation/log.dart';
import 'package:pica_comic/foundation/startup_metrics.dart';
import 'package:pica_comic/network/cookie_jar.dart';
import 'package:pica_comic/network/http_client.dart';
import 'package:pica_comic/network/http_proxy.dart';
import 'package:pica_comic/network/network_client_manager.dart';
import 'package:pica_comic/network/picacg_network/models.dart';
import 'package:pica_comic/network/webdav.dart';
import 'package:pica_comic/tools/app_links.dart';
import 'package:pica_comic/tools/background_service.dart';
import 'package:pica_comic/tools/cache_auto_clear.dart';
import 'package:pica_comic/tools/io_extensions.dart';
import 'package:pica_comic/tools/io_tools.dart';
import 'package:pica_comic/tools/tags_translation.dart';
import 'package:pica_comic/tools/translations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter/foundation.dart';

import 'ai/ai.dart';
import 'base.dart';
import 'comic_source/built_in/ehentai.dart';
import 'comic_source/built_in/ht_manga.dart';
import 'comic_source/built_in/jm.dart';
import 'comic_source/built_in/nhentai.dart';
import 'comic_source/built_in/picacg.dart';
import 'foundation/app.dart';
import 'network/nhentai_network/nhentai_main_network.dart';
import 'tools/prefs_helper.dart';
import 'package:logger/logger.dart';

/// 初始化首屏必须的基础环境。
///
/// 功能数据库、worker 和后台网络任务由各自功能在首次使用时初始化，不能
/// 放在这里阻塞首屏。此函数保留为普通 Future，避免把启动流程耦合到状态管理。
Future<void> initBase() => initializeCore();

/// 初始化首屏必须的基础环境。
Future<void> initializeCore({void Function()? configureNetworkClient}) async {
  final stopwatch = Stopwatch()..start();

  // 应用目录与偏好设置互不依赖，并行准备以缩短核心阶段。
  await Future.wait([App.init(), PrefsHelper.init()]);
  Log.i("App Status Start initialization.");
  await appdata.readData();
  // 网络客户端的监控桥接会创建日志控制器，因此必须等持久化设置加载后
  // 再注入，避免控制器把默认开关状态当成实际状态。
  configureNetworkClient?.call();

  // 应用设置决定日志等级，但不应因为日志配置失败而阻塞启动。
  try {
    final code = appdata.settings.length > 90 ? appdata.settings[90] : 'auto';
    final level = switch (code) {
      'trace' => Level.trace,
      'debug' => Level.debug,
      'info' => Level.info,
      'warning' => Level.warning,
      'error' => Level.error,
      _ => kReleaseMode ? Level.info : Level.trace,
    };
    setLoggerLevel(level);
  } catch (e, s) {
    Log.w('Failed to apply log level.\n$e\n$s');
  }

  // CookieJar 的数据库在后台打开；网络拦截器会等待它完成。
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  SingleInstanceCookieJar("${App.dataPath}/cookies.db");
  HttpProxyServer.createConfigFile();
  await checkDownloadPath();
  await _checkOldData();

  CacheManager().setLimitSize(appdata.appSettings.cacheLimit);

  // 这些数据会在首屏构建时被同步读取，必须在 MyApp 之前完成。
  await Future.wait([
    AppTranslation.init(),
    ComicSource.init(initializeRuntime: false),
  ]);
  // 这些默认值属于本地配置，不能等到后台运行时初始化后才提供给首屏。
  if (picacg.data['appChannel'] == null) {
    picacg.data['appChannel'] = '3';
  }
  if (picacg.data['imageQuality'] == null) {
    picacg.data['imageQuality'] = 'original';
  }

  // 只创建 Dio 和基础适配器；rhttp、代理和其他后台工作延后处理。
  networkClientManager.prepare();
  startupMetrics.mark('Core initialization completed');
  Log.i('Core initialization completed in ${stopwatch.elapsedMilliseconds}ms');
}

/// 启动首帧后的后台基础设施。
///
/// 这里不初始化下载、收藏和历史数据库，它们由各自的 Riverpod Provider
/// 在功能真正被使用时懒加载。
void startDeferredServices() {
  unawaited(_startDeferredServices());
}

/// 注册深链接监听。监听本身很轻量，提前注册可避免应用首帧期间丢失
/// Android 的外部链接；真正的页面导航仍会等待主 Navigator 创建完成。
void listenAppLinks() {
  if (!App.isAndroid) return;
  final appLinks = AppLinks();
  appLinks.allUriLinkStream.listen((uri) async {
    while (App.mainNavigatorKey == null) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    handleAppLinks(uri);
  });
}

Future<void> _startDeferredServices() async {
  // 网络后端切换不会阻塞首页；Switching adapter 可安全替换空闲连接。
  unawaited(networkClientManager.applyPreferredBackend());
  unawaited(ComicSource.initRuntime());
  unawaited(setNetworkProxy());
  unawaited(
    Future<void>.delayed(const Duration(milliseconds: 300), Webdav.syncData),
  );
  unawaited(startClearCache());
  unawaited(aiSettings.init());
  unawaited(notifications.init());
  unawaited(TagsTranslation.readData());

  if (appdata.settings[58] == "1") {
    HttpProxyServer.startServer();
  }

  if (App.isMobile) {
    await initializeWorkmanager();
  }

  unawaited(_cleanupLegacyCache());
}

Future<void> _cleanupLegacyCache() async {
  try {
    if (io.File("${App.dataPath}/cache.json").existsSync()) {
      io.File("${App.dataPath}/cache.json").deleteIgnoreError();
    }
    for (final path in [
      "${App.cachePath}/imageCache",
      "${App.cachePath}/cachedNetwork",
    ]) {
      final directory = io.Directory(path);
      if (directory.existsSync()) {
        await directory.deleteIgnoreError(recursive: true);
      }
    }
  } catch (e, s) {
    Log.w('Failed to clean legacy cache.\n$e\n$s');
  }
}

Future<void> _checkOldData() async {
  try {
    if (int.parse(appdata.settings[17]) >= 4) {
      appdata.settings[17] = '0';
    }
    if (int.parse(appdata.settings[40]) > 40) {
      appdata.settings[40] = '40';
    }
    appdata.blockingKeyword.removeWhere((value) => value.isEmpty);

    if (io.Directory("${App.dataPath}/comic_source/cookies/").existsSync() ||
        io.Directory("${App.dataPath}/eh_cookies").existsSync() ||
        io.Directory("${App.dataPath}/comic_source/cookies").existsSync()) {
      // cookies, old version use package cookie_jar
      final cookieJars = [
        PersistCookieJar(storage: FileStorage("${App.dataPath}/cookies")),
        PersistCookieJar(storage: FileStorage("${App.dataPath}/eh_cookies")),
        PersistCookieJar(
          storage: FileStorage("${App.dataPath}/comic_source/cookies/"),
        ),
      ];
      var cookies = <io.Cookie>[];
      for (var cookie in (await cookieJars[0].loadForRequest(
        Uri.parse("https://nhentai.net"),
      ))) {
        cookie.domain ??= ".nhentai.net";
        cookies.add(cookie);
      }
      for (var cookie in (await cookieJars[1].loadForRequest(
        Uri.parse("https://e-hentai.org"),
      ))) {
        cookie.domain ??= ".e-hentai.org";
        cookies.add(cookie);
      }
      for (var cookie in (await cookieJars[1].loadForRequest(
        Uri.parse("https://exhentai.org"),
      ))) {
        cookie.domain ??= ".exhentai.org";
        cookies.add(cookie);
      }
      try {
        for (var file in io.Directory(
          "${App.dataPath}/comic_source/cookies/",
        ).listSync()) {
          var domain = file.path.split("/").last;
          if (domain == '.domains' || domain == '.index') {
            continue;
          }
          if (domain.startsWith('.')) {
            domain = domain.substring(1);
          }
          for (var cookie in (await cookieJars[2].loadForRequest(
            Uri.parse("https://$domain"),
          ))) {
            cookie.domain ??= ".$domain";
            cookies.add(cookie);
          }
        }
      } finally {}
      if (io.Directory("${App.dataPath}/cookies").existsSync()) {
        io.Directory("${App.dataPath}/cookies").deleteSync(recursive: true);
      }
      if (io.Directory("${App.dataPath}/eh_cookies").existsSync()) {
        io.Directory("${App.dataPath}/eh_cookies").deleteSync(recursive: true);
      }
      if (io.Directory("${App.dataPath}/comic_source/cookies").existsSync()) {
        io.Directory(
          "${App.dataPath}/comic_source/cookies",
        ).deleteSync(recursive: true);
      }
    }

    await _checkAccountData();
  } catch (e, s) {
    Log.e("Init Check old data failed!\n$e$s");
  }
}

Future<void> _checkAccountData() async {
  var s = await SharedPreferences.getInstance();
  if (s.getString('picacgAccount') != null) {
    var account = s.getString('picacgAccount');
    var pwd = s.getString('picacgPassword');
    var token = s.getString('token');
    picacg.data['account'] = [account, pwd];
    picacg.data['token'] = token;
    picacg.data['user'] = Profile(
      id: s.getString("userId") ?? "",
      avatarUrl: s.getString("userAvatar") ?? '',
      email: s.getString("userEmail") ?? "",
      exp: s.getInt("userExp") ?? 0,
      level: s.getInt("userLevel") ?? 0,
      name: s.getString("userName") ?? "",
      title: s.getString("userTitle") ?? "",
      isPunched: false,
      slogan: '',
      frameUrl: '',
    ).toJson();
    picacg.data['appChannel'] = s.getString("appChannel") ?? "3";
    picacg.data['imageQuality'] = s.getString('image') ?? "original";
    await picacg.saveData();
    await s.remove('picacgAccount');
  }
  if (s.getString("jmName") != null) {
    var account = s.getString('jmName');
    var pwd = s.getString('jmPwd');
    jm.data['account'] = [account, pwd];
    jm.data['name'] = account;
    await s.remove("jmName");
    await jm.saveData();
  }
  if (s.getString("ehAccount") != null) {
    ehentai.data['account'] = 'ok';
    ehentai.data['name'] = s.getString("ehAccount")!;
    await s.remove("ehAccount");
    await ehentai.saveData();
  }
  if (s.getString('htName') != null) {
    var account = s.getString('htName');
    var pwd = s.getString('htPwd');
    htManga.data['account'] = [account, pwd];
    htManga.data['name'] = account;
    await s.remove('htName');
    await htManga.saveData();
  }
  await NhentaiNetwork().init();
  if (NhentaiNetwork().logged) {
    nhentai.data['account'] = 'ok';
    await nhentai.saveData();
  }
}
