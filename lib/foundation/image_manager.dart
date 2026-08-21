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
import 'package:pica_comic/network/cache_network.dart';
import 'package:pica_comic/network/cookie_jar.dart';
import 'package:pica_comic/network/network_client_manager.dart';
import 'package:pica_comic/network/eh_network/eh_models.dart';
import 'package:pica_comic/network/eh_network/get_gallery_id.dart';
import 'package:pica_comic/network/hitomi_network/hitomi_models.dart';
import 'package:pica_comic/network/image_config.dart';
import 'package:pica_comic/tools/extensions.dart';
import 'package:pica_comic/tools/file_type.dart';

import '../base.dart';
import '../network/eh_network/eh_main_network.dart';
import '../network/hitomi_network/image.dart';
import '../network/jm_network/headers.dart';

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

  static bool get haveTask => instance._downloadTasks.isNotEmpty;

  static void clearTasks() {
    for (final task in instance._downloadTasks.values.toList()) {
      if (!task.cancelToken.isCancelled) {
        task.cancelToken.cancel("Image download cancelled");
      }
    }
    for (final task in instance._ehAuthenticationTasks.values.toList()) {
      if (!task.cancelToken.isCancelled) {
        task.cancelToken.cancel("EH authentication cancelled");
      }
    }
  }

  ImageManager._create();

  Dio get dio => networkClientManager.mediaDio;

  int ehgtLoading = 0;

  /// 缓存下载进度
  final Map<String, _ImageDownloadTask> _downloadTasks = {};

  /// EH 认证加载任务，同一画廊只允许一个认证请求执行。
  final Map<String, _EhAuthenticationTask> _ehAuthenticationTasks = {};

  ({
    StreamController<DownloadProgress> controller,
    CancelToken cancelToken,
    bool isOwner,
  })
  _getOrCreateController(
    String cacheKey,
    StreamController<DownloadProgress> controller,
  ) {
    final existingTask = _downloadTasks[cacheKey];
    if (existingTask != null) {
      Log.d(() => "_putImageStream $cacheKey: already downloading");
      _connectStream(existingTask.controller, controller, cancelOnError: true);
      return (
        controller: existingTask.controller,
        cancelToken: existingTask.cancelToken,
        isOwner: false,
      );
    }

    Log.d(() => "_putImageStream $cacheKey");
    final cancelToken = CancelToken();
    late final StreamController<DownloadProgress> downloadController;
    downloadController = StreamController<DownloadProgress>.broadcast(
      onCancel: () {
        if (!downloadController.isClosed && !cancelToken.isCancelled) {
          cancelToken.cancel("No image download listeners");
        }
      },
    );
    final task = _ImageDownloadTask(downloadController, cancelToken);
    _downloadTasks[cacheKey] = task;
    downloadController.done.whenComplete(() {
      if (identical(_downloadTasks[cacheKey], task)) {
        _downloadTasks.remove(cacheKey);
      }
    });
    _connectStream(downloadController, controller, cancelOnError: true);
    return (
      controller: downloadController,
      cancelToken: cancelToken,
      isOwner: true,
    );
  }

  /// 连接两个StreamController，传输所有事件（数据、错误、完成）
  static StreamSubscription<T> _connectStream<T>(
    StreamController<T> source,
    StreamController<T> target, {
    bool cancelOnError = false,
  }) {
    final subscription = source.stream.listen(
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
    target.onCancel = subscription.cancel;
    return subscription;
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
    if (cache != null &&
        (await cache.file.exists()) &&
        (await cache.file.length()) > 0) {
      Log.d(() => "checkFileCache $cacheKey: already cached");
      controller.add(
        DownloadProgress(1, 1, url, cache.filePath, null, cache.type),
      );
      return true;
    } else {
      if (cache != null) await CacheManager().delete(cacheKey);
      return false;
    }
  }

  /// 获取图片, 适用于没有任何限制的图片链接
  Stream<DownloadProgress> getImage(
    final String url, [
    Map<String, String>? headers,
  ]) {
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
    final task = _getOrCreateController(cacheKey, controller);
    if (!task.isOwner) return;
    final downloadController = task.controller;

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
      var dioRes = await dio.get<ResponseBody>(
        realUrl,
        options: Options(
          responseType: ResponseType.stream,
          headers: headers,
          extra: {
            NetworkCookieInterceptor.cookieJarKey:
                SingleInstanceCookieJar.instance!,
          },
        ),
        cancelToken: task.cancelToken,
      );
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
        var progress = DownloadProgress(
          imageData.length,
          (expectedBytes ?? imageData.length + 1),
          url,
          savePath,
        );
        downloadController.add(progress);
      }
      var ext = getExt(dioRes);
      cachingFile.fileType = ext;
      await cachingFile.close();
      downloadController.add(
        DownloadProgress(
          imageData.length,
          imageData.length,
          url,
          savePath,
          Uint8List.fromList(imageData),
          ext,
          cachingFile,
        ),
      );
    } catch (e, s) {
      caching?.cancel();
      Log.e("Network $e\n$s");
      if (e is DioException && e.type == DioExceptionType.badResponse) {
        var statusCode = e.response?.statusCode;
        if (statusCode != null && statusCode >= 400 && statusCode < 500) {
          downloadController.addError(
            BadRequestException(e.message.toString()),
          );
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
    final Gallery gallery,
    final int page,
  ) {
    final controller = StreamController<DownloadProgress>();
    _putEhImageStream(controller: controller, gallery: gallery, page: page);
    return controller.stream;
  }

  /// 下载 EH 图片，临时链接失效时自动刷新链接与认证。
  Future<void> _putEhImageStream({
    required StreamController<DownloadProgress> controller,
    required Gallery gallery,
    required int page,
  }) async {
    final cacheKey = "${gallery.link}$page";
    final gid = getGalleryId(gallery.link);
    if (await _checkFileCache(controller: controller, url: cacheKey)) {
      await controller.close();
      return;
    }

    final task = _getOrCreateController(cacheKey, controller);
    if (!task.isOwner) return;
    final output = task.controller;
    CachingFile? caching;
    try {
      caching = await CacheManager().openWrite(cacheKey);
      final savePath = caching.file.path;
      output.add(DownloadProgress(0, 100, cacheKey, savePath));
      final readerRes = await EhNetwork().getReaderLink(
        gallery.link,
        page,
        cancelToken: task.cancelToken,
      );
      if (readerRes.error) {
        throw readerRes.errorMessage ?? "Failed to get reader link";
      }
      final readerLink = readerRes.data;
      await _ensureEhAuthentication(gallery, readerLink, gid, task.cancelToken);

      var link = await _resolveEhImageLink(
        gallery,
        readerLink,
        gid,
        page,
        task.cancelToken,
      );
      ({Uint8List data, String ext})? image;
      Object? lastError;
      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          image = await _downloadEhImage(
            dio,
            link.imageUrl,
            cacheKey,
            savePath,
            caching,
            output,
            task.cancelToken,
          );
          break;
        } catch (e) {
          lastError = e;
          if (task.cancelToken.isCancelled || e is ImageExceedError) rethrow;
          if (attempt == 2) break;
          await Future.delayed(Duration(milliseconds: 400 * (attempt + 1)));
          link = await _renewEhImageLink(
            gallery,
            readerLink,
            gid,
            page,
            link,
            task.cancelToken,
            attempt > 0,
          );
        }
      }
      if (image == null) {
        throw Exception("Failed to load EH image after 3 attempts: $lastError");
      }

      caching.fileType = image.ext;
      await caching.close();
      output.add(
        DownloadProgress(
          image.data.length,
          image.data.length,
          cacheKey,
          savePath,
          image.data,
          image.ext,
          caching,
        ),
      );
    } catch (e, stackTrace) {
      await caching?.cancel();
      Log.e("EH image download failed: $e\n$stackTrace");
      if (!output.isClosed) output.addError(e, stackTrace);
    } finally {
      if (!output.isClosed) await output.close();
    }
  }

  /// 确保同一画廊只有一个认证请求在执行。
  Future<void> _ensureEhAuthentication(
    Gallery gallery,
    String readerLink,
    String gid,
    CancelToken callerToken, {
    bool force = false,
  }) async {
    _throwIfCancelled(callerToken);
    gallery.auth ??= {};
    bool valid() =>
        gallery.auth!["showKey"]?.isNotEmpty == true ||
        gallery.auth!["mpvKey"]?.isNotEmpty == true;
    if (!force && valid()) return;

    final running = _ehAuthenticationTasks[gid];
    if (running != null) {
      await running.future;
      _throwIfCancelled(callerToken);
      if (valid()) return;
    }
    if (force) _clearEhAuthentication(gallery);

    final token = CancelToken();
    final future = _loadEhAuthentication(gallery, readerLink, gid, token);
    final task = _EhAuthenticationTask(future, token);
    _ehAuthenticationTasks[gid] = task;
    try {
      await future;
      _throwIfCancelled(callerToken);
    } finally {
      if (identical(_ehAuthenticationTasks[gid], task)) {
        _ehAuthenticationTasks.remove(gid);
      }
    }
  }

  Future<void> _loadEhAuthentication(
    Gallery gallery,
    String readerLink,
    String gid,
    CancelToken cancelToken,
  ) async {
    try {
      final res = await EhNetwork().request(
        readerLink,
        expiredTime: CacheExpiredTime.no,
        cancelToken: cancelToken,
      );
      if (res.error) throw res.errorMessage ?? "Failed to load reader page";
      final document = parse(res.data);
      final showScript = document
          .querySelectorAll("script")
          .firstWhereOrNull((e) => e.text.contains("showkey"));
      final showKey = showScript == null
          ? null
          : RegExp(r'showkey="(.*?)"').firstMatch(showScript.text)?.group(1);
      if (showKey?.isNotEmpty == true) {
        gallery.auth!["showKey"] = showKey!;
        gallery.auth!.remove("mpvKey");
        gallery.auth!.remove("imgKey");
        return;
      }

      final script = document
          .querySelectorAll("script")
          .firstWhereOrNull((e) => e.text.contains("mpvkey"))
          ?.text;
      if (script == null) throw Exception("Failed to get EH authentication");
      final mpvKey = RegExp(
        r'mpvkey\s*=\s*"([^"]+)"',
      ).firstMatch(script)?.group(1);
      final listText = RegExp(
        r'imagelist\s*=\s*(\[.*?\])\s*;',
        dotAll: true,
      ).firstMatch(script)?.group(1);
      if (mpvKey == null || listText == null) {
        throw Exception("Invalid EH MPV authentication");
      }
      final list = jsonDecode(listText) as List<dynamic>;
      gallery.auth!["mpvKey"] = mpvKey;
      gallery.auth!["imgKey"] = list.map((e) => e["k"]).join(",");
      gallery.auth!.remove("showKey");
      Log.d(() => "ImageManager: EH authentication loaded gid=$gid");
    } catch (_) {
      _clearEhAuthentication(gallery);
      rethrow;
    }
  }

  void _clearEhAuthentication(Gallery gallery) {
    gallery.auth ??= {};
    gallery.auth!.remove("showKey");
    gallery.auth!.remove("mpvKey");
    gallery.auth!.remove("imgKey");
  }

  void _throwIfCancelled(CancelToken cancelToken) {
    final error = cancelToken.cancelError;
    if (error != null) throw error;
  }

  Future<({String imageUrl, String? nl, bool mpv})> _resolveEhImageLink(
    Gallery gallery,
    String readerLink,
    String gid,
    int page,
    CancelToken cancelToken, {
    String? nl,
  }) async {
    final keys = gallery.auth?["imgKey"]?.split(",");
    final isMpv =
        gallery.auth?["mpvKey"] != null &&
        keys != null &&
        page > 0 &&
        page <= keys.length;
    if (isMpv) {
      final res = await EhNetwork().apiRequest({
        "gid": int.parse(gid),
        "imgkey": keys[page - 1],
        "method": "imagedispatch",
        "page": page,
        "mpvkey": gallery.auth!["mpvKey"],
        if (nl != null) "nl": nl,
      }, cancelToken: cancelToken);
      if (res.error) throw res.errorMessage ?? "EH imagedispatch failed";
      final json = jsonDecode(res.data) as Map<String, dynamic>;
      final url = json["i"]?.toString() ?? "";
      if (!url.isURL) throw Exception("Invalid EH image URL");
      final nextNl = json["s"]?.toString();
      return (
        imageUrl: url,
        nl: nextNl?.isEmpty == true ? null : nextNl,
        mpv: true,
      );
    }

    try {
      final res = await EhNetwork().apiRequest({
        "gid": int.parse(gid),
        "imgkey": _ehImageKey(readerLink),
        "method": "showpage",
        "page": page,
        "showkey": gallery.auth!["showKey"],
      }, cancelToken: cancelToken);
      if (res.error) throw res.errorMessage ?? "EH showpage failed";
      final json = jsonDecode(res.data) as Map<String, dynamic>;
      final i3 = json["i3"]?.toString() ?? "";
      final i6 = json["i6"]?.toString() ?? "";
      var url = RegExp(r'src="([^"]+)"').firstMatch(i3)?.group(1) ?? "";
      final origins = RegExp(r'<a href="([^"]+)"').allMatches(i6).toList();
      final original = origins.isEmpty ? "" : origins.last.group(1) ?? "";
      if (appdata.settings[29] == "1" && original.isURL) url = original;
      if (!url.isURL) throw Exception("Invalid EH showpage image URL");
      return (
        imageUrl: url,
        nl: RegExp(r"nl\('(.+?)'\)").firstMatch(i6)?.group(1),
        mpv: false,
      );
    } catch (e) {
      Log.w("EH showpage API failed, fallback to HTML: $e");
      final res = await EhNetwork().request(
        readerLink,
        expiredTime: CacheExpiredTime.no,
        cancelToken: cancelToken,
      );
      if (res.error) throw res.errorMessage ?? "Failed to reload reader page";
      final document = parse(res.data);
      var url =
          document.querySelector("div#i3 > a > img")?.attributes["src"] ?? "";
      final original =
          document
              .querySelectorAll("div#i6 a")
              .firstWhereOrNull((e) => e.text.contains("original"))
              ?.attributes["href"] ??
          "";
      if (appdata.settings[29] == "1" && original.isURL) url = original;
      if (!url.isURL) throw Exception("Invalid EH reader image URL");
      final nextNl = document
          .querySelector("a#loadfail")
          ?.attributes["onclick"]
          ?.split("'")
          .firstWhereOrNull((e) => e.contains("-"));
      return (imageUrl: url, nl: nextNl, mpv: false);
    }
  }

  Future<({String imageUrl, String? nl, bool mpv})> _renewEhImageLink(
    Gallery gallery,
    String readerLink,
    String gid,
    int page,
    ({String imageUrl, String? nl, bool mpv}) current,
    CancelToken cancelToken,
    bool forceAuthentication,
  ) async {
    if (!forceAuthentication && current.nl != null) {
      try {
        if (current.mpv) {
          return _resolveEhImageLink(
            gallery,
            readerLink,
            gid,
            page,
            cancelToken,
            nl: current.nl,
          );
        }
        final value = await EhNetwork().getImageLinkWithNL(
          gid,
          _ehImageKey(readerLink),
          page,
          current.nl!,
          cancelToken: cancelToken,
        );
        if (value.$1.isURL) {
          return (imageUrl: value.$1, nl: value.$2, mpv: false);
        }
      } catch (e) {
        if (cancelToken.isCancelled) rethrow;
        Log.w("EH nl refresh failed: $e");
      }
    }
    await _ensureEhAuthentication(
      gallery,
      readerLink,
      gid,
      cancelToken,
      force: true,
    );
    return _resolveEhImageLink(gallery, readerLink, gid, page, cancelToken);
  }

  String _ehImageKey(String readerLink) {
    final segments = Uri.parse(readerLink).pathSegments;
    if (segments.length < 2) {
      throw const FormatException("Invalid EH reader link");
    }
    return segments[1];
  }

  Future<({Uint8List data, String ext})> _downloadEhImage(
    Dio dio,
    String imageUrl,
    String cacheKey,
    String savePath,
    CachingFile caching,
    StreamController<DownloadProgress> output,
    CancelToken cancelToken,
  ) async {
    if (!imageUrl.isURL) throw const FormatException("Invalid EH image URL");
    if (imageUrl.contains("509.gif")) throw ImageExceedError();
    caching.reset();

    final res = await dio.get<ResponseBody>(
      imageUrl,
      options: Options(
        responseType: ResponseType.stream,
        headers: {"user-agent": webUA, "cookie": EhNetwork().cookiesStr},
        extra: {
          NetworkCookieInterceptor.cookieJarKey:
              SingleInstanceCookieJar.instance!,
        },
      ),
      cancelToken: cancelToken,
    );
    final body = res.data;
    if (body == null) throw const FormatException("Empty EH image response");
    final contentType = _bodyHeader(body, "content-type")?.toLowerCase();
    if (contentType != null && !contentType.startsWith("image/")) {
      throw FormatException("Unexpected image content type: $contentType");
    }

    final expected = body.contentLength < 0 ? null : body.contentLength;
    final bytes = <int>[];
    await for (final chunk in body.stream) {
      bytes.addAll(chunk);
      await caching.writeBytes(chunk);
      output.add(
        DownloadProgress(
          bytes.length,
          (expected ?? bytes.length) + 1,
          cacheKey,
          savePath,
        ),
      );
    }
    if (bytes.isEmpty) throw const FormatException("Empty EH image data");
    if (expected != null && expected != bytes.length) {
      throw FormatException("Incomplete EH image: $expected/${bytes.length}");
    }
    final data = Uint8List.fromList(bytes);
    final type = detectFileType(data);
    if (!type.mime.startsWith("image/") || type.ext == ".") {
      throw const FormatException("EH response is not an image");
    }
    return (data: data, ext: type.ext.substring(1));
  }

  String? _bodyHeader(ResponseBody body, String name) {
    for (final entry in body.headers.entries) {
      if (entry.key.toLowerCase() == name && entry.value.isNotEmpty) {
        return entry.value.first;
      }
    }
    return null;
  }

  ///为Hitomi设计的图片加载函数
  ///
  /// 使用hash标识图片
  Stream<DownloadProgress> getHitomiImage(HitomiFile image, String galleryId) {
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
    if (await _checkFileCache(controller: controller, url: '', key: cacheKey)) {
      return;
    }

    final task = _getOrCreateController(cacheKey, controller);
    if (!task.isOwner) return;
    final downloadController = task.controller;

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
      var res = await dio.get<ResponseBody>(
        url,
        options: Options(
          responseType: ResponseType.stream,
          headers: {
            "User-Agent": webUA,
            "Referer": "https://hitomi.la/reader/$galleryId.html",
          },
        ),
        cancelToken: task.cancelToken,
      );
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
          currentBytes,
          (expectedBytes ?? currentBytes + 1),
          url,
          savePath,
        );
        downloadController.add(progress);
      }
      var ext = getExt(res);
      cachingFile.fileType = ext;
      await cachingFile.close();
      downloadController.add(
        DownloadProgress(
          currentBytes,
          currentBytes,
          url,
          savePath,
          Uint8List.fromList(data),
          ext,
          cachingFile,
        ),
      );
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

  /// 获取禁漫图片, 如果缓存中没有, 则尝试下载
  ///
  /// - [url] 图片 URL
  /// - [headers] 请求头
  /// - [epsId] 章节 ID，用于图片反混淆算法
  /// - [scrambleId] 混淆 ID，用于确定是否需要反混淆，通常使用 [kJmScrambleId]
  /// - [bookId] 漫画 ID，用于图片反混淆算法
  Stream<DownloadProgress> getJmImage(
    String url,
    Map<String, String>? headers, {
    required String epsId,
    required String scrambleId,
    required String bookId,
  }) {
    final controller = StreamController<DownloadProgress>();
    _putJmImageStream(
      controller,
      url,
      headers,
      epsId: epsId,
      scrambleId: scrambleId,
      bookId: bookId,
    );
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
    final task = _getOrCreateController(cacheKey, controller);
    if (!task.isOwner) return;
    final downloadController = task.controller;

    CachingFile? caching;

    try {
      final cachingFile = await CacheManager().openWrite(cacheKey);
      caching = cachingFile;
      final savePath = cachingFile.file.path;
      downloadController.add(DownloadProgress(0, 1, url, savePath));

      var bytes = <int>[];
      String? ext;
      try {
        var res = await dio.get<ResponseBody>(
          url,
          options: Options(
            responseType: ResponseType.stream,
            headers: getImgHeaders(),
            extra: {
              NetworkCookieInterceptor.cookieJarKey:
                  SingleInstanceCookieJar.instance!,
            },
          ),
          cancelToken: task.cancelToken,
        );
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
          Uint8List.fromList(bytes),
          epsId,
          scrambleId,
          bookId,
          savePath,
        );
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
    String url,
    String comicId,
    String epId,
    String sourceKey,
  ) {
    final controller = StreamController<DownloadProgress>();
    _putCustomImageStream(
      controller: controller,
      url: url,
      comicId: comicId,
      epId: epId,
      sourceKey: sourceKey,
    );
    return controller.stream;
  }

  Future<void> _putCustomImageStream({
    required StreamController<DownloadProgress> controller,
    required String url,
    required String comicId,
    required String epId,
    required String sourceKey,
  }) async {
    var cacheKey = "$sourceKey$comicId$epId$url";
    Log.d("getCustomImage $url");

    if (await _checkFileCache(
      controller: controller,
      url: url,
      key: cacheKey,
    )) {
      controller.close();
      return;
    }

    final task = _getOrCreateController(cacheKey, controller);
    if (!task.isOwner) return;
    final downloadController = task.controller;

    CachingFile? caching;

    var source =
        ComicSource.find(sourceKey) ??
        (throw "Unknown Comic Source $sourceKey");

    try {
      ImageConfig? config;

      if (source.getImageLoadingConfig == null) {
        config = null;
      } else {
        config = source.getImageLoadingConfig!(url, comicId, epId);
      }

      caching = await CacheManager().openWrite(cacheKey);
      final savePath = caching.file.path;

      var res = await dio.request<ResponseBody>(
        config?.url ?? url,
        data: config?.data,
        cancelToken: task.cancelToken,
        options: Options(
          method: config?.method ?? 'GET',
          headers: config?.headers ?? {'user-agent': webUA},
          responseType: ResponseType.stream,
          extra: {
            NetworkCookieInterceptor.cookieJarKey:
                SingleInstanceCookieJar.instance!,
          },
        ),
      );

      List<int> imageData = [];

      int? expectedBytes = res.data!.contentLength;
      if (expectedBytes == -1) {
        expectedBytes = null;
      }

      bool shouldModifyData = config?.onResponse != null;

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
        var data = (config!.onResponse as JSInvokable)(
          Uint8List.fromList(imageData),
        );
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

  Stream<DownloadProgress> getCustomThumbnail(
    String url,
    String sourceKey, [
    Map<String, String>? headers,
  ]) {
    final controller = StreamController<DownloadProgress>();
    _putCustomThumbnailStream(
      controller: controller,
      url: url,
      sourceKey: sourceKey,
      headers: headers,
    );
    return controller.stream;
  }

  Future<void> _putCustomThumbnailStream({
    required StreamController<DownloadProgress> controller,
    required String url,
    required String sourceKey,
    Map<String, String>? headers,
  }) async {
    var cacheKey = "$sourceKey$url";
    if (await _checkFileCache(
      controller: controller,
      url: url,
      key: cacheKey,
    )) {
      controller.close();
      return;
    }
    final task = _getOrCreateController(cacheKey, controller);
    if (!task.isOwner) return;
    final downloadController = task.controller;

    CachingFile? caching;

    var source =
        ComicSource.find(sourceKey) ??
        (throw "Unknown Comic Source $sourceKey");

    try {
      ImageConfig? config;

      if (source.getThumbnailLoadingConfig == null) {
        config = null;
      } else {
        config = source.getThumbnailLoadingConfig!(url);
      }

      caching = await CacheManager().openWrite(cacheKey);
      final savePath = caching.file.path;

      var res = await dio.request<ResponseBody>(
        config?.url ?? url,
        data: config?.data,
        cancelToken: task.cancelToken,
        options: Options(
          method: config?.method ?? 'GET',
          headers: config?.headers ?? headers ?? {'user-agent': webUA},
          responseType: ResponseType.stream,
          extra: {
            NetworkCookieInterceptor.cookieJarKey:
                SingleInstanceCookieJar.instance!,
          },
        ),
      );

      List<int> imageData = [];

      int? expectedBytes = res.data!.contentLength;
      if (expectedBytes == -1) {
        expectedBytes = null;
      }

      bool shouldModifyData = config?.onResponse != null;

      await for (var data in res.data!.stream) {
        if (!shouldModifyData) {
          await caching.writeBytes(data);
        }
        imageData.addAll(data);
        var progress = DownloadProgress(
          imageData.length,
          expectedBytes ?? (imageData.length + 1),
          url,
          savePath,
        );
        downloadController.add(progress);
      }

      Uint8List? result;

      if (shouldModifyData) {
        var data = (config!.onResponse as JSInvokable)(
          Uint8List.fromList(imageData),
        );
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
        1,
        1,
        url,
        savePath,
        result ?? Uint8List.fromList(imageData),
      );
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
        _ => null,
      };
    }
    ext ??= url.split('.').last;
    if (!["jpg", "jpeg", "png", "gif", "webp"].contains(ext)) {
      ext = "jpg";
      Log.w(
        "ImageManager Unknown image extension: \n"
        "Content-Type: $contentType\n"
        "URL: $url",
      );
    }
    return ext;
  }
}

class _ImageDownloadTask {
  const _ImageDownloadTask(this.controller, this.cancelToken);
  final StreamController<DownloadProgress> controller;
  final CancelToken cancelToken;
}

class _EhAuthenticationTask {
  const _EhAuthenticationTask(this.future, this.cancelToken);
  final Future<void> future;
  final CancelToken cancelToken;
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
    this._currentBytes,
    this._expectedBytes,
    this.url,
    this.savePath, [
    this.data,
    this.ext,
    this.cachingFile,
  ]);

  File getFile() => File(savePath);
}

class ImageExceedError extends Error {
  @override
  String toString() => "Maximum image loading limit reached.";
}
