
import 'dart:io';
import 'package:collection/collection.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as Path;
import 'package:pica_comic/tools/str_ext.dart';

const sImageExtensions = [
  '.jpg',
  '.jpeg',
  '.png',
  '.webp',
  '.gif',
  '.bmp',
  '.heif',
];

bool predictImageFile(FileSystemEntity file) {
  return sImageExtensions.contains(Path.extension(file.path).toLowerCase());
}


String sFileRelativeFromPath = '';
int fileNameCompare(FileSystemEntity a, FileSystemEntity b) {
  final aName = Path.relative(a.path, from: sFileRelativeFromPath);
  final bName = Path.relative(b.path, from: sFileRelativeFromPath);
  return aName.compareIndex(bName);
}


extension FileListSystemEntityExt on Iterable<FileSystemEntity> {

  Iterable<FileSystemEntity> sortedByName() {
    final regexp = RegExp(r'[^\d]+|\d+');
    return map((file){
      final name = Path.canonicalize(file.path);
      final weights = regexp
          .allMatches(name)
          .map((match) => match.group(0))
          .where((group) => group != null)
          .toList();
      return (file, weights);
    }).sorted((a, b){
      final weightsA = a.$2;
      final weightsB = b.$2;
      var pos = 0;
      var weightA = weightsA[pos];
      var weightB = weightsB[pos];

      while (weightA != null && weightB != null) {
        int? numA = int.tryParse(weightA);
        int? numB = int.tryParse(weightB);

        if (numA != null && numB != null && numA != numB) {
          return numA - numB;
        }

        if (weightA != weightB) {
          return weightA.compareTo(weightB);
        }

        pos++;
        weightA = weightsA.length > pos ? weightsA[pos] : null;
        weightB = weightsB.length > pos ? weightsB[pos] : null;
      }

      if (weightA != null) {
        return 1;
      } else {
        return -1;
      }
    }).map((e) => e.$1);
  }
}
