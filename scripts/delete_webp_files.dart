import 'dart:io';
import 'dart:convert';

Future<void> main() async {
  // 获取用户输入的路径
  print('请输入要搜索和删除文件的目录路径:');
  print('提示: 直接按回车键将使用当前工作目录');

  String? inputPath = stdin.readLineSync();
  Directory targetDirectory;

  if (inputPath == null || inputPath.trim().isEmpty) {
    targetDirectory = Directory.current;
    print('使用当前工作目录: ${targetDirectory.path}');
  } else {
    targetDirectory = Directory(inputPath.trim());
    if (!await targetDirectory.exists()) {
      print('错误: 路径 "$inputPath" 不存在或不是有效目录');
      return;
    }
    print('使用指定目录: ${targetDirectory.path}');
  }

  // 首先收集所有要删除的文件
  List<File> filesToDelete = [];

  // 递归遍历所有目录
  await for (var entity
      in targetDirectory.list(recursive: true, followLinks: false)) {
    if (entity is File && entity.path.endsWith('W2xEX_Q85.webp')) {
      filesToDelete.add(entity);
    }
  }

  // 列出文件信息
  print('\n找到 ${filesToDelete.length} 个以 W2xEX_Q85.webp 结尾的文件:');
  print('-' * 80);

  int totalSize = 0;
  for (var file in filesToDelete) {
    final size = await file.length();
    totalSize += size;
    print('文件路径: ${file.path}');
    print('文件大小: ${formatFileSize(size)}');
    print('-' * 80);
  }

  print('\n总计: ${filesToDelete.length} 个文件, 总大小: ${formatFileSize(totalSize)}');

  // 获取用户确认
  print('\n是否要删除这些文件? (y/n): ');
  final input = stdin.readLineSync(encoding: utf8);

  if (input?.toLowerCase() != 'y') {
    print('操作已取消');
    return;
  }

  // 执行删除操作
  int deletedCount = 0;
  int failedCount = 0;

  for (var file in filesToDelete) {
    try {
      await file.delete();
      print('已删除: ${file.path}');
      deletedCount++;
    } catch (e) {
      print('删除失败: ${file.path}, 错误: $e');
      failedCount++;
    }
  }

  print('\n删除完成:');
  print('成功删除: $deletedCount 个文件');
  print('删除失败: $failedCount 个文件');
  print('总计处理: ${filesToDelete.length} 个文件');
}

// 格式化文件大小
String formatFileSize(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  } else if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(2)} KB';
  } else if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  } else {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
