import 'package:pica_comic/network/comic_source_services.dart';
import 'package:pica_comic/foundation/app_settings_provider.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/network/res.dart';
import 'comic_source.dart';

final picacgFavorites = FavoriteData(
  key: ComicType.picacg.name,
  title: "Picacg",
  multiFolder: false,
  loadComic: (ref, i, [folder]) => ref
      .read(picacgNetworkProvider)
      .getFavorites(
        i,
        ref
            .read(appSettingsProvider)
            .enabled(AppSettingKeys.picacgFavoritesNewestFirst),
      ),
  loadFolders: null,
  addOrDelFavorite: (ref, id, folder, isAdding) async {
    var res = await ref
        .read(picacgNetworkProvider)
        .favouriteOrUnfavouriteComic(id);
    return res
        ? const Res(true)
        : const Res(false, errorMessage: "Network Error");
  },
);

/// eh较为特殊, 写统一接口有点麻烦, 不要使用这个进行构建页面
final ehFavorites = FavoriteData(
  key: ComicType.ehentai.name,
  title: "ehentai",
  multiFolder: true,
  loadComic: (ref, i, [folder]) => throw UnimplementedError(),
  loadFolders: null,
);

final jmFavorites = FavoriteData(
  key: ComicType.jm.name,
  title: "禁漫天堂",
  multiFolder: true,
  loadComic: (ref, i, [folder]) =>
      ref.read(jmNetworkProvider).getFolderComicsPage(folder!, i),
  loadFolders: (ref, [String? comicId]) =>
      ref.read(jmNetworkProvider).getFolders(),
  deleteFolder: (ref, id) => ref.read(jmNetworkProvider).deleteFolder(id),
  addFolder: (ref, name) => ref.read(jmNetworkProvider).createFolder(name),
  allFavoritesId: "0",
  addOrDelFavorite: (ref, id, folder, isAdding) async {
    if (isAdding) return const Res.error("invalid");
    var res = await ref.read(jmNetworkProvider).favorite(id, folder);
    return res;
  },
);

final htFavorites = FavoriteData(
  key: ComicType.htmanga.name,
  title: "绅士漫画",
  multiFolder: true,
  loadComic: (ref, i, [folder]) =>
      ref.read(htMangaNetworkProvider).getFavoriteFolderComics(folder!, i),
  loadFolders: (ref, [String? comicId]) =>
      ref.read(htMangaNetworkProvider).getFolders(),
  allFavoritesId: "0",
  deleteFolder: (ref, id) async {
    var res = await ref.read(htMangaNetworkProvider).deleteFolder(id);
    return res
        ? const Res(true)
        : const Res(false, errorMessage: "Network Error");
  },
  addFolder: (ref, name) async {
    var res = await ref.read(htMangaNetworkProvider).createFolder(name);
    return res
        ? const Res(true)
        : const Res(false, errorMessage: "Network Error");
  },
  addOrDelFavorite: (ref, id, folder, isAdding) async {
    if (isAdding) return const Res.error("invalid");
    var res = await ref.read(htMangaNetworkProvider).delFavorite(id);
    return res;
  },
);

final nhentaiFavorites = FavoriteData(
  key: ComicType.nhentai.name,
  title: "nhentai",
  multiFolder: false,
  loadComic: (ref, i, [folder]) =>
      ref.read(nhentaiNetworkProvider).getFavorites(i),
  loadFolders: null,
);
