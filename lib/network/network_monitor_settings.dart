import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../base.dart';

part 'network_monitor_settings.g.dart';

/// 网络监控设置在旧版设置数组中的位置。
const networkSpeedBallSettingIndex = 94;
const networkLogCollectingSettingIndex = 95;

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
      showSpeedBall: _readSetting(networkSpeedBallSettingIndex) == '1',
      ballX: _readImplicitDouble(networkSpeedBallXImplicitIndex, 16.0),
      ballY: _readImplicitDouble(networkSpeedBallYImplicitIndex, 0.0),
    );
  }

  /// 修改悬浮球显示状态。
  Future<void> setShowSpeedBall(bool value) async {
    _writeSetting(networkSpeedBallSettingIndex, value ? '1' : '0');
    state = state.copyWith(showSpeedBall: value);
    await appdata.updateSettings();
  }

  /// 保存悬浮球位置。
  Future<void> setBallPosition(double x, double y) async {
    _writeImplicit(networkSpeedBallXImplicitIndex, x.toString());
    _writeImplicit(networkSpeedBallYImplicitIndex, y.toString());
    state = state.copyWith(ballX: x, ballY: y);
    await appdata.writeImplicitData();
  }

  String _readSetting(int index) {
    if (appdata.settings.length <= index) return '0';
    return appdata.settings[index];
  }

  double _readImplicitDouble(int index, double fallback) {
    if (appdata.implicitData.length <= index) return fallback;
    return double.tryParse(appdata.implicitData[index]) ?? fallback;
  }

  void _writeSetting(int index, String value) {
    while (appdata.settings.length <= index) {
      appdata.settings.add('0');
    }
    appdata.settings[index] = value;
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
