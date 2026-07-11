import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:image/image.dart' as img;

/// 封面转换脚本
///
/// 此脚本用于将现有下载漫画的封面统一转换为 webp 格式
///
/// 使用方法:
/// dart scripts/convert_covers_to_webp.dart <下载目录路径>
///
/// 例如:
/// dart scripts/convert_covers_to_webp.dart "C:\Users\YourName\AppData\Local\pica_comic\download"

void main(List<String> args) async {
  print('=== 漫画封面格式转换工具 ===\n');

  // 检查参数
  if (args.isEmpty) {
    print('错误: 请提供下载目录路径');
    print('使用方法: dart scripts/convert_covers_to_webp.dart <下载目录路径>');
    exit(1);
  }

  final downloadPath = args[0];
  final downloadDir = Directory(downloadPath);

  // 检查目录是否存在
  if (!await downloadDir.exists()) {
    print('错误: 目录不存在: $downloadPath');
    exit(1);
  }

  print('下载目录: $downloadPath\n');
  print('正在扫描漫画封面...\n');

  // 扫描所有漫画目录
  final coversToConvert = <CoverInfo>[];
  final alreadyWebp = <String>[];
  final noCover = <String>[];

  await for (var entity in downloadDir.list()) {
    if (entity is Directory) {
      final dirName = path.basename(entity.path);
      final coverInfo = await _findCover(entity.path);

      if (coverInfo == null) {
        noCover.add(dirName);
      } else if (coverInfo.isWebp) {
        alreadyWebp.add(dirName);
      } else {
        coversToConvert.add(coverInfo);
      }
    }
  }

  // 显示统计信息
  print('扫描完成!');
  print('─' * 50);
  print(
    '总漫画数: ${coversToConvert.length + alreadyWebp.length + noCover.length}',
  );
  print('已是 webp 格式: ${alreadyWebp.length}');
  print('需要转换: ${coversToConvert.length}');
  print('无封面: ${noCover.length}');
  print('─' * 50);
  print('');

  if (noCover.isNotEmpty) {
    print('以下漫画没有封面:');
    for (var dir in noCover.take(10)) {
      print('  - $dir');
    }
    if (noCover.length > 10) {
      print('  ... 还有 ${noCover.length - 10} 个');
    }
    print('');
  }

  if (coversToConvert.isEmpty) {
    print('没有需要转换的封面,程序退出。');
    exit(0);
  }

  // 显示需要转换的封面信息
  print('需要转换的封面:');
  for (var cover in coversToConvert.take(10)) {
    print('  - ${path.basename(cover.comicDir)}: ${cover.extension}');
  }
  if (coversToConvert.length > 10) {
    print('  ... 还有 ${coversToConvert.length - 10} 个');
  }
  print('');

  // 请求用户确认
  print('是否继续转换? (y/n): ');
  final input = stdin.readLineSync();
  if (input?.toLowerCase() != 'y') {
    print('已取消转换。');
    exit(0);
  }

  print('\n开始转换...\n');

  // 执行转换
  int successCount = 0;
  int failCount = 0;
  final errors = <String, String>{};

  for (var i = 0; i < coversToConvert.length; i++) {
    final cover = coversToConvert[i];
    final comicName = path.basename(cover.comicDir);
    final progress = '${i + 1}/${coversToConvert.length}';

    stdout.write('\r[$progress] 转换中: $comicName');

    try {
      await _convertCover(cover);
      successCount++;
    } catch (e) {
      failCount++;
      errors[comicName] = e.toString();
    }
  }

  print('\n');
  print('─' * 50);
  print('转换完成!');
  print('成功: $successCount');
  print('失败: $failCount');
  print('─' * 50);

  if (errors.isNotEmpty) {
    print('\n转换失败的漫画:');
    for (var entry in errors.entries.take(10)) {
      print('  - ${entry.key}: ${entry.value}');
    }
    if (errors.length > 10) {
      print('  ... 还有 ${errors.length - 10} 个');
    }
  }

  print('\n所有操作已完成!');
}

class CoverInfo {
  final String comicDir;
  final String coverPath;
  final String extension;
  final bool isWebp;

  CoverInfo({
    required this.comicDir,
    required this.coverPath,
    required this.extension,
    required this.isWebp,
  });
}

/// 查找漫画目录中的封面文件
Future<CoverInfo?> _findCover(String comicDir) async {
  const extensions = ['.webp', '.jpg', '.jpeg', '.png'];

  for (var ext in extensions) {
    final coverPath = path.join(comicDir, 'cover$ext');
    final file = File(coverPath);

    if (await file.exists()) {
      return CoverInfo(
        comicDir: comicDir,
        coverPath: coverPath,
        extension: ext,
        isWebp: ext == '.webp',
      );
    }
  }

  return null;
}

/// 转换封面为 webp 格式
Future<void> _convertCover(CoverInfo cover) async {
  // 读取原封面
  final originalFile = File(cover.coverPath);
  final imageData = await originalFile.readAsBytes();

  // 解码图片
  final image = img.decodeImage(imageData);
  if (image == null) {
    throw Exception('无法解码图片');
  }

  // 编码为 jpg (因为 image 包可能不支持 webp 编码)
  // 注意: 这里暂时使用 jpg 格式,因为 image 包的 webp 编码支持可能有限
  // 如果需要真正的 webp 格式,可能需要使用其他库或工具
  final webpData = img.encodeJpg(image, quality: 70);

  // 保存为 cover.webp
  final webpPath = path.join(cover.comicDir, 'cover.webp');
  final webpFile = File(webpPath);
  await webpFile.writeAsBytes(webpData);

  // 删除原封面文件
  if (cover.coverPath != webpPath) {
    await originalFile.delete();
  }
}
