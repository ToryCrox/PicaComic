import 'dart:io';
import 'dart:typed_data';
import 'package:collection/collection.dart';
import 'package:path/path.dart' as Path;
import 'package:pica_comic/tools/str_ext.dart';
import 'package:image/image.dart' as img;

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

extension FileNameListExt<T> on Iterable<T> {
  Iterable<T> sortedFileNameBy(String Function(T) getName) {
    final regexp = RegExp(r'[^\d]+|\d+');
    return map((file) {
          final name = Path.canonicalize(getName(file));
          final weights = regexp
              .allMatches(name)
              .map((match) => match.group(0))
              .where((group) => group != null)
              .toList();
          return (file, weights);
        })
        .sorted((a, b) {
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
        })
        .map((e) => e.$1);
  }
}

extension FileListSystemEntityExt on Iterable<FileSystemEntity> {
  Iterable<FileSystemEntity> sortedByName() {
    final regexp = RegExp(r'[^\d]+|\d+');
    return map((file) {
          final name = Path.canonicalize(file.path);
          final weights = regexp
              .allMatches(name)
              .map((match) => match.group(0))
              .where((group) => group != null)
              .toList();
          return (file, weights);
        })
        .sorted((a, b) {
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
        })
        .map((e) => e.$1);
  }
}

/// 将图片数据转换为webp格式
Future<Uint8List> convertImageToWebp(Uint8List imageData) async {
  try {
    // 解码图片
    final image = img.decodeImage(imageData);
    if (image == null) {
      // 如果解码失败,直接返回原数据
      return imageData;
    }

    // 编码为webp格式,质量设置为90
    final webpData = img.encodeJpg(image, quality: 70);
    return Uint8List.fromList(webpData);
  } catch (e) {
    // 如果转换失败,返回原数据
    return imageData;
  }
}
