part of pica_settings;

class PicacgSettings extends ConsumerStatefulWidget {
  const PicacgSettings(this.popUp, {Key? key}) : super(key: key);
  final bool popUp;

  @override
  ConsumerState<PicacgSettings> createState() => _PicacgSettingsState();
}

class _PicacgSettingsState extends ConsumerState<PicacgSettings> {
  bool get showFrame =>
      appdata.getSetting(AppSettingKeys.picacgShowAvatarFrame) == "1";
  bool get punchIn =>
      appdata.getSetting(AppSettingKeys.picacgAutoCheckIn) == "1";

  static const _imageQualityValues = ["low", "middle", "high", "original"];

  @override
  Widget build(BuildContext context) {
    ref.watch(appSettingsProvider);
    return Column(
      children: [
        ListTile(title: Text("哔咔漫画".tl)),
        ListTile(
          leading: const Icon(Icons.dns),
          title: Text("设置分流".tl),
          trailing: Select(
            initialValue: int.parse(picacg.data['appChannel']) - 1,
            values: ["分流1".tl, "分流2".tl, "分流3".tl],
            onChange: (i) {
              picacg.data['appChannel'] = (i + 1).toString();
              picacg.saveData();
            },
          ),
        ),
        ListTile(
          leading: const Icon(Icons.image),
          title: Text("设置图片质量".tl),
          trailing: Select(
            initialValue: _imageQualityValues.indexOf(
              picacg.data['imageQuality'],
            ),
            width: App.locale.languageCode == "en" ? 140 : 120,
            values: ["低".tl, "中".tl, "高".tl, "原图".tl],
            onChange: (i) {
              picacg.data['imageQuality'] = _imageQualityValues[i];
              picacg.saveData();
            },
          ),
        ),
        ListTile(
          leading: const Icon(Icons.collections_bookmark_outlined),
          trailing: Select(
            initialValue: int.parse(
              appdata.getSetting(AppSettingKeys.picacgFavoritesNewestFirst),
            ),
            values: ["旧到新".tl, "新到旧".tl],
            onChange: (i) {
              _saveSetting(
                ref,
                AppSettingKeys.picacgFavoritesNewestFirst,
                i.toString(),
                persist: false,
              );
              _persistSettings(ref);
            },
          ),
          title: Text("收藏夹漫画排序模式".tl),
        ),
        ListTile(
          leading: const Icon(Icons.circle_outlined),
          title: Text("显示头像框".tl),
          trailing: Switch(
            value: showFrame,
            onChanged: (b) {
              _saveSetting(
                ref,
                AppSettingKeys.picacgShowAvatarFrame,
                b ? "1" : "0",
                persist: false,
              );
              _persistSettings(ref, fullData: true);
            },
          ),
          onTap: () {},
        ),
        ListTile(
          leading: const Icon(Icons.today),
          title: Text("自动打卡".tl),
          subtitle: App.isMobile
              ? Text("APP启动或是距离上次打卡间隔一天时执行".tl)
              : Text("启动时执行".tl),
          onTap: () {},
          trailing: Switch(
            value: punchIn,
            onChanged: (b) {
              _saveSetting(
                ref,
                AppSettingKeys.picacgAutoCheckIn,
                b ? "1" : "0",
                persist: false,
              );
              if (App.isMobile) {
                b ? runBackgroundService() : cancelBackgroundService();
              }
              _persistSettings(ref, fullData: true);
            },
          ),
        ),
      ],
    );
  }
}
