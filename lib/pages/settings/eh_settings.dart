part of pica_settings;

class EhSettings extends ConsumerStatefulWidget {
  const EhSettings(this.popUp, {Key? key}) : super(key: key);
  final bool popUp;

  @override
  ConsumerState<EhSettings> createState() => _EhSettingsState();
}

class _EhSettingsState extends ConsumerState<EhSettings> {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const ListTile(title: Text("E-Hentai")),
        ListTile(
          leading: const Icon(Icons.dns),
          title: Text("画廊站点".tl),
          trailing: Select(
            initialValue: int.parse(
              ref.watch(appSettingProvider(AppSettingKeys.ehSite)),
            ),
            width: 150,
            values: const ["e-hentai.org", "exhentai.org"],
            onChange: (i) {
              _saveSetting(
                ref,
                AppSettingKeys.ehSite,
                i.toString(),
                persist: false,
              );
              _persistSettings(ref);
            },
          ),
          //onTap: () => setEhDomain(context),
        ),
        ListTile(
          leading: const Icon(Icons.image),
          title: Text("优先加载原图".tl),
          subtitle: Text("可能导致加载失败".tl),
          trailing: Switch(
            value:
                ref.watch(
                  appSettingProvider(AppSettingKeys.ehPreferOriginal),
                ) ==
                "1",
            onChanged: (b) {
              setState(() {
                _saveSetting(
                  ref,
                  AppSettingKeys.ehPreferOriginal,
                  b ? "1" : "0",
                  persist: false,
                );
              });
              _persistSettings(ref);
            },
          ),
        ),
        ListTile(
          leading: const Icon(Icons.notifications_off_outlined),
          title: Text("忽略警告".tl),
          trailing: Switch(
            value:
                ref.watch(
                  appSettingProvider(AppSettingKeys.ehIgnoreWarnings),
                ) ==
                "1",
            onChanged: (b) {
              setState(() {
                _saveSetting(
                  ref,
                  AppSettingKeys.ehIgnoreWarnings,
                  b ? "1" : "0",
                  persist: false,
                );
              });
              _persistSettings(ref);
            },
          ),
        ),
        ListTile(
          leading: const Icon(Icons.notes),
          title: Text("优先显示副标题".tl),
          subtitle: Text("适用于已下载的画廊".tl),
          trailing: Switch(
            value:
                ref.watch(
                  appSettingProvider(AppSettingKeys.ehDownloadedUseSubtitle),
                ) ==
                "1",
            onChanged: (b) {
              setState(() {
                _saveSetting(
                  ref,
                  AppSettingKeys.ehDownloadedUseSubtitle,
                  b ? "1" : "0",
                  persist: false,
                );
              });
              _persistSettings(ref);
            },
          ),
        ),
        ListTile(
          leading: const Icon(Icons.request_page_rounded),
          title: Text("配置文件".tl),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => App.to(context, () => const EhProfileSelectPage()),
        ),
      ],
    );
  }
}

class EhProfileSelectPage extends ConsumerStatefulWidget {
  const EhProfileSelectPage({super.key});

  @override
  ConsumerState<EhProfileSelectPage> createState() =>
      _EhProfileSelectPageState();
}

class _EhProfileSelectPageState extends ConsumerState<EhProfileSelectPage> {
  bool loading = true;

  Map<String, String>? profiles;

  String? error;

  void loadData() async {
    var res = await EhNetwork().getProfiles();
    loading = false;
    if (res.error) {
      setState(() {
        error = res.errorMessageWithoutNull;
      });
    } else {
      setState(() {
        profiles = res.data;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(appSettingProvider(AppSettingKeys.ehProfile));
    if (loading) {
      loadData();
    }
    return Scaffold(
      appBar: AppBar(title: const Text("Profile")),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
          ? Center(child: Text(error!))
          : profiles == null
          ? const Center(child: Text("Unknown Error"))
          : buildBody(),
    );
  }

  Widget buildBody() {
    profiles?[""] = "Do not modify";
    var keys = profiles?.keys.toList();
    if (keys != null) {
      keys.sort();
    }
    return ListView.builder(
      itemCount: profiles!.length,
      itemBuilder: (context, index) {
        var key = keys!.elementAt(index);
        var value = profiles![key]!;
        return RadioListTile<String>(
          title: Text(value),
          value: key,
          groupValue: ref.read(appSettingProvider(AppSettingKeys.ehProfile)),
          onChanged: (value) async {
            setState(() {
              _saveSetting(ref, AppSettingKeys.ehProfile, key, persist: false);
            });
            _persistSettings(ref);
          },
        );
      },
    );
  }
}
