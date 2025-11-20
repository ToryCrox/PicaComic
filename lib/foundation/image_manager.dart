import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_qjs/flutter_qjs.dart';
import 'package:html/parser.dart';
import 'package:pica_comic/comic_source/comic_source.dart';
import 'package:pica_comic/foundation/cache_manager.dart';
import 'package:pica_comic/foundation/image_loader/image_recombine.dart';
import 'package:pica_comic/foundation/log.dart';
import 'package:pica_comic/network/app_dio.dart';
import 'package:pica_comic/network/cookie_jar.dart';
import 'package:pica_comic/network/eh_network/eh_models.dart';
import 'package:pica_comic/network/eh_network/get_gallery_id.dart';
import 'package:pica_comic/network/hitomi_network/hitomi_models.dart';
import 'package:pica_comic/tools/extensions.dart';
import 'package:pica_comic/tools/file_type.dart';

import '../base.dart';
import '../network/eh_network/eh_main_network.dart';
import '../network/hitomi_network/image.dart';
import '../network/jm_network/headers.dart';
import '../network/res.dart';

class BadRequestException {
  final String message;

  const BadRequestException(this.message);

  @override
  String toString() => message;
}

class ImageManager {
  static ImageManager instance = ImageManager._create();

  ///用于标记正在加载的项目, 避免出现多个异步函数加载同一张图片
  //static Map<String, DownloadProgress> loadingItems = {};

  /// Image cache manager for reader and download manager
  factory ImageManager() => instance;

  static bool get haveTask => instance._downloadControllers.isNotEmpty;

  static void clearTasks() {
  }

  ImageManager._create();

  final dio = logDio(BaseOptions())
    ..interceptors.add(CookieManagerSql(SingleInstanceCookieJar.instance!));

  int ehgtLoading = 0;

  /// 缓存下载进度
  final Map<String, StreamController<DownloadProgress>> _downloadControllers =
      {};

  StreamController<DownloadProgress> _getOrCreateController(
      String cacheKey, StreamController<DownloadProgress> controller) {
    StreamController<DownloadProgress>? downloadController =
        _downloadControllers[cacheKey];
    if (downloadController != null) {
      Log.d(() => "_putImageStream $cacheKey: already downloading");
      _connectStream(downloadController, controller, cancelOnError: true);
      return downloadController;
    } else {
      Log.d(() => "_putImageStream $cacheKey");
      downloadController = StreamController<DownloadProgress>.broadcast();
      _downloadControllers[cacheKey] = downloadController;
      _connectStream(downloadController, controller, cancelOnError: true);
    }
    downloadController.stream.listen((e) {}, onDone: () {
      _downloadControllers.remove(cacheKey);
    });
    return downloadController;
  }

  /// 连接两个StreamController，传输所有事件（数据、错误、完成）
  static StreamSubscription<T> _connectStream<T>(
    StreamController<T> source,
    StreamController<T> target, {
    bool cancelOnError = false,
  }) {
    return source.stream.listen(
      (T data) {
        // 只在目标StreamController未关闭时添加数据
        if (!target.isClosed) {
          target.add(data);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        // 只在目标StreamController未关闭时添加错误
        if (!target.isClosed) {
          target.addError(error, stackTrace);
        }
      },
      onDone: () {
        // 只在目标StreamController未关闭时关闭
        if (!target.isClosed) {
          target.close();
        }
      },
      cancelOnError: cancelOnError,
    );
  }

  Future<bool> _checkFileCache({
    required StreamController<DownloadProgress> controller,
    required String url,
    String? key,
  }) async {
    final isFileUrl = url.startsWith("file://");
    if (isFileUrl) {
      final file = File(url.replaceFirst('file://', ''));
      if (await file.exists()) {
        controller.add(DownloadProgress(1, 1, url, file.path, null, null));
      } else {
        controller.addError(Exception("File not found ${file.path}"));
      }
      return true;
    }
    final cacheKey = key ?? url;
    var cache = await CacheManager().findCache(cacheKey);
    if (cache != null && (await cache.file.exists())) {
      Log.d(() => "checkFileCache $cacheKey: already cached");
      controller
          .add(DownloadProgress(1, 1, url, cache.filePath, null, cache.type));
      return true;
    } else {
      return false;
    }
  }

  /// 获取图片, 适用于没有任何限制的图片链接
  Stream<DownloadProgress> getImage(final String url,
      [Map<String, String>? headers]) {
    final controller = StreamController<DownloadProgress>();
    _putImageStream(controller: controller, url: url, headers: headers);
    return controller.stream;
  }

  /// 1. 先检查文件缓存
  /// 2. 再检查是否有正在下载的图片
  /// 3. 下载图片
  Future<void> _putImageStream({
    required StreamController<DownloadProgress> controller,
    required final String url,
    Map<String, String>? headers,
  }) async {
    if (await _checkFileCache(controller: controller, url: url)) {
      controller.close();
      return;
    }
    final cacheKey = url;
    final downloadController = _getOrCreateController(cacheKey, controller);

    CachingFile? caching;
    try {
      final cachingFile = await CacheManager().openWrite(cacheKey);
      caching = cachingFile;
      final savePath = cachingFile.file.path;
      downloadController.add(DownloadProgress(0, 100, url, savePath));
      headers = headers ?? {};
      headers["User-Agent"] ??= webUA;
      headers["Connection"] = "Keep-Alive";
      var realUrl = url;
      if (url.contains("s.exhentai.org")) {
        // s.exhentai.org 有严格的加载限制
        realUrl = url.replaceFirst("s.exhentai.org", "ehgt.org");
      }
      if (realUrl.contains("ehgt.org")) {
        if (ehgtLoading < 3) {
          ehgtLoading++;
          await Future.delayed(const Duration(milliseconds: 10));
        } else {
          while (ehgtLoading > 2) {
            await Future.delayed(const Duration(milliseconds: 200));
          }
          ehgtLoading++;
        }
      }
      var dioRes = await dio.get<ResponseBody>(realUrl,
          options:
              Options(responseType: ResponseType.stream, headers: headers));
      if (dioRes.data == null) {
        throw Exception("Empty Data");
      }
      List<int> imageData = [];
      int? expectedBytes;
      try {
        expectedBytes =
            int.parse(dioRes.data!.headers["Content-Length"]![0]) + 1;
      } catch (e) {
        //忽略
      }
      await for (var res in dioRes.data!.stream) {
        imageData.addAll(res);
        await cachingFile.writeBytes(res);
        var progress = DownloadProgress(imageData.length,
            (expectedBytes ?? imageData.length + 1), url, savePath);
        downloadController.add(progress);
      }
      var ext = getExt(dioRes);
      cachingFile.fileType = ext;
      await cachingFile.close();
      downloadController.add(DownloadProgress(
        imageData.length,
        imageData.length,
        url,
        savePath,
        Uint8List.fromList(imageData),
        ext,
        cachingFile,
      ));
    } catch (e, s) {
      caching?.cancel();
      Log.e("Network $e\n$s");
      if (e is DioException && e.type == DioExceptionType.badResponse) {
        var statusCode = e.response?.statusCode;
        if (statusCode != null && statusCode >= 400 && statusCode < 500) {
          downloadController
              .addError(BadRequestException(e.message.toString()));
        } else {
          downloadController.addError(e);
        }
      } else {
        downloadController.addError(e);
      }
    } finally {
      if (url.contains("ehgt.org") || url.contains("s.exhentai.org")) {
        ehgtLoading--;
      }
      downloadController.close();
    }
  }

  Stream<DownloadProgress> getEhImageNew(
      final Gallery gallery, final int page) {
    final controller = StreamController<DownloadProgress>();
    _putEhImageNewStream(controller: controller, gallery: gallery, page: page);
    return controller.stream;
  }

  Future<void> _putEhImageNewStream({
    required StreamController<DownloadProgress> controller,
    required Gallery gallery,
    required int page,
}) async {
    final galleryLink = gallery.link;
    final cacheKey = "$galleryLink$page";
    final gid = getGalleryId(galleryLink);
    Log.d("getEhImageNew $cacheKey, '$galleryLink");
    final key = cacheKey;
    if (await _checkFileCache(controller: controller, url: key)) {
      controller.close();
      return;
    }

    final downloadController = _getOrCreateController(cacheKey, controller);

    CachingFile? caching;

    try {
      final cachingFile = await CacheManager().openWrite(key);
      caching = cachingFile;
      final savePath = cachingFile.file.path;
      downloadController.add(DownloadProgress(0, 100, key, savePath));

      final options = BaseOptions(
          followRedirects: true,
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 20),
          headers: {"user-agent": webUA, "cookie": EhNetwork().cookiesStr});

      var dio = logDio(options);

      // Get imgKey
      final readerLink =
          (await EhNetwork().getReaderLink(galleryLink, page)).data;
      Log.d("getEhImageNew $cacheKey, readerLink:'$readerLink'");

      Future<void> getShowKey() async {
        while (gallery.auth!["showKey"] == "loading") {
          await Future.delayed(const Duration(milliseconds: 100));
        }
        if (gallery.auth!["showKey"] != null ||
            gallery.auth!["mpvKey"] != null) {
          return;
        }
        gallery.auth!["showKey"] = "loading";
        try {
          var res = await EhNetwork().request(readerLink);

          var html = parse(res.data);
          var script = html
              .querySelectorAll("script")
              .firstWhereOrNull((element) => element.text.contains("showkey"));
          if (script != null) {
            var match = RegExp(r'showkey="(.*?)"').firstMatch(script.text);
            final showKey = match!.group(1)!;
            gallery.auth!["showKey"] = showKey;
          } else {
            final script = html
                .querySelectorAll("script")
                .firstWhereOrNull((element) => element.text.contains("mpvkey"))
                ?.text;
            if (script == null) {
              throw Exception("Failed to get showKey or mpvkey");
            }
            var mpvKey = script
                .split(";")
                .firstWhere((element) => element.contains("mpvkey"));
            gallery.auth!["mpvKey"] = mpvKey.removeAllBlank
                .replaceFirst("varmpvkey=", "")
                .replaceAll('"', "");
            var imageListScript = script
                .split(";")
                .firstWhere((element) => element.contains("imagelist"))
                .removeAllBlank
                .replaceFirst("varimagelist=", "");
            gallery.auth!["imgKey"] =
                jsonDecode(imageListScript).map((e) => e["k"]).join(",");
            gallery.auth!.remove("showKey");
          }
        } catch (e) {
          gallery.auth!.remove("showKey");
          rethrow;
        }
      }

      await getShowKey();
      assert(
          gallery.auth?["showKey"] != null || gallery.auth?["mpvKey"] != null);

      downloadController.add(DownloadProgress(0, 100, cacheKey, savePath));


      Response<ResponseBody>? res;

      var imgKey = readerLink.split('/')[4];

      int totalBytes = 0;
      List<int> data = [];

      if (gallery.auth?["mpvKey"] != null) {
        Future<(String image, String nl)> getImageFromApi([String? nl]) async {
          Res<String>? apiRes = await EhNetwork().apiRequest({
            "gid": int.parse(gid),
            "imgkey": gallery.auth!["imgKey"]!.split(',')[page - 1],
            "method": "imagedispatch",
            "page": page,
            "mpvkey": gallery.auth!["mpvKey"],
            if (nl != null) "nl": nl
          });
          var apiJson = const JsonDecoder().convert(apiRes.data);
          return (apiJson["i"].toString(), apiJson["s"].toString());
        }

        var (image, nl) = await getImageFromApi();
        int retryTimes = 0;
        while (res == null) {
          try {
            if (image == "") {
              throw "empty url";
            }
            res = await dio.get<ResponseBody>(image,
                options: Options(responseType: ResponseType.stream));
            if (res.data!.headers["Content-Type"]?[0] ==
                    "text/html; charset=UTF-8" ||
                res.data!.headers["content-type"]?[0] ==
                    "text/html; charset=UTF-8") {
              throw ImageExceedError();
            }
          } catch (e) {
            retryTimes++;
            if (retryTimes == 4) {
              throw "Failed to load image.\nMaximum number of retries reached.";
            }
            (image, nl) = await getImageFromApi(nl);
          }
        }
      } else {
        Future<(String, String, String?)> getImageFromApi() async {
          // get image url through api
          Res<String>? apiRes = await EhNetwork().apiRequest({
            "gid": int.parse(gid),
            "imgkey": imgKey,
            "method": "showpage",
            "page": page,
            "showkey": gallery.auth!["showKey"]
          });

          if (apiRes.error && apiRes.errorMessage!.contains("handshake")) {
            throw "Failed to make api request.\n"
                "This may be due to too frequent requests.\n"
                "Try to wait for some time and retry.";
          }

          var apiJson = const JsonDecoder().convert(apiRes.data);

          var i6 = apiJson["i6"] as String;

          RegExp regex = RegExp(r"nl\('(.+?)'\)");
          var nl = regex.firstMatch(i6)?.group(1);

          var originImage = i6.split("<a href=\"").last.split("\">").first;

          var image = apiJson["i3"] as String;

          image = image.substring(
              image.indexOf("src=\"") + 5, image.indexOf("\" style"));

          return (image, originImage, nl);
        }

        Future<(String, String, String?)> getImageFromHtml() async {
          var res = await EhNetwork().request(readerLink);
          if (res.error) {
            throw res.errorMessage ?? "error";
          } else {
            var document = parse(res.data);
            var image =
                document.querySelector("div#i3 > a > img")?.attributes["src"];
            var nl = document
                .querySelector("div#i6 > div > a#loadfail")
                ?.attributes["onclick"]
                ?.split('\'')
                .firstWhereOrNull((element) => element.contains('-'));
            var originImage = document
                    .querySelectorAll("div#i6 > div > a")
                    .firstWhereOrNull(
                        (element) => element.text.contains("original"))
                    ?.attributes["href"] ??
                "";
            return (image ?? "", originImage, nl);
          }
        }

        String image, originImage;
        String? nl;

        try {
          (image, originImage, nl) = await getImageFromApi();
        } catch (e) {
          (image, originImage, nl) = await getImageFromHtml();
        }

        if (image.contains("509.gif")) {
          throw ImageExceedError();
        }

        if (appdata.settings[29] == "1" && originImage.isURL) {
          image = originImage;
        }

        int retryTimes = 0;
        var currentBytes = 0;

        while (true) {
          try {
            data.clear();
            cachingFile.reset();
            if (image == "") {
              throw "empty url";
            }
            res = await dio.get<ResponseBody>(image,
                options: Options(responseType: ResponseType.stream));
            if (res.data!.headers["Content-Type"]?[0] ==
                    "text/html; charset=UTF-8" ||
                res.data!.headers["content-type"]?[0] ==
                    "text/html; charset=UTF-8") {
              throw ImageExceedError();
            }
            var stream = res.data!.stream;
            int? expectedBytes;
            try {
              expectedBytes =
                  int.parse(res.data!.headers["Content-Length"]![0]);
            } catch (e) {
              try {
                expectedBytes =
                    int.parse(res.data!.headers["content-length"]![0]);
              } finally {}
            }

            await for (var b in stream) {
              await cachingFile.writeBytes(b);
              currentBytes += b.length;
              data.addAll(b);
              var progress = DownloadProgress(
                currentBytes,
                expectedBytes + 1,
                cacheKey,
                savePath,
              );
              downloadController.add(progress);
            }
            totalBytes = currentBytes;
            break;
          } catch (e) {
            retryTimes++;
            if (retryTimes == 4) {
              throw "Failed to load image.\nMaximum number of retries reached.";
            }
            if (nl == null) {
              rethrow;
            }
            var (newImage, newNl) = await EhNetwork().getImageLinkWithNL(
                getGalleryId(galleryLink), imgKey, page, nl);
            image = newImage;
            if (kDebugMode) {
              print("Get new image: $image, new nl $newNl");
            }
            if (newNl != null) {
              nl = newNl;
            }
          }
        }
      }
      final ext = detectFileType(data).ext.replaceFirst(('.'), '');
      cachingFile.fileType = ext;
      await cachingFile.close();
      final progress = DownloadProgress(
        totalBytes,
        totalBytes,
        cacheKey,
        savePath,
        Uint8List.fromList(data),
        ext,
        cachingFile,
      );
      downloadController.add(progress);
    } catch (e, s) {
      caching?.cancel();
      Log.e("Network $e\n$s");
      if (e is DioException && e.type == DioExceptionType.badResponse) {
        var statusCode = e.response?.statusCode;
        if (statusCode != null && statusCode >= 400 && statusCode < 500) {
          //throw BadRequestException(e.message.toString());
        }
      }
      downloadController.addError(e);
    } finally {
      downloadController.close();
    }
  }

  ///为Hitomi设计的图片加载函数
  ///
  /// 使用hash标识图片
  Stream<DownloadProgress> getHitomiImage(
      HitomiFile image, String galleryId) {
    final controller = StreamController<DownloadProgress>();
    _putHitomiImageStream(
      controller: controller,
      image: image,
      galleryId: galleryId,
    );
    return controller.stream;
  }

  Future<void> _putHitomiImageStream({
    required StreamController<DownloadProgress> controller,
    required HitomiFile image,
    required String galleryId,
  }) async {
    Log.d("Get Hitomi image ${image.hash}");
    final cacheKey = image.hash;
    if(await _checkFileCache(controller: controller, url: '', key: cacheKey)) {
      return;
    }

    final downloadController = _getOrCreateController(cacheKey, controller);

    CachingFile? caching;
    try {
      final cachingFile = await CacheManager().openWrite(cacheKey);
      caching = cachingFile;
      final savePath = cachingFile.file.path;
      downloadController.add(DownloadProgress(0, 100, cacheKey, savePath));

      final gg = GG();
      var url = await gg.urlFromUrlFromHash(galleryId, image, 'webp', null);
      int l;
      for (l = url.length - 1; l >= 0; l--) {
        if (url[l] == '.') {
          break;
        }
      }
      var dio = logDio();
      dio.options.headers = {
        "User-Agent": webUA,
        "Referer": "https://hitomi.la/reader/$galleryId.html"
      };

      var res = await dio.get<ResponseBody>(url,
          options: Options(responseType: ResponseType.stream));
      var stream = res.data!.stream;
      int? expectedBytes;
      try {
        expectedBytes = int.parse(res.data!.headers["Content-Length"]![0]);
      } catch (e) {
        try {
          expectedBytes = int.parse(res.data!.headers["content-length"]![0]);
        } catch (e) {
          //忽视
        }
      }
      var currentBytes = 0;
      var data = <int>[];
      await for (var b in stream) {
        data.addAll(b);
        await cachingFile.writeBytes(b);
        currentBytes += b.length;
        var progress = DownloadProgress(
            currentBytes, (expectedBytes ?? currentBytes + 1), url, savePath);
        downloadController.add(progress);
      }
      var ext = getExt(res);
      cachingFile.fileType = ext;
      await cachingFile.close();
      downloadController.add(DownloadProgress(currentBytes, currentBytes, url, savePath,
          Uint8List.fromList(data), ext, cachingFile));
    } catch (e) {
      caching?.cancel();
      if (e is DioException && e.type == DioExceptionType.badResponse) {
        var statusCode = e.response?.statusCode;
        if (statusCode != null && statusCode >= 400 && statusCode < 500) {
          //throw BadRequestException(e.message.toString());
        }
      }
      downloadController.addError(e);
    } finally {
      downloadController.close();
    }
  }

  ///获取禁漫图片, 如果缓存中没有, 则尝试下载
  Stream<DownloadProgress> getJmImage(
    String url,
    Map<String, String>? headers, {
    required String epsId,
    required String scrambleId,
    required String bookId,
  }) {
    final controller = StreamController<DownloadProgress>();
    _putJmImageStream(controller, url, headers,
        epsId: epsId, scrambleId: scrambleId, bookId: bookId);
    return controller.stream;
  }

  Future<void> _putJmImageStream(
    StreamController<DownloadProgress> controller,
    String url,
    Map<String, String>? headers, {
    required String epsId,
    required String scrambleId,
    required String bookId,
  }) async {
    bookId = bookId.replaceAll(RegExp(r"\..+"), "");
    final urlWithoutParam = url.replaceAll(RegExp(r"\?.+"), "");

    final cacheKey = urlWithoutParam;
    if (await _checkFileCache(controller: controller, url: url)) {
      Log.d("_putImageStream $url: already cached");
      controller.close();
      return;
    }
    final downloadController = _getOrCreateController(cacheKey, controller);

    CachingFile? caching;

    try {
      final cachingFile = await CacheManager().openWrite(cacheKey);
      caching = cachingFile;
      final savePath = cachingFile.file.path;
      downloadController.add(DownloadProgress(0, 1, url, savePath));

      var dio = logDio();

      var bytes = <int>[];
      String? ext;
      try {
        var res = await dio.get<ResponseBody>(url,
            options: Options(
                responseType: ResponseType.stream, headers: getImgHeaders()));
        ext = getExt(res);
        var stream = res.data!.stream;
        await for (var b in stream) {
          //不直接写入文件, 因为需要对图片进行重组, 处理完成后再写入
          bytes.addAll(b);
          //构建虚假的进度条, 因为无法获取jm文件大小
          var total = max(1 << 20, bytes.length + 1);
          var progress = DownloadProgress(bytes.length, total, url, savePath);
          downloadController.add(progress);
        }
      } catch (e) {
        rethrow;
      }
      var progress = DownloadProgress(
        bytes.length,
        (bytes.length / 0.75).toInt(),
        url,
        savePath,
      );
      downloadController.add(progress);
      if (url.split('.').last != "gif") {
        bytes = await startRecombineAndWriteImage(
            Uint8List.fromList(bytes), epsId, scrambleId, bookId, savePath);
      }
      await cachingFile.writeBytes(bytes);

      cachingFile.fileType = ext;
      await cachingFile.close();
      progress = DownloadProgress(
        bytes.length,
        bytes.length,
        url,
        savePath,
        Uint8List.fromList(bytes),
        ext,
        cachingFile,
      );
      downloadController.add(progress);
    } catch (e) {
      caching?.cancel();
      if (e is DioException && e.type == DioExceptionType.badResponse) {
        var statusCode = e.response?.statusCode;
        if (statusCode != null && statusCode >= 400 && statusCode < 500) {
          //BadRequestException(e.message.toString());
        }
      }
      downloadController.addError(e);
      rethrow;
    } finally {
      downloadController.close();
    }
  }

  Stream<DownloadProgress> getCustomImage(
      String url, String comicId, String epId, String sourceKey) {
    final controller = StreamController<DownloadProgress>();
    _putCustomImageStream(controller: controller, url: url, comicId: comicId, epId: epId, sourceKey: sourceKey);
    return controller.stream;
  }
  Future<void> _putCustomImageStream({
     required StreamController<DownloadProgress> controller,
      required String url, required String comicId, required String epId, required String sourceKey}) async{
    var cacheKey = "$sourceKey$comicId$epId$url";
    Log.d("getCustomImage $url");

    if (await _checkFileCache(controller: controller, url: url)) {
      controller.close();
      return;
    }

    final downloadController = _getOrCreateController(cacheKey, controller);

    CachingFile? caching;

    var source = ComicSource.find(sourceKey) ??
        (throw "Unknown Comic Source $sourceKey");

    try {
      Map<String, dynamic> config;

      if (source.getImageLoadingConfig == null) {
        config = {};
      } else {
        config = source.getImageLoadingConfig!(url, comicId, epId);
      }

      caching = await CacheManager().openWrite(cacheKey);
      final savePath = caching.file.path;

      var res = await dio.request<ResponseBody>(config['url'] ?? url,
          data: config['data'],
          options: Options(
              method: config['method'] ?? 'GET',
              headers: config['headers'] ?? {'user-agent': webUA},
              responseType: ResponseType.stream));

      List<int> imageData = [];

      int? expectedBytes = res.data!.contentLength;
      if (expectedBytes == -1) {
        expectedBytes = null;
      }

      bool shouldModifyData = config['onResponse'] != null;

      await for (var data in res.data!.stream) {
        if (!shouldModifyData) {
          await caching.writeBytes(data);
        }
        imageData.addAll(data);
        var progress = DownloadProgress(
          imageData.length,
          (expectedBytes ?? imageData.length + 1),
          url,
          savePath,
        );
        downloadController.add(progress);
      }

      Uint8List? result;

      if (shouldModifyData) {
        var data = (config['onResponse']
            as JSInvokable)(Uint8List.fromList(imageData));
        imageData.clear();
        if (data is! Uint8List) {
          throw "Invalid Config: onImageLoad.onResponse return invalid type\n"
              "Expected: Uint8List(ArrayBuffer)\n"
              "Got: ${data.runtimeType}";
        }
        result = data;
        await caching.writeBytes(data);
      }

      var ext = getExt(res);
      caching.fileType = ext;
      await caching.close();
      var length = result?.length ?? imageData.length;
      final progress = DownloadProgress(
        length,
        length,
        url,
        savePath,
        result ?? Uint8List.fromList(imageData),
        ext,
      );
      downloadController.add(progress);
    } catch (e) {
      caching?.cancel();
      if (e is DioException && e.type == DioExceptionType.badResponse) {
        var statusCode = e.response?.statusCode;
        if (statusCode != null && statusCode >= 400 && statusCode < 500) {
         // throw BadRequestException(e.message.toString());
        }
      }
      downloadController.addError(e);
    } finally {
      downloadController.close();
    }
  }

  // Future<void> wait(String cacheKey) {
  //   if (loadingItems[cacheKey] == null) {
  //     return Future.value();
  //   }
  //   int timeout = 50;
  //   return Future.doWhile(() async {
  //     await Future.delayed(const Duration(milliseconds: 300));
  //     timeout--;
  //     if (timeout == 0) {
  //       loadingItems.remove(cacheKey);
  //       return false;
  //     }
  //     return loadingItems[cacheKey] != null;
  //   });
  // }

  Stream<DownloadProgress> getCustomThumbnail(String url, String sourceKey,
      [Map<String, String>? headers]) {
    final controller = StreamController<DownloadProgress>();
    _putCustomThumbnailStream(controller: controller, url: url, sourceKey: sourceKey, headers: headers);
    return controller.stream;
  }

  Future<void> _putCustomThumbnailStream({
    required StreamController<DownloadProgress> controller,
    required String url, required String sourceKey, Map<String, String>? headers}) async {
    var cacheKey = "$sourceKey$url";
    if (await _checkFileCache(controller: controller, url: url, key: cacheKey)) {
      controller.close();
      return;
    }
    final downloadController = _getOrCreateController(cacheKey, controller);

    CachingFile? caching;

    var source = ComicSource.find(sourceKey) ??
        (throw "Unknown Comic Source $sourceKey");

    try {
      Map<String, dynamic> config;

      if (source.getThumbnailLoadingConfig == null) {
        config = {};
      } else {
        config = source.getThumbnailLoadingConfig!(url);
      }

      config['headers'] ??= headers;

      caching = await CacheManager().openWrite(cacheKey);
      final savePath = caching.file.path;

      var res = await dio.request<ResponseBody>(config['url'] ?? url,
          data: config['data'],
          options: Options(
              method: config['method'] ?? 'GET',
              headers: config['headers'] ?? {'user-agent': webUA},
              responseType: ResponseType.stream));

      List<int> imageData = [];

      int? expectedBytes = res.data!.contentLength;
      if (expectedBytes == -1) {
        expectedBytes = null;
      }

      bool shouldModifyData = config['onResponse'] != null;

      await for (var data in res.data!.stream) {
        if (!shouldModifyData) {
          await caching.writeBytes(data);
        }
        imageData.addAll(data);
        var progress = DownloadProgress(imageData.length,
            expectedBytes ?? (imageData.length + 1), url, savePath);
        downloadController.add(progress);
      }

      Uint8List? result;

      if (shouldModifyData) {
        var data = (config['onResponse']
            as JSInvokable)(Uint8List.fromList(imageData));
        imageData.clear();
        if (data is! Uint8List) {
          throw "Invalid Config: onImageLoad.onResponse return invalid type\n"
              "Expected: Uint8List(ArrayBuffer)\n"
              "Got: ${data.runtimeType}";
        }
        result = data;
        await caching.writeBytes(data);
      }

      await caching.close();
      final progress = DownloadProgress(
          1, 1, url, savePath, result ?? Uint8List.fromList(imageData));
      downloadController.add(progress);
    } catch (e) {
      Log.e("Network Failed to load a image:\nUrl:$url\nError:$e");
      caching?.cancel();
      if (e is DioException && e.type == DioExceptionType.badResponse) {
        var statusCode = e.response?.statusCode;
        if (statusCode != null && statusCode >= 400 && statusCode < 500) {
          throw BadRequestException(e.message.toString());
        }
      }
      downloadController.addError(e);
    } finally {
      downloadController.close();
    }
  }

  Future<File?> getFile(String key) async {
    var cache = await CacheManager().findCache(key);
    return cache?.file;
  }

  Future<void> clear() async {
    await CacheManager().clear();
  }

  Future<bool> find(String key) async {
    return await CacheManager().findCache(key) != null;
  }

  Future<void> delete(String key) async {
    await CacheManager().delete(key);
  }

  String? getExt(Response res) {
    String? ext;
    var url = res.realUri.toString();
    var contentType =
        (res.headers["Content-Type"] ?? res.headers["content-type"])?[0];
    if (contentType != null) {
      ext = switch (contentType) {
        "image/jpeg" => "jpg",
        "image/png" => "png",
        "image/gif" => "gif",
        "image/webp" => "webp",
        _ => null
      };
    }
    ext ??= url.split('.').last;
    if (!["jpg", "jpeg", "png", "gif", "webp"].contains(ext)) {
      ext = "jpg";
      Log.w("ImageManager Unknown image extension: \n"
          "Content-Type: $contentType\n"
          "URL: $url");
    }
    return ext;
  }
}

class DownloadProgress {
  final int _currentBytes;
  final int _expectedBytes;
  final String url;
  final String savePath;
  final Uint8List? data;
  final String? ext;
  final CachingFile? cachingFile;

  int get currentBytes => _currentBytes;

  int get expectedBytes => _expectedBytes;

  bool get finished => _currentBytes == _expectedBytes;

  const DownloadProgress(
      this._currentBytes, this._expectedBytes, this.url, this.savePath,
      [this.data, this.ext, this.cachingFile]);

  File getFile() => File(savePath);
}

class ImageExceedError extends Error {
  @override
  String toString() => "Maximum image loading limit reached.";
}
