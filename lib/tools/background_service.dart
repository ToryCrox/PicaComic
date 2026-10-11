import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:pica_comic/comic_source/built_in/picacg.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/foundation/log.dart';
import 'package:workmanager/workmanager.dart';
import '../base.dart';
import '../network/network_client_manager.dart';
import '../network/picacg_network/methods.dart';
import 'notification.dart';

Future<void>? _workmanagerInitialization;

/// 初始化 Workmanager，并复用并发调用中的同一个 Future。
Future<void> initializeWorkmanager() {
  if (!App.isMobile) return Future.value();
  final pending = _workmanagerInitialization;
  if (pending != null) return pending;
  final future = _initializeWorkmanager();
  _workmanagerInitialization = future;
  return future;
}

Future<void> _initializeWorkmanager() async {
  try {
    await Workmanager().initialize(onStart);
  } catch (_) {
    _workmanagerInitialization = null;
    rethrow;
  }
}

@pragma('vm:entry-point')
void onStart() {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  Workmanager().executeTask((taskName, inputData) async {
    await App.init();
    // 独立 isolate 没有页面 ProviderScope，必须先读取本进程的持久化数据。
    // TODO: 后续重构后台任务时，一并向业务服务注入设置仓库或快照，不复用界面的 Ref。
    appdata = Appdata();
    await appdata.readData();
    final networkClient = NetworkClientManager.instance;
    await networkClient.initialize();
    var notifications = Notifications();
    await notifications.init();
    try {
      if (picacg.data['token'] != "") {
        var userInfo = await network.getProfile(false);
        if (userInfo.error) {
          return true;
        }
        if (userInfo.data.isPunched == false) {
          var res = await network.punchIn();
          if (res) {
            notifications.sendUnimportantNotification("自动打卡", "成功签到");
            return true;
          }
        } else {
          return true;
        }
      }
      return true;
    } finally {
      await networkClient.dispose();
    }
  });
}

void runBackgroundService() async {
  try {
    await initializeWorkmanager();
    await Workmanager().cancelAll();
    await Workmanager().registerPeriodicTask(
      "Piacg PunchIn",
      "打卡",
      frequency: const Duration(minutes: 1440),
      constraints: Constraints(networkType: NetworkType.connected),
    );
  } catch (e, s) {
    Log.w('Failed to schedule background check-in.\n$e\n$s');
  }
}

void cancelBackgroundService() async {
  try {
    await initializeWorkmanager();
    await Workmanager().cancelAll();
  } catch (e, s) {
    Log.w('Failed to cancel background check-in.\n$e\n$s');
  }
}
