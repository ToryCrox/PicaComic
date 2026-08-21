import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'network_log.dart';
import 'network_speed_monitor.dart';

part 'network_telemetry.g.dart';

/// 网络层与 Riverpod 状态之间的桥接对象。
class NetworkTelemetryBridge {
  NetworkTelemetryBridge._();

  static final instance = NetworkTelemetryBridge._();

  NetworkLogSink? _logSink;
  NetworkSpeedMonitor? _speedMonitor;

  NetworkLogSink get logSink => _logSink ?? const _NoopNetworkLogSink();

  NetworkSpeedMonitor get speedMonitor =>
      _speedMonitor ??= NetworkSpeedMonitor();

  /// 由 Riverpod 应用 Provider 注入实际状态控制器。
  void configure({
    required NetworkLogSink logSink,
    required NetworkSpeedMonitor speedMonitor,
  }) {
    _logSink = logSink;
    _speedMonitor = speedMonitor;
  }
}

/// 配置应用级网络监控桥接对象。
@Riverpod(keepAlive: true)
NetworkTelemetryBridge networkTelemetryBridge(Ref ref) {
  final bridge = NetworkTelemetryBridge.instance;
  bridge.configure(
    logSink: ref.read(networkLogControllerProvider.notifier),
    speedMonitor: ref.read(networkSpeedMonitorProvider),
  );
  return bridge;
}

class _NoopNetworkLogSink implements NetworkLogSink {
  const _NoopNetworkLogSink();

  @override
  NetworkLogRequestToken? beginRequest(RequestOptions options) => null;

  @override
  void completeResponse(NetworkLogRequestToken token, Response response) {}

  @override
  void failRequest(NetworkLogRequestToken token, DioException error) {}
}
