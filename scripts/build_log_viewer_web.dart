import 'dart:io';
import 'package:path/path.dart' as path;

/// 构建日志查看器 Web 应用
/// 
/// 构建流程：
/// 1. 进入 Web 应用目录
/// 2. 执行 flutter build web
/// 3. 复制构建产物到 log_viewer_server/assets/web/
void main() async {
  print('开始构建日志查看器 Web 应用...');
  
  // 1. 进入 Web 目录
  const webDir = 'packages/log_viewer_web';
  final webDirFile = Directory(webDir);
  
  if (!webDirFile.existsSync()) {
    print('错误: Web 目录不存在: $webDir');
    exit(1);
  }
  
  // 2. 构建 Web 应用
  print('正在构建 Web 应用...');
  // 在 Windows 上使用 flutter.bat，其他平台使用 flutter
  final flutterCommand = Platform.isWindows ? 'flutter.bat' : 'flutter';
  final buildResult = await Process.run(
    flutterCommand,
    ['build', 'web', '--release'],
    workingDirectory: webDir,
    runInShell: true, // 使用 shell 来查找命令
  );
  
  if (buildResult.exitCode != 0) {
    print('构建失败:');
    print(buildResult.stderr);
    exit(1);
  }
  
  print('Web 应用构建完成');
  
  // 3. 复制构建产物到 log_viewer_server 模块
  final sourceDir = Directory('$webDir/build/web');
  final targetDir = Directory('packages/log_viewer_server/assets/web');
  
  if (!sourceDir.existsSync()) {
    print('错误: 构建产物目录不存在: ${sourceDir.path}');
    exit(1);
  }
  
  print('正在复制构建产物...');
  
  // 删除目标目录（如果存在）
  if (targetDir.existsSync()) {
    await targetDir.delete(recursive: true);
  }
  
  // 创建目标目录
  await targetDir.create(recursive: true);
  
  // 复制文件
  await _copyDirectory(sourceDir, targetDir);
  
  print('构建完成！构建产物已复制到: ${targetDir.path}');
  print('提示: 需要在 log_viewer_server 的 pubspec.yaml 中声明 assets/web/ 资源');
}

/// 递归复制目录
Future<void> _copyDirectory(Directory source, Directory target) async {
  await for (final entity in source.list(recursive: false)) {
    // 使用 path.basename 获取文件名或目录名，跨平台兼容
    final basename = path.basename(entity.path);
    final targetPath = path.join(target.path, basename);
    
    if (entity is File) {
      await entity.copy(targetPath);
    } else if (entity is Directory) {
      final targetDir = Directory(targetPath);
      await targetDir.create(recursive: true);
      await _copyDirectory(entity, targetDir);
    }
  }
}

