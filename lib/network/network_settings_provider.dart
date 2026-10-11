import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:synchronized/synchronized.dart';

import '../foundation/app_settings_provider.dart';
import 'http_client.dart';
import 'http_proxy.dart';
import 'network_client_manager.dart';
import 'network_config.dart';

part 'network_settings_provider.g.dart';

/// 网络配置的类型化状态，保留代理的系统代理标记。
class NetworkSettingsState {
  const NetworkSettingsState({
    required this.proxy,
    required this.backend,
    required this.protocol,
    required this.hostsEnabled,
  });

  final String proxy;
  final NetworkBackend backend;
  final NetworkProtocol protocol;
  final bool hostsEnabled;

  bool get useSystemProxy => proxy == '0';

  @override
  bool operator ==(Object other) =>
      other is NetworkSettingsState &&
      proxy == other.proxy &&
      backend == other.backend &&
      protocol == other.protocol &&
      hostsEnabled == other.hostsEnabled;

  @override
  int get hashCode => Object.hash(proxy, backend, protocol, hostsEnabled);

  /// 从命名设置快照还原网络配置，Web 始终使用 Dio。
  factory NetworkSettingsState.fromSnapshot(
    AppSettingsSnapshot snapshot, {
    bool isWeb = kIsWeb,
  }) {
    return NetworkSettingsState(
      proxy: snapshot.value(AppSettingKeys.proxy, '0'),
      backend: isWeb
          ? NetworkBackend.dio
          : NetworkConfigExtension.fromValue(
              snapshot.value(AppSettingKeys.networkBackend),
            ),
      protocol: NetworkProtocolExtension.fromValue(
        snapshot.value(AppSettingKeys.networkProtocol),
      ),
      hostsEnabled: snapshot.enabled(AppSettingKeys.hostsEnabled),
    );
  }
}

/// 网络配置的副作用边界，可替换以避免测试修改原生代理或共享 Dio。
class NetworkSettingsRuntime {
  const NetworkSettingsRuntime({
    required this.applyProxy,
    required this.applyClient,
    required this.reloadHosts,
  });

  final Future<void> Function() applyProxy;
  final Future<void> Function() applyClient;
  final void Function() reloadHosts;
}

/// 使用现有应用级网络管理器，不接管其生命周期。
final networkSettingsRuntimeProvider = Provider<NetworkSettingsRuntime>((ref) {
  final manager = ref.read(networkClientManagerProvider);
  return NetworkSettingsRuntime(
    applyProxy: setNetworkProxy,
    applyClient: manager.applySettings,
    reloadHosts: HttpProxyServer.reload,
  );
});

/// 网络设置操作入口，串行完成保存和应用，失败保留用户配置。
@Riverpod(keepAlive: true)
class NetworkSettingsController extends _$NetworkSettingsController {
  final Lock _lock = Lock();

  @override
  NetworkSettingsState build() {
    return ref.watch(
      appSettingsProvider.select(NetworkSettingsState.fromSnapshot),
    );
  }

  /// 保存并应用代理。
  Future<void> setProxy(String proxy) =>
      _update(AppSettingKeys.proxy, proxy, fullData: true, applyProxy: true);

  /// 保存并切换网络后端。
  Future<void> setBackend(NetworkBackend backend) {
    if (kIsWeb) return Future.value();
    return _update(AppSettingKeys.networkBackend, backend.value);
  }

  /// 保存并切换 HTTP 协议。
  Future<void> setProtocol(NetworkProtocol protocol) =>
      _update(AppSettingKeys.networkProtocol, protocol.value);

  /// 保存 Hosts 开关，并保持现有代理服务器重载行为。
  Future<void> setHostsEnabled(bool enabled) => _update(
    AppSettingKeys.hostsEnabled,
    enabled ? '1' : '0',
    applyProxy: true,
    reloadHosts: enabled,
  );

  /// 保存成功后才应用传输设置，应用异常交由页面展示。
  Future<void> _update(
    String key,
    String value, {
    bool fullData = false,
    bool applyProxy = false,
    bool reloadHosts = false,
  }) {
    return _lock.synchronized(() async {
      final settings = ref.read(appSettingsProvider.notifier);
      final runtime = ref.read(networkSettingsRuntimeProvider);
      await settings.setValue(key, value, fullData: fullData);
      if (reloadHosts) runtime.reloadHosts();
      if (applyProxy) await runtime.applyProxy();
      await runtime.applyClient();
    });
  }
}
