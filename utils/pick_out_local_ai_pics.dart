

import 'dart:io';
import 'package:path/path.dart' as Path;

bool execute = false;

Future<void> main() async {
  final srcDir = Directory(r'');
  final destDir = srcDir;

  final targetMoveMap = <FileSystemEntity, String>{};
  for (final subDir in srcDir.listSync()) {
    if (subDir is! Directory) {
      continue;
    }
    String subDirName = Path.basename(subDir.path);
    final dirNameArr = subDirName.split('.');
    if (dirNameArr.length == 2) {
      subDirName = '${dirNameArr[0].padLeft(2, '0')}.${dirNameArr[1].padLeft(2, '0')}';
    }

    for (final file in subDir.listSync()) {
      final extension = Path.extension(file.path);
      if (!{'.7z', '.rar', '.zip'}.contains(extension)) {
        print('${file.path} is not a archive file or dir');
        continue;
      }
      final fileName = Path.basename(file.path);
      final newFileName = '[$subDirName] $fileName';
      targetMoveMap[file] = Path.join(destDir.path, newFileName);
    }
  }
  int index = 0;
  for (final entry in targetMoveMap.entries) {
    final src = entry.key;
    final dest = entry.value;
    index++;
    print('move file $index:\n    $src\n    $dest');
    if (execute) {
      await src.rename(dest);
    }

  }


}
