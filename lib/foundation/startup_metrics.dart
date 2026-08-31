import 'package:flutter/foundation.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/foundation/log.dart';

/// 记录启动关键时间点，仅用于性能观测，不参与启动状态编排。
class StartupMetrics {
  StartupMetrics._() : _startedAt = DateTime.now();

  static final instance = StartupMetrics._();

  final DateTime _startedAt;
  final Set<String> _marked = {};

  /// 记录一个只应出现一次的启动阶段。
  void mark(String name) {
    if (!_marked.add(name)) return;
    final elapsed = DateTime.now().difference(_startedAt).inMilliseconds;
    final message = 'Startup metric: $name ${elapsed}ms';
    // Profile/release 模式下日志文件路径依赖 App.init()。Dart 入口和
    // 首帧指标可能早于它，因此初始化前先回退到 debugPrint，避免反过来
    // 因记录指标触发 App.dataPath 的 late 初始化错误。
    if (App.isInitialized) {
      Log.i(message);
    } else {
      debugPrint(message);
    }
  }
}

final startupMetrics = StartupMetrics.instance;
