import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/services.dart';
import 'package:pica_comic/foundation/log.dart';
import 'package:dio_http2_adapter/dio_http2_adapter.dart';
import 'package:pica_comic/network/http_client.dart';
import 'package:pica_comic/network/network_config.dart';
import 'package:pica_comic/network/network_interceptors.dart';
import 'package:pica_comic/network/network_telemetry.dart';
import '../base.dart';
import '../foundation/app.dart';

class MyLogInterceptor implements Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    Log.e(
      "Network ${err.requestOptions.method} ${err.requestOptions.path}\n$err\n${err.response?.data.toString()}",
    );
    switch (err.type) {
      case DioExceptionType.badResponse:
        var statusCode = err.response?.statusCode;
        if (statusCode != null) {
          err = err.copyWith(
            message:
                "Invalid Status Code: $statusCode. "
                "${_getStatusCodeInfo(statusCode)}",
          );
        }
      case DioExceptionType.connectionTimeout:
        err = err.copyWith(message: "Connection Timeout");
      case DioExceptionType.receiveTimeout:
        err = err.copyWith(
          message:
              "Receive Timeout: "
              "This indicates that the server is too busy to respond",
        );
      case DioExceptionType.unknown:
        if (err.toString().contains("Connection terminated during handshake")) {
          err = err.copyWith(
            message:
                "Connection terminated during handshake: "
                "This may be caused by the firewall blocking the connection "
                "or your requests are too frequent.",
          );
        } else if (err.toString().contains("Connection reset by peer")) {
          err = err.copyWith(
            message:
                "Connection reset by peer: "
                "The error is unrelated to app, please check your network.",
          );
        }
      default:
        {}
    }
    handler.next(err);
  }

  static const errorMessages = <int, String>{
    400: "The Request is invalid.",
    401: "The Request is unauthorized.",
    403: "No permission to access the resource. Check your account or network.",
    404: "Not found.",
    429: "Too many requests. Please try again later.",
  };

  String _getStatusCodeInfo(int? statusCode) {
    if (statusCode != null && statusCode >= 500) {
      return "This is server-side error, please try again later. "
          "Do not report this issue.";
    } else {
      return errorMessages[statusCode] ?? "";
    }
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    var headers = response.headers.map.map(
      (key, value) => MapEntry(
        key.toLowerCase(),
        value.length == 1 ? value.first : value.toString(),
      ),
    );
    headers.remove("cookie");
    String content;
    if (response.data is List<int>) {
      try {
        content = utf8.decode(response.data, allowMalformed: false);
      } catch (e) {
        content = "<Bytes>\nlength:${response.data.length}";
      }
    } else {
      content = response.data.toString();
    }
    if ((response.statusCode != null && response.statusCode! < 400)) {
      Log.i(
        () =>
            "Network Response ${response.realUri.toString()} ${response.statusCode} "
            "[${response.extra['networkBackend'] ?? 'unknown'}/"
            "${response.extra['networkProtocol'] ?? 'unknown'}]\n"
            "headers:\n$headers\n$content",
      );
    } else {
      Log.e(
        () =>
            "Network Response ${response.realUri.toString()} ${response.statusCode} "
            "[${response.extra['networkBackend'] ?? 'unknown'}/"
            "${response.extra['networkProtocol'] ?? 'unknown'}]\n"
            "headers:\n$headers\n$content",
      );
    }
    handler.next(response);
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.connectTimeout ??= const Duration(seconds: 15);
    options.sendTimeout ??= const Duration(seconds: 15);
    options.receiveTimeout ??= options.responseType == ResponseType.stream
        ? const Duration(seconds: 60)
        : const Duration(seconds: 30);
    handler.next(options);
  }
}

class AppHttpAdapter implements HttpClientAdapter {
  HttpClientAdapter? adapter;

  final NetworkProtocol protocol;

  AppHttpAdapter(this.protocol);

  static Future<HttpClientAdapter> createAdapter(
    NetworkProtocol protocol,
  ) async {
    return protocol == NetworkProtocol.http1
        ? IOHttpClientAdapter()
        : Http2Adapter(
            ConnectionManager(
              idleTimeout: const Duration(seconds: 15),
              onClientCreate: (_, config) {
                if (proxyHttpOverrides?.proxyStr != null &&
                    appdata.settings[58] != "1") {
                  config.proxy = Uri.parse(
                    'http://${proxyHttpOverrides?.proxyStr}',
                  );
                }
              },
            ),
          );
  }

  @override
  void close({bool force = false}) {
    adapter?.close(force: force);
  }

  /// 直接使用ip访问绕过sni
  bool changeHost(RequestOptions options) {
    var config = const JsonDecoder().convert(
      File("${App.dataPath}/rule.json").readAsStringSync(),
    );
    if ((config["sni"] ?? []).contains(options.uri.host) &&
        (config["rule"] ?? {})[options.uri.host] != null) {
      options.path = options.path.replaceFirst(
        options.uri.host,
        config["rule"][options.uri.host]!,
      );
      return true;
    }
    return false;
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    adapter ??= await createAdapter(protocol);
    int retry = 0;
    var usedFallback = false;
    while (true) {
      try {
        var res = await fetchOnce(o, requestStream, cancelFuture);
        res.extra = {
          ...res.extra,
          ..._networkMetadata(usedFallback: usedFallback),
        };
        return res;
      } catch (e) {
        if (e is DioException) {
          if (e.response?.statusCode != null) {
            var code = e.response!.statusCode!;
            if (code >= 400 && code < 500) {
              rethrow;
            }
          }
        }
        if (!_canRetry(o, requestStream, e)) rethrow;
        Log.e("Network ${o.method} ${o.path}\n$e\nRetrying...");
        retry++;
        if (retry == 2) {
          rethrow;
        }
        if (protocol != NetworkProtocol.http1 && adapter is Http2Adapter) {
          adapter!.close(force: true);
          adapter = await createAdapter(NetworkProtocol.http1);
          usedFallback = true;
        }
        await Future.delayed(const Duration(seconds: 1));
      }
    }
  }

  Map<String, String> _networkMetadata({required bool usedFallback}) {
    final isHttp2 = adapter is Http2Adapter;
    return {
      'networkBackend': 'dio',
      'networkProtocol': isHttp2 ? 'http2' : 'http1',
      'networkProtocolSource': usedFallback
          ? 'fallback'
          : isHttp2
          ? 'actual'
          : 'configured',
      if (usedFallback) 'networkFallback': 'http1',
    };
  }

  bool _canRetry(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Object error,
  ) {
    if (requestStream != null) return false;
    if (error is DioException &&
        (error.type == DioExceptionType.cancel ||
            error.type == DioExceptionType.badCertificate)) {
      return false;
    }
    return switch (options.method.toUpperCase()) {
      'GET' || 'HEAD' || 'OPTIONS' => true,
      _ => false,
    };
  }

  Future<ResponseBody> fetchOnce(
    RequestOptions o,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    var options = o.copyWith();
    Log.i(
      () =>
          "Network ${options.method} ${options.path}\nheaders:\n${options.headers.toString()}\ndata:${options.data}",
    );
    if (appdata.settings[58] == "0") {
      return checkCookie(
        await adapter!.fetch(options, requestStream, cancelFuture),
      );
    }
    if (!changeHost(options)) {
      return checkCookie(
        await adapter!.fetch(options, requestStream, cancelFuture),
      );
    }
    if (options.headers["host"] == null && options.headers["Host"] == null) {
      options.headers["host"] = options.uri.host;
    }
    options.followRedirects = false;
    var res = await adapter!.fetch(options, requestStream, cancelFuture);
    while (res.statusCode < 400 && res.statusCode > 300) {
      var location = res.headers["location"]!.first;
      if (location.contains("http") && Uri.tryParse(location) != null) {
        if (Uri.parse(location).host != o.uri.host) {
          options.path = location;
          changeHost(options);
          res = await adapter!.fetch(options, requestStream, cancelFuture);
        } else {
          location = Uri.parse(location).path;
          options.path = options.path.contains("https://")
              ? "https://${options.uri.host}$location"
              : "http://${options.uri.host}$location";
          res = await adapter!.fetch(options, requestStream, cancelFuture);
        }
      } else {
        options.path = options.path.contains("https://")
            ? "https://${options.uri.host}$location"
            : "http://${options.uri.host}$location";
        res = await adapter!.fetch(options, requestStream, cancelFuture);
      }
    }
    return checkCookie(res);
  }

  /// 检查cookie是否合法, 去除无效cookie
  ResponseBody checkCookie(ResponseBody res) {
    if (res.headers["set-cookie"] == null) {
      return res;
    }

    var cookies = <String>[];

    var invalid = <String>[];

    for (var cookie in res.headers["set-cookie"]!) {
      try {
        Cookie.fromSetCookieValue(cookie);
        cookies.add(cookie);
      } catch (e) {
        invalid.add(cookie);
      }
    }

    if (cookies.isNotEmpty) {
      res.headers["set-cookie"] = cookies;
    } else {
      res.headers.remove("set-cookie");
    }

    if (invalid.isNotEmpty) {
      res.headers["invalid-cookie"] = invalid;
    }

    return res;
  }
}

Dio logDio([BaseOptions? options, bool http2 = false]) {
  final bridge = NetworkTelemetryBridge.instance;
  var dio = Dio(options)
    ..interceptors.add(NetworkSpeedInterceptor(bridge.speedMonitor))
    ..interceptors.add(NetworkLogInterceptor(bridge.logSink))
    ..interceptors.add(MyLogInterceptor());
  dio.httpClientAdapter = AppHttpAdapter(
    http2 ? NetworkProtocol.http2 : NetworkProtocol.http1,
  );
  return dio;
}
