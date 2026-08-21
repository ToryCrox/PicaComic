/// 网络后端。
enum NetworkBackend {
  /// 使用 rhttp 原生网络实现。
  rhttp,

  /// 使用 Dio 自带的网络实现。
  dio,
}

/// 网络协议偏好。
enum NetworkProtocol {
  /// 由底层网络库自动协商。
  auto,

  /// 强制使用 HTTP/1.1。
  http1,

  /// 优先或强制使用 HTTP/2。
  http2,
}

/// 网络配置的序列化辅助方法。
extension NetworkConfigExtension on NetworkBackend {
  String get value => switch (this) {
    NetworkBackend.rhttp => 'rhttp',
    NetworkBackend.dio => 'dio',
  };

  static NetworkBackend fromValue(String? value) {
    return value == NetworkBackend.dio.value
        ? NetworkBackend.dio
        : NetworkBackend.rhttp;
  }
}

/// 网络协议的序列化辅助方法。
extension NetworkProtocolExtension on NetworkProtocol {
  String get value => switch (this) {
    NetworkProtocol.auto => 'auto',
    NetworkProtocol.http1 => 'http1',
    NetworkProtocol.http2 => 'http2',
  };

  static NetworkProtocol fromValue(String? value) {
    return switch (value) {
      'http1' => NetworkProtocol.http1,
      'http2' => NetworkProtocol.http2,
      _ => NetworkProtocol.auto,
    };
  }
}
