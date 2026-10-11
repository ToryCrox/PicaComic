part of pica_settings;

/// 网络配置面板，观察已保存配置并通过 Notifier 应用修改。
class NetworkSettings extends ConsumerStatefulWidget {
  const NetworkSettings({super.key});

  @override
  ConsumerState<NetworkSettings> createState() => _NetworkSettingsState();
}

class _NetworkSettingsState extends ConsumerState<NetworkSettings> {
  /// 保存及应用失败时显示现有网络错误提示。
  Future<void> _applyNetworkSettings(Future<void> Function() action) async {
    try {
      await action();
    } catch (e, s) {
      Log.e('Apply network settings failed.\n$e\n$s');
      if (mounted) {
        showToast(message: '网络设置应用失败');
      }
    }
  }

  String _backendLabel(NetworkBackend backend) {
    return switch (backend) {
      NetworkBackend.rhttp => 'rhttp',
      NetworkBackend.dio => 'Dio',
    };
  }

  String _protocolLabel(NetworkProtocol protocol) {
    return switch (protocol) {
      NetworkProtocol.auto => '自动',
      NetworkProtocol.http1 => 'HTTP/1.1',
      NetworkProtocol.http2 => 'HTTP/2',
    };
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(appSettingsProvider);
    final settings = ref.watch(networkSettingsControllerProvider);
    final controller = ref.read(networkSettingsControllerProvider.notifier);
    final backend = settings.backend;
    final protocol = settings.protocol;
    final showSpeedBall = ref.watch(networkSpeedBallEnabledProvider);
    final collectNetworkLogs = ref.watch(networkLogCollectingProvider);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const ListTile(title: Text("Http Proxy")),
        ListTile(
          leading: const Icon(Icons.network_ping),
          title: Text("设置代理".tl),
          trailing: const Icon(Icons.arrow_right),
          onTap: () {
            setProxy(context);
          },
        ),
        ListTile(
          leading: const Icon(Icons.swap_horiz),
          title: const Text('网络后端'),
          subtitle: kIsWeb ? const Text('Web 平台固定使用 Dio') : null,
          trailing: DropdownButton<NetworkBackend>(
            mouseCursor: appClickableMouseCursor,
            dropdownMenuItemMouseCursor: appClickableMouseCursor,
            value: backend,
            onChanged: kIsWeb
                ? null
                : (value) {
                    if (value == null) return;
                    unawaited(
                      _applyNetworkSettings(() => controller.setBackend(value)),
                    );
                  },
            items: NetworkBackend.values
                .map(
                  (value) => DropdownMenuItem(
                    value: value,
                    child: Text(_backendLabel(value)),
                  ),
                )
                .toList(),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.http),
          title: const Text('HTTP 协议'),
          trailing: DropdownButton<NetworkProtocol>(
            mouseCursor: appClickableMouseCursor,
            dropdownMenuItemMouseCursor: appClickableMouseCursor,
            value: protocol,
            onChanged: (value) {
              if (value == null) return;
              unawaited(
                _applyNetworkSettings(() => controller.setProtocol(value)),
              );
            },
            items: NetworkProtocol.values
                .map(
                  (value) => DropdownMenuItem(
                    value: value,
                    child: Text(_protocolLabel(value)),
                  ),
                )
                .toList(),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.speed),
          title: const Text('显示网速悬浮球'),
          subtitle: const Text('在应用内容上显示实时上传和下载速度'),
          trailing: Switch(
            value: showSpeedBall,
            onChanged: (value) => ref
                .read(networkMonitorSettingsProvider.notifier)
                .setShowSpeedBall(value),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.network_check),
          title: const Text('网络日志采集'),
          subtitle: const Text('仅保存在内存中，单条请求体最多 64 KB'),
          trailing: Switch(
            value: collectNetworkLogs,
            onChanged: (value) => ref
                .read(networkLogControllerProvider.notifier)
                .setCollecting(value),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.network_check),
          title: const Text('查看网络日志'),
          subtitle: const Text('查看应用网络请求'),
          onTap: () => NetworkLogPage.show(context),
        ),
        ListTile(
          title: Row(
            children: [
              const Text("Hosts"),
              const SizedBox(width: 2),
              InkWell(
                mouseCursor: appClickableMouseCursor,
                borderRadius: const BorderRadius.all(Radius.circular(18)),
                onTap: () => showDialogMessage(
                  context,
                  "警告".tl,
                  "${"此功能已不再受支持".tl}\n${"请勿反馈相关问题".tl}",
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.red,
                  size: 18,
                ),
              ),
            ],
          ),
        ),
        ListTile(
          leading: const Icon(Icons.dns),
          title: Text("启用".tl),
          trailing: Switch(
            value: settings.hostsEnabled,
            onChanged: (value) {
              unawaited(
                _applyNetworkSettings(() => controller.setHostsEnabled(value)),
              );
            },
          ),
        ),
        ListTile(
          leading: const Icon(Icons.rule),
          title: Text("规则".tl),
          trailing: const Icon(Icons.arrow_right),
          onTap: () {
            App.globalTo(() => const EditRuleView());
          },
        ),
        // ListTile(
        //   leading: const Icon(Icons.help),
        //   title: Text("帮助".tl),
        //   trailing: const Icon(Icons.arrow_right),
        //   onTap: (){
        //     launchUrlString("https://github.com/user/repo/blob/master/help.md");
        //   },
        // ),
        Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).padding.bottom,
          ),
        ),
      ],
    );
  }
}

class EditRuleView extends ConsumerStatefulWidget {
  const EditRuleView({super.key});

  @override
  ConsumerState<EditRuleView> createState() => _EditRuleViewState();
}

class _EditRuleViewState extends ConsumerState<EditRuleView> {
  final file = File("${App.dataPath}/rule.json");

  late TextEditingController controller;

  @override
  void initState() {
    HttpProxyServer.createConfigFile();
    controller = TextEditingController(text: file.readAsStringSync());
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
    file.writeAsStringSync(controller.text, mode: FileMode.writeOnly);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(appSettingsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text("rule.json")),
      body: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            8,
            0,
            8,
            MediaQuery.of(context).padding.bottom,
          ),
          child: TextField(
            keyboardType: TextInputType.multiline,
            maxLines: null,
            decoration: const InputDecoration(border: InputBorder.none),
            controller: controller,
          ),
        ),
      ),
    );
  }
}
