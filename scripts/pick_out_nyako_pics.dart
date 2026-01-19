/// 文件整理工具脚本
///
/// 功能说明：
/// 1. 扫描指定源目录下的所有子目录
/// 2. 将子目录中的压缩包文件（.7z/.rar/.zip）或子目录移动到目标目录
/// 3. 移动时重命名文件，添加格式化的子目录名作为前缀
/// 4. 移动完成后，自动删除空的子目录
///
/// 目录名格式化规则：
/// - 如果子目录名为 "X.Y" 格式（如 "1.2"），将格式化为 "XX.YY"（如 "01.02"）
/// - 其他格式的目录名保持不变
///
/// 使用方法：
/// ```bash
/// # 基本用法（显示预览，等待确认）
/// dart run scripts/pick_out_nyako_pics.dart "源目录路径"
///
/// # 自动执行（跳过确认）
/// dart run scripts/pick_out_nyako_pics.dart "源目录路径" --yes
///
/// # 示例
/// dart run scripts/pick_out_nyako_pics.dart "E:\漫画\comic_folder"
/// dart run scripts/pick_out_nyako_pics.dart "E:\漫画\comic_folder" --yes
/// ```
///
/// 执行流程：
/// 1. 扫描目录并显示移动预览
/// 2. 如果没有 --yes 参数，提示用户按回车确认
/// 3. 执行移动并清理空目录
///
/// 示例：
/// 源目录结构：
/// ```
/// source/
/// ├── 1.2/
/// │   ├── comic.zip
/// │   └── readme.txt    (将被跳过，非压缩包或目录)
/// ├── 3.10/
/// │   └── images/       (目录会被移动)
/// └── other/
///     └── file.rar
/// ```
///
/// 执行后结果：
/// ```
/// source/
/// ├── [01.02] comic.zip
/// ├── [03.10] images/
/// └── [other] file.rar
/// ```
/// 空的子目录（1.2、3.10）会被自动删除
///
/// 注意事项：
/// - 移动操作不可逆，请仔细预览后再确认
/// - 如果目标路径已存在同名文件，移动会失败
/// - 只有完全空的子目录会被删除
/// - Windows 建议使用 PowerShell 或 VS Code 终端运行

import 'dart:io';
import 'package:path/path.dart' as Path;

/// 支持的压缩包扩展名
const supportedExtensions = {'.7z', '.rar', '.zip', '.mp4'};

/// 格式化目录名称
///
/// 将 "X.Y" 格式的目录名格式化为 "XX.YY" 格式
/// 例如: "1.2" -> "01.02", "3.10" -> "03.10"
/// 其他格式的目录名保持不变
String formatDirectoryName(String name) {
  final parts = name.split('.');
  if (parts.length == 2) {
    return '${parts[0].padLeft(2, '0')}.${parts[1].padLeft(2, '0')}';
  }
  return name;
}

/// 检查文件是否为支持的压缩包或目录
///
/// 返回 true 如果：
/// - 实体是一个目录
/// - 实体是一个文件且扩展名为 .7z/.rar/.zip
bool isTargetFile(FileSystemEntity entity) {
  if (entity is Directory) return true;
  if (entity is File) {
    final extension = Path.extension(entity.path);
    return supportedExtensions.contains(extension);
  }
  return false;
}

/// 收集移动目标的结果
///
/// 包含两个信息：
/// - [targetMoveMap]: 文件/目录与其目标路径的映射
/// - [subDirectories]: 所有包含待移动文件的子目录（用于后续清理空目录）
class MoveTargets {
  final Map<FileSystemEntity, String> targetMoveMap;
  final Set<Directory> subDirectories;

  MoveTargets(this.targetMoveMap, this.subDirectories);
}

/// 收集所有需要移动的文件/目录
///
/// 扫描 [srcDir] 下的所有子目录，找出符合条件的文件/目录：
/// - 压缩包文件（.7z/.rar/.zip）
/// - 子目录
///
/// 返回 [MoveTargets] 对象，包含移动目标和涉及的子目录
MoveTargets collectMoveTargets(Directory srcDir, Directory destDir) {
  final targetMoveMap = <FileSystemEntity, String>{};
  final subDirectories = <Directory>{};

  for (final subDir in srcDir.listSync()) {
    // 跳过非目录项
    if (subDir is! Directory) continue;

    // 格式化子目录名作为前缀
    final subDirName = formatDirectoryName(Path.basename(subDir.path));
    bool hasTarget = false;

    for (final file in subDir.listSync()) {
      // 检查是否为支持的文件类型
      if (!isTargetFile(file)) {
        print('跳过: ${file.path} (非压缩包或目录)');
        continue;
      }

      hasTarget = true;
      final fileName = Path.basename(file.path);
      // 新文件名格式: [子目录名] 原文件名
      final newFileName = '[$subDirName] $fileName';
      targetMoveMap[file] = Path.join(destDir.path, newFileName);
    }

    // 记录包含待移动文件的子目录
    if (hasTarget) {
      subDirectories.add(subDir);
    }
  }

  return MoveTargets(targetMoveMap, subDirectories);
}

/// 显示移动预览
///
/// 打印所有将要移动的文件/目录及其目标路径
/// 如果没有找到任何文件，显示提示信息
void displayPreview(Map<FileSystemEntity, String> targetMoveMap) {
  if (targetMoveMap.isEmpty) {
    print('\n没有找到需要移动的文件。');
    return;
  }

  print('\n========== 移动预览 ==========');
  print('共找到 ${targetMoveMap.length} 个文件/目录需要移动:\n');

  int index = 0;
  for (final entry in targetMoveMap.entries) {
    index++;
    print('[$index] 源: ${entry.key.path}');
    print('    目标: ${entry.value}\n');
  }

  print('==============================');
}

/// 清理空目录
///
/// 遍历 [directories] 中的所有目录，删除空目录
/// 显示删除操作的统计信息
void cleanUpEmptyDirectories(Set<Directory> directories) {
  if (directories.isEmpty) return;

  print('\n正在清理空目录...');
  int deletedCount = 0;

  for (final dir in directories) {
    try {
      // 目录可能已被删除或不存在
      if (!dir.existsSync()) continue;

      final contents = dir.listSync();
      if (contents.isEmpty) {
        dir.deleteSync();
        print('  删除空目录: ${Path.basename(dir.path)}');
        deletedCount++;
      }
    } catch (e) {
      print('  删除目录失败 ${dir.path}: $e');
    }
  }

  if (deletedCount > 0) {
    print('已删除 $deletedCount 个空目录。');
  } else {
    print('没有需要删除的空目录。');
  }
}

/// 执行文件移动
///
/// 遍历所有待移动的文件/目录并执行移动操作
/// 移动完成后，自动清理空的子目录
/// 显示移动进度和结果统计
void executeMoves(MoveTargets moveTargets) {
  final targetMoveMap = moveTargets.targetMoveMap;
  print('\n开始执行移动...\n');

  int successCount = 0;
  int index = 0;

  for (final entry in targetMoveMap.entries) {
    index++;
    final src = entry.key;
    final dest = entry.value;

    try {
      print('[$index/${targetMoveMap.length}] 移动: ${Path.basename(src.path)}');
      src.renameSync(dest);
      successCount++;
    } catch (e) {
      print('    错误: $e');
    }
  }

  print('\n完成! 成功移动 $successCount/${targetMoveMap.length} 个文件/目录。');

  // 清理空目录
  cleanUpEmptyDirectories(moveTargets.subDirectories);
}

/// 显示使用说明
void showUsage() {
  print('用法: dart run scripts/pick_out_nyako_pics.dart <源目录路径> [--yes]\n');
  print('参数:');
  print('  源目录路径    要处理的目录路径（支持中文路径）');
  print('  --yes         跳过确认，自动执行\n');
  print('示例:');
  print('  dart run scripts/pick_out_nyako_pics.dart "E:\\漫画\\comic_folder"');
  print('  dart run scripts/pick_out_nyako_pics.dart "E:\\漫画\\comic_folder" --yes\n');
}

/// 主函数
///
/// 执行流程：
/// 1. 解析命令行参数获取源目录路径
/// 2. 验证目录存在性
/// 3. 扫描并收集移动目标
/// 4. 显示移动预览
/// 5. 如果没有 --yes 参数，提示用户按回车确认
/// 6. 执行移动并清理空目录
void main(List<String> args) {
  print('========== 文件移动工具 ==========');

  // 解析参数
  if (args.isEmpty) {
    print('错误: 请提供源目录路径\n');
    showUsage();
    exit(1);
  }

  final srcPath = args[0];
  final autoConfirm = args.contains('--yes');

  // 验证输入不为空
  if (srcPath.isEmpty) {
    print('错误: 源目录路径不能为空。');
    exit(1);
  }

  final srcDir = Directory(srcPath);
  // 验证目录存在
  if (!srcDir.existsSync()) {
    print('错误: 源目录不存在: $srcPath');
    exit(1);
  }

  print('源目录: $srcPath');

  // 目标目录默认为源目录（文件被移动到同级目录）
  final destDir = srcDir;

  // 收集移动目标
  print('\n正在扫描目录...');
  final moveTargets = collectMoveTargets(srcDir, destDir);

  // 显示预览
  displayPreview(moveTargets.targetMoveMap);

  if (moveTargets.targetMoveMap.isEmpty) {
    exit(0);
  }

  // 询问确认（除非使用 --yes 参数）
  if (!autoConfirm) {
    stdout.write('\n确认执行移动? (y/n): ');
    final input = stdin.readLineSync();
    final trimmed = input?.trim().toLowerCase() ?? '';
    if (trimmed != 'y' && trimmed != 'yes') {
      print('已取消操作。');
      exit(0);
    }
  }

  executeMoves(moveTargets);
}
