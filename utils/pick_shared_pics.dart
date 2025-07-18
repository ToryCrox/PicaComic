

import 'dart:io';
import 'package:path/path.dart' as Path;

bool execute = false;

/// 整理图片，类似这种 001_4.4_Ayanami_Pixiv_00040.webp， 196_4.5_Nahida_Extra_00883.webp
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
      final fileName = Path.basename(file.path);
      final fileNameArray = fileName.split('_');
      if (fileNameArray.length < 5) {
        print('fileNameArray length < 5: ${file.path}');
        continue;
      }
      String date = fileNameArray[1];
      // 将4.4转化为 04.04
      final dateArray = date.split('.');
      if (dateArray.length < 2) {
        print('dateArray length < 2: ${file.path}');
        continue;
      }
      date = '${dateArray[0].padLeft(2, '0')}.${dateArray[1].padLeft(2, '0')}';
      final isDoubleDate = fileNameArray[1] == fileNameArray[2];
      String role = fileNameArray.sublist(isDoubleDate ? 3 : 2, fileNameArray.length - 2).join('_');
      final newDirName = '[$date] ${role}';
      targetMoveMap[newDirName] ??= [];
      targetMoveMap[newDirName]!.add(file.path);
    }
  }
  for (final entry in targetMoveMap.entries) {
    final newDir = Directory(Path.join(destDir.path, entry.key));
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
