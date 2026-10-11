import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/network/update.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 首帧后的更新检查结果；null 表示没有新版本或今日已经检查过。
final updateCheckProvider = FutureProvider<String?>((ref) async {
  ref.keepAlive();
  if (appdata.getSetting(AppSettingKeys.checkUpdatesOnStartup) != '1')
    return null;

  final preferences = await SharedPreferences.getInstance();
  final lastCheck = preferences.getInt('lastCheckUpdate');
  if (lastCheck != null &&
      DateTime.now()
              .difference(DateTime.fromMillisecondsSinceEpoch(lastCheck))
              .inDays <
          1) {
    return null;
  }

  final hasUpdate = await checkUpdate();
  await preferences.setInt(
    'lastCheckUpdate',
    DateTime.now().millisecondsSinceEpoch,
  );
  if (hasUpdate != true) return null;
  return getUpdatesInfo();
});
