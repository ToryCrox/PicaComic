import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:rhttp/rhttp.dart' as rh;

import 'network_config.dart';

/// 使用 rhttp 的 Dio 适配器。
class RhttpDioAdapter implements HttpClientAdapter {
  RhttpDioAdapter({
    required rh.RhttpClient client,
    required rh.ClientSettings baseSettings,
    required NetworkProtocol protocol,
  }) : _client = client,
       _baseSettings = baseSettings,
       _protocol = protocol;

  final rh.RhttpClient _client;
  final rh.ClientSettings _baseSettings;
  final NetworkProtocol _protocol;
  bool _closed = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (_closed) {
      throw StateError('The rhttp adapter has been closed.');
    }

    final cancelToken = rh.CancelToken();
    cancelFuture?.whenComplete(() {
      unawaited(cancelToken.cancel());
    });

    try {
      final response = await _send(
        options,
        requestStream,
        cancelToken,
        _protocol,
      );
      final responseBody = ResponseBody(
        _bodyStream(response.body, options),
        response.statusCode,
        headers: response.headerMapList,
        isRedirect: response.statusCode >= 300 && response.statusCode < 400,
      );
      responseBody.extra = {
        'networkBackend': 'rhttp',
        'networkProtocol': response.version.name,
        'networkProtocolSource': 'actual',
        if (response.remoteIp != null) 'remoteIp': response.remoteIp,
      };
      return responseBody;
    } catch (error, stackTrace) {
      if (_canFallback(options, requestStream, error)) {
        try {
          final response = await _send(
            options,
            null,
            cancelToken,
            NetworkProtocol.http1,
          );
          final responseBody = ResponseBody(
            _bodyStream(response.body, options),
            response.statusCode,
            headers: response.headerMapList,
            isRedirect: response.statusCode >= 300 && response.statusCode < 400,
          );
          responseBody.extra = {
            'networkBackend': 'rhttp',
            'networkProtocol': response.version.name,
            'networkProtocolSource': 'fallback',
            'networkFallback': 'http1',
            if (response.remoteIp != null) 'remoteIp': response.remoteIp,
          };
          return responseBody;
        } catch (fallbackError, fallbackStackTrace) {
          Error.throwWithStackTrace(
            _toDioException(options, fallbackError),
            fallbackStackTrace,
          );
        }
      }
      Error.throwWithStackTrace(_toDioException(options, error), stackTrace);
    }
  }

  Future<rh.HttpStreamResponse> _send(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    rh.CancelToken cancelToken,
    NetworkProtocol protocol,
  ) {
    final headers = <String, String>{};
    options.headers.forEach((key, value) {
      if (value != null) {
        headers[key] = value.toString();
      }
    });

    final timeoutSettings = _baseSettings.timeoutSettings;
    final requestTimeout = options.responseType == ResponseType.stream
        ? null
        : options.receiveTimeout;
    final requestSettings = _baseSettings.copyWith(
      httpVersionPref: _toHttpVersion(protocol),
      proxySettings: _proxySettings(options),
      timeoutSettings: timeoutSettings?.copyWith(
        timeout: requestTimeout ?? timeoutSettings.timeout,
        connectTimeout:
            options.connectTimeout ?? timeoutSettings.connectTimeout,
      ),
      redirectSettings: options.followRedirects
          ? rh.RedirectSettings.limited(options.maxRedirects)
          : rh.RedirectSettings.none(),
    );

    final body = requestStream == null
        ? null
        : rh.HttpBody.stream(requestStream, length: _contentLength(options));

    final request = rh.HttpRequest(
      client: _client,
      settings: requestSettings,
      method: rh.HttpMethod(options.method.toUpperCase()),
      url: options.uri.toString(),
      headers: rh.HttpHeaders.rawMap(headers),
      body: body,
      expectBody: rh.HttpExpectBody.stream,
      cancelToken: cancelToken,
    );
    return _client.send(request).then((response) {
      if (response is! rh.HttpStreamResponse) {
        throw StateError('rhttp returned a non-stream response.');
      }
      return response;
    });
  }

  Stream<Uint8List> _bodyStream(
    Stream<Uint8List> body,
    RequestOptions options,
  ) {
    final timeout = options.responseType == ResponseType.stream
        ? (options.receiveTimeout ?? const Duration(seconds: 60))
        : null;
    return timeout == null ? body : body.timeout(timeout);
  }

  int? _contentLength(RequestOptions options) {
    final value =
        options.headers['content-length'] ?? options.headers['Content-Length'];
    return int.tryParse(value?.toString() ?? '');
  }

  rh.ProxySettings? _proxySettings(RequestOptions options) {
    final value = options.extra['networkProxy'];
    if (value is! String || value.isEmpty) {
      return _baseSettings.proxySettings;
    }
    final proxy = value.startsWith('http://') || value.startsWith('https://')
        ? value
        : 'http://$value';
    return rh.ProxySettings.proxy(proxy);
  }

  rh.HttpVersionPref _toHttpVersion(NetworkProtocol protocol) {
    return switch (protocol) {
      NetworkProtocol.auto => rh.HttpVersionPref.all,
      NetworkProtocol.http1 => rh.HttpVersionPref.http1_1,
      NetworkProtocol.http2 => rh.HttpVersionPref.http2,
    };
  }

  bool _canFallback(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Object error,
  ) {
    if (_protocol != NetworkProtocol.http2 ||
        requestStream != null ||
        !{'GET', 'HEAD', 'OPTIONS'}.contains(options.method.toUpperCase())) {
      return false;
    }
    return error is rh.RhttpConnectionException ||
        error is rh.RhttpTimeoutException ||
        error is rh.RhttpUnknownException;
  }

  DioException _toDioException(RequestOptions options, Object error) {
    final type = switch (error) {
      rh.RhttpCancelException() => DioExceptionType.cancel,
      rh.RhttpTimeoutException() => DioExceptionType.connectionTimeout,
      rh.RhttpInvalidCertificateException() => DioExceptionType.badCertificate,
      rh.RhttpStatusCodeException() => DioExceptionType.badResponse,
      rh.RhttpConnectionException() => DioExceptionType.connectionError,
      _ => DioExceptionType.unknown,
    };
    return DioException(
      requestOptions: options,
      type: type,
      error: error,
      message: error.toString(),
    );
  }

  @override
  void close({bool force = false}) {
    if (_closed) return;
    _closed = true;
    _client.dispose(cancelRunningRequests: force);
  }
}

/// 创建一个 rhttp Dio 适配器。
Future<HttpClientAdapter> createRhttpDioAdapter({
  required NetworkProtocol protocol,
  String? proxy,
}) async {
  final proxySettings = proxy == null || proxy.isEmpty
      ? null
      : rh.ProxySettings.proxy(
          proxy.startsWith('http://') || proxy.startsWith('https://')
              ? proxy
              : 'http://$proxy',
        );
  final settings = rh.ClientSettings(
    cookieSettings: const rh.CookieSettings.none(),
    httpVersionPref: switch (protocol) {
      NetworkProtocol.auto => rh.HttpVersionPref.all,
      NetworkProtocol.http1 => rh.HttpVersionPref.http1_1,
      NetworkProtocol.http2 => rh.HttpVersionPref.http2,
    },
    proxySettings: proxySettings,
    throwOnStatusCode: false,
    timeoutSettings: const rh.TimeoutSettings(
      keepAliveTimeout: Duration(seconds: 60),
      keepAlivePing: Duration(seconds: 30),
      connectTimeout: Duration(seconds: 15),
    ),
  );
  final client = await rh.RhttpClient.create(settings: settings);
  return RhttpDioAdapter(
    client: client,
    baseSettings: settings,
    protocol: protocol,
  );
}
