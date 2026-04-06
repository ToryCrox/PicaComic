import 'dart:io';

import 'package:path/path.dart' as p;

/// IceZ 图片整理脚本。
///
/// 用途：
/// - 按文件名规则 `名称 (数字).扩展名` 自动归档图片；
/// - 例如 `Aemeath (03).jpg` 会移动到同级 `Aemeath/` 目录下。
///
/// 适用场景：
/// - 既支持传入单个月份目录，也支持传入父目录；
/// - 传入父目录时，会递归扫描其所有子目录，并在各自目录内完成整理。
///
/// 执行流程：
/// - 先输出树形预览（目录、图片数量、最多 5 张示例）；
/// - 用户输入 `y` 后才会真正移动文件，避免误操作。
///
/// 使用方式：
/// - `dart scripts/organize_icez_images.dart <目录路径>`

/// 单个文件移动计划。
class MovePlan {
  /// 源目录。
  final String sourceDirPath;

  /// 源文件。
  final File sourceFile;

  /// 目标目录名（根据文件名前缀提取）。
  final String targetDirName;

  /// 目标文件完整路径。
  final String targetFilePath;

  const MovePlan({
    required this.sourceDirPath,
    required this.sourceFile,
    required this.targetDirName,
    required this.targetFilePath,
  });
}

/// 单个文件跳过信息。
class SkipItem {
  /// 被跳过的文件路径。
  final String path;

  /// 跳过原因。
  final String reason;

  const SkipItem({
    required this.path,
    required this.reason,
  });
}

/// 扫描结果。
class ScanResult {
  /// 待移动计划列表。
  final List<MovePlan> plans;

  /// 被跳过条目。
  final List<SkipItem> skipped;

  const ScanResult({
    required this.plans,
    required this.skipped,
  });
}

final _imageExtensions = <String>{
  '.jpg',
  '.jpeg',
  '.png',
  '.webp',
  '.bmp',
  '.gif',
  '.avif',
};

final _fileNamePattern = RegExp(r'^(.+?)\s*\((\d+)\)$');

void main(List<String> args) async {
  print('=== IceZ 图片整理脚本 ===\n');

  if (args.isEmpty) {
    print('错误: 请提供目录路径');
    print('用法: dart scripts/organize_icez_images.dart <目录路径>');
    exit(1);
  }

  final rootPath = args[0];
  final rootDir = Directory(rootPath);

  if (!await rootDir.exists()) {
    print('错误: 目录不存在: $rootPath');
    exit(1);
  }

  final scanResult = await _scanAllDirs(rootDir);
  _printPreview(rootDir.path, scanResult);

  if (scanResult.plans.isEmpty) {
    print('没有可执行的整理项，任务结束。');
    exit(0);
  }

  stdout.write('是否确认执行上述移动操作? (y/n): ');
  final input = stdin.readLineSync()?.trim().toLowerCase();
  if (input != 'y') {
    print('操作已取消。');
    exit(0);
  }

  await _executePlans(rootDir.path, scanResult.plans);
}

/// 扫描输入目录及其所有子目录，生成移动计划和跳过列表。
Future<ScanResult> _scanAllDirs(Directory rootDir) async {
  final plans = <MovePlan>[];
  final skipped = <SkipItem>[];

  final allDirs = <Directory>[rootDir];
  await for (final entity in rootDir.list(recursive: true, followLinks: false)) {
    if (entity is Directory) {
      allDirs.add(entity);
    }
  }

  allDirs.sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));

  for (final dir in allDirs) {
    await _scanSingleDir(dir, plans, skipped);
  }

  plans.sort((a, b) {
    final sourceCmp = a.sourceDirPath.toLowerCase().compareTo(b.sourceDirPath.toLowerCase());
    if (sourceCmp != 0) return sourceCmp;

    final dirCmp = a.targetDirName.toLowerCase().compareTo(b.targetDirName.toLowerCase());
    if (dirCmp != 0) return dirCmp;

    return p.basename(a.sourceFile.path).toLowerCase().compareTo(p.basename(b.sourceFile.path).toLowerCase());
  });

  return ScanResult(plans: plans, skipped: skipped);
}

/// 扫描单个目录直系文件。
Future<void> _scanSingleDir(
  Directory currentDir,
  List<MovePlan> plans,
  List<SkipItem> skipped,
) async {
  await for (final entity in currentDir.list(followLinks: false)) {
    if (entity is! File) {
      continue;
    }

    final extension = p.extension(entity.path).toLowerCase();
    if (!_imageExtensions.contains(extension)) {
      skipped.add(SkipItem(
        path: entity.path,
        reason: '不是支持的图片类型',
      ));
      continue;
    }

    final fileNameWithoutExtension = p.basenameWithoutExtension(entity.path);
    final match = _fileNamePattern.firstMatch(fileNameWithoutExtension);
    if (match == null) {
      skipped.add(SkipItem(
        path: entity.path,
        reason: '文件名不符合“名称 (数字)”规则',
      ));
      continue;
    }

    final dirName = match.group(1)?.trim();
    if (dirName == null || dirName.isEmpty) {
      skipped.add(SkipItem(
        path: entity.path,
        reason: '无法提取目录名',
      ));
      continue;
    }

    final currentBaseName = p.basename(currentDir.path).trim();
    if (dirName.toLowerCase() == currentBaseName.toLowerCase()) {
      skipped.add(SkipItem(
        path: entity.path,
        reason: '文件已位于对应目录，跳过',
      ));
      continue;
    }

    final targetDirPath = p.join(currentDir.path, dirName);
    final targetFilePath = p.join(targetDirPath, p.basename(entity.path));

    if (File(targetFilePath).existsSync()) {
      skipped.add(SkipItem(
        path: entity.path,
        reason: '目标文件已存在',
      ));
      continue;
    }

    plans.add(MovePlan(
      sourceDirPath: currentDir.path,
      sourceFile: entity,
      targetDirName: dirName,
      targetFilePath: targetFilePath,
    ));
  }
}

/// 打印执行前预览结构（树形）。
void _printPreview(String rootPath, ScanResult result) {
  print('扫描目录: $rootPath\n');

  final grouped = <String, Map<String, List<MovePlan>>>{};
  for (final plan in result.plans) {
    final bySource = grouped.putIfAbsent(plan.sourceDirPath, () => <String, List<MovePlan>>{});
    bySource.putIfAbsent(plan.targetDirName, () => <MovePlan>[]).add(plan);
  }

  print('--- 预览：整理后新增/变更结构 ---');
  if (grouped.isEmpty) {
    print('无可移动文件。\n');
  } else {
    print('.');

    final sourceDirs = grouped.keys.toList()
      ..sort((a, b) => p.relative(a, from: rootPath).toLowerCase().compareTo(p.relative(b, from: rootPath).toLowerCase()));

    for (var i = 0; i < sourceDirs.length; i++) {
      final sourceDirPath = sourceDirs[i];
      final isLastSource = i == sourceDirs.length - 1;
      final sourcePrefix = isLastSource ? '└── ' : '├── ';
      final sourceChildPrefix = isLastSource ? '    ' : '│   ';

      final relSource = p.relative(sourceDirPath, from: rootPath);
      final sourceLabel = relSource == '.' ? '(当前目录)' : '$relSource/';
      print('$sourcePrefix$sourceLabel');

      final targetGroups = grouped[sourceDirPath]!;
      final targetDirs = targetGroups.keys.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

      for (var j = 0; j < targetDirs.length; j++) {
        final targetDir = targetDirs[j];
        final files = targetGroups[targetDir]!;
        files.sort((a, b) => p.basename(a.sourceFile.path).toLowerCase().compareTo(p.basename(b.sourceFile.path).toLowerCase()));

        final isLastTarget = j == targetDirs.length - 1;
        final targetPrefix = isLastTarget ? '└── ' : '├── ';
        final targetChildPrefix = isLastTarget ? '    ' : '│   ';

        print('$sourceChildPrefix$targetPrefix$targetDir/ (${files.length} 张)');

        final displayCount = files.length > 5 ? 5 : files.length;
        for (var k = 0; k < displayCount; k++) {
          final fileName = p.basename(files[k].sourceFile.path);
          final isLastFile = k == displayCount - 1 && files.length <= 5;
          final filePrefix = isLastFile ? '└── ' : '├── ';
          print('$sourceChildPrefix$targetChildPrefix$filePrefix$fileName');
        }

        if (files.length > 5) {
          print('$sourceChildPrefix$targetChildPrefix└── ... (还有 ${files.length - 5} 张)');
        }
      }
    }
    print('');
  }

  print('--- 跳过项 ---');
  if (result.skipped.isEmpty) {
    print('无。\n');
  } else {
    for (final item in result.skipped) {
      final relPath = p.relative(item.path, from: rootPath);
      print('SKIP | $relPath | ${item.reason}');
    }
    print('');
  }

  print('汇总: 待移动 ${result.plans.length} 个文件，跳过 ${result.skipped.length} 个条目。\n');
}

/// 执行移动计划。
Future<void> _executePlans(String rootPath, List<MovePlan> plans) async {
  print('\n开始执行移动...\n');
  var success = 0;

  for (final plan in plans) {
    try {
      final targetDir = Directory(p.dirname(plan.targetFilePath));
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }

      final sourceRelPath = p.relative(plan.sourceFile.path, from: rootPath);
      final targetRelPath = p.relative(plan.targetFilePath, from: rootPath);

      await plan.sourceFile.rename(plan.targetFilePath);
      success++;
      print('已移动: $sourceRelPath -> $targetRelPath');
    } catch (e) {
      print('失败: ${plan.sourceFile.path} | 错误: $e');
    }
  }

  print('\n=== 处理完成 ===');
  print('成功: $success/${plans.length}');
}
