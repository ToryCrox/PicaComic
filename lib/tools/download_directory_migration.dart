import 'dart:io';

import 'package:path/path.dart' as path;

/// 复制下载目录并逐文件校验长度；连接关闭后调用，不吞掉子目录异常。
Future<void> copyDownloadDirectory(
  Directory source,
  Directory destination,
) async {
  final oldRoot = path.normalize(source.absolute.path);
  final newRoot = path.normalize(destination.absolute.path);
  if (path.equals(oldRoot, newRoot) ||
      path.isWithin(oldRoot, newRoot) ||
      path.isWithin(newRoot, oldRoot)) {
    throw ArgumentError('下载目录不能相同或互相包含');
  }
  if (await destination.exists() && !(await destination.list().isEmpty)) {
    throw StateError('迁移目标目录必须为空；已有下载目录请选择不复制文件');
  }
  await destination.create(recursive: true);
  await for (final entity in source.list(recursive: true, followLinks: false)) {
    final relative = path.relative(entity.path, from: oldRoot);
    final target = path.join(newRoot, relative);
    if (!path.isWithin(newRoot, path.normalize(target))) {
      throw StateError('下载目录中的文件位置无效');
    }
    if (entity is Directory) {
      await Directory(target).create(recursive: true);
    } else if (entity is File) {
      final output = File(target);
      await output.parent.create(recursive: true);
      await entity.copy(output.path);
      if (await entity.length() != await output.length()) {
        throw StateError('下载文件复制不完整：$relative');
      }
    } else {
      throw StateError('下载目录中的链接不支持自动迁移：$relative');
    }
  }
}
