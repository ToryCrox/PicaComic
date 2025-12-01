import 'dart:convert';
import 'dart:io';

import 'package:pica_comic/tools/extensions.dart';

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

String sanitizeFileName(String fileName) {
  const maxLength = 255;

  // Windows 保留文件名
  const reservedNames = [
    'CON',
    'PRN',
    'AUX',
    'NUL',
    'COM1',
    'COM2',
    'COM3',
    'COM4',
    'COM5',
    'COM6',
    'COM7',
    'COM8',
    'COM9',
    'LPT1',
    'LPT2',
    'LPT3',
    'LPT4',
    'LPT5',
    'LPT6',
    'LPT7',
    'LPT8',
    'LPT9'
  ];

  // 替换非法字符为空格
  final invalidChars = RegExp(r'[<>:"/\\|?*]');
  var sanitizedFileName = fileName.replaceAll(invalidChars, ' ');

  // 合并连续空格为单个空格
  sanitizedFileName = sanitizedFileName.replaceAll(RegExp(r'\s+'), ' ');

  // 移除开头和结尾的空格和点号
  sanitizedFileName = sanitizedFileName.trim();
  while (sanitizedFileName.startsWith('.') || sanitizedFileName.endsWith('.')) {
    if (sanitizedFileName.startsWith('.')) {
      sanitizedFileName = sanitizedFileName.substring(1);
    }
    if (sanitizedFileName.endsWith('.')) {
      sanitizedFileName =
          sanitizedFileName.substring(0, sanitizedFileName.length - 1);
    }
    sanitizedFileName = sanitizedFileName.trim();
  }

  if (sanitizedFileName.isEmpty) {
    throw Exception('Invalid File Name: Empty length.');
  }

  // 检查是否为 Windows 保留文件名
  final upperName = sanitizedFileName.toUpperCase();
  if (reservedNames.contains(upperName)) {
    sanitizedFileName = '_$sanitizedFileName';
  }

  // 限制长度(考虑 UTF-8 编码)
  while (true) {
    final bytes = utf8.encode(sanitizedFileName);
    if (bytes.length > maxLength) {
      sanitizedFileName =
          sanitizedFileName.substring(0, sanitizedFileName.length - 1);
    } else {
      break;
    }
  }

  return sanitizedFileName;
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
