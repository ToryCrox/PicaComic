
import 'dart:io';
import 'package:path/path.dart' as Path;
import 'package:pica_comic/tools/str_ext.dart';

const sImageExtensions = [
  '.jpg',
  '.jpeg',
  '.png',
  '.webp',
  '.gif',
  '.bmp',
  '.heif'
];

bool predictImageFile(FileSystemEntity file) {
  return sImageExtensions.contains(Path.extension(file.path).toLowerCase());
}

int fileNameCompare(FileSystemEntity a, FileSystemEntity b) {
  final aName = a.path;
  final bName = b.path;
  return aName.compareIndex(bName);
}