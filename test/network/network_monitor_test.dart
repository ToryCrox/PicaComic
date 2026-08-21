import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pica_comic/base.dart';
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
}
