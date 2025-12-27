import 'dart:io';
import 'package:path/path.dart' as p;

/// 目录层级整理脚本
///
/// 功能：
/// 给定一个目录，扫描其下的子目录。
/// 如果某个子目录 (A) 下面只包含一个文件夹 (B)，
/// 则将 B 中的所有内容移动到 A 中，并删除 B。
///
/// 特性：
/// - 先预览，后执行
/// - 显示移动源、目标及文件数量
/// - 列出不符合移动条件的目录及原因
///
/// 使用方法:
/// dart scripts/flatten_nested_dirs.dart <目录路径>

class ScanResult {
  final Directory parentDir;
  final Directory? subDir;     // 仅当 canMove 为 true 时非空
  final int itemCount;         // 仅当 canMove 为 true 时有效
  final bool canMove;
  final String? skipReason;    // 仅当 canMove 为 false 时非空

  ScanResult.move({
    required this.parentDir,
    required this.subDir,
    required this.itemCount,
  }) : canMove = true, skipReason = null;

  ScanResult.skip({
    required this.parentDir,
    required this.skipReason,
  }) : canMove = false, subDir = null, itemCount = 0;
}

void main(List<String> args) async {
  print('=== 目录层级整理工具 ===\n');

  if (args.isEmpty) {
    print('错误: 请提供目录路径');
    print('使用方法: dart scripts/flatten_nested_dirs.dart <目录路径>');
    exit(1);
  }

  final rootPath = args[0];
  final rootDir = Directory(rootPath);

  if (!await rootDir.exists()) {
    print('错误: 目录不存在: $rootPath');
    exit(1);
  }

  print('正在扫描目录: $rootPath ...\n');

  final moveResults = <ScanResult>[];
  final skipResults = <ScanResult>[];

  // 1. 扫描阶段
  await for (var entity in rootDir.list(followLinks: false)) {
    if (entity is Directory) {
      final result = await _analyzeDirectory(entity);
      if (result.canMove) {
        moveResults.add(result);
      } else {
        skipResults.add(result);
      }
    }
  }

  // 2. 预览阶段
  
  // 显示被跳过的项
  if (skipResults.isNotEmpty) {
    print('以下目录将被 [跳过] (不符合条件):\n');
    print('${'操作'.padRight(6)} | ${'目录名'.padRight(40)} | 原因');
    print('-' * 80);
    for (var res in skipResults) {
      final dirName = p.basename(res.parentDir.path);
      // 截断过长的目录名以便显示
      var displayDirName = dirName;
      if (displayDirName.length > 39) {
        displayDirName = '${displayDirName.substring(0, 36)}...';
      }
      print('${'SKIP'.padRight(6)} | ${displayDirName.padRight(40)} | ${res.skipReason}');
    }
    print('-' * 80);
    print('共计跳过 ${skipResults.length} 个目录。\n');
  }

  // 显示将要移动的项
  if (moveResults.isNotEmpty) {
    print('以下目录将被 [修改]:\n');
    print('${'操作'.padRight(6)} | ${'文件数'.padRight(6)} | ${'详情 (内层源 -> 外层目标)'}');
    print('-' * 80);

    for (var res in moveResults) {
      final subDirName = p.basename(res.subDir!.path);
      final parentDirName = p.basename(res.parentDir.path);
      print('${'MOVE'.padRight(6)} | ${res.itemCount.toString().padRight(6)} | $subDirName -> $parentDirName');
    }
    print('-' * 80);
  } else {
    print('未发现需要处理的嵌套目录。');
  }

  print('\n总结: ${moveResults.length} 个目录待处理，${skipResults.length} 个目录跳过。\n');

  if (moveResults.isEmpty) {
    exit(0);
  }

  // 3. 确认阶段
  stdout.write('是否确认执行上述 ${moveResults.length} 个移动操作? (y/n): ');
  final input = stdin.readLineSync();
  
  if (input?.toLowerCase() != 'y') {
    print('操作已取消。');
    exit(0);
  }

  // 4. 执行阶段
  print('\n开始执行...\n');
  int successCount = 0;
  
  for (var res in moveResults) {
    bool success = await _executeOperation(res);
    if (success) successCount++;
  }

  print('\n=== 处理完成 ===');
  print('成功处理: $successCount/${moveResults.length}');
}

/// 分析目录是否符合移动条件
Future<ScanResult> _analyzeDirectory(Directory parentDir) async {
  try {
    final children = await parentDir.list(followLinks: false).toList();
    
    if (children.isEmpty) {
      return ScanResult.skip(parentDir: parentDir, skipReason: '目录为空');
    }

    // 如果目录下的内容数量不为 1
    if (children.length > 1) {
       return ScanResult.skip(parentDir: parentDir, skipReason: '包含多个文件/目录 (${children.length}个)');
    }

    // 如果唯一的内容不是目录
    if (children.first is! Directory) {
      return ScanResult.skip(parentDir: parentDir, skipReason: '唯一内容不是目录');
    }

    final subDir = children.first as Directory;
    
    // 统计子目录下的内容数量
    final subContents = await subDir.list(followLinks: false).toList();
    
    return ScanResult.move(
      subDir: subDir, 
      parentDir: parentDir, 
      itemCount: subContents.length
    );

  } catch (e) {
    return ScanResult.skip(parentDir: parentDir, skipReason: '访问出错: $e');
  }
}

/// 执行移动操作
Future<bool> _executeOperation(ScanResult op) async {
  if (!op.canMove || op.subDir == null) return false;

  final parentDirName = p.basename(op.parentDir.path);
  try {
    // 移动所有内容
    await for (var entity in op.subDir!.list(followLinks: false)) {
      final fileName = p.basename(entity.path);
      final newPath = p.join(op.parentDir.path, fileName);
      
      if (entity.path == newPath) continue;

      if (entity is File) {
        await entity.rename(newPath);
      } else if (entity is Directory) {
        await entity.rename(newPath);
      }
    }

    // 删除空目录
    await op.subDir!.delete();
    print('已完成: $parentDirName');
    return true;

  } catch (e) {
    print('失败 ($parentDirName): $e');
    return false;
  }
}
