import 'dart:io';
import 'package:open_file/open_file.dart';
import 'log.dart';

class FileUtils {
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
        // 使用 powershell 的 Invoke-Item。
        // 它与 cmd 的 start 命令行为一致，但支持 -LiteralPath 参数，可以正确处理包含 [ ] 等通配符的路径。
        // 同样会通过 ShellExecute 唤起，支持三方文件管理器。
        // 同时 powershell 是原生 Unicode 环境，不会截断 ④ 等特殊字符。
        // 我们需要对路径中的单引号进行转义，防止 powershell 语法错误。
        final escapedPath = path.replaceAll("'", "''");
        final result = await Process.run('powershell', [
          '-NoProfile',
          '-Command',
          "Invoke-Item -LiteralPath '$escapedPath'",
        ]);
        Log.d(
          () =>
              'openFileOrDirectory result: ${result.exitCode}, ${result.stdout}, ${result.stderr}',
        );
        return;
      } else {
        Log.w(() => 'openFileOrDirectory not directory: $path, type: $type');
      }
    }
    // 其他情况（非 Windows，或 Windows 下的文件）使用 open_file
    await OpenFile.open(path);
  }
}
