import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'network_log.dart';
import 'network_speed_monitor.dart';

const _speedRequestIdKey = '__pica_network_speed_request_id__';
const _networkLogTokenKey = '__pica_network_log_token__';

/// 统计 Dio 请求产生的上传和下载流量。
class NetworkSpeedInterceptor extends Interceptor {
  NetworkSpeedInterceptor(this.monitor);

  final NetworkSpeedMonitor monitor;
  final Map<String, int> _lastReceivedBytes = {};

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final id = '${options.hashCode}-${DateTime.now().microsecondsSinceEpoch}';
    options.extra[_speedRequestIdKey] = id;
    final originalCallback = options.onReceiveProgress;
    options.onReceiveProgress = (received, total) {
      final last = _lastReceivedBytes[id] ?? 0;
      final increment = received - last;
      if (increment > 0) {
        monitor.recordDownload(increment);
      }
      _lastReceivedBytes[id] = received;
      originalCallback?.call(received, total);
    };
    monitor.recordUpload(_calculateUploadSize(options));
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final id = response.requestOptions.extra[_speedRequestIdKey] as String?;
    final hadProgress = id != null && _lastReceivedBytes.containsKey(id);
    if (id != null) {
      _lastReceivedBytes.remove(id);
    }
    if (!hadProgress) {
      monitor.recordDownload(_calculateResponseSize(response));
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final id = err.requestOptions.extra[_speedRequestIdKey] as String?;
    if (id != null) {
      _lastReceivedBytes.remove(id);
    }
    handler.next(err);
  }

  int _calculateUploadSize(RequestOptions options) {
    final data = options.data;
    if (data == null) return 0;
    if (data is Uint8List || data is List<int>) {
      return (data as List<int>).length;
    }
    if (data is String) return utf8.encode(data).length;
    return utf8.encode(data.toString()).length;
  }

  int _calculateResponseSize(Response response) {
    final contentLength = int.tryParse(
      response.headers[Headers.contentLengthHeader]?.first ?? '',
    );
    if (contentLength != null && contentLength >= 0) return contentLength;
    final data = response.data;
    if (data == null || data is ResponseBody) return 0;
    if (data is Uint8List || data is List<int>) {
      return (data as List<int>).length;
    }
    return utf8.encode(data.toString()).length;
  }
}

/// 采集 Dio 请求详情。
class NetworkLogInterceptor extends Interceptor {
  NetworkLogInterceptor(this.sink);

  final NetworkLogSink sink;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = sink.beginRequest(options);
    if (token != null) {
      options.extra[_networkLogTokenKey] = token;
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final token = response.requestOptions.extra[_networkLogTokenKey];
    if (token is NetworkLogRequestToken) {
      sink.completeResponse(token, response);
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final token = err.requestOptions.extra[_networkLogTokenKey];
    if (token is NetworkLogRequestToken) {
      sink.failRequest(token, err);
    }
    handler.next(err);
  }
}
