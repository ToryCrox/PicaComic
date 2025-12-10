import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:archive/archive.dart';

/// ZIP 文件解压脚本
///
/// 此脚本用于递归扫描目录中的所有 ZIP 文件，解压并将文件平铺到 ZIP 所在目录，然后删除 ZIP 文件
///
/// 使用方法:
/// dart scripts/extract_zips.dart <目录路径>
///
/// 例如:
/// dart scripts/extract_zips.dart "C:\Users\YourName\Downloads"
///
/// 注意: 使用前需要安装 archive 包
/// 运行: dart pub add archive

void main(List<String> args) async {
  print('=== ZIP 文件解压工具 ===\n');

  // 检查参数
  if (args.isEmpty) {
    print('错误: 请提供目录路径');
    print('使用方法: dart scripts/extract_zips.dart <目录路径>');
    exit(1);
  }

  final targetPath = args[0];
  final targetDir = Directory(targetPath);

  // 检查目录是否存在
  if (!await targetDir.exists()) {
    print('错误: 目录不存在: $targetPath');
    exit(1);
  }

  print('目标目录: $targetPath\n');
  print('正在扫描 ZIP 文件...\n');

  // 递归查找所有 ZIP 文件
  final zipFiles = <ZipFileInfo>[];
  await _findZipFiles(targetDir, zipFiles);

  // 显示找到的 ZIP 文件
  if (zipFiles.isEmpty) {
    print('未找到任何 ZIP 文件，程序退出。');
    exit(0);
  }

  print('找到 ${zipFiles.length} 个 ZIP 文件:');
  print('─' * 70);
  for (var zipFile in zipFiles) {
    final sizeStr = _formatFileSize(zipFile.size);
    final relativePath = path.relative(zipFile.path, from: targetPath);
    print('  $relativePath ($sizeStr)');
  }
  print('─' * 70);
  print('');

  // 请求用户确认
  print('是否继续解压这些 ZIP 文件? (y/n): ');
  final input = stdin.readLineSync();
  if (input?.toLowerCase() != 'y') {
    print('已取消操作。');
    exit(0);
  }

  print('\n开始解压...\n');

  // 执行解压
  int successCount = 0;
  int failCount = 0;
  final errors = <String, String>{};

  for (var i = 0; i < zipFiles.length; i++) {
    final zipFile = zipFiles[i];
    final zipName = path.basename(zipFile.path);
    final overallProgress = '${i + 1}/${zipFiles.length}';

    print('[$overallProgress] 开始解压: $zipName');

    try {
      await _extractZip(zipFile.path, zipName, (current, total) {
        final percent = (current / total * 100).toStringAsFixed(1);
        stdout.write('\r  进度: $current/$total ($percent%)');
      });
      // 清除进度行并显示完成信息
      stdout.write('\r' + ' ' * 60 + '\r'); // 清除当前行
      print('  完成: $zipName');
      successCount++;
    } catch (e) {
      // 清除进度行并显示失败信息
      stdout.write('\r' + ' ' * 60 + '\r'); // 清除当前行
      print('  失败: $zipName');
      failCount++;
      errors[zipName] = e.toString();
    }
  }

  print('\n');
  print('─' * 70);
  print('解压完成!');
  print('成功: $successCount');
  print('失败: $failCount');
  print('─' * 70);

  if (errors.isNotEmpty) {
    print('\n解压失败的文件:');
    for (var entry in errors.entries) {
      print('  - ${entry.key}: ${entry.value}');
    }
  }

  print('\n所有操作已完成!');
}

/// ZIP 文件信息
class ZipFileInfo {
  final String path;
  final int size;

  ZipFileInfo({
    required this.path,
    required this.size,
  });
}

/// 递归查找所有 ZIP 文件
Future<void> _findZipFiles(Directory dir, List<ZipFileInfo> zipFiles) async {
  await for (var entity in dir.list()) {
    if (entity is File) {
      final fileName = entity.path.toLowerCase();
      if (fileName.endsWith('.zip')) {
        final stat = await entity.stat();
        zipFiles.add(ZipFileInfo(
          path: entity.path,
          size: stat.size,
        ));
      }
    } else if (entity is Directory) {
      await _findZipFiles(entity, zipFiles);
    }
  }
}

/// 解压 ZIP 文件
/// 
/// [zipPath] ZIP 文件路径
/// [zipName] ZIP 文件名（用于显示）
/// [onProgress] 进度回调函数，参数为 (当前文件数, 总文件数)
Future<void> _extractZip(
  String zipPath,
  String zipName,
  void Function(int current, int total) onProgress,
) async {
  final zipFile = File(zipPath);
  final zipDir = Directory(path.dirname(zipPath));

  // 读取 ZIP 文件
  final bytes = await zipFile.readAsBytes();
  final archive = ZipDecoder().decodeBytes(bytes);

  // 先统计文件总数
  final fileList = archive.where((file) => file.isFile).toList();
  final totalFiles = fileList.length;

  if (totalFiles == 0) {
    print('  警告: ZIP 文件中没有可解压的文件');
    await zipFile.delete();
    return;
  }

  // 解压所有文件到 ZIP 所在目录（平铺）
  int currentFile = 0;
  for (var file in fileList) {
    currentFile++;
    
    // 更新进度
    onProgress(currentFile, totalFiles);

    // 获取文件名（只取文件名，忽略路径）
    // 处理路径分隔符，确保跨平台兼容
    var fileName = file.name.replaceAll('\\', '/');
    fileName = path.basename(fileName);
    
    // 如果文件名为空或只有路径分隔符，跳过
    if (fileName.isEmpty || fileName == '/' || fileName == '\\') {
      continue;
    }

    // 清理文件名中的非法字符（Windows 文件名限制）
    fileName = _sanitizeFileName(fileName);

    // 构建目标文件路径
    final targetPath = path.join(zipDir.path, fileName);

    // 如果目标文件已存在，添加序号避免覆盖
    var finalPath = targetPath;
    var counter = 1;
    while (await File(finalPath).exists()) {
      final ext = path.extension(fileName);
      final nameWithoutExt = path.basenameWithoutExtension(fileName);
      final dir = path.dirname(finalPath);
      finalPath = path.join(dir, '$nameWithoutExt ($counter)$ext');
      counter++;
    }

    // 写入文件
    final targetFile = File(finalPath);
    await targetFile.writeAsBytes(file.content as List<int>);
  }

  // 删除 ZIP 文件
  await zipFile.delete();
}

/// 清理文件名中的非法字符
String _sanitizeFileName(String fileName) {
  // Windows 文件名非法字符: < > : " / \ | ? *
  final illegalChars = RegExp(r'[<>:"/\\|?*]');
  return fileName.replaceAll(illegalChars, '_');
}

/// 格式化文件大小
String _formatFileSize(int bytes) {
  if (bytes < 1024) {
    return '${bytes}B';
  } else if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(2)}KB';
  } else if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)}MB';
  } else {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)}GB';
  }
}

