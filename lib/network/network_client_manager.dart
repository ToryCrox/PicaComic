import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../base.dart';
import '../foundation/log.dart';
import 'app_dio.dart';
import 'cloudflare.dart';
import 'cookie_jar.dart';
import 'http_client.dart';
import 'network_config.dart';
import 'network_interceptors.dart';
import 'network_telemetry.dart';
import 'rhttp_dio_adapter.dart';
import 'rhttp_init.dart';

/// 管理应用内漫画网络请求的两个共享 Dio。
// TODO: 后续调整网络依赖时，将设置读取连带改为注入配置或仓库；共享 Dio 仍保持应用级生命周期。
class NetworkClientManager {
  NetworkClientManager._();

  /// 应用级单例。
  static final instance = NetworkClientManager._();

  late final Dio apiDio;
  late final Dio mediaDio;

  late final _SwitchingHttpClientAdapter _apiAdapter;
  late final _SwitchingHttpClientAdapter _mediaAdapter;

  bool _dioCreated = false;
  bool _initialized = false;
  Future<void>? _initializationFuture;
  bool _rhttpAvailable = false;
  bool _disposed = false;
  NetworkTelemetryBridge _telemetry = NetworkTelemetryBridge.instance;

  /// 当前实际生效的网络后端。
  NetworkBackend get effectiveBackend {
    if (kIsWeb || !_rhttpAvailable) {
      return NetworkBackend.dio;
    }
    return appdata.appSettings.networkBackend;
  }

  /// 当前配置的 HTTP 协议偏好。
  NetworkProtocol get protocol => appdata.appSettings.networkProtocol;

  /// 注入 Riverpod 管理的网络监控状态。
  void configureTelemetry(NetworkTelemetryBridge telemetry) {
    _telemetry = telemetry;
  }

  /// 创建可立即使用的 Dio 和基础适配器。
  ///
  /// 该步骤不初始化可选的 rhttp 后端，因此可以在首屏前快速完成。
  void prepare() {
    if (_disposed) {
      throw StateError('NetworkClientManager has been disposed.');
    }
    _createDioIfNeeded();
  }

  /// 初始化网络运行时和共享 Dio。
  Future<void> initialize() => applyPreferredBackend();

  /// 首屏后应用首选网络后端、协议和代理设置。
  ///
  /// 同时调用时共享同一个 Future；失败后清除 Future，调用方可以重试。
  Future<void> applyPreferredBackend() {
    prepare();
    if (_initialized) return Future.value();
    final pending = _initializationFuture;
    if (pending != null) return pending;

    final future = _initializePreferredBackend();
    _initializationFuture = future;
    return future;
  }

  Future<void> _initializePreferredBackend() async {
    try {
      if (_initialized) return;

      if (!kIsWeb &&
          appdata.appSettings.networkBackend == NetworkBackend.rhttp) {
        try {
          await initializeRhttp();
          _rhttpAvailable = true;
        } catch (e, s) {
          _rhttpAvailable = false;
          Log.e('rhttp initialization failed, fallback to Dio.\n$e\n$s');
        }
      }

      await _applySettings();
      _initialized = true;
    } catch (_) {
      _initializationFuture = null;
      rethrow;
    }
  }

  /// 应用网络设置，后续新请求会使用新的传输层。
  Future<void> applySettings() async {
    if (_disposed) return;
    if (!_initialized) {
      await applyPreferredBackend();
      return;
    }
    await _applySettings();
  }

  Future<void> _applySettings() async {
    _createDioIfNeeded();

    if (!kIsWeb &&
        appdata.appSettings.networkBackend == NetworkBackend.rhttp &&
        !_rhttpAvailable) {
      try {
        await initializeRhttp();
        _rhttpAvailable = true;
      } catch (e, s) {
        Log.e('rhttp is unavailable, keep using Dio.\n$e\n$s');
      }
    }

    final backend = effectiveBackend;
    final currentProtocol = protocol;
    String? proxy;
    try {
      proxy = await getProxy();
    } catch (e, s) {
      Log.w('Failed to read network proxy.\n$e\n$s');
    }

    try {
      final apiTransport = await _createTransport(
        backend: backend,
        protocol: currentProtocol,
        proxy: proxy,
      );
      final mediaTransport = await _createTransport(
        backend: backend,
        protocol: currentProtocol,
        proxy: proxy,
      );
      _apiAdapter.replace(apiTransport);
      _mediaAdapter.replace(mediaTransport);
    } catch (e, s) {
      if (backend == NetworkBackend.rhttp) {
        _rhttpAvailable = false;
        Log.e('rhttp transport creation failed, fallback to Dio.\n$e\n$s');
        final apiTransport = await _createTransport(
          backend: NetworkBackend.dio,
          protocol: currentProtocol,
          proxy: proxy,
        );
        final mediaTransport = await _createTransport(
          backend: NetworkBackend.dio,
          protocol: currentProtocol,
          proxy: proxy,
        );
        _apiAdapter.replace(apiTransport);
        _mediaAdapter.replace(mediaTransport);
        return;
      }
      rethrow;
    }
  }

  Future<HttpClientAdapter> _createTransport({
    required NetworkBackend backend,
    required NetworkProtocol protocol,
    required String? proxy,
  }) {
    if (backend == NetworkBackend.rhttp) {
      return createRhttpDioAdapter(protocol: protocol, proxy: proxy);
    }
    return Future.value(AppHttpAdapter(protocol));
  }

  void _createDioIfNeeded() {
    if (_dioCreated) return;
    _apiAdapter = _SwitchingHttpClientAdapter();
    _mediaAdapter = _SwitchingHttpClientAdapter();
    apiDio =
        Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              sendTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
            ),
          )
          ..httpClientAdapter = _apiAdapter
          ..interceptors.add(NetworkCookieInterceptor())
          ..interceptors.add(CloudflareInterceptor())
          ..interceptors.add(NetworkSpeedInterceptor(_telemetry.speedMonitor))
          ..interceptors.add(NetworkLogInterceptor(_telemetry.logSink))
          ..interceptors.add(MyLogInterceptor());
    mediaDio =
        Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              sendTimeout: const Duration(seconds: 30),
              receiveTimeout: const Duration(seconds: 60),
            ),
          )
          ..httpClientAdapter = _mediaAdapter
          ..interceptors.add(NetworkCookieInterceptor())
          ..interceptors.add(CloudflareInterceptor())
          ..interceptors.add(NetworkSpeedInterceptor(_telemetry.speedMonitor))
          ..interceptors.add(NetworkLogInterceptor(_telemetry.logSink))
          ..interceptors.add(MyLogInterceptor());
    _dioCreated = true;
  }

  /// 释放两个共享 Dio 和底层网络传输。
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    if (_dioCreated) {
      _apiAdapter.close(force: true);
      _mediaAdapter.close(force: true);
    }
  }
}

/// 便于非 Widget 网络代码访问同一个应用级管理器。
NetworkClientManager get networkClientManager => NetworkClientManager.instance;

/// Riverpod 应用级网络管理器。
final networkClientManagerProvider = Provider<NetworkClientManager>((ref) {
  final manager = NetworkClientManager.instance;
  manager.configureTelemetry(ref.read(networkTelemetryBridgeProvider));
  // 这是应用级单例，ProviderScope（例如页面级测试容器）销毁时不能
  // 释放它，否则其他页面或后续 Provider 会拿到已经关闭的 Dio。
  return manager;
});

class _SwitchingHttpClientAdapter implements HttpClientAdapter {
  _AdapterGeneration _current = _AdapterGeneration(HttpClientAdapter());
  bool _closed = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => _current.fetch(options, requestStream, cancelFuture);

  void replace(HttpClientAdapter adapter) {
    if (_closed) {
      adapter.close(force: true);
      return;
    }
    final old = _current;
    _current = _AdapterGeneration(adapter);
    old.retire();
  }

  @override
  void close({bool force = false}) {
    if (_closed) return;
    _closed = true;
    _current.close(force: force);
  }
}

class _AdapterGeneration {
  _AdapterGeneration(this.adapter);

  final HttpClientAdapter adapter;
  int _activeRequests = 0;
  bool _retired = false;
  bool _closed = false;

  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    _activeRequests++;
    try {
      final response = await adapter.fetch(
        options,
        requestStream,
        cancelFuture,
      );
      var released = false;
      void release() {
        if (released) return;
        released = true;
        _activeRequests--;
        _closeIfRetired();
      }

      final source = response.stream;
      final controller = StreamController<Uint8List>();
      late StreamSubscription<Uint8List> subscription;
      controller.onListen = () {
        subscription = source.listen(
          controller.add,
          onError: controller.addError,
          onDone: () {
            release();
            controller.close();
          },
          cancelOnError: true,
        );
      };
      controller.onCancel = () async {
        await subscription.cancel();
        release();
      };

      final wrapped = ResponseBody(
        controller.stream,
        response.statusCode,
        statusMessage: response.statusMessage,
        isRedirect: response.isRedirect,
        redirects: response.redirects,
        headers: response.headers,
        onClose: () {
          release();
        },
      );
      wrapped.extra = response.extra;
      return wrapped;
    } catch (e) {
      _activeRequests--;
      _closeIfRetired();
      rethrow;
    }
  }

  void retire() {
    _retired = true;
    _closeIfRetired();
  }

  void close({bool force = false}) {
    if (_closed) return;
    _closed = true;
    adapter.close(force: force);
  }

  void _closeIfRetired() {
    if (_retired && _activeRequests == 0) {
      close();
    }
  }
}
