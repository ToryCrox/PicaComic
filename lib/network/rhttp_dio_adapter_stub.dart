import 'package:dio/dio.dart';

import 'network_config.dart';

/// Web 平台的 rhttp 适配器占位实现。
Future<HttpClientAdapter> createRhttpDioAdapter({
  required NetworkProtocol protocol,
  String? proxy,
}) async {
  throw UnsupportedError('rhttp is not supported on Web');
}
