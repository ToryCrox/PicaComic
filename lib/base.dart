import 'dart:convert';
import 'dart:io';

import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/foundation/log.dart';
import 'package:pica_comic/network/jm_network/jm_network.dart';
import 'package:pica_comic/network/webdav.dart';
import 'package:pica_comic/tools/extensions.dart';
import 'package:pica_comic/tools/io_tools.dart';
import 'package:pica_comic/tools/notification.dart';
import 'package:pica_comic/foundation/history.dart';
import 'package:pica_comic/foundation/local_favorites.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synchronized/synchronized.dart';
import 'foundation/def.dart';
import 'foundation/settings_events.dart';
import 'foundation/app_setting_keys.dart';
export 'foundation/app_setting_keys.dart';
import 'network/network_config.dart';
export 'foundation/def.dart';
export 'package:pica_comic/network/download/download_manager.dart';

String get pathSep => Platform.pathSeparator;

/// 页面保存与 WebDAV 版本更新共用的文件写入锁。
final _settingsFileLock = Lock();

class Appdata {
  ///搜索历史
  List<String> searchHistory = [];
  Set<String> favoriteTags = {};

  ///历史记录管理器, 可以通过factory构造函数访问, 也可以通过这里访问
  var history = HistoryManager();

  Map<String, String> _settings = Map.of(defaultAppSettings);

  /// 设置的只读 key-value 视图，业务代码不能直接修改内部 Map。
  Map<String, String> get settings => Map.unmodifiable(_settings);

  /// 用完整命名配置替换设置，缺失项使用默认值。
  set settings(Map<String, String> values) {
    _settings = Map.of(defaultAppSettings);
    for (final entry in values.entries) {
      if (defaultAppSettings.containsKey(entry.key)) {
        _settings[entry.key] = entry.value;
      }
    }
    notifySettingsChanged();
  }

  /// 同步读取设置，未知 key 表示调用方存在错误。
  String getSetting(String key) {
    final value = _settings[key];
    if (value == null) throw ArgumentError.value(key, 'key', '未知设置项');
    return value;
  }

  /// 统一内存写入入口，所有变更都会通知 Riverpod 设置消费者。
  void setSetting(String key, String value) {
    if (!defaultAppSettings.containsKey(key)) {
      throw ArgumentError.value(key, 'key', '未知设置项');
    }
    _settings[key] = value;
    notifySettingsChanged();
  }

  /// 隐式数据, 用于存储一些不需要用户设置的数据, 此数据通常为某些组件的状态, 此设置不应当被同步
  List<String> implicitData = [
    "1;;", //收藏夹状态
    "0", // 双页模式下第一页显示单页
    "0", // 点击关闭按钮时不显示提示
    webUA, // UA
    "16.0", // 网速悬浮球 X 坐标
    "0.0", // 网速悬浮球 Y 坐标
  ];

  Future<void> writeImplicitData() async {
    var s = await SharedPreferences.getInstance();
    await s.setStringList("implicitData", implicitData);
  }

  Future<void> readImplicitData() async {
    var s = await SharedPreferences.getInstance();
    var data = s.getStringList("implicitData");
    if (data == null) {
      await writeImplicitData();
      return;
    }
    for (int i = 0; i < data.length && i < implicitData.length; i++) {
      implicitData[i] = data[i];
    }
  }

  ///屏蔽的关键词
  List<String> blockingKeyword = [];

  ///是否第一次使用的判定, 用于显示提示
  List<String> firstUse = [
    "1", //屏蔽关键词1
    "1", //屏蔽关键词2(已废弃)
    "1", //漫画详情页
    "0", //是否进入过app
    "1", //显示本地收藏夹的管理提示
  ];

  /// 读取命名 key 的设置文件；不再支持旧数组格式。
  Future<void> readSettings() async {
    final file = File('${App.dataPath}/settings');
    if (await file.exists()) {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) throw const FormatException('设置文件必须是 JSON 对象');
      settings = Map<String, String>.from(decoded);
    } else {
      notifySettingsChanged();
    }
  }

  Future<void> updateSettings([bool syncData = true]) async {
    notifySettingsChanged();
    await _settingsFileLock.synchronized(() async {
      final settingsFile = File("${App.dataPath}/settings");
      await settingsFile.writeAsString(jsonEncode(settings));
    });
    if (syncData) {
      Webdav.uploadData();
    }
  }

  void writeFirstUse() async {
    var s = await SharedPreferences.getInstance();
    await s.setStringList("firstUse", firstUse);
  }

  void writeHistory() async {
    var s = await SharedPreferences.getInstance();
    await s.setStringList("search", searchHistory);
    await s.setStringList("favoriteTags", favoriteTags.toList());
  }

  Future<void> writeData([bool sync = true]) async {
    if (sync) {
      Webdav.uploadData();
    }
    var s = await SharedPreferences.getInstance();
    await updateSettings(false);
    await s.setStringList("blockingKeyword", blockingKeyword);
    await s.setStringList("firstUse", firstUse);
  }

  Future<bool> readData() async {
    var s = await SharedPreferences.getInstance();
    try {
      await readSettings();
      searchHistory = s.getStringList("search") ?? [];
      favoriteTags = (s.getStringList("favoriteTags") ?? []).toSet();
      blockingKeyword = s.getStringList("blockingKeyword") ?? [];
      if (s.getStringList("firstUse") != null) {
        var st = s.getStringList("firstUse")!;
        for (int i = 0; i < st.length; i++) {
          firstUse[i] = st[i];
        }
      }
      await readImplicitData();
      return firstUse[3] == "1";
    } catch (e) {
      return false;
    }
  }

  Map<String, dynamic> toJson() => {
    "settings": settings,
    "firstUse": firstUse,
    "blockingKeywords": blockingKeyword,
    "favoriteTags": favoriteTags.toList(),
  };

  bool readDataFromJson(Map<String, dynamic> json) {
    try {
      final newSettings = Map<String, String>.from(json['settings'] as Map);
      final downloadPath = getSetting(AppSettingKeys.downloadDirectory);
      final authRequired = getSetting(AppSettingKeys.requireAuthentication);
      settings = {
        ...newSettings,
        AppSettingKeys.downloadDirectory: downloadPath,
        AppSettingKeys.requireAuthentication: authRequired,
      };
      var newFirstUse = List<String>.from(json["firstUse"]);
      for (var i = 0; i < firstUse.length && i < newFirstUse.length; i++) {
        firstUse[i] = newFirstUse[i];
      }
      if (json["history"] != null) {
        history.readDataFromJson(json["history"]);
      }
      // merge data
      blockingKeyword = Set<String>.from(
        ((json["blockingKeywords"] ?? []) + blockingKeyword) as List,
      ).toList();
      favoriteTags = Set.from(
        (json["favoriteTags"] ?? []) + List.from(favoriteTags),
      );
      writeData(false);
      return true;
    } catch (e, s) {
      Log.e("Appdata.readDataFromJson error reading appdata$e\n$s");
      readData();
      return false;
    }
  }

  final appSettings = _Settings();
}

Appdata _appdata = Appdata();

/// 当前应用数据，旧业务代码仍可同步读取。
Appdata get appdata => _appdata;

/// 替换数据后通知设置消费者，兼容清空数据及后台独立实例。
set appdata(Appdata value) {
  _appdata = value;
  notifySettingsChanged();
}

var notifications = Notifications();

/// clear all data
Future<void> clearAppdata({JmNetwork? jmNetwork}) async {
  var s = await SharedPreferences.getInstance();
  await s.clear();
  var settingsFile = File("${App.dataPath}/settings");
  if (await settingsFile.exists()) {
    await settingsFile.delete();
  }
  appdata.history.clearHistory();
  appdata = Appdata();
  await appdata.readData();
  await eraseCache();
  if (jmNetwork != null) await jmNetwork.cookieJar.deleteAll();
  await LocalFavoritesManager().clearAll();
}

/// 网络、阅读器及后台任务使用的同步设置视图。
class _Settings {
  /// 漫画块显示模式：0 详细，1 简略。
  int get comicTileDisplayType => int.parse(
    appdata.getSetting(AppSettingKeys.comicTileDisplay).split(',').first,
  );

  set comicTileDisplayType(int v) {
    var values = appdata.getSetting(AppSettingKeys.comicTileDisplay).split(',');
    if (values.length != 2) {
      values = ['0', '1.0'];
    }
    values[0] = v.toString();
    appdata.setSetting(AppSettingKeys.comicTileDisplay, values.join(','));
  }

  /// 漫画列表模式：0 连续，1 分页。
  int get comicsListDisplayType =>
      int.parse(appdata.getSetting(AppSettingKeys.comicsListDisplayMode));

  set comicsListDisplayType(int value) {
    appdata.setSetting(AppSettingKeys.comicsListDisplayMode, value.toString());
  }

  /// 判断指定内置漫画源是否启用。
  bool isComicSourceEnabled(String key) {
    var index = builtInSources.indexWhere((e) => e.name == key);
    if (index == -1) {
      throw "Not Found";
    }
    // 处理旧版本设置字符串长度不足的情况,新增的漫画源默认启用
    if (index >=
        appdata.getSetting(AppSettingKeys.enabledBuiltInSources).length) {
      return true;
    }
    return appdata.getSetting(AppSettingKeys.enabledBuiltInSources)[index] ==
        '1';
  }

  /// 生成内置漫画源开关的新值，保存由页面的 Notifier 完成。
  String comicSourceEnabledValue(String key, bool enabled) {
    final index = builtInSources.indexWhere((e) => e.name == key);
    if (index == -1) throw ArgumentError.value(key, 'key', '未知漫画源');
    var values = appdata.getSetting(AppSettingKeys.enabledBuiltInSources);
    values = values.padRight(index + 1, '1');
    return values.setValueAt(enabled ? '1' : '0', index);
  }

  List<String> get jmApiDomains =>
      appdata.getSetting(AppSettingKeys.jmApiDomains).split(',');

  set jmApiDomains(List<String> domains) {
    appdata.setSetting(AppSettingKeys.jmApiDomains, domains.join(','));
  }

  String get jmImgUrlIndex =>
      int.parse(appdata.getSetting(AppSettingKeys.jmImageStream)) < 4
      ? appdata.getSetting(AppSettingKeys.jmImageStream)
      : "0";

  List<String> get explorePages =>
      appdata.getSetting(AppSettingKeys.explorePages).split(',');

  set explorePages(List<String> pages) {
    appdata.setSetting(AppSettingKeys.explorePages, pages.join(','));
  }

  List<String> get categoryPages =>
      appdata.getSetting(AppSettingKeys.categoryPages).split(',');

  set categoryPages(List<String> pages) {
    appdata.setSetting(AppSettingKeys.categoryPages, pages.join(','));
  }

  String get initialSearchTarget =>
      appdata.getSetting(AppSettingKeys.defaultSearchSource);

  set initialSearchTarget(String value) {
    appdata.setSetting(AppSettingKeys.defaultSearchSource, value);
  }

  bool get reduceBrightnessInDarkMode =>
      appdata.getSetting(AppSettingKeys.dimImagesInDarkMode) == "1";

  set reduceBrightnessInDarkMode(bool value) {
    appdata.setSetting(AppSettingKeys.dimImagesInDarkMode, value ? "1" : "0");
  }

  bool get showPageInfoInReader =>
      appdata.getSetting(AppSettingKeys.showReaderPageInfo) == "1";

  set showPageInfoInReader(bool value) {
    appdata.setSetting(AppSettingKeys.showReaderPageInfo, value ? "1" : "0");
  }

  bool get showButtonsInReader =>
      appdata.getSetting(AppSettingKeys.showReaderButtons) == "1";

  set showButtonsInReader(bool value) {
    appdata.setSetting(AppSettingKeys.showReaderButtons, value ? "1" : "0");
  }

  bool get flipPageWithClick =>
      appdata.getSetting(AppSettingKeys.readerTapToTurnPage) == "1";

  set flipPageWithClick(bool value) {
    appdata.setSetting(AppSettingKeys.readerTapToTurnPage, value ? "1" : "0");
  }

  bool get useDarkBackground =>
      appdata.getSetting(AppSettingKeys.readerDarkBackground) == "1";

  set useDarkBackground(bool value) {
    appdata.setSetting(AppSettingKeys.readerDarkBackground, value ? "1" : "0");
  }

  bool get fullyHideBlockedWorks =>
      appdata.getSetting(AppSettingKeys.fullyHideBlockedComics) == "1";

  set fullyHideBlockedWorks(bool value) {
    appdata.setSetting(
      AppSettingKeys.fullyHideBlockedComics,
      value ? "1" : "0",
    );
  }

  /// 下载页是否禁用拖动。
  bool get downloadPageDragDisabled =>
      appdata.getSetting(AppSettingKeys.downloadPageDragDisabled) == "1";

  set downloadPageDragDisabled(bool value) {
    appdata.setSetting(
      AppSettingKeys.downloadPageDragDisabled,
      value ? "1" : "0",
    );
  }

  /// 图片缓存容量上限，单位 MB。
  int get cacheLimit =>
      int.tryParse(appdata.getSetting(AppSettingKeys.cacheLimitMb)) ?? 500;

  set cacheLimit(int value) {
    appdata.setSetting(AppSettingKeys.cacheLimitMb, value.toString());
  }

  List<String> get networkFavorites =>
      appdata.getSetting(AppSettingKeys.networkFavoritePages).split(',');

  set networkFavorites(List<String> pages) {
    appdata.setSetting(AppSettingKeys.networkFavoritePages, pages.join(','));
  }

  String get font => appdata.getSetting(AppSettingKeys.font);

  set font(String value) => appdata.setSetting(AppSettingKeys.font, value);

  /// 漫画翻译结果根目录，为空时仅扫描原漫画目录内的 `result` 目录。
  String get translationResultDirectory =>
      appdata.getSetting(AppSettingKeys.translationResultDirectory);

  set translationResultDirectory(String value) {
    appdata.setSetting(AppSettingKeys.translationResultDirectory, value);
  }

  /// 网络后端，默认为 rhttp。
  NetworkBackend get networkBackend => NetworkConfigExtension.fromValue(
    appdata.getSetting(AppSettingKeys.networkBackend),
  );

  set networkBackend(NetworkBackend value) {
    appdata.setSetting(AppSettingKeys.networkBackend, value.value);
  }

  /// HTTP 协议偏好，默认为自动协商。
  NetworkProtocol get networkProtocol => NetworkProtocolExtension.fromValue(
    appdata.getSetting(AppSettingKeys.networkProtocol),
  );

  set networkProtocol(NetworkProtocol value) {
    appdata.setSetting(AppSettingKeys.networkProtocol, value.value);
  }
}
