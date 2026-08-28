import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:pica_comic/base.dart';
import 'package:pica_comic/comic_source/comic_source.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/foundation/cache_manager.dart';
import 'package:pica_comic/foundation/history.dart';
import 'package:pica_comic/foundation/local_favorites.dart';
import 'package:pica_comic/foundation/log.dart';
import 'package:pica_comic/network/cookie_jar.dart';
import 'package:pica_comic/network/download/download_model.dart';
import 'package:pica_comic/tools/io_extensions.dart';
import 'package:zip_flutter/zip_flutter.dart';

import '../foundation/app.dart';

Future<double> getFolderSize(Directory path) async {
  double total = 0;
  try {
    // 使用异步操作避免阻塞主线程
    await for (var entity in path.list(recursive: true)) {
      if (entity is File) {
        try {
          // 使用异步的 length() 而不是同步的 lengthSync()
          final length = await entity.length();
          total += length / 1024 / 1024;
        } catch (e) {
          // 忽略无法访问的文件（可能被删除或权限问题）
          Log.d(() => 'getFolderSize: 无法读取文件大小 ${entity.path}: $e');
        }
      }
    }
  } catch (e, s) {
    Log.e('getFolderSize: 计算文件夹大小失败 ${path.path}: $e\n$s');
  }
  return total;
}

Future<bool> exportComic(
  String id,
  String name, [
  List<String>? epNames,
]) async {
  try {
    name = sanitizeFileName(name);
    final comicPath = await downloadManager.getFullDirectory(id);
    final coverFile = await downloadManager.getCover(id);
    var data = ExportComicData(
      id,
      downloadManager.path!,
      comicPath,
      name,
      epNames,
      await coverFile.exists() ? coverFile.path : null,
    );
    var res = await compute(runningExportComic, data);
    if (!res) {
      return false;
    }

    if (App.isMobile) {
      var params = SaveFileDialogParams(
        sourceFilePath: p.join(data.outputPath, '$name.zip'),
      );
      await FlutterFileDialog.saveFile(params: params);
    } else {
      final FileSaveLocation? result = await getSaveLocation(
        suggestedName: '$name.zip',
      );

      if (result != null) {
        const String mimeType = 'application/zip';
        final XFile textFile = XFile(
          p.join(data.outputPath, '$name.zip'),
          mimeType: mimeType,
        );
        await textFile.saveTo(result.path);
      }
    }

    var file = File(p.join(data.outputPath, '$name.zip'));
    file.delete();
    return true;
  } catch (e) {
    return false;
  }
}

Future<bool> exportComics(List<DownloadedItem> comics) async {
  try {
    var exportDatas = <ExportComicData>[];
    for (var comic in comics) {
      var id = comic.id;
      var name = sanitizeFileName(comic.name);
      var outputPath = downloadManager.path;
      var epNames = comic.eps;
      exportDatas.add(
        ExportComicData(
          id,
          outputPath!,
          comic.directoryPath,
          name,
          epNames,
          comic.coverPath,
        ),
      );
    }
    await Isolate.run(() => runningExportComics(exportDatas));
    if (App.isMobile) {
      var params = SaveFileDialogParams(
        sourceFilePath: '${downloadManager.path}/comics.zip',
      );
      await FlutterFileDialog.saveFile(params: params);
    } else {
      final FileSaveLocation? result = await getSaveLocation(
        suggestedName: 'comics.zip',
      );

      if (result != null) {
        const String mimeType = 'application/zip';
        final XFile textFile = XFile(
          '${downloadManager.path}/comics.zip',
          mimeType: mimeType,
        );
        await textFile.saveTo(result.path);
      }
    }
    var file = File('${downloadManager.path}/comics.zip');
    if (file.existsSync()) {
      file.delete();
    }
    return true;
  } catch (e) {
    return false;
  }
}

Future<bool> exportPdf(String pdfPath) async {
  try {
    if (App.isMobile) {
      var params = SaveFileDialogParams(sourceFilePath: pdfPath);
      await FlutterFileDialog.saveFile(params: params);
    } else {
      final FileSaveLocation? result = await getSaveLocation(
        suggestedName: File(pdfPath).name,
        acceptedTypeGroups: [
          const XTypeGroup(label: 'pdf', extensions: ['pdf']),
        ],
      );

      if (result != null) {
        const String mimeType = 'application/pdf';
        final XFile textFile = XFile(pdfPath, mimeType: mimeType);
        await textFile.saveTo(result.path);
      }
    }
    if (File(pdfPath).existsSync()) {
      File(pdfPath).delete();
    }
    return true;
  } catch (e) {
    return false;
  }
}

class ExportComicData {
  final String id;
  final String outputPath;
  final String comicPath;
  final String name;
  final List<String>? epNames;
  final String? coverPath;

  ExportComicData(
    this.id,
    this.outputPath,
    this.comicPath,
    this.name,
    this.epNames,
    this.coverPath,
  );
}

Future<bool> runningExportComic(ExportComicData data) async {
  final fileName = p.join(data.outputPath, '${data.name}.zip');
  try {
    final comicDirectory = Directory(data.comicPath);
    var zipFile = ZipFile.open(fileName);
    String? currentDirName;

    void walk(String directoryPath) {
      for (var entry in Directory(directoryPath).listSync()) {
        if (entry is Directory) {
          var index = int.parse(entry.name) - 1;
          currentDirName = sanitizeFileName(
            data.epNames?.elementAtOrNull(index) ?? "Chapter ${index + 1}",
          );
          walk(entry.path);
        } else {
          if (entry is File && _isExportedCoverFile(entry.name)) continue;
          var filePathInZip = sanitizeFileName(data.name);
          if (currentDirName != null) {
            filePathInZip += "/$currentDirName";
          }
          filePathInZip += "/${entry.name}";
          zipFile.addFile(filePathInZip, entry.path);
        }
      }
    }

    walk(comicDirectory.path);
    _addExportedCover(zipFile, data);
    zipFile.close();
    return true;
  } catch (e, s) {
    Log.e("IO $e\n$s");
    return false;
  }
}

Future<bool> runningExportComics(List<ExportComicData> datas) async {
  try {
    var result = p.join(datas.first.outputPath, 'comics.zip');
    if (File(result).existsSync()) {
      File(result).deleteSync();
    }
    var zipFile = ZipFile.open(result);
    for (var data in datas) {
      final directory = Directory(data.comicPath);

      String? currentDirName;

      void walk(String directoryPath) {
        for (var entry in Directory(directoryPath).listSync()) {
          if (entry is Directory) {
            var index = int.parse(entry.name) - 1;
            currentDirName = sanitizeFileName(
              data.epNames?.elementAtOrNull(index) ?? "Chapter ${index + 1}",
            );
            walk(entry.path);
          } else {
            if (entry is File && _isExportedCoverFile(entry.name)) continue;
            var filePathInZip = sanitizeFileName(data.name);
            if (currentDirName != null) {
              filePathInZip += "/$currentDirName";
            }
            filePathInZip += "/${entry.name}";
            zipFile.addFile(filePathInZip, entry.path);
          }
        }
      }

      walk(directory.path);
      _addExportedCover(zipFile, data);
    }
    zipFile.close();
    return true;
  } catch (e, s) {
    Log.e("IO $e\n$s");
    return false;
  }
}

bool _isExportedCoverFile(String fileName) {
  final lowerName = fileName.toLowerCase();
  return lowerName == 'cover.jpg' ||
      lowerName == 'cover.jpeg' ||
      lowerName == 'cover.png' ||
      lowerName == 'cover.webp';
}

void _addExportedCover(ZipFile zipFile, ExportComicData data) {
  final coverPath = data.coverPath;
  if (coverPath == null) return;

  final coverFile = File(coverPath);
  if (!coverFile.existsSync()) return;

  final archivePath = '${sanitizeFileName(data.name)}/cover.webp';
  zipFile.addFile(archivePath, coverFile.path);
}

Future<void> eraseCache() async {
  return CacheManager().clear();
}

Future<void> copyDirectory(Directory source, Directory destination) async {
  try {
    List<FileSystemEntity> contents = source.listSync();
    for (FileSystemEntity content in contents) {
      String newPath =
          destination.path +
          Platform.pathSeparator +
          content.path.split(Platform.pathSeparator).last;

      if (content is File) {
        content.copySync(newPath);
      } else if (content is Directory) {
        Directory newDirectory = Directory(newPath);
        newDirectory.createSync();
        copyDirectory(content.absolute, newDirectory.absolute);
      }
    }
  } catch (e, s) {
    Log.e("IO $e\n$s");
    rethrow;
  }
}

/// move all files and directories from source to destination
Future<void> moveDirectory(Directory source, Directory destination) async {
  try {
    source = source.absolute;
    destination = destination.absolute;
    List<FileSystemEntity> contents = source.listSync();
    for (FileSystemEntity content in contents) {
      if (content is File) {
        await content.rename(
          destination.path + Platform.pathSeparator + content.name,
        );
      } else if (content is Directory) {
        Directory newDirectory = Directory(
          destination.path + Platform.pathSeparator + content.name,
        );
        newDirectory.createSync(recursive: true);
        await moveDirectory(content, newDirectory);
      }
    }
    await source.deleteIgnoreError(recursive: true);
  } catch (e, s) {
    Log.e("IO $e\n$s");
    rethrow;
  }
}

///检查下载目录是否可用, 不可用则重置
Future<void> checkDownloadPath() async {
  var path = appdata.settings[22];
  if (path != "") {
    var directory = Directory(path);
    if (!directory.existsSync()) {
      appdata.settings[22] = "";
      appdata.updateSettings();
    }
  }
}

Future<String?> _exportData(
  String path,
  String appdataString,
  String? downloadPath,
  String outPath,
) async {
  var encode = ZipFile.open(outPath);
  try {
    var filePath = "$path${pathSep}appdata";
    var file = File(filePath);
    if (file.existsSync()) {
      file.deleteSync();
    }
    file.createSync();
    file.writeAsStringSync(appdataString);
    encode.addFile(file.uri.pathSegments.last, file.path);
    var localFavorite = File("$path${pathSep}local_favorite.db");
    var history = File("$path${pathSep}history.db");
    if (!localFavorite.existsSync()) {
      localFavorite.createSync();
    }
    if (!history.existsSync()) {
      history.createSync();
    }
    encode.addFile(
      localFavorite.name,
      localFavorite.path.replaceAll("\\", "/"),
    );
    encode.addFile(history.name, history.path);
    encode.addFile('cookies.db', "$path/cookies.db");
    await for (var entry in Directory("$path/comic_source").list()) {
      if (entry is File) {
        encode.addFile('comic_source/${entry.name}', entry.path);
      }
    }
    if (downloadPath != null) {
      downloadPath = downloadPath.replaceAll('\\', '/');
      var sourceFolder = downloadPath.substring(
        0,
        downloadPath.lastIndexOf('/'),
      );
      void walk(String path) {
        for (var entry in Directory(path).listSync()) {
          if (entry is Directory) {
            walk(entry.path);
          } else {
            var filePathInZip = entry.path.replaceFirst(sourceFolder, "");
            if (filePathInZip.startsWith('/') ||
                filePathInZip.startsWith('\\')) {
              filePathInZip = filePathInZip.substring(1);
            }
            encode.addFile(filePathInZip, entry.path);
          }
        }
      }

      walk(downloadPath);
    }
    return null;
  } catch (e) {
    return e.toString();
  } finally {
    encode.close();
  }
}

Future<String> exportDataToFile(bool includeDownload, String outPath) async {
  var path = App.dataPath;
  try {
    var appdataString = const JsonEncoder().convert(appdata.toJson());
    var downloadPath = includeDownload ? downloadManager.path : null;
    var res = await compute<List<String?>, String?>(
      (message) =>
          _exportData(message[0]!, message[1]!, message[2], message[3]!),
      [path, appdataString, downloadPath, outPath],
    );

    if (res != null) {
      throw Exception(res);
    }
  } catch (e, s) {
    Log.e("IO $e\n$s");
    rethrow;
  }
  return outPath;
}

Future<bool> runExportData(bool includeDownload) async {
  try {
    var outPath = '${App.cachePath}/userdata.picadata';
    if (App.isDesktop) {
      final FileSaveLocation? result = await getSaveLocation(
        suggestedName: 'userData.picadata',
      );
      if (result == null) {
        return true;
      }
      outPath = result.path;
    }
    if (await File(outPath).exists()) {
      await File(outPath).delete();
    }
    await exportDataToFile(includeDownload, outPath);

    var dialog = showLoadingDialog(
      App.globalContext!,
      barrierDismissible: false,
      allowCancel: false,
    );

    if (App.isMobile) {
      var params = SaveFileDialogParams(sourceFilePath: outPath);
      await FlutterFileDialog.saveFile(params: params);
      File(outPath).delete();
    }

    dialog.close();
  } catch (e, s) {
    Log.e("IO $e\n$s");
    return false;
  }
  return true;
}

/// import data, filePath is used for webdav
Future<bool> importData([String? filePath]) async {
  final enableCheck = filePath != null;
  var path = (await getApplicationSupportDirectory()).path;
  if (filePath == null) {
    if (App.isMobile) {
      var params = const OpenFileDialogParams();
      filePath = await FlutterFileDialog.pickFile(params: params);
    } else {
      const XTypeGroup typeGroup = XTypeGroup(label: 'data');
      final XFile? file = await openFile(
        acceptedTypeGroups: <XTypeGroup>[typeGroup],
      );
      filePath = file?.path;
    }
    if (filePath == null) {
      Log.e("importData filePath is null");
      return false;
    }
  }
  SingleInstanceCookieJar.instance?.dispose();
  downloadManager.dispose();
  String data = '';
  try {
    data = await compute<List<String>, String>(
      (data) async {
        var path = data[0];
        ZipFile.openAndExtract(data[1], "$path/dataTemp");
        var downloadPath = Directory(data[2]);
        List<FileSystemEntity> contents = Directory(
          "$path/dataTemp",
        ).listSync();
        for (FileSystemEntity item in contents) {
          if (item is Directory) {
            if (item.name != "comic_source" && item.name != "download") {
              item.renameSync('$path/dataTemp/download');
            }
          }
        }
        final json = File("$path/dataTemp/appdata").readAsStringSync();
        int fileVersion = int.parse(
          ((const JsonDecoder().convert(json))["settings"] as List)
                  .elementAtOrNull(46) ??
              "1",
        );
        if (fileVersion <= int.parse(data[3]) && data[4] == "1") {
          return json;
        }
        var localFavorite = File('$path/dataTemp/localFavorite');
        if (localFavorite.existsSync()) {
          localFavorite.copySync('$path/localFavorite');
        } else {
          var localFavorite2 = File('$path/dataTemp/local_favorite.db');
          localFavorite2.copySync('$path/local_favorite_temp.db');
        }
        var history = File('$path/dataTemp/history.db');
        if (history.existsSync()) {
          history.copySync('$path/history_temp.db');
        }
        var comicSource = Directory('$path/dataTemp/comic_source');
        if (comicSource.existsSync()) {
          Directory("$path/comic_source").deleteSync(recursive: true);
          comicSource.renameSync('$path/comic_source');
        }
        var cookies = File('$path/dataTemp/cookies.db');
        if (cookies.existsSync()) {
          cookies.copySync('$path/cookies.db');
        }
        var downloadData = Directory("$path/dataTemp/download");
        if (downloadData.existsSync()) {
          downloadPath.deleteSync(recursive: true);
          downloadPath.createSync();
          await moveDirectory(downloadData, downloadPath);
        }
        return json;
      },
      [
        path,
        filePath,
        downloadManager.path!,
        appdata.settings[46],
        (enableCheck ? "1" : "0"),
      ],
    );
  } catch (e, s) {
    Log.e("importData $e\n$s");
    return false;
  } finally {
    await ComicSource.reload();
    SingleInstanceCookieJar.instance?.init();
    await downloadManager.init();
    Directory("$path/dataTemp").deleteSync(recursive: true);
  }
  var json = const JsonDecoder().convert(data);
  int fileVersion = int.parse(
    (json["settings"] as List).elementAtOrNull(46) ?? "1",
  );
  int appVersion = int.parse(appdata.settings[46]);
  if (fileVersion <= appVersion && enableCheck) {
    Log.i(
      "Appdata The data file version is $fileVersion, while the app data version is "
      "$appVersion\nStop importing data",
    );
  }
  var dataReadRes = appdata.readDataFromJson(json);
  if (!dataReadRes) {
    Log.e("Appdata appdata.readDataFromJson(json) failed");
    return false;
  }
  await LocalFavoritesManager().readData();
  LocalFavoritesManager().updateUI();
  await HistoryManager().tryUpdateDb();
  return true;
}

void saveLog(String log) async {
  var path = (await getTemporaryDirectory()).path;
  var file = File("$path${pathSep}logs.txt");
  file.writeAsStringSync(log);
  if (App.isMobile) {
    var params = SaveFileDialogParams(
      sourceFilePath: "$path${pathSep}logs.txt",
    );
    await FlutterFileDialog.saveFile(params: params);
  } else {
    final String? directoryPath = await getDirectoryPath();
    if (directoryPath != null) {
      await file.copy("$directoryPath${pathSep}logs.txt");
    }
  }
}

Future<void> exportStringDataAsFile(String data, String fileName) async {
  if (App.isMobile) {
    var cachePath = (await getApplicationCacheDirectory()).path;
    var file = File("$cachePath$pathSep$fileName");
    if (!file.existsSync()) {
      file.createSync();
    }
    file.writeAsStringSync(data);
    var params = SaveFileDialogParams(sourceFilePath: file.path);
    await FlutterFileDialog.saveFile(params: params);
  } else {
    final FileSaveLocation? result = await getSaveLocation(
      suggestedName: fileName,
    );
    if (result == null) {
      return;
    }

    final Uint8List fileData = Uint8List.fromList(
      const Utf8Encoder().convert(data),
    );
    const String mimeType = 'text/plain';
    final XFile textFile = XFile.fromData(
      fileData,
      mimeType: mimeType,
      name: fileName,
    );
    await textFile.saveTo(result.path);
  }
}

Future<String?> getDataFromUserSelectedFile(List<String> extensions) async {
  String? filePath;
  if (App.isMobile) {
    var params = const OpenFileDialogParams();
    filePath = await FlutterFileDialog.pickFile(params: params);
  } else {
    XTypeGroup typeGroup = XTypeGroup(label: 'data', extensions: extensions);
    final XFile? file = await openFile(
      acceptedTypeGroups: <XTypeGroup>[typeGroup],
    );
    filePath = file?.path;
  }
  if (filePath == null) {
    return null;
  }
  return File(filePath).readAsStringSync();
}

extension FileExtension on File {
  String get name => uri.pathSegments.last;
}

String bytesLengthToReadableSize(int size) {
  if (size < 1024) {
    return "$size B";
  } else if (size < 1024 * 1024) {
    return "${(size / 1024).toStringAsFixed(2)} KB";
  } else if (size < 1024 * 1024 * 1024) {
    return "${(size / 1024 / 1024).toStringAsFixed(2)} MB";
  } else {
    return "${(size / 1024 / 1024 / 1024).toStringAsFixed(2)} GB";
  }
}
