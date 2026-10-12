part of pica_settings;

class JmSettings extends ConsumerStatefulWidget {
  const JmSettings(this.popUp, {Key? key}) : super(key: key);
  final bool popUp;

  @override
  ConsumerState<JmSettings> createState() => _JmSettingsState();

  static const builtInApiDomains = <String>[
    "www.cdntwice.org",
    "www.cdnsha.org",
    "www.cdnaspa.cc",
    "www.cdnntr.cc",
  ];

  static void updateApiDomains([bool showLoading = false]) async {
    var title = "";
    var msg = "";
    List<String> domains = builtInApiDomains;
    var controller = showLoading ? showLoadingDialog(App.globalContext!) : null;
    var res = await appComicSourceServices.jm.getApiDomains();
    if (res.error) {
      title += "更新失败".tl;
      msg += "${"使用内置域名:".tl}\n";
    } else {
      title += "更新成功".tl;
      domains = res.data;
    }
    controller?.close();
    for (String domain in domains) {
      msg += "${"域名".tl}${domains.indexOf(domain) + 1}: $domain\n";
    }
    msg = msg.trim();
    showConfirmDialog(App.globalContext!, title, msg, () async {
      await _settingsController(
        App.globalContext!,
      ).setValue(AppSettingKeys.jmApiDomains, domains.join(','));
      await updateAppVersionCode();
      appComicSourceServices.jm.loginFromAppdata();
    });
  }

  static void daily([bool showLoading = false]) async {
    if (!jm.isLogin && showLoading) {
      showToast(message: "未登录".tl);
      return;
    }
    var controller = showLoading ? showLoadingDialog(App.globalContext!) : null;
    var res = await appComicSourceServices.jm.dailyChk();
    controller?.close();
    var title = res.success ? "签到成功".tl : "签到失败".tl;
    var msg = res.success ? "${res.subData}".tl : res.errorMessage;
    if (showLoading) showDialogMessage(App.globalContext!, title, msg!);
  }

  static Future<void> updateAppVersionCode() async {
    var res = await appComicSourceServices.jm.getAppVersionCode();
    if (!res.error) {
      await _settingsController(
        App.globalContext!,
      ).setValue(AppSettingKeys.jmAppVersion, res.data);
    }
  }
}

class _JmSettingsState extends ConsumerState<JmSettings> {
  @override
  Widget build(BuildContext context) {
    final autoSelectStream =
        ref.watch(appSettingProvider(AppSettingKeys.jmAutoSelectDomain)) == "1";
    final autoCheckIn =
        ref.watch(appSettingProvider(AppSettingKeys.jmAutoCheckIn)) == "1";
    return Column(
      children: [
        ListTile(title: Text("禁漫天堂".tl)),
        ListTile(
          leading: const Icon(Icons.track_changes),
          title: Text("自动选择域名".tl),
          subtitle: Text("登录时自动选择API域名".tl),
          trailing: Switch(
            value: autoSelectStream,
            onChanged: (b) {
              _saveSetting(
                ref,
                AppSettingKeys.jmAutoSelectDomain,
                b ? "1" : "0",
                persist: false,
              );
              setState(() {});
              _persistSettings(ref);
              if (b) appComicSourceServices.jm.loginFromAppdata();
            },
          ),
        ),
        ListTile(
          leading: const Icon(Icons.dns),
          title: Text("API域名".tl),
          trailing: IgnorePointer(
            ignoring: autoSelectStream,
            child: Opacity(
              opacity: !autoSelectStream ? 1.0 : 0.5,
              child: Select(
                initialValue: int.parse(
                  ref.watch(appSettingProvider(AppSettingKeys.jmApiStream)),
                ),
                values: ["分流1".tl, "分流2".tl, "分流3".tl, "分流4".tl],
                onChange: (i) {
                  _saveSetting(
                    ref,
                    AppSettingKeys.jmApiStream,
                    i.toString(),
                    persist: false,
                  );
                  _persistSettings(ref);
                  appComicSourceServices.jm.loginFromAppdata();
                },
              ),
            ),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.dns_outlined),
          title: Text("图片分流".tl),
          trailing: Select(
            initialValue:
                (int.tryParse(
                          ref.watch(
                            appSettingProvider(AppSettingKeys.jmImageStream),
                          ),
                        ) ??
                        0)
                    .clamp(0, 3),
            values: ["分流1".tl, "分流2".tl, "分流3".tl, "分流4".tl],
            onChange: (i) {
              _saveSetting(
                ref,
                AppSettingKeys.jmImageStream,
                i.toString(),
                persist: false,
              );
              _persistSettings(ref);
              if (jm.isLogin) appComicSourceServices.jm.updateImgUrl(i + 1);
            },
          ),
        ),
        ListTile(
          leading: const Icon(Icons.favorite_border),
          title: Text("收藏夹漫画排序模式".tl),
          trailing: Select(
            initialValue: int.parse(
              ref.watch(appSettingProvider(AppSettingKeys.jmFavoritesOrder)),
            ),
            width: App.locale.languageCode == "en" ? 130 : 120,
            values: ["最新收藏".tl, "最新更新".tl],
            onChange: (i) {
              _saveSetting(
                ref,
                AppSettingKeys.jmFavoritesOrder,
                i.toString(),
                persist: false,
              );
              _persistSettings(ref);
            },
          ),
        ),
        ListTile(
          leading: const Icon(Icons.update_outlined),
          title: Text("更新API域名".tl),
          onTap: () => JmSettings.updateApiDomains(true),
          trailing: const Icon(Icons.arrow_right),
        ),
        ListTile(
          leading: const Icon(Icons.today),
          title: Text("自动签到".tl),
          subtitle: Text("勾选启用, 点击测试".tl),
          onTap: () => JmSettings.daily(true),
          trailing: Switch(
            value: autoCheckIn,
            onChanged: (b) {
              _saveSetting(
                ref,
                AppSettingKeys.jmAutoCheckIn,
                b ? "1" : "0",
                persist: false,
              );
              setState(() {});
              _persistSettings(ref);
              if (b && jm.isLogin) JmSettings.daily(false);
            },
          ),
        ),
      ],
    );
  }
}
