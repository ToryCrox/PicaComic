import 'dart:async';
import 'dart:isolate';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/foundation/cache_manager.dart';
import 'package:pica_comic/foundation/log.dart';
import 'package:pica_comic/network/download/file_downloader.dart';
import 'package:pica_comic/network/eh_network/eh_models.dart';
import 'package:pica_comic/network/download/download_model.dart';
import 'package:pica_comic/foundation/image_manager.dart';
import 'package:pica_comic/network/http_client.dart';
import 'package:zip_flutter/zip_flutter.dart';
import 'dart:io';
import '../../tools/io_tools.dart';
import 'eh_main_network.dart';
import 'package:pica_comic/network/download/models/download_color_tag.dart';
import 'get_gallery_id.dart';

class DownloadedGallery extends DownloadedItem {
  Gallery gallery;
  double? size;
  @override
  DownloadColorTag? color;

  DownloadedGallery(this.gallery, this.size, {this.color});

  @override
  Map<String, dynamic> toJson() => {
    "gallery": gallery.toJson(),
    "size": size,
    "color": color?.name,
  };

  DownloadedGallery.fromJson(Map<String, dynamic> map)
    : gallery = Gallery.fromJson(map["gallery"]),
      size = map["size"],
      color = DownloadColorTag.fromString(map["color"]);

  @override
  DownloadType get type => DownloadType.ehentai;

  @override
  List<int> get downloadedEps => [0];

  @override
  List<String> get eps => ["EP 1"];

  @override
  String get name {
    if (appdata.settings[78] == "1") {
      return gallery.subTitle ?? gallery.title;
    } else {
      return gallery.title;
    }
  }

  @override
  String get id => getGalleryId(gallery.link);

  @override
  String get subTitle => gallery.uploader;

  @override
  double? get comicSize => size;

  @override
  set comicSize(double? value) {
    size = value;
  }

  List<String> _getTags() {
    var res = <String>[];
    gallery.tags.forEach(
      (key, value) => value.forEach((element) => res.add(element)),
    );
    return res;
  }

  @override
  List<String> get tags => _getTags();
}

///e-hentai的下载进程模型
class EhDownloadingTask extends DownloadingTask {
  EhDownloadingTask(
    this.gallery,
    super.whenFinish,
    super.onError,
    super.updateInfo,
    super.id,
    this.downloadType, {
    super.type = DownloadType.ehentai,
  });

  ///画廊模型
  final Gallery gallery;

  final int downloadType;

  @override
  Map<String, String> get headers => {
    "Cookie": EhNetwork().cookiesStr,
    "User-Agent": webUA,
    "Referer": EhNetwork().ehBaseUrl,
  };

  @override
  String get cover =>
      gallery.coverPath.replaceFirst('s.exhentai.org', 'ehgt.org');

  @override
  String get title => gallery.title;

  @override
  Future<Map<int, List<String>>> getLinks() async {
    return {
      0: List.generate(
        (int.parse(gallery.maxPage)),
        (index) => (index + 1).toString(),
      ),
    };
  }

  @override
  Stream<DownloadProgress> downloadImage(String link) {
    return ImageManager().getEhImageNew(
      gallery,
      int.parse(link),
      // 每次下载页面时读取当前设置；原图不可用时允许回退到普通图。
      preferOriginal: appdata.settings[29] == "1",
    );
  }

  @override
  Map<String, dynamic> toMap() {
    // 创建 gallery 的副本，移除可能过期的认证信息
    final galleryJson = gallery.toJson();
    if (galleryJson['auth'] != null) {
      final auth = Map<String, dynamic>.from(galleryJson['auth']);
      // 移除会过期的字段，避免下次恢复时使用过期的认证
      auth.remove('showKey');
      auth.remove('mpvKey');
      auth.remove('imgKey');
      // 确保清理可能遗留的 loading 状态
      if (auth['showKey'] == 'loading') {
        auth.remove('showKey');
      }
      galleryJson['auth'] = auth;
    }

    return {
      "gallery": galleryJson,
      "downloadType": downloadType,
      "_downloadLink": _downloadLink,
      "_currentBytes": _currentBytes,
      "_totalBytes": _totalBytes,
      ...super.toBaseMap(),
    };
  }

  @override
  Future<void> onStart() async {
    await super.onStart();

    // 彻底重置所有认证相关的状态，确保从保存数据恢复时不会使用过期的认证
    if (gallery.auth != null) {
      gallery.auth!.remove("showKey");
      gallery.auth!.remove("mpvKey");
      gallery.auth!.remove("imgKey");
      // 确保没有留下 "loading" 状态，防止死锁
      if (gallery.auth!["showKey"] == "loading") {
        gallery.auth!.remove("showKey");
      }
    }

    // 清除图片缓存，强制重新获取新的图片链接
    await CacheManager().deleteKeyword("exhentai.org");
    await CacheManager().deleteKeyword("e-hentai.org");

    Log.d(() => 'EhDownloadingTask: 已重置认证状态 id=$id');
  }

  int? _currentBytes;

  int? _totalBytes;

  @override
  int get totalPages {
    if (downloadType == 0) {
      return super.totalPages;
    } else {
      return _totalBytes ?? 1;
    }
  }

  @override
  int get downloadedPages {
    if (downloadType == 0) {
      return super.downloadedPages;
    } else {
      return _currentBytes ?? 0;
    }
  }

  _IsolateDownloader? _downloader;

  bool _stop = false;

  String? _downloadLink;

  int _currentSpeed = 0;

  @override
  int get currentSpeed =>
      downloadType == 0 ? super.currentSpeed : _currentSpeed;

  @override
  start() async {
    if (downloadType == 0) {
      return super.start();
    } else {
      await onStart();
      _stop = false;
      try {
        await downloadCover();
        if (gallery.auth?["archiveDownload"] == null) {
          throw "No archive download link";
        }
        if (_downloadLink == null) {
          var res = await EhNetwork().getArchiveDownloadLink(
            gallery.auth!["archiveDownload"]!,
            downloadType,
          );
          if (_stop) {
            return;
          }
          if (res.error) {
            throw res.errorMessage!;
          }
          _downloadLink = res.data;
        }
        _downloader = _IsolateDownloader(_downloadLink!, path, (
          current,
          total,
          speed,
        ) {
          _currentBytes = current;
          _totalBytes = total;
          _currentSpeed = speed;
          updateInfo?.call();
          if (current == total) {
            if (downloadManager.downloading.firstOrNull != this) return;
            finish();
          }
        }, onError!);
        _downloader!.start();
      } catch (e, s) {
        Log.e("Download $e\n$s");
        lastError = e;
        onError?.call();
        return;
      }
    }
  }

  void finish() async {
    onFinish?.call();
  }

  @override
  pause() async {
    if (downloadType == 0) {
      return super.pause();
    } else {
      _stop = true;
      _downloader?.pause();
    }
  }

  @override
  stop() async {
    if (downloadType == 0) {
      return super.stop();
    } else {
      _stop = true;
      _downloader?.stop();
      var directory = Directory(path);
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    }
  }

  EhDownloadingTask.fromMap(
    Map<String, dynamic> map,
    DownloadProgressCallback whenFinish,
    DownloadProgressCallback whenError,
    DownloadProgressCallbackAsync updateInfo,
    String id,
  ) : gallery = Gallery.fromJson(map["gallery"]),
      downloadType = map["downloadType"],
      _currentBytes = map["_currentBytes"],
      _totalBytes = map["_totalBytes"],
      _downloadLink = map["_downloadLink"],
      super.fromMap(map, whenFinish, whenError, updateInfo);

  @override
  FutureOr<DownloadedItem> toDownloadedItem() async {
    final size = await getFolderSize(Directory(path));
    return DownloadedGallery(gallery, size);
  }
}

class _IsolateDownloader {
  final String url;

  final String savePath;

  late ReceivePort port;

  late SendPort sendPort;

  final void Function(int current, int total, int speed) updateInfo;

  final void Function() onError;

  _IsolateDownloader(this.url, this.savePath, this.updateInfo, this.onError);

  Isolate? isolate;

  void stop() {
    sendPort.send("stop");
    isolate = null;
    port.close();
  }

  void pause() {
    stop();
  }

  void start() async {
    port = ReceivePort();
    isolate = await Isolate.spawn<_DownloadData>(
      run,
      _DownloadData(port.sendPort, url, savePath, await getProxy()),
    );
    var total = 0;
    port.listen((message) {
      if (message is SendPort) {
        sendPort = message;
      } else if (message is DownloadingStatus) {
        updateInfo(
          message.downloadedBytes,
          message.totalBytes + 1,
          message.bytesPerSecond,
        );
        total = message.totalBytes;
      } else if (message == "finish") {
        isolate?.kill(priority: Isolate.immediate);
        isolate = null;
        updateInfo(total + 1, total + 1, 0);
      } else if (message is _DownloadException) {
        isolate?.kill(priority: Isolate.immediate);
        isolate = null;
        Log.e("Download ${message.message}");
        onError();
      }
    });
  }

  static void run(_DownloadData data) async {
    var receivePort = ReceivePort();

    final sendPort = data.port;

    sendPort.send(receivePort.sendPort);

    final url = data.url;

    final savePath = data.savePath;

    FileDownloader? task;

    receivePort.listen((message) {
      if (message == "stop") {
        task?.stop().then((value) => Isolate.current.kill());
      }
    });

    Future.sync(() async {
      task = FileDownloader(url, "$savePath/temp.zip", data.proxy);

      try {
        await for (var status in task!.start()) {
          sendPort.send(status);
        }
        ZipFile.openAndExtract("$savePath/temp.zip", savePath);
        var files = Directory(savePath).listSync();
        files.sort((a, b) => a.path.compareTo(b.path));
        int index = 0;
        for (var entry in Directory(savePath).listSync()) {
          if (entry is File) {
            var name = entry.path.split(pathSep).last;
            if (name.endsWith(".zip")) {
              entry.deleteSync();
            } else if (!name.contains("cover")) {
              var baseName = index.toString();
              index++;
              var ext = name.split(".").last;
              entry.renameSync("$savePath/$baseName.$ext");
            }
          }
        }
        sendPort.send("finish");
      } catch (e, s) {
        sendPort.send(_DownloadException("$e\n$s"));
      }
    });
  }
}

class _DownloadData {
  final SendPort port;
  final String url;
  final String savePath;
  final String? proxy;

  const _DownloadData(this.port, this.url, this.savePath, this.proxy);
}

class _DownloadException {
  final String message;

  const _DownloadException(this.message);
}
