import 'dart:io';
import 'package:path/path.dart' as Path;

bool execute = false;

/// 整理图片，类似这种 20241219_1_ChloeWelter_012.webp, 也有可能是20241219_1_012.webp
/// 分别是 图片编号，图片日期，图片角色, 图片来源(固定是Pixiv, Extra)，图片编号
Future<void> main() async {
  final srcDir = Directory(r'');
  final destDir = srcDir;
  // key: 目录
  // value: 原始文件路径
  final targetMoveMap = <String, List<String>>{};
  for (final subDir in srcDir.listSync()) {
    if (subDir is! Directory) {
      continue;
    }
    for (final file in subDir.listSync()) {
      final fileName = Path.basenameWithoutExtension(file.path);
      final fileNameArray = fileName.split('_');
      if (fileNameArray.length < 3) {
        print('fileNameArray length < 5: ${file.path}');
        continue;
      }
      String targetKey;
      String mayName = fileNameArray[2];

      /// 判断mayName是否是纯数字
      if (int.tryParse(mayName) == null) {
        targetKey = fileNameArray.sublist(0, 3).join('_');
      } else {
        targetKey = fileNameArray.sublist(0, 2).join('_');
      }
      final newDirPath = Path.join(subDir.path, targetKey);
      targetMoveMap[newDirPath] ??= [];
      targetMoveMap[newDirPath]!.add(file.path);
    }
  }
  for (final entry in targetMoveMap.entries) {
    final newDir = Directory(entry.key);
    if (execute) {
      if (!newDir.existsSync()) {
        newDir.createSync(recursive: true);
      }
    }

    print('newDir: ${newDir.path}, files: ${entry.value.length}');
    for (final file in entry.value) {
      //print('    ${Path.basename(file)}');
      if (execute) {
        final oldFile = File(file);
        final newFilePath = Path.join(newDir.path, Path.basename(file));
        await oldFile.rename(newFilePath);
      }
    }
  }
}
