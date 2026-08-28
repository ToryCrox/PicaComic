import 'dart:convert';
import 'dart:io';

import 'package:pica_comic/tools/extensions.dart';

/// 下载目录单个名称的最大 UTF-8 字节数。
///
/// 该限制明显低于常见文件系统的 255 字节上限，为下载根目录、章节目录和
/// 图片文件名预留空间，同时避免资源管理器中出现过长的漫画目录名。
const int maxDownloadDirectoryNameBytes = 120;

extension FileSystemEntityExt on FileSystemEntity {
  String get name {
    var path = this.path;
    if (path.endsWith('/') || path.endsWith('\\')) {
      path = path.substring(0, path.length - 1);
    }

    int i = path.length - 1;

    while (i >= 0 && path[i] != '\\' && path[i] != '/') {
      i--;
    }

    return path.substring(i + 1);
  }

  Future<void> deleteIgnoreError({bool recursive = false}) async {
    try {
      await delete(recursive: recursive);
    } catch (e) {
      // ignore
    }
  }
}

extension FileExtension on File {
  /// Get file size information in MB
  double getMBSizeSync() {
    var bytes = lengthSync();
    return bytes / 1024 / 1024;
  }

  String get extension => path.split('.').last;
}

extension DirectoryExtension on Directory {
  /// 异步获取目录大小信息（单位：MB）
  ///
  /// 递归遍历目录下的所有文件，累加文件大小并转换为 MB
  /// 如果目录不存在，返回 0
  ///
  /// 注意：此方法使用异步操作，不会阻塞主线程
  Future<double> getMBSize() async {
    if (!(await exists())) return 0;
    double total = 0;
    // 异步遍历目录下的所有文件和子目录
    await for (var f in list(recursive: true)) {
      // 只统计文件，忽略目录
      if (await FileSystemEntity.type(f.path) == FileSystemEntityType.file) {
        total += await File(f.path).length() / 1024 / 1024;
      }
    }
    return total;
  }

  /// Get directory size information in MB (Sync)
  ///
  /// if directory is not exist, return 0;
  ///
  /// Warning: This method blocks the main thread. Use getMBSize() instead.
  double getMBSizeSync() {
    if (!existsSync()) return 0;
    double total = 0;
    for (var f in listSync(recursive: true)) {
      if (FileSystemEntity.typeSync(f.path) == FileSystemEntityType.file) {
        total += File(f.path).lengthSync() / 1024 / 1024;
      }
    }
    return total;
  }

  Future<int> get size async {
    if (!existsSync()) return 0;
    int total = 0;
    for (var f in listSync(recursive: true)) {
      if (FileSystemEntity.typeSync(f.path) == FileSystemEntityType.file) {
        total += await File(f.path).length();
      }
    }
    return total;
  }

  Directory renameX(String newName) {
    newName = sanitizeFileName(newName);
    return renameSync(path.replaceLast(name, newName));
  }
}

/// 将外部文本转换为可跨平台使用的文件名。
///
/// [maxLength] 按 UTF-8 字节计算，以兼容使用字节限制名称长度的文件系统。
/// Windows 非法字符、控制字符、保留设备名以及首尾空格和点号都会被处理。
String sanitizeFileName(String fileName, [int maxLength = 255]) {
  if (maxLength < 1) {
    throw ArgumentError.value(maxLength, 'maxLength', '必须大于 0');
  }

  // 替换 Windows 非法字符和 U+0000-U+001F 控制字符为空格。
  final invalidChars = RegExp(r'[<>:"/\\|?*\x00-\x1F]');
  var sanitizedFileName = fileName.replaceAll(invalidChars, ' ');

  // 合并连续空白字符为单个空格。
  sanitizedFileName = sanitizedFileName.replaceAll(RegExp(r'\s+'), ' ');
  sanitizedFileName = _trimInvalidEdgeCharacters(sanitizedFileName);

  if (sanitizedFileName.isEmpty) {
    throw const FormatException('Invalid File Name: Empty length.');
  }

  // Windows 保留设备名即使带扩展名也不可作为普通文件名使用。
  if (_isWindowsReservedFileName(sanitizedFileName)) {
    sanitizedFileName = '_$sanitizedFileName';
  }

  sanitizedFileName = _truncateUtf8(sanitizedFileName, maxLength);
  sanitizedFileName = _trimInvalidEdgeCharacters(sanitizedFileName);
  if (sanitizedFileName.isEmpty) {
    throw const FormatException('Invalid File Name: Empty length.');
  }

  return sanitizedFileName;
}

String _trimInvalidEdgeCharacters(String value) {
  var result = value.trim();
  while (result.startsWith('.') || result.endsWith('.')) {
    if (result.startsWith('.')) {
      result = result.substring(1);
    }
    if (result.endsWith('.')) {
      result = result.substring(0, result.length - 1);
    }
    result = result.trim();
  }
  return result;
}

bool _isWindowsReservedFileName(String fileName) {
  final baseName = fileName.split('.').first.toUpperCase();
  return RegExp(r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$').hasMatch(baseName);
}

String _truncateUtf8(String value, int maxLength) {
  if (utf8.encode(value).length <= maxLength) {
    return value;
  }

  final codePoints = <int>[];
  var byteLength = 0;
  for (final rune in value.runes) {
    final runeByteLength = utf8.encode(String.fromCharCode(rune)).length;
    if (byteLength + runeByteLength > maxLength) {
      break;
    }
    codePoints.add(rune);
    byteLength += runeByteLength;
  }
  return String.fromCharCodes(codePoints);
}

/// 按统一格式生成安全且长度受限的下载目录名。
String buildDownloadDirectoryName({
  required String type,
  required String id,
  required String title,
  int maxLength = maxDownloadDirectoryNameBytes,
}) {
  final prefix = '[$type][$id]';
  final titleMaxLength = maxLength - utf8.encode(prefix).length;
  if (titleMaxLength < 1) {
    throw ArgumentError.value(maxLength, 'maxLength', '目录名长度不足以容纳下载类型和 ID');
  }
  final titleToUse = title.isNotEmpty ? title : id;
  final sanitizedTitle = sanitizeFileName(titleToUse, titleMaxLength);
  return '$prefix$sanitizedTitle';
}

/// 生成下载漫画封面的文件名。
///
/// 封面文件名只依赖来源和下载 ID，不依赖漫画目录名称，因此重命名漫画目录后
/// 无需同步移动封面文件。
String buildDownloadCoverFileName({
  required String sourceKey,
  required String id,
}) {
  return '${sanitizeFileName(sourceKey)}_${sanitizeFileName(id)}.webp';
}

String findValidDirectoryName(String path, String directory) {
  var name = sanitizeFileName(directory);
  // var dir = Directory("$path/$name");
  // var i = 1;
  // while(dir.existsSync()){
  //   name = sanitizeFileName("$directory($i)");
  //   dir = Directory("$path/$name");
  //   i++;
  // }
  return name;
}
