import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../base.dart';
import '../foundation/app_settings_provider.dart';

part 'network_monitor_settings.g.dart';

/// 网络监控设置的命名 key。
const networkSpeedBallSettingKey = AppSettingKeys.showNetworkSpeedBall;
const networkLogCollectingSettingKey = AppSettingKeys.collectNetworkLogs;

/// 网络悬浮球坐标在隐式设置中的位置。
const networkSpeedBallXImplicitIndex = 4;
const networkSpeedBallYImplicitIndex = 5;

/// 网络监控相关的持久化设置。
class NetworkMonitorSettings {
  const NetworkMonitorSettings({
    required this.showSpeedBall,
    required this.ballX,
    required this.ballY,
  });

  final bool showSpeedBall;
  final double ballX;
  final double ballY;

  NetworkMonitorSettings copyWith({
    bool? showSpeedBall,
    double? ballX,
    double? ballY,
  }) {
    return NetworkMonitorSettings(
      showSpeedBall: showSpeedBall ?? this.showSpeedBall,
      ballX: ballX ?? this.ballX,
      ballY: ballY ?? this.ballY,
    );
  }
}

/// 管理网络悬浮球及其位置。
@Riverpod(keepAlive: true)
class NetworkMonitorSettingsController
    extends _$NetworkMonitorSettingsController {
  @override
  NetworkMonitorSettings build() {
    return NetworkMonitorSettings(
      showSpeedBall: ref.watch(
        appSettingsProvider.select(
          (s) => s.enabled(networkSpeedBallSettingKey),
        ),
      ),
      ballX: _readImplicitDouble(networkSpeedBallXImplicitIndex, 16.0),
      ballY: _readImplicitDouble(networkSpeedBallYImplicitIndex, 0.0),
    );
  }

  /// 修改悬浮球显示状态。
  Future<void> setShowSpeedBall(bool value) async {
    await ref
        .read(appSettingsProvider.notifier)
        .setValue(networkSpeedBallSettingKey, value ? '1' : '0');
  }

  /// 保存悬浮球位置。
  Future<void> setBallPosition(double x, double y) async {
    _writeImplicit(networkSpeedBallXImplicitIndex, x.toString());
    _writeImplicit(networkSpeedBallYImplicitIndex, y.toString());
    state = state.copyWith(ballX: x, ballY: y);
    await appdata.writeImplicitData();
  }

  double _readImplicitDouble(int index, double fallback) {
    if (appdata.implicitData.length <= index) return fallback;
    return double.tryParse(appdata.implicitData[index]) ?? fallback;
  }

  void _writeImplicit(int index, String value) {
    while (appdata.implicitData.length <= index) {
      appdata.implicitData.add('');
    }
    appdata.implicitData[index] = value;
  }
}

/// 网络监控设置 Provider 的简洁名称。
const networkMonitorSettingsProvider = networkMonitorSettingsControllerProvider;

/// 悬浮球是否显示。
@riverpod
bool networkSpeedBallEnabled(Ref ref) {
  return ref.watch(networkMonitorSettingsProvider).showSpeedBall;
}
