// ignore_for_file: avoid_print

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:pica_comic/tools/io_extensions.dart';

const _comicsDirectoryName = 'comics';
const _coversDirectoryName = 'covers';
const _reservedRootDirectories = {_comicsDirectoryName, _coversDirectoryName};

/// 将旧版下载目录迁移到 comics/covers 目录结构。
///
/// 默认只执行扫描和预览。只有显式传入 --apply 才会移动文件。
/// 数据库只以只读方式加载，用于确认目录属于已登记的下载漫画。
/// 数据库和任务文件本身不会被写入、删除或移动。
Future<void> main(List<String> args) async {
  try {
    final options = _parseOptions(args);
    if (options.showHelp) {
      _printUsage();
      return;
    }

    final root = Directory(p.normalize(p.absolute(options.rootPath)));
    if (!await root.exists()) {
      throw StateError('下载目录不存在：${root.path}');
    }

    final database = _readDatabase(root);
    final plans = _buildPlans(root, database);
    final missingDatabaseDirectories = _findMissingDatabaseDirectories(
      root,
      database,
    );

    _printSummary(root, database, plans, missingDatabaseDirectories, options);
    if (!options.apply) {
      print('\n当前为预览模式，未移动任何文件。需要执行迁移时请加上 --apply。');
      return;
    }

    final result = await _applyPlans(root, plans);
    print(
      '\n迁移完成：移动漫画 ${result.comicsMoved} 个，'
      '移动封面 ${result.coversMoved} 个，'
      '跳过 ${result.skipped} 个，失败 ${result.failed} 个。',
    );
    print('数据库和任务文件未被修改。');
  } on FormatException catch (error) {
    stderr.writeln('参数错误：${error.message}');
    _printUsage();
    exitCode = 2;
  } catch (error) {
    stderr.writeln('迁移未执行：$error');
    exitCode = 1;
  }
}

class _Options {
  final String rootPath;
  final bool apply;
  final bool showHelp;
  final bool verbose;

  const _Options({
    required this.rootPath,
    required this.apply,
    required this.showHelp,
    required this.verbose,
  });
}

_Options _parseOptions(List<String> args) {
  if (args.contains('--help') || args.contains('-h')) {
    return const _Options(
      rootPath: '',
      apply: false,
      showHelp: true,
      verbose: false,
    );
  }

  String? rootPath;
  var apply = false;
  var dryRun = false;
  var verbose = false;
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--root') {
      if (i + 1 >= args.length) {
        throw const FormatException('--root 缺少目录路径');
      }
      rootPath = args[++i];
    } else if (arg == '--apply') {
      apply = true;
    } else if (arg == '--dry-run') {
      dryRun = true;
    } else if (arg == '--verbose') {
      verbose = true;
    } else {
      throw FormatException('无法识别参数：$arg');
    }
  }

  if (rootPath == null || rootPath.trim().isEmpty) {
    throw const FormatException('必须提供 --root <下载目录>');
  }
  if (apply && dryRun) {
    throw const FormatException('--apply 和 --dry-run 不能同时使用');
  }

  return _Options(
    rootPath: rootPath,
    apply: apply,
    showHelp: false,
    verbose: verbose,
  );
}

void _printUsage() {
  print('用法：');
  print('  fvm dart run scripts/migrate_download_layout.dart --root <下载目录>');
  print(
    '  fvm dart run scripts/migrate_download_layout.dart '
    '--root <下载目录> --apply',
  );
  print(
    '  fvm dart run scripts/migrate_download_layout.dart '
    '--root <下载目录> --verbose',
  );
  print('\n默认是预览模式；--apply 才会移动文件。');
  print('--verbose 可显示每个将要执行的移动操作。');
}

/// 只读加载数据库中的网络下载目录。
///
/// 数据库中的下载类型没有单独字段，应用根据 ID 推断来源类型。
/// 这里复用同样的判断顺序，只把网络漫画加入迁移白名单；本地漫画和
/// kemono 附件不属于下载根目录迁移范围。
_DatabaseSnapshot _readDatabase(Directory root) {
  final databaseFile = File(p.join(root.path, 'download.db'));
  if (!databaseFile.existsSync()) {
    throw StateError('数据库文件不存在：${databaseFile.path}');
  }

  try {
    // sqflite_common_ffi 会定位项目依赖中自带的 Windows sqlite3.dll。
    sqfliteFfiInit();
    final database = sqlite3.open(databaseFile.path, mode: OpenMode.readOnly);
    try {
      final rows = database.select('SELECT id, directory FROM download');
      final records = <String, _DownloadRecord>{};
      var eligibleRows = 0;
      for (final row in rows) {
        final id = row['id']?.toString() ?? '';
        final directory = row['directory']?.toString() ?? '';
        final sourceKey = _inferDatabaseSourceKey(id);
        if (sourceKey == null || directory.trim().isEmpty) continue;

        eligibleRows++;
        records[directory] = _DownloadRecord(
          id: id,
          directory: directory,
          sourceKey: sourceKey,
        );
      }
      return _DatabaseSnapshot(
        totalRows: rows.length,
        eligibleRows: eligibleRows,
        recordsByDirectory: records,
      );
    } finally {
      database.dispose();
    }
  } catch (error) {
    throw StateError('无法以只读方式打开数据库：$error');
  }
}

String? _inferDatabaseSourceKey(String id) {
  if (id.isEmpty || id.startsWith('LC')) return null;
  if (id.startsWith('kemono-attachment-')) return null;
  if (id.contains('-')) return 'other';
  if (id.startsWith('jm')) return 'jm';
  if (id.startsWith('hitomi')) return 'hitomi';
  if (id.startsWith('nhentai')) return 'nhentai';
  if (id.startsWith('Ht')) return 'htmanga';
  if (RegExp(r'^\d+$').hasMatch(id)) return 'ehentai';
  return 'picacg';
}

List<_MigrationPlan> _buildPlans(Directory root, _DatabaseSnapshot database) {
  final comicsRoot = Directory(p.join(root.path, _comicsDirectoryName));
  final coversRoot = Directory(p.join(root.path, _coversDirectoryName));
  final plans = <_MigrationPlan>[];

  for (final entity in root.listSync().whereType<Directory>()) {
    if (_reservedRootDirectories.contains(entity.name)) continue;

    final record = database.recordsByDirectory[entity.name];
    if (record == null) {
      plans.add(
        _MigrationPlan.skipped(
          record: _DownloadRecord(
            id: '',
            directory: entity.name,
            sourceKey: null,
          ),
          reason: '数据库中没有对应的 download.directory 记录，保持原位置',
        ),
      );
      continue;
    }

    final parsedDirectory = _parseLegacyDirectoryName(entity.name);
    if (parsedDirectory != null &&
        parsedDirectory.sourceKey != record.sourceKey) {
      plans.add(
        _MigrationPlan.skipped(
          record: record,
          reason:
              '目录类型 ${parsedDirectory.sourceKey} 与数据库类型 '
              '${record.sourceKey} 不一致，避免误移动而跳过',
        ),
      );
      continue;
    }

    final sourcePath = entity.path;
    final targetPath = p.join(comicsRoot.path, entity.name);
    final targetExists = Directory(targetPath).existsSync();
    if (targetExists) {
      plans.add(
        _MigrationPlan.skipped(
          record: record,
          reason: '旧目录和 comics 目录同时存在，避免覆盖而跳过',
        ),
      );
      continue;
    }

    final coverTarget = File(
      p.join(
        coversRoot.path,
        buildDownloadCoverFileName(sourceKey: record.sourceKey!, id: record.id),
      ),
    );
    final legacyCover = _findLegacyCover(sourcePath);

    plans.add(
      _MigrationPlan(
        record: record,
        sourcePath: sourcePath,
        targetPath: targetPath,
        coverTarget: coverTarget.path,
        legacyCoverPath: legacyCover?.path,
        skippedReason: null,
      ),
    );
  }
  return plans;
}

List<_DownloadRecord> _findMissingDatabaseDirectories(
  Directory root,
  _DatabaseSnapshot database,
) {
  final existingDirectories = <String>{
    ...root.listSync().whereType<Directory>().map((entity) => entity.name),
  };
  final comicsRoot = Directory(p.join(root.path, _comicsDirectoryName));
  if (comicsRoot.existsSync()) {
    existingDirectories.addAll(
      comicsRoot.listSync().whereType<Directory>().map((entity) => entity.name),
    );
  }

  return database.recordsByDirectory.values
      .where((record) => !existingDirectories.contains(record.directory))
      .toList();
}

File? _findLegacyCover(String comicPath) {
  const extensions = ['webp', 'jpg', 'jpeg', 'png'];
  for (final extension in extensions) {
    final file = File(p.join(comicPath, 'cover.$extension'));
    if (file.existsSync()) return file;
  }
  return null;
}

_LegacyDirectoryInfo? _parseLegacyDirectoryName(String directory) {
  final match = RegExp(r'^\[([^\]]+)\]\[([^\]]+)\]').firstMatch(directory);
  if (match == null) return null;

  final sourceKey = match.group(1)!;
  if (!_sourceKeys.contains(sourceKey)) return null;
  return _LegacyDirectoryInfo(sourceKey: sourceKey, id: match.group(2)!);
}

const _sourceKeys = {
  'picacg',
  'ehentai',
  'jm',
  'hitomi',
  'htmanga',
  'nhentai',
  'other',
};

void _printSummary(
  Directory root,
  _DatabaseSnapshot database,
  List<_MigrationPlan> plans,
  List<_DownloadRecord> missingDatabaseDirectories,
  _Options options,
) {
  final actionPlans = plans.where((plan) => !plan.isSkipped).toList();
  final skippedPlans = plans.where((plan) => plan.isSkipped).toList();
  final orphanPlans = skippedPlans.where(
    (plan) => plan.record.sourceKey == null,
  );
  final missingCovers = actionPlans
      .where((plan) => plan.legacyCoverPath == null)
      .length;
  final coverConflicts = actionPlans
      .where((plan) => File(plan.coverTarget).existsSync())
      .length;

  print('${options.apply ? '执行' : '预览'}下载目录迁移：${root.path}');
  print('数据库 download.db 以只读方式加载，newDownload.json 不会读取或修改。');
  print(
    '数据库记录：${database.totalRows} 条，'
    '参与迁移白名单：${database.eligibleRows} 条，'
    '唯一目录：${database.recordsByDirectory.length} 条。',
  );
  print(
    '扫描到的根目录：${plans.length} 个，'
    '数据库登记且可处理：${actionPlans.length} 个，'
    '跳过：${skippedPlans.length} 个。',
  );
  print(
    '可移动封面：${actionPlans.length - missingCovers} 个，'
    '未找到封面：$missingCovers 个，'
    '封面目标冲突：$coverConflicts 个。',
  );
  print(
    '数据库登记但当前根目录和 comics 中均不存在的目录：'
    '${missingDatabaseDirectories.length} 个。',
  );

  if (missingDatabaseDirectories.isNotEmpty) {
    for (final record in missingDatabaseDirectories) {
      print('[数据库缺目录] ${record.id}: ${record.directory}');
    }
  }
  if (orphanPlans.isNotEmpty) {
    print('数据库没有记录、因此保持原位置的根目录：${orphanPlans.length} 个。');
    for (final plan in orphanPlans) {
      print('[保留] ${plan.record.directory}: ${plan.skippedReason}');
    }
  }

  if (options.verbose) {
    for (final plan in actionPlans) {
      print('[移动] ${plan.sourcePath} -> ${plan.targetPath}');
      final legacyCover = plan.legacyCoverPath;
      if (legacyCover == null) {
        print('[提示] ${plan.record.id}: 未找到 cover.webp/jpg/jpeg/png');
      } else if (File(plan.coverTarget).existsSync()) {
        print('[冲突] $legacyCover -> ${plan.coverTarget}（目标已存在，保留原文件）');
      } else {
        print('[移动] $legacyCover -> ${plan.coverTarget}');
      }
    }
  } else {
    print('如需查看每个移动路径，请追加 --verbose。');
  }
}

Future<_MigrationResult> _applyPlans(
  Directory root,
  List<_MigrationPlan> plans,
) async {
  final comicsRoot = Directory(p.join(root.path, _comicsDirectoryName));
  final coversRoot = Directory(p.join(root.path, _coversDirectoryName));
  await comicsRoot.create(recursive: true);
  await coversRoot.create(recursive: true);

  var comicsMoved = 0;
  var coversMoved = 0;
  var skipped = plans.where((plan) => plan.isSkipped).length;
  var failed = 0;

  for (final plan in plans.where((plan) => !plan.isSkipped)) {
    try {
      final sourceDirectory = Directory(plan.sourcePath);
      final targetDirectory = Directory(plan.targetPath);
      if (await sourceDirectory.exists()) {
        if (await targetDirectory.exists()) {
          print('[跳过] ${plan.record.id}: comics 目标已存在，未覆盖');
          skipped++;
          continue;
        }
        await sourceDirectory.rename(plan.targetPath);
        comicsMoved++;
      }

      final legacyCover = _findLegacyCover(plan.targetPath);
      if (legacyCover == null) continue;

      final coverTarget = File(plan.coverTarget);
      if (await coverTarget.exists()) {
        print('[冲突] ${plan.record.id}: 集中封面已存在，保留原封面');
        skipped++;
        continue;
      }
      await legacyCover.rename(coverTarget.path);
      coversMoved++;
    } catch (error) {
      failed++;
      print('[失败] ${plan.record.id}: $error');
    }
  }

  return _MigrationResult(
    comicsMoved: comicsMoved,
    coversMoved: coversMoved,
    skipped: skipped,
    failed: failed,
  );
}

class _DatabaseSnapshot {
  final int totalRows;
  final int eligibleRows;
  final Map<String, _DownloadRecord> recordsByDirectory;

  const _DatabaseSnapshot({
    required this.totalRows,
    required this.eligibleRows,
    required this.recordsByDirectory,
  });
}

class _DownloadRecord {
  final String id;
  final String directory;
  final String? sourceKey;

  const _DownloadRecord({
    required this.id,
    required this.directory,
    required this.sourceKey,
  });
}

class _LegacyDirectoryInfo {
  final String sourceKey;
  final String id;

  const _LegacyDirectoryInfo({required this.sourceKey, required this.id});
}

class _MigrationPlan {
  final _DownloadRecord record;
  final String sourcePath;
  final String targetPath;
  final String coverTarget;
  final String? legacyCoverPath;
  final String? skippedReason;

  const _MigrationPlan({
    required this.record,
    required this.sourcePath,
    required this.targetPath,
    required this.coverTarget,
    required this.legacyCoverPath,
    required this.skippedReason,
  });

  _MigrationPlan.skipped({required this.record, required String reason})
    : sourcePath = '',
      targetPath = '',
      coverTarget = '',
      legacyCoverPath = null,
      skippedReason = reason;

  bool get isSkipped => skippedReason != null;
}

class _MigrationResult {
  final int comicsMoved;
  final int coversMoved;
  final int skipped;
  final int failed;

  const _MigrationResult({
    required this.comicsMoved,
    required this.coversMoved,
    required this.skipped,
    required this.failed,
  });
}
