part of pica_settings;

class LocalFavoritesSettings extends ConsumerStatefulWidget {
  const LocalFavoritesSettings({super.key});

  @override
  ConsumerState<LocalFavoritesSettings> createState() =>
      _LocalFavoritesSettingsState();
}

class _LocalFavoritesSettingsState
    extends ConsumerState<LocalFavoritesSettings> {
  @override
  Widget build(BuildContext context) {
    final defaultFolder = ref.watch(
      appSettingProvider(AppSettingKeys.defaultFavoriteFolder),
    );
    final syncPages = ref.watch(
      appSettingProvider(AppSettingKeys.favoriteSyncPages),
    );
    return Column(
      children: [
        Builder(
          builder: (context) {
            final folderNames =
                ref.watch(localFavoritesProvider).asData?.value.folderNames ??
                const <String>[];
            return ListTile(
              leading: const Icon(Icons.book),
              title: Text("快速收藏".tl),
              subtitle: Text("长按收藏按钮执行快速收藏".tl),
              trailing: Select(
                initialValue: folderNames.indexOf(defaultFolder),
                onChange: (i) {
                  _saveSetting(
                    ref,
                    AppSettingKeys.defaultFavoriteFolder,
                    folderNames[i],
                    persist: false,
                  );
                  _persistSettings(ref);
                },
                values: folderNames,
              ),
            );
          },
        ),
        SelectSettingWithAppdata(
          icon: const Icon(Icons.bookmark_add),
          title: "新收藏添加至".tl,
          options: ["最后".tl, "最前".tl],
          settingKey: AppSettingKeys.localFavoriteInsertPosition,
        ),
        SelectSettingWithAppdata(
          icon: const Icon(Icons.move_up),
          title: "阅读后移动本地收藏至".tl,
          options: ["无操作".tl, "最后".tl, "最前".tl],
          settingKey: AppSettingKeys.localFavoriteMoveAfterReading,
        ),
        SelectSettingWithAppdata(
          icon: const Icon(Icons.touch_app),
          title: "点击漫画时".tl,
          options: ["查看信息".tl, "阅读".tl],
          settingKey: AppSettingKeys.localFavoriteTapAction,
        ),
        ListTile(
          leading: const Icon(Icons.sync),
          title: Text("下拉更新拉取页数".tl),
          trailing: Select(
            initialValue: [
              "1",
              "2",
              "3",
              "4",
              "5",
              "10",
              "99",
            ].indexOf(syncPages),
            values: const ["1", "2", "3", "4", "5", "10", "99"],
            onChange: (i) {
              _saveSetting(
                ref,
                AppSettingKeys.favoriteSyncPages,
                ["1", "2", "3", "4", "5", "10", "99"][i],
                persist: false,
              );
              _persistSettings(ref);
            },
            width: 140,
          ),
        ),
        Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).padding.bottom,
          ),
        ),
      ],
    );
  }
}
