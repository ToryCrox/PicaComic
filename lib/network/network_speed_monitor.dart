import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'network_speed_monitor.g.dart';

/// 单次速度采样数据。
class NetworkSpeedData {
  const NetworkSpeedData({
    required this.downloadSpeed,
    required this.uploadSpeed,
    required this.timestamp,
  });

  final int downloadSpeed;
  final int uploadSpeed;
  final DateTime timestamp;

  String get downloadSpeedText => formatNetworkSpeed(downloadSpeed);

  String get uploadSpeedText => formatNetworkSpeed(uploadSpeed);
}

/// 格式化网络速度。
String formatNetworkSpeed(int bytesPerSecond) {
  if (bytesPerSecond < 1024) {
    return '$bytesPerSecond B/s';
  }
  if (bytesPerSecond < 1024 * 1024) {
    return '${(bytesPerSecond / 1024).toStringAsFixed(1)} KB/s';
  }
  return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(2)} MB/s';
}

/// 汇总应用内网络上传和下载速度。
class NetworkSpeedMonitor {
  NetworkSpeedMonitor({Duration interval = const Duration(seconds: 1)})
    : _interval = interval;

  final Duration _interval;
  final StreamController<NetworkSpeedData> _controller =
      StreamController<NetworkSpeedData>.broadcast();

  Timer? _timer;
  DateTime _lastUpdateTime = DateTime.now();
  int _downloadBytes = 0;
  int _uploadBytes = 0;
  bool _disposed = false;

  /// 当前速度采样流。
  Stream<NetworkSpeedData> get speedStream => _controller.stream;

  /// 是否正在采集速度。
  bool get isRunning => _timer != null;

  /// 开始采集速度。
  void start() {
    if (_disposed || _timer != null) return;
    _downloadBytes = 0;
    _uploadBytes = 0;
    _lastUpdateTime = DateTime.now();
    _timer = Timer.periodic(_interval, (_) => _updateSpeed());
  }

  /// 停止采集速度并丢弃当前采样窗口。
  void stop() {
    _timer?.cancel();
    _timer = null;
    _downloadBytes = 0;
    _uploadBytes = 0;
  }

  /// 记录下载字节数。
  void recordDownload(int bytes) {
    if (!_disposed && _timer != null && bytes > 0) {
      _downloadBytes += bytes;
    }
  }

  /// 记录上传字节数。
  void recordUpload(int bytes) {
    if (!_disposed && _timer != null && bytes > 0) {
      _uploadBytes += bytes;
    }
  }

  void _updateSpeed() {
    final now = DateTime.now();
    final seconds = now.difference(_lastUpdateTime).inMicroseconds / 1000000;
    if (seconds <= 0) return;

    _controller.add(
      NetworkSpeedData(
        downloadSpeed: (_downloadBytes / seconds).round(),
        uploadSpeed: (_uploadBytes / seconds).round(),
        timestamp: now,
      ),
    );
    _downloadBytes = 0;
    _uploadBytes = 0;
    _lastUpdateTime = now;
  }

  /// 释放监控器。
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    stop();
    _controller.close();
  }
}

/// 应用级速度监控器，由网络层和 UI 共同使用。
@Riverpod(keepAlive: true)
NetworkSpeedMonitor networkSpeedMonitor(Ref ref) {
  final monitor = NetworkSpeedMonitor();
  ref.onDispose(monitor.dispose);
  return monitor;
}

/// 悬浮球显示时监听速度流，页面销毁后自动停止采集。
@riverpod
Stream<NetworkSpeedData> networkSpeed(Ref ref) {
  final monitor = ref.read(networkSpeedMonitorProvider);
  monitor.start();
  ref.onDispose(monitor.stop);
  return monitor.speedStream;
}
