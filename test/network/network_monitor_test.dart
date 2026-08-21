import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/network/network_interceptors.dart';
import 'package:pica_comic/network/network_log.dart';
import 'package:pica_comic/network/network_monitor_settings.dart';
import 'package:pica_comic/network/network_speed_monitor.dart';

void main() {
  test('NetworkSpeedMonitor 每秒汇总并推送速度', () async {
    final monitor = NetworkSpeedMonitor(
      interval: const Duration(milliseconds: 10),
    );
    addTearDown(monitor.dispose);
    final values = <NetworkSpeedData>[];
    final subscription = monitor.speedStream.listen(values.add);
    addTearDown(subscription.cancel);

    monitor.start();
    monitor.recordDownload(1024);
    monitor.recordUpload(512);
    await Future<void>.delayed(const Duration(milliseconds: 25));

    expect(values, isNotEmpty);
    expect(values.first.downloadSpeed, greaterThan(0));
    expect(values.first.uploadSpeed, greaterThan(0));
    monitor.stop();
    expect(monitor.isRunning, isFalse);
  });

  test('networkSpeed Provider 销毁后停止速度计时器', () async {
    final monitor = NetworkSpeedMonitor(
      interval: const Duration(milliseconds: 10),
    );
    final container = ProviderContainer(
      overrides: [networkSpeedMonitorProvider.overrideWithValue(monitor)],
    );
    addTearDown(() {
      container.dispose();
      monitor.dispose();
    });

    final subscription = container.listen(networkSpeedProvider, (_, _) {});
    await Future<void>.delayed(const Duration(milliseconds: 15));
    expect(monitor.isRunning, isTrue);
    subscription.close();
    container.dispose();
    expect(monitor.isRunning, isFalse);
  });

  test('NetworkLogController 记录请求、响应并限制 500 条', () {
    final oldValue = appdata.settings[networkLogCollectingSettingIndex];
    appdata.settings[networkLogCollectingSettingIndex] = '1';
    addTearDown(
      () => appdata.settings[networkLogCollectingSettingIndex] = oldValue,
    );

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(networkLogControllerProvider.notifier);
    final options = RequestOptions(
      method: 'POST',
      path: 'https://example.com/api',
      data: const {'hello': 'world'},
      headers: const {'X-Test': 'value'},
    );
    final token = controller.beginRequest(options);
    expect(token, isNotNull);

    final response = Response<Map<String, dynamic>>(
      requestOptions: options,
      statusCode: 200,
      data: const {'ok': true},
      headers: Headers.fromMap(const {
        'content-type': ['application/json'],
      }),
      extra: const {
        'networkBackend': 'rhttp',
        'networkProtocol': 'http2',
        'networkProtocolSource': 'actual',
      },
    );
    controller.completeResponse(token!, response);

    var state = container.read(networkLogControllerProvider);
    expect(state.logs, hasLength(1));
    expect(state.logs.single.statusCode, 200);
    expect(state.logs.single.protocolInfo.displayText, 'HTTP/2 · 实际');
    expect(state.logs.single.requestBody?.content, contains('hello'));

    for (var i = 0; i <= networkLogMaxCount; i++) {
      controller.beginRequest(
        RequestOptions(method: 'GET', path: 'https://example.com/$i'),
      );
    }
    state = container.read(networkLogControllerProvider);
    expect(state.logs, hasLength(networkLogMaxCount));
    expect(state.logs.any((log) => log.url.endsWith('/0')), isFalse);
    expect(state.filteredLogs.first.url, endsWith('/500'));
  });

  test('NetworkLogBody 对二进制和 64 KB 文本采用不同策略', () {
    final binary = NetworkLogBody.capture(List<int>.filled(10, 1));
    expect(binary?.isBinary, isTrue);
    expect(binary?.byteLength, 10);

    final text = NetworkLogBody.capture('a' * (networkLogBodyMaxLength + 1));
    expect(text?.isTruncated, isTrue);
    expect(text?.content.length, networkLogBodyMaxLength);
    expect(text?.byteLength, networkLogBodyMaxLength + 1);
  });

  test('Protocol 优先使用实际值并保留来源', () {
    final options = RequestOptions(path: 'https://example.com');
    final actual = protocolInfoFromResponse(
      Response(
        requestOptions: options,
        extra: const {
          'networkBackend': 'rhttp',
          'networkProtocol': 'http2',
          'networkProtocolSource': 'actual',
        },
      ),
    );
    final configured = protocolInfoFromResponse(
      Response(
        requestOptions: options,
        extra: const {
          'networkProtocol': 'http1',
          'networkProtocolSource': 'configured',
        },
      ),
    );
    final fallback = protocolInfoFromResponse(
      Response(
        requestOptions: options,
        extra: const {
          'networkProtocol': 'http1',
          'networkProtocolSource': 'fallback',
          'networkFallback': 'http1',
        },
      ),
    );
    final unknown = protocolInfoFromResponse(Response(requestOptions: options));

    expect(actual.displayText, 'HTTP/2 · 实际');
    expect(configured.displayText, 'HTTP/1.1 · 配置');
    expect(fallback.displayText, 'HTTP/1.1 · fallback');
    expect(fallback.fallback, 'http1');
    expect(unknown.displayText, 'Unknown · 未知');
  });

  test('网络日志可以分类、关联图片路径并合并分片', () {
    final oldValue = appdata.settings[networkLogCollectingSettingIndex];
    appdata.settings[networkLogCollectingSettingIndex] = '1';
    addTearDown(
      () => appdata.settings[networkLogCollectingSettingIndex] = oldValue,
    );

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(networkLogControllerProvider.notifier);

    NetworkLogRequestToken addImagePart(String path) {
      final options = RequestOptions(
        method: 'GET',
        path: path,
        extra: const {
          networkRequestKindExtraKey: 'image',
          networkTransferIdExtraKey: 'download-1',
        },
      );
      final token = controller.beginRequest(options)!;
      controller.completeResponse(
        token,
        Response<List<int>>(
          requestOptions: options,
          statusCode: 206,
          data: List<int>.filled(4, 1),
          headers: Headers.fromMap(const {
            'content-type': ['image/jpeg'],
          }),
        ),
      );
      return token;
    }

    addImagePart('https://example.com/image');
    addImagePart('https://example.com/image');
    controller.reportArtifactReady(
      transferId: 'download-1',
      path: 'C:/cache/image.jpg',
      source: NetworkArtifactSource.download,
    );
    controller.setRequestKindFilter(NetworkRequestKind.image);

    final entries = container.read(networkLogEntriesProvider);
    expect(entries, hasLength(1));
    expect(entries.single.isGrouped, isTrue);
    expect(entries.single.logs, hasLength(2));
    expect(entries.single.artifactPath, 'C:/cache/image.jpg');
    expect(entries.single.requestKind, NetworkRequestKind.image);
    expect(entries.single.byteLength, 8);
    expect(entries.single.protocolDisplayText, 'Unknown · 未知');
  });

  test('请求类型根据响应 Content-Type 兜底分类', () {
    expect(
      classifyNetworkResponse(
        contentType: 'text/html; charset=utf-8',
        url: Uri.parse('https://example.com/page'),
      ),
      NetworkRequestKind.html,
    );
    expect(
      classifyNetworkResponse(
        contentType: 'application/json',
        url: Uri.parse('https://example.com/data'),
      ),
      NetworkRequestKind.api,
    );
    expect(
      inferNetworkRequestKind(Uri.parse('https://example.com/a.webp')),
      NetworkRequestKind.image,
    );
  });

  test('api.php 按响应 Content-Type 分类并保留实际 URL fallback', () {
    final url = Uri.parse('https://exhentai.org/api.php');
    expect(inferNetworkRequestKind(url), NetworkRequestKind.api);
    expect(
      classifyNetworkResponse(
        contentType: 'text/html; charset=UTF-8',
        url: url,
      ),
      NetworkRequestKind.html,
    );
    expect(
      classifyNetworkResponse(contentType: 'image/jpeg', url: url),
      NetworkRequestKind.image,
    );
    expect(
      classifyNetworkResponse(contentType: null, url: url),
      NetworkRequestKind.api,
    );

    final log = NetworkLog(
      id: 'api-image',
      url: 'https://exhentai.org/api.php',
      method: 'POST',
      requestTime: DateTime(2026),
      requestKind: NetworkRequestKind.image,
      contentType: 'image/jpeg',
      artifactPath: 'C:/cache/api-response.jpg',
    );
    expect(log.isImageResponse, isTrue);
  });

  test('图片下载上下文不会把 api.php 关联到最终图片文件', () {
    final oldValue = appdata.settings[networkLogCollectingSettingIndex];
    appdata.settings[networkLogCollectingSettingIndex] = '1';
    addTearDown(
      () => appdata.settings[networkLogCollectingSettingIndex] = oldValue,
    );

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(networkLogControllerProvider.notifier);
    final interceptor = NetworkLogInterceptor(controller);

    runNetworkTelemetryContext<void>(
      transferId: 'image-download-1',
      requestKind: NetworkRequestKind.image,
      action: () {
        final imageOptions = RequestOptions(
          method: 'GET',
          path: 'https://example.com/image-content',
        );
        interceptor.onRequest(imageOptions, RequestInterceptorHandler());

        final apiOptions = RequestOptions(
          method: 'POST',
          path: 'https://exhentai.org/api.php',
        );
        interceptor.onRequest(apiOptions, RequestInterceptorHandler());

        expect(
          imageOptions.extra[networkTransferIdExtraKey],
          'image-download-1',
        );
        expect(apiOptions.extra[networkTransferIdExtraKey], isNull);
      },
    );

    final logs = container.read(networkLogControllerProvider).logs;
    expect(logs, hasLength(2));
    expect(logs.first.requestKind, NetworkRequestKind.image);
    expect(logs.first.transferId, 'image-download-1');
    expect(logs.last.requestKind, NetworkRequestKind.api);
    expect(logs.last.transferId, isNull);
  });
}
