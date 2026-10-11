part of pica_settings;

class ComicSourceSettings extends ConsumerStatefulWidget {
  const ComicSourceSettings({super.key});

  @override
  ConsumerState<ComicSourceSettings> createState() =>
      _ComicSourceSettingsState();

  // static void checkCustomComicSourceUpdate([bool showLoading = false]) async {
  //   if (ComicSource.sources.isEmpty) {
  //     return;
  //   }
  //   var controller = showLoading ? showLoadingDialog(App.globalContext!) : null;
  //   var dio = logDio();
  //   var res = await dio.get<String>(
  //       "https://raw.githubusercontent.com/user/repo/master/index.json");
  //   if (res.statusCode != 200) {
  //     showToast(message: "网络错误".tl);
  //     return;
  //   }
  //   var list = jsonDecode(res.data!) as List;
  //   var versions = <String, String>{};
  //   for (var source in list) {
  //     versions[source['key']] = source['version'];
  //   }
  //   var shouldUpdate = <String>[];
  //   for (var source in ComicSource.sources) {
  //     if (versions.containsKey(source.key) &&
  //         versions[source.key] != source.version) {
  //       shouldUpdate.add(source.key);
  //     }
  //   }
  //   controller?.close();
  //   if (shouldUpdate.isEmpty) {
  //     return;
  //   }
  //   var msg = "";
  //   for (var key in shouldUpdate) {
  //     msg += "${ComicSource.find(key)?.name}: v${versions[key]}\n";
  //   }
  //   msg = msg.trim();
  //   showConfirmDialog(App.globalContext!, "有可用更新".tl, msg, () {
  //     for (var key in shouldUpdate) {
  //       var source = ComicSource.find(key);
  //       _ComicSourceSettingsState.update(source!);
  //     }
  //   });
  // }
}

extension _WidgetExt on Widget {
  Widget withDivider() {
    return Column(children: [this, const Divider()]);
  }
}

class _ComicSourceSettingsState extends ConsumerState<ComicSourceSettings> {
  var url = "";

  @override
  Widget build(BuildContext context) {
    ref.watch(appSettingsProvider);
    return Column(
      children: [
        const _BuiltInSources(),
        if (appdata.appSettings.isComicSourceEnabled(ComicType.picacg.name))
          const PicacgSettings(false).withDivider(),
        if (appdata.appSettings.isComicSourceEnabled(ComicType.ehentai.name))
          const EhSettings(false).withDivider(),
        if (appdata.appSettings.isComicSourceEnabled(ComicType.nhentai.name))
          const NhSettings(false).withDivider(),
        if (appdata.appSettings.isComicSourceEnabled(ComicType.jm.name))
          const JmSettings(false).withDivider(),
        if (appdata.appSettings.isComicSourceEnabled(ComicType.hitomi.name))
          const HitomiSettings(false).withDivider(),
        if (appdata.appSettings.isComicSourceEnabled(ComicType.htmanga.name))
          const HtSettings(false),
        Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).padding.bottom,
          ),
        ),
      ],
    );
  }
}

class _ComicSourceList extends ConsumerStatefulWidget {
  const _ComicSourceList(this.onAdd);

  final Future<void> Function(String) onAdd;

  @override
  ConsumerState<_ComicSourceList> createState() => _ComicSourceListState();
}

class _ComicSourceListState extends ConsumerState<_ComicSourceList> {
  bool loading = true;
  List? json;

  void load() async {
    var dio = networkClientManager.apiDio;
    var res = await dio.get<String>(
      "https://raw.githubusercontent.com/wgh136/pica_configs/master/index.json",
    );
    if (res.statusCode != 200) {
      showToast(message: "网络错误".tl);
      return;
    }
    setState(() {
      json = jsonDecode(res.data!);
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(appSettingsProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text("漫画源".tl),
        actions: const [
          IconButton(onPressed: App.globalBack, icon: Icon(Icons.close)),
        ],
      ),
      body: buildBody(),
    );
  }

  Widget buildBody() {
    if (loading) {
      load();
      return const Center(child: CircularProgressIndicator());
    } else {
      var currentKey = ComicSource.sources.map((e) => e.key.name).toList();
      return ListView.builder(
        itemCount: json!.length,
        itemBuilder: (context, index) {
          var key = json![index]["key"];
          var action = currentKey.contains(key)
              ? const Icon(Icons.check)
              : Tooltip(
                  message: "Add",
                  child: IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () async {
                      await widget.onAdd(
                        "https://raw.githubusercontent.com/wgh136/pica_configs/master/${json![index]["fileName"]}",
                      );
                      setState(() {});
                    },
                  ),
                );

          return ListTile(
            title: Text(json![index]["name"]),
            subtitle: Text(json![index]["version"]),
            trailing: action,
          );
        },
      );
    }
  }
}

class _BuiltInSources extends ConsumerStatefulWidget {
  const _BuiltInSources();

  @override
  ConsumerState<_BuiltInSources> createState() => _BuiltInSourcesState();
}

class _BuiltInSourcesState extends ConsumerState<_BuiltInSources> {
  @override
  Widget build(BuildContext context) {
    ref.watch(appSettingsProvider);
    return Column(
      children: [
        const Divider(),
        ListTile(title: Text("内置漫画源".tl)),
        for (int index = 0; index < builtInSources.length; index++)
          buildTile(index),
        const Divider(),
      ],
    );
  }

  bool isLoading = false;

  Widget buildTile(int index) {
    var key = builtInSources[index];
    return ListTile(
      title: Text(ComicSource.builtIn.firstWhere((e) => e.key == key).name.tl),
      trailing: Switch(
        value: appdata.appSettings.isComicSourceEnabled(key.name),
        onChanged: (v) async {
          if (isLoading) return;
          isLoading = true;
          await ref
              .read(appSettingsProvider.notifier)
              .setValue(
                AppSettingKeys.enabledBuiltInSources,
                appdata.appSettings.comicSourceEnabledValue(key.name, v),
              );
          if (!v) {
            ComicSource.sources.removeWhere((e) => e.key == key);
            await _validatePages(ref);
          } else {
            var source = ComicSource.builtIn.firstWhere((e) => e.key == key);
            ComicSource.sources.add(source);
            source.loadData();
            await _addAllPagesWithComicSource(source, ref);
          }
          isLoading = false;
          if (mounted) {
            setState(() {});
            context
                .findAncestorStateOfType<_ComicSourceSettingsState>()
                ?.setState(() {});
          }
        },
      ),
    );
  }
}

/// 禁用漫画源后批量移除对应的页面配置。
Future<void> _validatePages(WidgetRef ref) async {
  var explorePages = appdata.appSettings.explorePages;
  var categoryPages = appdata.appSettings.categoryPages;
  var networkFavorites = appdata.appSettings.networkFavorites;

  var totalExplorePages = ComicSource.sources
      .map((e) => e.explorePages.map((e) => e.title))
      .expand((element) => element)
      .toList();
  var totalCategoryPages = ComicSource.sources
      .map((e) => e.categoryData?.key)
      .where((element) => element != null)
      .map((e) => e!)
      .toList();
  var totalNetworkFavorites = ComicSource.sources
      .map((e) => e.favoriteData?.key)
      .where((element) => element != null)
      .map((e) => e!)
      .toList();

  for (var page in List.from(explorePages)) {
    if (!totalExplorePages.contains(page)) {
      explorePages.remove(page);
    }
  }
  for (var page in List.from(categoryPages)) {
    if (!totalCategoryPages.contains(page)) {
      categoryPages.remove(page);
    }
  }
  for (var page in List.from(networkFavorites)) {
    if (!totalNetworkFavorites.contains(page)) {
      networkFavorites.remove(page);
    }
  }

  await ref.read(appSettingsProvider.notifier).setValues({
    AppSettingKeys.explorePages: (explorePages).join(','),
    AppSettingKeys.categoryPages: (categoryPages).join(','),
    AppSettingKeys.networkFavoritePages: (networkFavorites).join(','),
  });
}

/// 启用漫画源后批量补充对应的页面配置。
Future<void> _addAllPagesWithComicSource(
  ComicSource source,
  WidgetRef ref,
) async {
  var explorePages = appdata.appSettings.explorePages;
  var categoryPages = appdata.appSettings.categoryPages;
  var networkFavorites = appdata.appSettings.networkFavorites;

  if (source.explorePages.isNotEmpty) {
    for (var page in source.explorePages) {
      if (!explorePages.contains(page.title)) {
        explorePages.add(page.title);
      }
    }
  }
  if (source.categoryData != null &&
      !categoryPages.contains(source.categoryData!.key)) {
    categoryPages.add(source.categoryData!.key);
  }
  if (source.favoriteData != null &&
      !networkFavorites.contains(source.favoriteData!.key)) {
    networkFavorites.add(source.favoriteData!.key);
  }

  await ref.read(appSettingsProvider.notifier).setValues({
    AppSettingKeys.explorePages: (explorePages.toSet().toList()).join(','),
    AppSettingKeys.categoryPages: (categoryPages.toSet().toList()).join(','),
    AppSettingKeys.networkFavoritePages: (networkFavorites.toSet().toList())
        .join(','),
  });
}
