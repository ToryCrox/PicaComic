import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

/// 从 pixez_flutter 移植的随应用提供的 cwebp 工具。
class CwebpTool {
  const CwebpTool(
    this.executablePath, {
    this.timeout = const Duration(seconds: 30),
  });

  final String executablePath;
  final Duration timeout;

  /// 查找打包或开发环境中的编码工具；不依赖 pixez 安装目录。
  static Future<CwebpTool?> resolve({String? preferredPath}) async {
    if (preferredPath != null) {
      return await File(preferredPath).exists()
          ? CwebpTool(preferredPath)
          : null;
    }
    if (!Platform.isWindows) return null;
    final executableDir = path.dirname(Platform.resolvedExecutable);
    for (final candidate in [
      path.join(
        executableDir,
        'data',
        'flutter_assets',
        'assets',
        'executables',
        'cwebp.exe',
      ),
      path.join(executableDir, 'assets', 'executables', 'cwebp.exe'),
      path.join(Directory.current.path, 'assets', 'executables', 'cwebp.exe'),
    ]) {
      if (await File(candidate).exists()) return CwebpTool(candidate);
    }
    return null;
  }

  /// 不经 shell 启动进程，超时终止并收集输出。
  Future<ProcessResult> run(List<String> arguments) async {
    final process = await Process.start(
      executablePath,
      arguments,
      runInShell: false,
    );
    final stdout = process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .join();
    final stderr = process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .join();
    int exitCode;
    try {
      exitCode = await process.exitCode.timeout(timeout);
    } on TimeoutException {
      process.kill();
      await process.exitCode;
      await Future.wait([stdout, stderr]);
      rethrow;
    }
    return ProcessResult(process.pid, exitCode, await stdout, await stderr);
  }

  /// 验证工具可执行。
  Future<void> checkAvailability() async {
    final result = await run(const ['-version']);
    if (result.exitCode != 0) throw StateError('cwebp 无法执行：${result.stderr}');
  }
}
