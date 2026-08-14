import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:path/path.dart' as path;
import 'package:pica_comic/foundation/log.dart';
import 'package:pica_comic/tools/image_utils.dart';

/// 支持由外部翻译工具产生的图片格式。
const translationResultImageExtensions = {
  '.jpg',
  '.jpeg',
  '.png',
  '.gif',
  '.webp',
  '.bmp',
};

/// 图片尺寸。
class TranslationImageDimensions {
  const TranslationImageDimensions(this.width, this.height);

  final int width;
  final int height;

  @override
  String toString() => '$width × $height';
}

/// 一对可被替换的原图与译图。
class TranslationReplacementPair {
  const TranslationReplacementPair({
    required this.originalPath,
    required this.translatedPath,
    required this.originalSize,
    required this.translatedSize,
    this.originalDimensions,
    this.translatedDimensions,
  });

  final String originalPath;
  final String translatedPath;
  final int originalSize;
  final int translatedSize;
  final TranslationImageDimensions? originalDimensions;
  final TranslationImageDimensions? translatedDimensions;

  String get baseName => path.basenameWithoutExtension(originalPath);

  String get destinationPath => path.join(
    path.dirname(originalPath),
    '$baseName${path.extension(translatedPath).toLowerCase()}',
  );
}

/// 没有参与替换的文件及原因。
class TranslationUnmatchedFile {
  const TranslationUnmatchedFile({
    required this.filePath,
    required this.isOriginal,
    required this.reason,
  });

  final String filePath;
  final bool isOriginal;
  final String reason;
}

/// 单本漫画的扫描结果。
class TranslationReplacementPlan {
  const TranslationReplacementPlan({
    required this.comicDirectory,
    required this.resultDirectories,
    required this.pairs,
    required this.unmatched,
  });

  final String comicDirectory;
  final Set<String> resultDirectories;
  final List<TranslationReplacementPair> pairs;
  final List<TranslationUnmatchedFile> unmatched;

  int get originalTotalSize =>
      pairs.fold(0, (total, pair) => total + pair.originalSize);

  int get translatedTotalSize =>
      pairs.fold(0, (total, pair) => total + pair.translatedSize);
}

/// 单张图片的替换结果。
class TranslationReplacementResult {
  const TranslationReplacementResult({required this.pair, this.error});

  final TranslationReplacementPair pair;
  final String? error;

  bool get isSuccess => error == null;
}

/// 整次替换的汇总。
class TranslationReplacementSummary {
  const TranslationReplacementSummary({
    required this.results,
    required this.intermediateDirectoriesCleaned,
  });

  final List<TranslationReplacementResult> results;
  final bool intermediateDirectoriesCleaned;

  int get successCount => results.where((result) => result.isSuccess).length;

  int get failureCount => results.length - successCount;
}

/// 扫描并安全应用漫画目录中的翻译结果。
///
/// 每个 `result/` 目录只与其父目录内的图片匹配，避免多章节漫画发生跨目录覆盖。
class TranslationResultReplacer {
  static const resultDirectoryName = 'result';
  static const _intermediateDirectoryNames = ['inpainted', 'mask'];

  /// 快速判断是否存在至少一组可替换图片。
  Future<bool> hasReplacementCandidate(String comicDirectory) async {
    try {
      final plan = await prepare(comicDirectory, includeDimensions: false);
      return plan.pairs.isNotEmpty;
    } catch (error, stackTrace) {
      Log.e(
        '检查翻译结果目录失败: $comicDirectory',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// 扫描漫画及其章节目录中的 `result/`。
  Future<TranslationReplacementPlan> prepare(
    String comicDirectory, {
    bool includeDimensions = true,
  }) async {
    final rootDirectory = Directory(comicDirectory);
    if (comicDirectory.isEmpty || !await rootDirectory.exists()) {
      return TranslationReplacementPlan(
        comicDirectory: comicDirectory,
        resultDirectories: const {},
        pairs: const [],
        unmatched: const [],
      );
    }

    final resultDirectories = await _findResultDirectories(rootDirectory);
    final pairs = <TranslationReplacementPair>[];
    final unmatched = <TranslationUnmatchedFile>[];
    for (final resultDirectory in resultDirectories) {
      await _scanResultDirectory(
        resultDirectory,
        pairs: pairs,
        unmatched: unmatched,
        includeDimensions: includeDimensions,
      );
    }
    final sortedPairs = pairs
        .sortedFileNameBy((pair) => pair.originalPath)
        .toList();
    final sortedUnmatched = unmatched
        .sortedFileNameBy((file) => file.filePath)
        .toList();
    return TranslationReplacementPlan(
      comicDirectory: comicDirectory,
      resultDirectories: resultDirectories
          .map((directory) => directory.path)
          .toSet(),
      pairs: sortedPairs,
      unmatched: sortedUnmatched,
    );
  }

  /// 应用计划；未匹配译图或替换失败时保留中间目录，方便用户重试。
  ///
  /// 未匹配原图表示该页无需翻译，不会阻止清理已经使用完的中间产物。
  Future<TranslationReplacementSummary> apply(
    TranslationReplacementPlan plan,
  ) async {
    final results = <TranslationReplacementResult>[];
    for (final pair in plan.pairs) {
      results.add(await _replaceOne(pair));
    }

    await _removeEmptyResultDirectories(plan.resultDirectories);
    final allSucceeded =
        results.isNotEmpty && results.every((result) => result.isSuccess);
    final resultDirectoriesRemoved = await _resultDirectoriesRemoved(
      plan.resultDirectories,
    );
    final hasUnmatchedTranslation = plan.unmatched.any(
      (file) => !file.isOriginal,
    );
    var intermediateDirectoriesCleaned = false;
    if (allSucceeded && !hasUnmatchedTranslation && resultDirectoriesRemoved) {
      await _removeIntermediateDirectories(plan.resultDirectories);
      intermediateDirectoriesCleaned = true;
    }
    return TranslationReplacementSummary(
      results: results,
      intermediateDirectoriesCleaned: intermediateDirectoriesCleaned,
    );
  }

  Future<Set<Directory>> _findResultDirectories(Directory rootDirectory) async {
    final resultDirectories = <Directory>{};
    await for (final entity in rootDirectory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! Directory ||
          path.basename(entity.path).toLowerCase() != resultDirectoryName) {
        continue;
      }
      if (_isInsideIgnoredDirectory(entity.path, rootDirectory.path)) continue;
      resultDirectories.add(entity);
    }
    return resultDirectories;
  }

  bool _isInsideIgnoredDirectory(String directoryPath, String rootPath) {
    var current = Directory(path.dirname(directoryPath));
    final normalizedRoot = path.normalize(rootPath);
    while (true) {
      final currentPath = path.normalize(current.path);
      if (path.equals(currentPath, normalizedRoot)) return false;
      final name = path.basename(currentPath).toLowerCase();
      if (name == resultDirectoryName ||
          _intermediateDirectoryNames.contains(name)) {
        return true;
      }
      final parentPath = path.dirname(currentPath);
      if (path.equals(parentPath, currentPath)) return false;
      current = Directory(parentPath);
    }
  }

  Future<void> _scanResultDirectory(
    Directory resultDirectory, {
    required List<TranslationReplacementPair> pairs,
    required List<TranslationUnmatchedFile> unmatched,
    required bool includeDimensions,
  }) async {
    final originals = await _readImages(resultDirectory.parent);
    final translations = await _readImages(resultDirectory);
    final originalByName = _groupByBaseName(originals);
    final translatedByName = _groupByBaseName(translations);
    final allNames = <String>{...originalByName.keys, ...translatedByName.keys};

    for (final name in allNames) {
      final originalFiles = originalByName[name] ?? const <File>[];
      final translatedFiles = translatedByName[name] ?? const <File>[];
      if (originalFiles.length == 1 && translatedFiles.length == 1) {
        final original = originalFiles.single;
        final translated = translatedFiles.single;
        pairs.add(
          TranslationReplacementPair(
            originalPath: original.path,
            translatedPath: translated.path,
            originalSize: await original.length(),
            translatedSize: await translated.length(),
            originalDimensions: includeDimensions
                ? await _readImageDimensions(original)
                : null,
            translatedDimensions: includeDimensions
                ? await _readImageDimensions(translated)
                : null,
          ),
        );
        continue;
      }
      _addUnmatched(
        originalFiles,
        isOriginal: true,
        reason: originalFiles.length > 1
            ? '同级目录中存在同名原图，无法确定替换目标'
            : 'result 中没有同名译图',
        unmatched: unmatched,
      );
      _addUnmatched(
        translatedFiles,
        isOriginal: false,
        reason: translatedFiles.length > 1
            ? 'result 中存在同名译图，无法确定替换目标'
            : '同级目录中没有同名原图',
        unmatched: unmatched,
      );
    }
  }

  Future<List<File>> _readImages(Directory directory) async {
    final files = <File>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) continue;
      final fileName = path.basename(entity.path).toLowerCase();
      if (fileName == 'cover.jpg' ||
          fileName == 'cover.jpeg' ||
          fileName == 'cover.png' ||
          fileName == 'cover.webp') {
        continue;
      }
      if (translationResultImageExtensions.contains(path.extension(fileName))) {
        files.add(entity);
      }
    }
    return files;
  }

  Map<String, List<File>> _groupByBaseName(List<File> files) {
    final result = <String, List<File>>{};
    for (final file in files) {
      final key = path.basenameWithoutExtension(file.path).toLowerCase();
      result.putIfAbsent(key, () => []).add(file);
    }
    return result;
  }

  void _addUnmatched(
    List<File> files, {
    required bool isOriginal,
    required String reason,
    required List<TranslationUnmatchedFile> unmatched,
  }) {
    for (final file in files) {
      unmatched.add(
        TranslationUnmatchedFile(
          filePath: file.path,
          isOriginal: isOriginal,
          reason: reason,
        ),
      );
    }
  }

  Future<TranslationImageDimensions?> _readImageDimensions(File file) async {
    try {
      final Uint8List bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      try {
        return TranslationImageDimensions(image.width, image.height);
      } finally {
        image.dispose();
        codec.dispose();
      }
    } catch (error, stackTrace) {
      Log.w('读取翻译图片尺寸失败: ${file.path}', error: error, stackTrace: stackTrace);
      return null;
    }
  }

  Future<TranslationReplacementResult> _replaceOne(
    TranslationReplacementPair pair,
  ) async {
    final original = File(pair.originalPath);
    final translated = File(pair.translatedPath);
    final destination = File(pair.destinationPath);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final extension = path.extension(destination.path);
    final stage = File(
      path.join(
        original.parent.path,
        '.${path.basenameWithoutExtension(destination.path)}.translation-stage-$stamp$extension',
      ),
    );
    final backup = File(
      path.join(
        original.parent.path,
        '.${path.basename(original.path)}.translation-backup-$stamp',
      ),
    );
    var originalMoved = false;
    var destinationWritten = false;

    try {
      if (!await original.exists()) throw StateError('原图已不存在');
      if (!await translated.exists()) throw StateError('译图已不存在');
      if (await destination.exists() &&
          !path.equals(destination.path, original.path)) {
        throw StateError('目标文件已存在：${path.basename(destination.path)}');
      }

      await translated.copy(stage.path);
      await original.rename(backup.path);
      originalMoved = true;
      await stage.rename(destination.path);
      destinationWritten = true;
      try {
        await backup.delete();
      } catch (error, stackTrace) {
        Log.w('清理原图备份失败: ${backup.path}', error: error, stackTrace: stackTrace);
      }
      try {
        await translated.delete();
      } catch (error, stackTrace) {
        Log.w(
          '清理已使用译图失败: ${translated.path}',
          error: error,
          stackTrace: stackTrace,
        );
      }
      return TranslationReplacementResult(pair: pair);
    } catch (error, stackTrace) {
      Log.e(
        '应用翻译结果失败: ${pair.originalPath}',
        error: error,
        stackTrace: stackTrace,
      );
      try {
        if (destinationWritten && await destination.exists()) {
          await destination.delete();
        }
        if (originalMoved && await backup.exists()) {
          await backup.rename(original.path);
        }
      } catch (restoreError, restoreStackTrace) {
        Log.e(
          '恢复原图失败: ${pair.originalPath}',
          error: restoreError,
          stackTrace: restoreStackTrace,
        );
      }
      return TranslationReplacementResult(pair: pair, error: error.toString());
    } finally {
      try {
        if (await stage.exists()) await stage.delete();
      } catch (error, stackTrace) {
        Log.w(
          '清理翻译临时文件失败: ${stage.path}',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
  }

  Future<void> _removeEmptyResultDirectories(
    Set<String> resultDirectories,
  ) async {
    for (final directoryPath in resultDirectories) {
      final directory = Directory(directoryPath);
      if (!await directory.exists()) continue;
      if (await directory.list(followLinks: false).isEmpty) {
        await directory.delete();
      }
    }
  }

  Future<void> _removeIntermediateDirectories(
    Set<String> resultDirectories,
  ) async {
    final parentDirectories = resultDirectories
        .map((directory) => path.dirname(directory))
        .toSet();
    for (final parentDirectory in parentDirectories) {
      for (final name in _intermediateDirectoryNames) {
        final directory = Directory(path.join(parentDirectory, name));
        if (await directory.exists()) await directory.delete(recursive: true);
      }
    }
  }

  Future<bool> _resultDirectoriesRemoved(Set<String> resultDirectories) async {
    for (final directoryPath in resultDirectories) {
      if (await Directory(directoryPath).exists()) return false;
    }
    return true;
  }
}
