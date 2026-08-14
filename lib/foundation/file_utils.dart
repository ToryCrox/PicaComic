import 'dart:io';
import 'package:open_file/open_file.dart';
import 'log.dart';

class FileUtils {
  static const _openPathEnvironmentKey = 'PICA_COMIC_OPEN_PATH';

  /// 打开文件或文件夹
  /// 针对 Windows 下 Unicode 路径（如 ④ 等特殊字符）导致的 cmd 截断问题：
  /// 1. 不使用 explorer.exe，因为它会强制使用系统资源管理器，跳过三方管理器。
  /// 2. 不使用 cmd /c start，因为它存在旧版编码问题，不支持复杂的 Unicode。
  /// 3. 使用 powershell -Command Invoke-Item -LiteralPath，既支持 Unicode 且能避开 [ ] 的通配符解析问题，又能尊重系统默认关联。
  static Future<void> openFileOrDirectory(String path) async {
    if (Platform.isWindows) {
      final type = await FileSystemEntity.type(path);
      Log.d(() => 'openFileOrDirectory: $path, type: $type');
      if (type == FileSystemEntityType.directory) {
        // 路径通过环境变量传递，避免直引号、弯引号等内容被 PowerShell
        // 当作命令语法解析，同时保留 Invoke-Item 对默认文件管理器的支持。
        final result = await Process.run(
          'powershell',
          [
            '-NoProfile',
            '-Command',
            'Invoke-Item -LiteralPath \$env:$_openPathEnvironmentKey',
          ],
          environment: {_openPathEnvironmentKey: path},
        );
        Log.d(
          () =>
              'openFileOrDirectory result: ${result.exitCode}, ${result.stdout}, ${result.stderr}',
        );
        if (result.exitCode == 0) {
          return;
        }
        Log.w(
          () =>
              'openFileOrDirectory: PowerShell 打开目录失败，回退到 open_file，'
              'exitCode=${result.exitCode}, stderr=${result.stderr}',
        );
      } else {
        Log.w(() => 'openFileOrDirectory not directory: $path, type: $type');
      }
    }
    // 其他情况（非 Windows，或 Windows 下的文件）使用 open_file
    await OpenFile.open(path);
  }
}
