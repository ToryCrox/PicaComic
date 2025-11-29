import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/foundation/database/download_database.dart';
import 'package:pica_comic/foundation/log.dart';
import 'package:pica_comic/network/download_model.dart';
import 'package:pica_comic/network/models/download_tag.dart';
import 'package:pica_comic/network/eh_network/eh_models.dart';
import 'package:pica_comic/network/eh_network/get_gallery_id.dart';
import 'package:pica_comic/network/favorite_download.dart';
import 'package:pica_comic/network/hitomi_network/hitomi_download_model.dart';
import 'package:pica_comic/network/hitomi_network/hitomi_models.dart' as hitomi;
import 'package:pica_comic/network/htmanga_network/ht_download_model.dart';
import 'package:pica_comic/network/htmanga_network/models.dart';
import 'package:pica_comic/network/jm_network/jm_download.dart';
import 'package:pica_comic/network/jm_network/jm_models.dart';
import 'package:pica_comic/network/nhentai_network/download.dart';
import 'package:pica_comic/network/picacg_network/picacg_download_model.dart';
import 'package:pica_comic/pages/download_page.dart';
import 'package:pica_comic/tools/extensions.dart';
import 'package:pica_comic/tools/io_extensions.dart';
import 'package:pica_comic/tools/io_tools.dart';
import 'package:pica_comic/tools/map_extension.dart';
import 'package:pica_comic/tools/shared_compute.dart';
import 'package:pica_comic/tools/str_ext.dart';
import 'package:pica_comic/tools/translations.dart';
import 'package:pica_comic/tools/type_util.dart';
import 'package:path/path.dart' as Path;
import 'package:synchronized/synchronized.dart';

import '../comic_source/comic_source.dart';
import '../components/components.dart';
import '../foundation/local_favorites.dart';
import '../tools/debounce.dart';
import '../tools/image_utils.dart';
import '../tools/throttle.dart';
import 'custom_download_model.dart';
import 'eh_network/eh_download_model.dart';
import 'hitomi_network/hitomi_models.dart';
import 'nhentai_network/models.dart';
import 'picacg_network/models.dart';

typedef DownloadingCallback = void Function();

class DownloadManager implements Listenable {
  static DownloadManager? cache;

  factory DownloadManager() => cache ?? (cache = DownloadManager._create());

  DownloadManager._create();

  ///下载目录
  String? path;

  ///下载队列
  var downloading = Queue<DownloadingItem>();

  ///是否正在下载
  bool isDownloading = false;

  ///是否出现了错误
  bool _error = false;

  ///是否出现了错误
  bool get error => _error;

  ///是否初始化
  bool _runInit = false;

  final DownloadDatabase _db = DownloadDatabase();

  final List<VoidCallback> _listeners = [];

  @override
  void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  void notifyListeners() {
    for (var listener in _listeners) {
      listener();
    }
  }

  ///获取下载目录
  Future<void> _getPath() async {
    if (appdata.settings[22] == "") {
      final appPath = await getApplicationSupportDirectory();
      path = "${appPath.path}/download";
    } else {
      path = appdata.settings[22];
    }
    if (App.isIOS) {
      if (path!.startsWith('/var/mobile/Containers/Data/Application/')) {
        if (!Directory(path!).existsSync()) {
          final appPath = await getApplicationSupportDirectory();
          path = "${appPath.path}/download";
        }
      }
    }
    var dir = Directory(path!);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    if (App.isAndroid) {
      var file = File("$path/.nomedia");
      if (!file.existsSync()) {
        await file.create();
      }
    }
  }

  ///更换下载目录
  Future<String> updatePath(String newPath, {bool transform = true}) async {
    if (transform) {
      var source = Directory(path!);
      final appPath = await getApplicationSupportDirectory();
      var destination = Directory(
        newPath == "" ? "${appPath.path}${pathSep}download" : newPath,
      );
      try {
        await copyDirectory(source, destination);
        for (var i in source.listSync()) {
          await i.delete(recursive: true);
        }
      } catch (e) {
        return e.toString();
      }
    }

    _runInit = false;
    downloading.clear();
    await init();
    return "ok";
  }

  ///读取数据, 获取未完成的下载和已下载的漫画ID
  Future<void> _getInfo() async {
    //读取数据
    var file = File("$path${pathSep}newDownload.json");
    if (!file.existsSync()) {
      //await _saveInfo();
    } else {
      try {
        var json = const JsonDecoder().convert(await file.readAsString());
        for (var item in json["downloading"]) {
          downloading.add(
              downloadingItemFromMap(item, _onFinish, _onError, _saveInfo));
        }
      } catch (e, s) {
        Log.e("IO Failed to read downloaded information\n$e\n$s");
        // file.deleteSync();
        // await _saveInfo();
      }
    }
  }

  Future<void> _initDb() async {
    var oldData = <String, DownloadedItem>{};
    if (!File("$path/download.db").existsSync()) {
      for (var entry in await Directory(path!).list().toList()) {
        if (entry is Directory) {
          var infoFile = File("${entry.path}/info.json");
          if (infoFile.existsSync()) {
            var id = entry.name;
            var json = await infoFile.readAsString();
            var time = await infoFile.lastModified();
            var comic = _getComicFromJson(id: id, json: json, time: time);
            if (comic != null) {
              infoFile.delete();
              var directory = comic.name;
              int i = -1;
              while (entry is Directory) {
                try {
                  entry = entry.renameX(directory);
                  break;
                } catch (e) {
                  i++;
                  if (i > 20) {
                    // it seems that the error is unrelated to the directory name
                    Log.e(
                        "IO Failed to rename directory: Trying rename ${entry.name} to ${comic.name}\n$e");
                    break;
                  }
                  directory = comic.name + i.toString();
                }
              }
              oldData[entry.name] = comic;
            }
          }
        }
      }
    }
    await _db.init(dbPath: "$path/download.db");
    for (var entry in oldData.entries) {
      await _addToDb(entry.value, entry.key);
    }
  }

  void dispose() {
    _runInit = false;
    downloading.forEach((e) => e.stop());
    downloading.clear();
  }

  ///初始化下载管理器
  Future<void> init() async {
    if (_runInit) return;
    _runInit = true;
    await _getPath();
    await _getInfo();
    await _initDb();
  }

  static final _saveInfoThrottle =
      Debounce(duration: const Duration(milliseconds: 200));

  ///储存当前的下载队列信息, 每完成一张图片的下载调用一次
  Future<void> _saveInfo() async {
    _saveInfoThrottle.call(() async {
      notifyListeners();
      final t1 = DateTime.now();
      var data = <String, dynamic>{};
      data["downloading"] = <Map<String, dynamic>>[];
      for (var item in downloading) {
        data["downloading"].add(item.toMap());
      }
      final saveItem = SaveInfoItem(data, path ?? '');
      sharedCompute(saveToFile, saveItem);
      // var file = File("$path${pathSep}newDownload.json");
      // await file.writeAsString(const JsonEncoder().convert(data));
    });
  }

  static Future<void> saveToFile(SaveInfoItem item) async {
    var file = File("${item.path}${pathSep}newDownload.json");
    await file.writeAsString(const JsonEncoder().convert(item.items));
  }

  /// move comic to first
  void moveToFirst(DownloadingItem item) {
    if (downloading.first == item) {
      return;
    }
    pause();
    downloading.remove(item);
    downloading.addFirst(item);
    start();
  }

  String generateId(String source, String id) {
    var comicSource = ComicSource.find(source)!;
    if (comicSource.matchBriefIdReg != null) {
      id = RegExp(comicSource.matchBriefIdReg!).firstMatch(id)!.group(1)!;
    }
    id = "$source-$id";
    return id;
  }

  ///当一个下载任务完成时, 调用此函数
  void _onFinish() async {
    var task = downloading.removeFirst();
    await _addToDb(await task.toDownloadedItem(), task.directory!);
    await _saveInfo();
    StateController.findOrNull<DownloadPageLogic>()?.refresh();
    if (downloading.isNotEmpty) {
      //清除已完成的任务, 开始下一个任务
      downloading.first.start();
    } else {
      //标记状态为未在下载
      isDownloading = false;
      notifications.endProgress();
    }
  }

  ///暂停下载
  void pause() {
    isDownloading = false;
    downloading.first.pause();
  }

  ///出现错误时调用此函数
  void _onError() {
    pause();
    _error = true;
    notifications.sendNotification("下载出错".tl, "点击查看详情".tl);
    notifyListeners();
  }

  ///开始或继续下载
  void start() {
    _error = false;
    if (isDownloading) return;
    downloading.first.start();
    isDownloading = true;
  }

  ///取消指定的下载
  void cancel(String id) {
    var index = 0;
    for (var i in downloading) {
      if (i.id == id) break;
      index++;
    }

    if (index == 0) {
      _error = false;
      downloading.first.stop();
      downloading.removeFirst();
    } else {
      downloading.removeWhere((element) => element.id == id);
    }

    notifyListeners();

    if (downloading.isEmpty) {
      isDownloading = false;
      notifications.endProgress();
    } else {
      downloading.first.start();
    }
    _saveInfo();
  }

  Future<DownloadedItem?> getComicOrNull(String id) async {
    return _getComicWithDb(id);
  }

  ///删除已下载的漫画
  Future<void> delete(List<String> ids) async {
    for (var id in ids) {
      Log.i("IO delete comic: $id");
      final dirPath = await getFullDirectory(id);
      await _deleteFromDb(id);
      if (dirPath.isNotEmpty) {
        var comic = Directory(dirPath);
        try {
          Log.d('delete comic path: $dirPath');
          await comic.delete(recursive: true);
        } catch (e, s) {
          showToast(message: 'delete error ${dirPath}');
          Log.e('delete comic error $e', stackTrace: s);
          if (e is PathNotFoundException) {
            //忽略
          } else {
            rethrow;
          }
        }
      } else {
        Log.w("IO delete comic error: comic not found $id");
      }
    }
  }

  Future<void> deleteWithoutFile(List<String> ids) async {
    for (var id in ids) {
      await _deleteFromDb(id);
    }
  }

  /// return error message when error, or null if success.
  Future<String?> deleteEpisode(DownloadedItem comic, int ep) async {
    try {
      if (comic.downloadedEps.length == 1) {
        return "Delete Error: only one downloaded episode";
      }
      final fullPath = await getFullDirectory(comic.id);
      if (Directory("$fullPath/${ep + 1}").existsSync()) {
        Directory("$fullPath/${ep + 1}").deleteSync(recursive: true);
      }
      var size = Directory(fullPath).getMBSizeSync();
      comic.downloadedEps.remove(ep);
      comic.comicSize = size;
      await _addToDb(
          comic, comic.directory ?? await getDirectoryName(comic.id));
      return null;
    } catch (e, s) {
      Log.e("IO $e/n$s");
      return e.toString();
    }
  }

  /// 更新漫画大小
  Future<double> updateComicSize(DownloadedItem comic) async {
    try {
      final dirPath = await getFullDirectory(comic.id);
      final size = Directory(dirPath).getMBSizeSync();
      comic.comicSize = size;
      debugPrint("update comic size: ${comic.id} $size");
      await updateSize(comic.id, size);
      return size;
    } catch (e) {
      Log.e("IO ${e.toString()}");
      return 0;
    }
  }

  /// 获取漫画章节的长度, 适用于有章节的漫画
  Future<int> getEpLength(String id, int ep) async {
    final fullDirPath = await getFullDirectory(id);
    var directory = Directory("$fullDirPath/$ep");
    var files = directory.list();
    return files.length;
  }

  /// 获取漫画的长度, 适用于无章节的漫画
  Future<int> getComicLength(String id) async {
    final fullDirPath = await getDirectoryName(id);
    var directory = Directory(fullDirPath);
    var files = directory.list();
    return await files.length - 1;
  }

  ///获取图片, 对于无章节的漫画, ep参数为0
  Future<File> getImage(String id, int ep, int index) async {
    final fullDirPath = await getFullDirectory(id); // 这里需要修改为同步方法或者重构调用处
    String downloadPath;
    if (ep == 0) {
      downloadPath = "$fullDirPath/";
    } else {
      downloadPath = "$fullDirPath/$ep/";
    }
    for (var file in Directory(downloadPath).listSync()) {
      if (file.uri.pathSegments.last.replaceFirst(RegExp(r"\..+"), "") ==
          index.toString()) {
        return file as File;
      }
    }
    throw Exception("File not found");
  }

  Future<File?> getDownloadImageOrNull(String title, int ep, int index) async {
    final directory = findValidDirectoryName(DownloadManager().path!, title);
    String downloadPath;
    if (ep == 0) {
      downloadPath = "$path/$directory/";
    } else {
      downloadPath = "$path/$directory/$ep/";
    }
    final dir = Directory(downloadPath);
    if (!(await dir.exists())) return null;
    return dir.listSync().whereType<File>().toList().firstWhereOrNull(
        (e) => Path.basenameWithoutExtension(e.path) == index.toString());
  }

  Future<String> getImageDirectory(String id, int ep) async {
    String downloadPath;
    final dirName = await getDirectoryName(id);
    if (ep == 0) {
      downloadPath = "$path/$dirName/";
    } else {
      downloadPath = "$path/$dirName/$ep/";
    }
    final dir = Directory(downloadPath);
    if (!(await dir.exists())) {
      await dir.create(recursive: true);
    }
    return dir.absolute.path;
  }

  Future<List<String>> getAllImageFileList(String id, int ep) async {
    String downloadPath;
    final dirName = await getDirectoryName(id);
    if (ep == 0) {
      downloadPath = "$path/$dirName/";
    } else {
      downloadPath = "$path/$dirName/$ep/";
    }
    final dir = Directory(downloadPath);
    if (!(await dir.exists())) {
      return [];
    }
    final files = await dir.list(recursive: true).toList();
    sFileRelativeFromPath = downloadPath;
    return files
        .where(predictImageFile)
        .sortedByName()
        .map((e) => e.absolute.path)
        .toList();
  }

  Future<List<String>> getAllImagesByDir(String dirPath) async {
    final dir = Directory(dirPath);
    if (!(await dir.exists())) {
      return [];
    }
    final files = await dir.list(recursive: true).toList();
    sFileRelativeFromPath = Path.normalize(dirPath);
    return files
        .whereType<File>()
        .where(predictImageFile)
        .sortedByName()
        .map((e) => e.absolute.path)
        .toList();
  }

  Future<File> getImageAsync(String id, int ep, int index) async {
    String downloadPath;
    final dirName = await getDirectoryName(id);
    if (ep == 0) {
      downloadPath = "$path/$dirName/";
    } else {
      downloadPath = "$path/$dirName/$ep/";
    }
    var fileName = _downloadedFileName["$id$ep$index"];
    if (fileName != null) {
      final file = File(downloadPath + fileName);
      if (await file.exists()) {
        return file;
      }
    }
    await for (var file in Directory(downloadPath).list()) {
      var i = file.uri.pathSegments.last.replaceFirst(RegExp(r"\..+"), "");
      if (i.isNum) {
        if (_downloadedFileName.length > 2000) {
          _downloadedFileName.remove(_downloadedFileName.keys.first);
        }
        _downloadedFileName["$id$ep$i"] = file.name;
      }
    }
    if (_downloadedFileName["$id$ep$index"] == null) {
      throw Exception("File not found");
    }
    return File(downloadPath + _downloadedFileName["$id$ep$index"]!);
  }

  static final _downloadedFileName = <String, String>{};

  ///获取封面, 所有漫画源通用
  Future<File> getCoverAsync(String id, {bool check = false}) async {
    final dirName = await getDirectoryName(id);
    var file = File("$path/$dirName/cover.jpg");
    if (check) {
      const extensions = [".png", ".webp"];
      if (file.existsSync()) {
        return file;
      }
      file = File("$path/$dirName/cover.webp");
      if (file.existsSync()) {
        return file;
      }
      file = File("$path/$dirName/cover.png");
      if (file.existsSync()) {
        return file;
      }
    }
    return file;
  }

  Future<void> fillDownloadingItemCover(DownloadedItem item) async {
    final dirPath = Path.join(path ?? '', item.directory ?? '');
    if (dirPath.isEmpty) {
      return;
    }
    const extensions = ['.jpg', ".png", ".webp"];
    for (var extension in extensions) {
      final file = File(Path.join(dirPath, 'cover$extension'));
      if (await file.exists()) {
        item.coverPath = file.path;
        return;
      }
    }
  }

  Future<File> getCover(String id, {bool check = false}) async {
    final dirPath = await getFullDirectory(id);
    var file = File("$dirPath/cover.jpg");
    if (check) {
      const extensions = [".png", ".webp"];
      if (file.existsSync()) {
        return file;
      }
      file = File("$dirPath/cover.webp");
      if (file.existsSync()) {
        return file;
      }
      file = File("$dirPath/cover.png");
      if (file.existsSync()) {
        return file;
      }
    }
    return file;
  }
}

DownloadingItem downloadingItemFromMap(
    Map<String, dynamic> map,
    void Function() whenFinish,
    void Function() whenError,
    Future<void> Function() updateInfo) {
  switch (map["type"]) {
    case 0:
      return PicDownloadingItem.fromMap(
          map, whenFinish, whenError, updateInfo, map["id"]);
    case 1:
      return EhDownloadingItem.fromMap(
          map, whenFinish, whenError, updateInfo, map["id"]);
    case 2:
      return JmDownloadingItem.fromMap(
          map, whenFinish, whenError, updateInfo, map["id"]);
    case 3:
      return HitomiDownloadingItem.fromMap(
          map, whenFinish, whenError, updateInfo, map["id"]);
    case 4:
      return DownloadingHtComic.fromMap(
          map, whenFinish, whenError, updateInfo, map["id"]);
    case 5:
      return NhentaiDownloadingItem.fromMap(
          map, whenFinish, whenError, updateInfo, map["id"]);
    case 6:
      return CustomDownloadingItem.fromMap(
          map, whenFinish, whenError, updateInfo, map["id"]);
    case 7:
      return FavoriteDownloading.fromMap(
          map, whenFinish, whenError, updateInfo, map["id"]);
    default:
      throw UnimplementedError();
  }
}

extension AddDownloadExt on DownloadManager {
  ///添加哔咔漫画下载
  void addPicDownload(ComicItem comic, List<int> downloadEps) {
    downloading.addLast(PicDownloadingItem(
        comic, downloadEps, _onFinish, _onError, _saveInfo, comic.id));
    _saveInfo();
    if (!isDownloading) {
      downloading.first.start();
      isDownloading = true;
    }
  }

  ///添加E-Hentai下载
  /// 重复的英语: duplicateEnglishName
  /// - downloadEps: 下载的章节
  void addEhDownload(Gallery gallery, [int type = 0, bool duplicate = false]) {
    final id = getGalleryId(gallery.link);
    if (duplicate) {
      DownloadManager().deleteWithoutFile([id]);
    }
    downloading.addLast(EhDownloadingItem(
        gallery, _onFinish, _onError, _saveInfo, id, type,
        duplicate: duplicate));
    _saveInfo();
    if (!isDownloading) {
      downloading.first.start();
      isDownloading = true;
    }
  }

  ///添加禁漫下载
  void addJmDownload(JmComicInfo comic, List<int> downloadEps) {
    downloading.addLast(JmDownloadingItem(
        comic, downloadEps, _onFinish, _onError, _saveInfo, "jm${comic.id}"));
    _saveInfo();
    if (!isDownloading) {
      downloading.first.start();
      isDownloading = true;
    }
  }

  ///添加Hitomi下载
  void addHitomiDownload(HitomiComic comic, String cover, String link) {
    final id = "hitomi${comic.id}";
    downloading.addLast(HitomiDownloadingItem(
        comic, cover, link, _onFinish, _onError, _saveInfo, id));
    _saveInfo();
    if (!isDownloading) {
      downloading.first.start();
      isDownloading = true;
    }
  }

  ///添加绅士漫画下载
  void addHtDownload(HtComicInfo comic) {
    final id = "Ht${comic.id}";
    downloading
        .addLast(DownloadingHtComic(comic, _onFinish, _onError, _saveInfo, id));
    _saveInfo();
    if (!isDownloading) {
      downloading.first.start();
      isDownloading = true;
    }
  }

  void addNhentaiDownload(NhentaiComic comic) {
    final id = "nhentai${comic.id}";
    downloading.addLast(
        NhentaiDownloadingItem(comic, _onFinish, _onError, _saveInfo, id));
    _saveInfo();
    if (!isDownloading) {
      downloading.first.start();
      isDownloading = true;
    }
  }

  void addCustomDownload(ComicInfoData comic, List<int> downloadEps) {
    var id = generateId(comic.sourceKey, comic.comicId);
    downloading.addLast(CustomDownloadingItem(
        comic, downloadEps, _onFinish, _onError, _saveInfo, id));
    _saveInfo();
    if (!isDownloading) {
      downloading.first.start();
      isDownloading = true;
    }
  }

  void addFavoriteDownload(FavoriteItem comic) {
    var id = switch (comic.type.key) {
      0 => comic.target,
      1 => getGalleryId(comic.target),
      2 => "jm${comic.target}",
      3 => "hitomi${RegExp(r"\d+(?=\.html)").firstMatch(comic.target)![0]!}",
      4 => "Ht${comic.target}",
      6 => "nhentai${comic.target}",
      _ => generateId(comic.type.comicSource.key, comic.target)
    };
    downloading.addLast(
        FavoriteDownloading(comic, _onFinish, _onError, _saveInfo, id));
    _saveInfo();
    if (!isDownloading) {
      downloading.first.start();
      isDownloading = true;
    }
  }

  DownloadedItem? _getComicFromJson({
    required String id,
    required String json,
    required DateTime time,
    double? size,
    String? directory,
  }) {
    DownloadedItem comic;
    try {
      if (id.contains('-')) {
        comic = CustomDownloadedItem.fromJson(jsonDecode(json));
      } else if (id.startsWith("jm")) {
        comic = DownloadedJmComic.fromMap(jsonDecode(json));
      } else if (id.startsWith("hitomi")) {
        comic = DownloadedHitomiComic.fromMap(jsonDecode(json));
      } else if (id.startsWith("nhentai")) {
        comic = NhentaiDownloadedComic.fromJson(jsonDecode(json));
      } else if (id.startsWith("Ht")) {
        comic = DownloadedHtComic.fromJson(jsonDecode(json));
      } else if (id.isNum) {
        comic = DownloadedGallery.fromJson(jsonDecode(json));
      } else {
        comic = DownloadedComic.fromJson(jsonDecode(json));
      }
      comic.time = time;
      comic.directory = directory;
      if (size != null && size > 0) {
        comic.comicSize = size;
      }
      return comic;
    } catch (e, s) {
      Log.e("IO Failed to get a downloaded comic info:\n$e\n$s");
      return null;
    }
  }

  Future<void> _addToDb(DownloadedItem item, String directory,
      [DateTime? time]) async {
    await _db.addToDownload(
      item.id,
      item.name,
      item.subTitle,
      (time ?? DateTime.now()).millisecondsSinceEpoch,
      directory,
      item.comicSize ?? 0,
      jsonEncode(item.toJson()),
    );
  }

  /// 更新漫画大小
  Future<void> updateSize(String id, double size) async {
    await _db.updateDownloadSize(id, size);
  }

  Future<bool> isExists(String id) async {
    return await _db.isDownloadExists(id);
  }

  Future<void> _deleteFromDb(String id) async {
    await _db.deleteDownload(id);
    _cache.remove(id);
  }

  Future<DownloadedItem?> _getComicWithDb(String id) async {
    final result = await _db.getDownloadById(id);
    if (result == null) return null;

    return _getComicFromJson(
      id: result[kDownloadId] as String,
      json: result[kDownloadJson] as String,
      time: DateTime.fromMillisecondsSinceEpoch(result[kDownloadTime] as int),
      size: result[kDownloadSize] is double
          ? result[kDownloadSize] as double
          : (result[kDownloadSize] as int).toDouble(),
      directory: result[kDownloadDirectory] as String?,
    );
  }

  /// 根据ID获取已下载的漫画
  Future<DownloadedItem?> getDownloadedItemById(String id) async {
    return await _getComicWithDb(id);
  }

  // int get total {
  //   // 注意：这个方法需要异步处理，但在原来代码中是同步的
  //   // 在实际使用中，需要重构调用此属性的地方改为异步
  //   throw UnimplementedError('Use getTotal() instead');
  // }

  Future<int> getTotal() async {
    return await _db.getDownloadTotalCount();
  }

  /// order: time, title, subtitle, size
  Future<List<DownloadedItem>> getAll(
      [String order = 'time', String direction = 'desc']) async {
    String orderBy;
    switch (order) {
      case 'time':
        orderBy = kDownloadTime;
        break;
      case 'title':
        orderBy = kDownloadTitle;
        break;
      case 'subtitle':
        orderBy = kDownloadSubtitle;
        break;
      case 'size':
        orderBy = kDownloadSize;
        break;
      default:
        orderBy = kDownloadTime;
    }

    final result = await _db.getAllDownloads(
      orderBy: orderBy,
      descending: direction == 'desc',
    );

    return result
        .map(
          (e) => _getComicFromJson(
            id: e[kDownloadId] as String,
            json: e[kDownloadJson] as String,
            time: DateTime.fromMillisecondsSinceEpoch(e[kDownloadTime] as int),
            size: e[kDownloadSize] is double
                ? e[kDownloadSize] as double
                : (e[kDownloadSize] as int).toDouble(),
            directory: e[kDownloadDirectory] as String?,
          )!,
        )
        .toList();
  }

  static final _cache = <String, String>{};

  String getDirectory(String id) {
    var directory = _cache[id];
    if (directory == null) {
      // 注意：这个方法需要异步处理，但在原来代码中是同步的
      // 在实际使用中，需要重构调用此方法的地方改为异步
      throw UnimplementedError('Use getDirectoryAsync() instead');
    }
    return directory ?? '';
  }

  Future<String> getDirectoryName(String id) {
    var directory = _cache[id];
    if (directory != null && directory.isNotEmpty) {
      return SynchronousFuture(directory);
    }
    return Future.sync(() async {
      String? directory = await _db.getDownloadDirectory(id);
      if (directory == null) {
        debugPrint("Failed to get directory for $id");
        return '';
      }
      directory = _findAccurateDirectory(directory);
      if (_cache.length > 50) {
        _cache.remove(_cache.keys.first);
      }
      _cache[id] = directory;
      return directory;
    });
  }

  Future<String> getFullDirectory(String id) async {
    return getDirectoryName(id).then((e) {
      if (e.isEmpty) return '';
      return Path.join(path ?? '', e);
    });
  }

  String _findAccurateDirectory(String directory) {
    return sanitizeFileName(directory);
  }

  /// 添加一个本地的漫画
  Future<void> addLocalItem({
    required String path,
    required String title,
    required String subtitle,
    required Map<String, dynamic> json,
    required double size,
    required String cover,
  }) async {
    await _db.addLocalComic(
      path: path,
      title: title,
      subtitle: subtitle,
      json: jsonEncode(json),
      size: size,
      cover: cover,
    );
  }

  Future<List<Map<String, dynamic>>> getAllLocal() async {
    return (await _db.getAllLocalComics())
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<void> deleteLocal(String path) async {
    await _db.deleteLocalComic(path);
  }

  Future<void> addOrUpdateLocalHistory({
    required String path,
    required bool isReversed,
    required int pageIndex,
    required int time,
    Map<String, dynamic> json = const {},
  }) async {
    await _db.addOrUpdateLocalHistory(
      path: path,
      isReversed: isReversed ? 1 : 0,
      pageIndex: pageIndex,
      time: time,
      json: TypeUtil.parseString(json),
    );
  }

  Future<Map<String, dynamic>> getLocalHistory(String path) async {
    final result = await _db.getLocalHistory(path);
    if (result == null) return {};
    return TypeUtil.parseMap(result);
  }

  // ==================== Tag Management Methods ====================

  /// 创建标签
  Future<int> createTag(String name,
      {String? coverComicId, int category = 0}) async {
    return await _db.createTag(name,
        coverComicId: coverComicId, category: category);
  }

  /// 获取所有标签
  Future<List<DownloadTag>> getAllTags() async {
    final maps = await _db.getAllTags();
    return maps.map((map) => DownloadTag.fromMap(map)).toList();
  }

  /// 根据ID获取标签
  Future<DownloadTag?> getTagById(int tagId) async {
    final map = await _db.getTagById(tagId);
    return map != null ? DownloadTag.fromMap(map) : null;
  }

  /// 重命名标签
  Future<void> renameTag(int tagId, String newName) async {
    await _db.updateTagName(tagId, newName);
  }

  /// 更新标签封面（使用漫画ID）
  Future<void> updateTagCover(int tagId, String coverComicId) async {
    await _db.updateTagCover(tagId, coverComicId);
  }

  /// 删除标签
  Future<void> deleteTag(int tagId) async {
    await _db.deleteTag(tagId);
  }

  /// 为漫画添加标签
  Future<void> addTagToComic(String comicId, int tagId) async {
    await _db.addTagToComic(comicId, tagId);
  }

  /// 为漫画添加多个标签
  Future<void> addTagsToComic(String comicId, List<int> tagIds) async {
    for (var tagId in tagIds) {
      await _db.addTagToComic(comicId, tagId);
    }
  }

  /// 从漫画移除标签
  Future<void> removeTagFromComic(String comicId, int tagId) async {
    await _db.removeTagFromComic(comicId, tagId);
  }

  /// 获取漫画的所有标签
  Future<List<DownloadTag>> getComicTags(String comicId) async {
    final maps = await _db.getComicTags(comicId);
    return maps.map((map) => DownloadTag.fromMap(map)).toList();
  }

  Future<List<DownloadTag>> getCommonComicTags(List<String> comicIds) async {
    final maps = await _db.getCommonComicTags(comicIds);
    return maps.map((map) => DownloadTag.fromMap(map)).toList();
  }

  /// 获取所有漫画的标签映射
  Future<Map<String, List<String>>> getAllComicTagsMap() async {
    return await _db.getAllComicTags();
  }

  /// 获取标签下的所有漫画ID
  Future<List<String>> getComicIdsByTag(int tagId) async {
    return await _db.getComicIdsByTag(tagId);
  }

  /// 获取标签下的漫画数量
  Future<int> getTagComicCount(int tagId) async {
    return await _db.getTagComicCount(tagId);
  }

  /// 清除漫画的所有标签
  Future<void> clearComicTags(String comicId) async {
    await _db.clearComicTags(comicId);
  }

  /// 更新标签排序
  Future<void> updateTagSortOrder(int tagId, int sortOrder) async {
    await _db.updateTagSortOrder(tagId, sortOrder);
  }

  /// 批量更新标签排序
  Future<void> updateTagsSortOrder(List<int> tagIds) async {
    await _db.updateTagsSortOrder(tagIds);
  }

  /// 更新标签分类排序
  Future<void> updateTagCategorySortOrder(int tagId, int sortOrder) async {
    await _db.updateTagCategorySortOrder(tagId, sortOrder);
  }

  /// 更新标签分类
  Future<void> updateTagCategory(int tagId, int category) async {
    await _db.updateTagCategory(tagId, category);
  }

  /// 按分类获取标签
  Future<List<DownloadTag>> getTagsByCategory(int category) async {
    final maps = await _db.getTagsByCategory(category);
    return maps.map((map) => DownloadTag.fromMap(map)).toList();
  }
}

class SaveInfoItem {
  final Map<String, dynamic> items;
  final String path;

  SaveInfoItem(this.items, this.path);
}
