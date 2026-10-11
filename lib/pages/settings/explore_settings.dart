part of pica_settings;

/// 浏览与漫画块设置通过 Provider 响应导入和重置。
Widget buildExploreSettings(BuildContext context, bool popUp) {
  return Consumer(
    builder: (context, ref, _) => _buildExploreSettings(context, ref, popUp),
  );
}

/// 构造现有设置布局，保留运行时刷新行为。
Widget _buildExploreSettings(BuildContext context, WidgetRef ref, bool popUp) {
  final settings = ref.watch(appSettingsProvider);
  var searchSource = <String>[];
  for (var source in ComicSource.sources) {
    searchSource.add(source.key.name);
  }

  return Column(
    children: [
      SettingsTitle("显示".tl),
      SelectSettingWithAppdata(
        icon: const Icon(Icons.home_outlined),
        title: "初始页面".tl,
        options: ["我".tl, "收藏".tl, "探索".tl, "分类".tl, "下载".tl, "本地".tl],
        settingKey: AppSettingKeys.initialPage,
      ),
      NewPageSetting(
        title: "网络收藏页面".tl,
        onTap: () => showPopUpWidget(
          App.globalContext!,
          MultiPagesFilter(
            "网络收藏页面".tl,
            AppSettingKeys.networkFavoritePages,
            networkFavorites(),
          ),
        ),
        icon: const Icon(Icons.local_activity_outlined),
      ),
      NewPageSetting(
        title: "探索页面".tl,
        onTap: () => setExplorePages(context),
        icon: const Icon(Icons.explore_outlined),
      ),
      NewPageSetting(
        title: "分类页面".tl,
        onTap: () => showPopUpWidget(
          App.globalContext!,
          MultiPagesFilter(
            "分类页面".tl,
            AppSettingKeys.categoryPages,
            categoryPages(),
          ),
        ),
        icon: const Icon(Icons.account_tree_outlined),
      ),
      SelectSettingWithAppdata(
        icon: const Icon(Icons.list),
        title: "漫画列表显示方式".tl,
        options: ["连续模式".tl, "分页模式".tl],
        settingKey: AppSettingKeys.comicsListDisplayMode,
      ),
      NewPageSetting(
        title: "关键词屏蔽".tl,
        onTap: () => showPopUpWidget(
          context,
          BlockingKeywordPage(popUp: MediaQuery.of(context).size.width > 600),
        ),
        icon: const Icon(Icons.block),
      ),
      SwitchSetting(
        title: "完全隐藏屏蔽的作品".tl,
        settingKey: AppSettingKeys.fullyHideBlockedComics,
        icon: const Icon(Icons.visibility_off),
      ),
      SettingsTitle("工具".tl),
      SwitchSetting(
        title: "检查剪切板中的链接".tl,
        settingKey: AppSettingKeys.checkClipboardLinks,
        icon: const Icon(Icons.image),
      ),
      SelectSetting(
        leading: const Icon(Icons.search),
        title: "默认搜索源".tl,
        values: searchSource,
        initialValue: searchSource.indexOf(
          settings.value(AppSettingKeys.defaultSearchSource),
        ),
        onChanged: (i) {
          _saveSetting(
            ref,
            AppSettingKeys.defaultSearchSource,
            searchSource[i],
          );
        },
      ),
      SwitchSetting(
        title: "启用侧边翻页栏".tl,
        icon: const Icon(Icons.border_right),
        settingKey: AppSettingKeys.showListSidePaging,
      ),
      SelectSettingWithAppdata(
        title: "自动添加语言筛选".tl,
        settingKey: AppSettingKeys.searchLanguageFilter,
        options: ["无".tl, "chinese", "english", "japanese"],
        icon: const Icon(Icons.translate),
      ),
      ..._buildComicTileSettings(ref),
      Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
      ),
    ],
  );
}

/// 漫画块大小与布局设置，滑块只在拖动结束时持久化。
List<Widget> _buildComicTileSettings(WidgetRef ref) {
  final appearance = ref.watch(appearanceSettingsProvider);
  return [
    SettingsTitle("漫画块".tl),
    SelectSetting(
      leading: const Icon(Icons.web),
      title: "漫画块显示模式".tl,
      initialValue: appearance.comicTileMode,
      onChanged: (i) {
        _saveSetting(
          ref,
          AppSettingKeys.comicTileDisplay,
          '$i,${appearance.comicTileScale}',
        );
        MyApp.updater?.call();
      },
      values: ["详细".tl, "简略".tl],
    ),
    Builder(
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: SizedBox(
            width: double.infinity,
            height: 64,
            child: Row(
              children: [
                const SizedBox(width: 16),
                const Icon(Icons.crop_free),
                Expanded(
                  child: Stack(
                    children: [
                      Positioned(
                        top: 0,
                        left: 12,
                        right: 0,
                        child: Text(
                          "漫画块大小".tl,
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                      Positioned(
                        left: -8,
                        right: 0,
                        bottom: 0,
                        child: Slider(
                          max: 1.25,
                          min: 0.75,
                          divisions: 10,
                          value: appearance.comicTileScale,
                          overlayColor: WidgetStateColor.resolveWith(
                            (states) => Colors.transparent,
                          ),
                          onChangeEnd: (v) {
                            _saveSetting(
                              ref,
                              AppSettingKeys.comicTileDisplay,
                              null,
                            );
                          },
                          onChanged: (v) {
                            _saveSetting(
                              ref,
                              AppSettingKeys.comicTileDisplay,
                              '${appearance.comicTileMode},${v.toStringAsFixed(2)}',
                              persist: false,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                Text(appearance.comicTileScale.toStringAsFixed(2)),
                const SizedBox(width: 32),
              ],
            ),
          ),
        );
      },
    ),
    SelectSettingWithAppdata(
      title: "漫画块缩略图布局".tl,
      settingKey: AppSettingKeys.thumbnailFit,
      options: ["覆盖".tl, "容纳".tl],
      icon: const Icon(Icons.image),
    ),
    SwitchSetting(
      title: "显示收藏状态".tl,
      settingKey: AppSettingKeys.showComicFavoriteStatus,
      icon: const Icon(Icons.bookmark),
    ),
    SwitchSetting(
      title: "显示阅读位置".tl,
      settingKey: AppSettingKeys.showComicReadingProgress,
      icon: const Icon(Icons.history_toggle_off),
    ),
    Builder(
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: SizedBox(
            width: double.infinity,
            height: 64,
            child: Row(
              children: [
                const SizedBox(width: 16),
                const Icon(Icons.crop_free),
                Expanded(
                  child: Stack(
                    children: [
                      Positioned(
                        top: 0,
                        left: 12,
                        right: 0,
                        child: Text(
                          "图片收藏大小".tl,
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                      Positioned(
                        left: -8,
                        right: 0,
                        bottom: 0,
                        child: Slider(
                          max: 1.25,
                          min: 0.75,
                          divisions: 10,
                          value: appearance.imageFavoriteScale,
                          overlayColor: WidgetStateColor.resolveWith(
                            (states) => Colors.transparent,
                          ),
                          onChangeEnd: (v) {
                            _saveSetting(
                              ref,
                              AppSettingKeys.imageFavoriteScale,
                              null,
                            );
                          },
                          onChanged: (v) {
                            _saveSetting(
                              ref,
                              AppSettingKeys.imageFavoriteScale,
                              v.toStringAsFixed(2),
                              persist: false,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                Text(appearance.imageFavoriteScale.toStringAsFixed(2)),
                const SizedBox(width: 32),
              ],
            ),
          ),
        );
      },
    ),
  ];
}

Map<String, String> categoryPages() {
  return {
    for (var source in ComicSource.sources)
      if (source.categoryData != null)
        source.categoryData!.key: source.categoryData!.title.tl,
  };
}

Map<String, String> networkFavorites() {
  return {
    for (var source in ComicSource.sources)
      if (source.favoriteData != null)
        source.key.name: source.favoriteData!.title.tl,
  };
}
