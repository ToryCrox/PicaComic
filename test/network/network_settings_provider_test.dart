import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/foundation/app_settings_provider.dart';
import 'package:pica_comic/network/network_config.dart';
import 'package:pica_comic/network/network_settings_provider.dart';

void main() {
  test('命名网络配置还原且 Web 的实际后端固定 Dio', () {
    final values = Map<String, String>.from(defaultAppSettings);
    values[AppSettingKeys.proxy] = '';
    values[AppSettingKeys.hostsEnabled] = '1';
    values[AppSettingKeys.networkProtocol] = 'http2';
    final snapshot = AppSettingsSnapshot(values);
    final state = NetworkSettingsState.fromSnapshot(snapshot, isWeb: false);
    expect(state.proxy, '');
    expect(state.useSystemProxy, isFalse);
    expect(state.hostsEnabled, isTrue);
    expect(state.backend, NetworkBackend.rhttp);
    expect(state.protocol, NetworkProtocol.http2);
    expect(
      NetworkSettingsState.fromSnapshot(snapshot, isWeb: true).backend,
      NetworkBackend.dio,
    );
  });

  test('配置保存后才应用，代理沿用完整数据入口，Hosts 重载顺序正确', () async {
    final values = Map<String, String>.from(defaultAppSettings);
    final calls = <String>[];
    final container = _container(values, calls);
    addTearDown(container.dispose);
    final controller = container.read(
      networkSettingsControllerProvider.notifier,
    );
    await controller.setProtocol(NetworkProtocol.http2);
    expect(calls, ['settings', 'client:http2']);
    calls.clear();
    await controller.setProxy('127.0.0.1:7890');
    expect(values[AppSettingKeys.proxy], '127.0.0.1:7890');
    expect(calls, ['data', 'proxy', 'client:http2']);
    calls.clear();
    await controller.setHostsEnabled(true);
    expect(calls, ['settings', 'hosts', 'proxy', 'client:http2']);
    expect(
      container.read(networkSettingsControllerProvider).hostsEnabled,
      isTrue,
    );
  });

  test('应用失败保留已保存设置并向调用方暴露异常', () async {
    final values = Map<String, String>.from(defaultAppSettings);
    final calls = <String>[];
    final container = _container(values, calls, failApply: true);
    addTearDown(container.dispose);
    await expectLater(
      container
          .read(networkSettingsControllerProvider.notifier)
          .setProtocol(NetworkProtocol.http1),
      throwsStateError,
    );
    expect(calls, ['settings', 'client:http1']);
    expect(values[AppSettingKeys.networkProtocol], 'http1');
    expect(
      container.read(networkSettingsControllerProvider).protocol,
      NetworkProtocol.http1,
    );
  });

  test('保存失败不应用网络，快速连续修改按顺序完成', () async {
    final values = Map<String, String>.from(defaultAppSettings);
    final calls = <String>[];
    final failing = _container(values, calls, failSave: true);
    await expectLater(
      failing
          .read(networkSettingsControllerProvider.notifier)
          .setProtocol(NetworkProtocol.http2),
      throwsStateError,
    );
    expect(calls, ['settings']);
    failing.dispose();
    calls.clear();
    final container = _container(values, calls);
    addTearDown(container.dispose);
    final controller = container.read(
      networkSettingsControllerProvider.notifier,
    );
    await Future.wait([
      controller.setProtocol(NetworkProtocol.http1),
      controller.setProtocol(NetworkProtocol.http2),
    ]);
    expect(calls, ['settings', 'client:http1', 'settings', 'client:http2']);
  });
}

/// 使用隔离的旧存储和副作用，不修改实际代理和 Dio。
ProviderContainer _container(
  Map<String, String> values,
  List<String> calls, {
  bool failApply = false,
  bool failSave = false,
}) {
  final changes = StreamController<void>.broadcast();
  final repository = AppSettingsRepository(
    readValues: () => values,
    changes: changes.stream,
    notifyChanges: () => changes.add(null),
    saveSettings: (_) async {
      calls.add('settings');
      if (failSave) throw StateError('保存失败');
    },
    saveData: (_) async => calls.add('data'),
  );
  final container = ProviderContainer(
    overrides: [
      appSettingsRepositoryProvider.overrideWithValue(repository),
      networkSettingsRuntimeProvider.overrideWithValue(
        NetworkSettingsRuntime(
          applyProxy: () async => calls.add('proxy'),
          reloadHosts: () => calls.add('hosts'),
          applyClient: () async {
            calls.add('client:${values[AppSettingKeys.networkProtocol]}');
            if (failApply) throw StateError('应用失败');
          },
        ),
      ),
    ],
  );
  addTearDown(changes.close);
  return container;
}
