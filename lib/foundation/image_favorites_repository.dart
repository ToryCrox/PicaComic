import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:synchronized/synchronized.dart';

import '../tools/webp_thumbnail_encoder.dart';
import '../tools/type_util.dart';
import 'image_favorites.dart';
import 'log.dart';

/// 下载目录中的收藏库；数据库操作、删除及目录迁移共享同一把锁。
class ImageFavoritesRepository {
  ImageFavoritesRepository({
    required this.rootPath,
    required this.comicDirectory,
    required this.ensureReady,
    WebpThumbnailEncoder? encoder,
  }) : encoder = encoder ?? WebpThumbnailEncoder();

  final String Function() rootPath;
  final Future<String> Function(String id) comicDirectory;
  final Future<void> Function() ensureReady;
  final WebpThumbnailEncoder encoder;
  final Lock _lock = Lock();
  final Lock _rootLock = Lock();
  final _changes = StreamController<void>.broadcast();
  final _thumbnails = <String, Future<File>>{};
  Database? _db;
  String? _openedRoot;
  Future<void>? _pause;
  Future<void>? _thumbnailPause;
  bool _disposed = false;

  /// 收藏内容或缩略图发生变化的通知。
  Stream<void> get changes => _changes.stream;

  /// 与一次性迁移工具共用的新格式数据库结构。
  static const createTableSql = '''
    CREATE TABLE image_favorites (
      record_id TEXT PRIMARY KEY,
      source_key TEXT NOT NULL,
      comic_id TEXT NOT NULL,
      title TEXT NOT NULL,
      ep INTEGER NOT NULL,
      page INTEGER NOT NULL,
      storage TEXT NOT NULL CHECK(storage IN ('download','standalone')),
      download_id TEXT NOT NULL DEFAULT '',
      image_path TEXT NOT NULL,
      image_url TEXT NOT NULL DEFAULT '',
      other TEXT NOT NULL,
      UNIQUE(source_key,comic_id,ep,page),
      CHECK((storage='download' AND download_id<>'') OR
            (storage='standalone' AND download_id=''))
    )
  ''';

  /// 校验相对路径并统一使用 POSIX 格式持久化。
  static String relativePath(String value) {
    final normalized = path.posix.normalize(value.replaceAll('\\', '/'));
    if (value.isEmpty ||
        path.windows.isAbsolute(value) ||
        path.posix.isAbsolute(value) ||
        normalized == '..' ||
        normalized.startsWith('../') ||
        normalized.contains(':')) {
      throw ArgumentError('收藏文件必须使用有效相对路径');
    }
    return normalized;
  }

  /// 移除阅读元数据中的本机位置；网络地址可以保留。
  static dynamic portableMetadata(dynamic value) {
    if (value is String &&
        (value.startsWith('file://') ||
            path.windows.isAbsolute(value) ||
            path.posix.isAbsolute(value))) {
      return null;
    }
    if (value is Map) {
      return <String, dynamic>{
        for (final entry in value.entries)
          if (portableMetadata(entry.key.toString()) != null &&
              portableMetadata(entry.value) != null)
            entry.key.toString(): portableMetadata(entry.value),
      };
    }
    if (value is List) {
      return value.map(portableMetadata).where((e) => e != null).toList();
    }
    return value;
  }

  /// 等待目录迁移完成后串行访问收藏数据。
  Future<T> _access<T>(Future<T> Function() action) async {
    while (true) {
      await _pause;
      await ensureReady();
      final result = await _lock.synchronized(() async {
        // 等待锁期间可能开始迁移，释放锁后等待，不能在锁内等待迁移。
        if (_pause != null) return null;
        return _RepositoryResult(await action());
      });
      if (result != null) return result.value;
    }
  }

  /// 按当前有效下载目录打开数据库，切换目录后不复用旧连接。
  Future<Database> _database() async {
    if (_disposed) throw StateError('收藏仓库已关闭');
    final root = path.normalize(rootPath());
    if (_db != null && _openedRoot == root) return _db!;
    await _db?.close();
    await Directory(
      path.join(root, 'image_favorites', 'originals'),
    ).create(recursive: true);
    await Directory(
      path.join(root, 'image_favorites', 'thumbnails'),
    ).create(recursive: true);
    _db = await databaseFactory.openDatabase(
      path.join(root, 'image_favorites.db'),
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute(createTableSql);
          await db.execute(
            'CREATE INDEX image_favorites_title ON image_favorites(title)',
          );
          await db.execute(
            'CREATE INDEX image_favorites_download ON image_favorites(download_id)',
          );
        },
      ),
    );
    _openedRoot = root;
    return _db!;
  }

  /// 获取收藏列表，默认保持插入顺序。
  Future<List<ImageFavorite>> getAll() => _access(() async {
    final db = await _database();
    return (await db.query(
      'image_favorites',
      orderBy: 'rowid',
    )).map(ImageFavorite.fromRow).toList();
  });

  /// 获取单条收藏。
  Future<ImageFavorite?> find(String recordId) =>
      _access(() => _find(recordId));

  Future<ImageFavorite?> _find(String recordId) async {
    final rows = await (await _database()).query(
      'image_favorites',
      where: 'record_id=?',
      whereArgs: [recordId],
    );
    return rows.isEmpty ? null : ImageFavorite.fromRow(rows.single);
  }

  /// 保存加载完成的原图；只有文件位于对应下载漫画目录才保存引用。
  Future<ImageFavorite> add(
    ImageFavorite draft,
    File source, {
    String downloadId = '',
  }) => _access(() async {
    final db = await _database();
    final existing = await _find(draft.recordId);
    if (existing != null) return existing;
    if (!await source.exists()) throw StateError('收藏原图不存在');
    final directory = downloadId.isEmpty
        ? ''
        : await comicDirectory(downloadId);
    final isDownload =
        directory.isNotEmpty && path.isWithin(directory, source.path);
    final destination = File(
      path.join(
        rootPath(),
        'image_favorites',
        'originals',
        '${draft.recordId}${path.extension(source.path).toLowerCase()}',
      ),
    );
    final metadata = TypeUtil.parseMap(portableMetadata(draft.otherInfo));
    metadata.remove('url');
    final favorite = ImageFavorite(
      sourceKey: draft.sourceKey,
      comicId: draft.comicId,
      title: draft.title,
      ep: draft.ep,
      page: draft.page,
      otherInfo: metadata,
      storage: isDownload
          ? ImageFavoriteStorage.download
          : ImageFavoriteStorage.standalone,
      downloadId: isDownload ? downloadId : '',
      imagePath: relativePath(
        isDownload
            ? path.relative(source.path, from: directory)
            : path.relative(
                destination.path,
                from: path.join(rootPath(), 'image_favorites'),
              ),
      ),
      imageUrl:
          draft.imageUrl.startsWith('http://') ||
              draft.imageUrl.startsWith('https://')
          ? draft.imageUrl
          : '',
    );
    try {
      if (!isDownload) await _copy(source, destination);
      await db.insert('image_favorites', favorite.toRow());
    } catch (_) {
      if (!isDownload && await destination.exists()) await destination.delete();
      rethrow;
    }
    _notify();
    return favorite;
  });

  /// 解析最新记录的原图，目录重命名及转存后不使用过期记录。
  Future<File> originalFile(ImageFavorite favorite) => _access(() async {
    final current = await _find(favorite.recordId);
    if (current == null) throw StateError('图片收藏已删除');
    return _original(current);
  });

  Future<File> _original(ImageFavorite favorite) async {
    final relative = relativePath(favorite.imagePath);
    final base = favorite.storage == ImageFavoriteStorage.download
        ? await comicDirectory(favorite.downloadId)
        : path.join(rootPath(), 'image_favorites');
    if (base.isEmpty) throw StateError('收藏对应的下载记录不存在');
    final file = File(path.joinAll([base, ...relative.split('/')]));
    if (!await file.exists()) throw StateError('收藏原图不存在');
    return file;
  }

  /// 取消收藏；绝不删除下载漫画原图。
  Future<void> delete(String recordId) => _access(() async {
    final favorite = await _find(recordId);
    if (favorite == null) return;
    await (await _database()).delete(
      'image_favorites',
      where: 'record_id=?',
      whereArgs: [recordId],
    );
    if (favorite.storage == ImageFavoriteStorage.standalone) {
      await _remove(
        File(
          path.joinAll([
            rootPath(),
            'image_favorites',
            ...relativePath(favorite.imagePath).split('/'),
          ]),
        ),
      );
    }
    await _remove(_thumbnailFile(recordId));
    _notify();
  });

  /// 删除下载前转存所有关联原图；与实际删除共享锁，避免新收藏插入。
  Future<T> preservingDownload<T>(
    String id,
    Future<T> Function() action, {
    String? episodeDirectory,
  }) => _access(() async {
    final db = await _database();
    final rows = await db.query(
      'image_favorites',
      where: 'download_id=?',
      whereArgs: [id],
    );
    final converted = <ImageFavorite>[];
    final copied = <File>[];
    try {
      for (final row in rows) {
        final favorite = ImageFavorite.fromRow(row);
        final relative = relativePath(favorite.imagePath);
        if (episodeDirectory != null &&
            !relative.startsWith('${relativePath(episodeDirectory)}/')) {
          continue;
        }
        final original = await _original(favorite);
        final destination = File(
          path.join(
            rootPath(),
            'image_favorites',
            'originals',
            '${favorite.recordId}${path.extension(original.path)}',
          ),
        );
        await _copy(original, destination);
        copied.add(destination);
        converted.add(
          favorite.copyWith(
            storage: ImageFavoriteStorage.standalone,
            downloadId: '',
            imagePath: 'originals/${path.basename(destination.path)}',
          ),
        );
      }
      await db.transaction((txn) async {
        for (final favorite in converted) {
          await txn.update(
            'image_favorites',
            favorite.toRow(),
            where: 'record_id=?',
            whereArgs: [favorite.recordId],
          );
        }
      });
    } catch (_) {
      for (final file in copied) {
        await _remove(file);
      }
      rethrow;
    }
    if (converted.isNotEmpty) _notify();
    return action();
  });

  /// 缩略图每次请求检查磁盘，丢失或损坏时重建，同一记录共享任务。
  Future<File> thumbnail(ImageFavorite favorite) async {
    await _thumbnailPause;
    while (_thumbnailPause != null) {
      await _thumbnailPause;
    }
    final key = '${rootPath()}/${favorite.recordId}';
    final pending = _thumbnails[key];
    if (pending != null) return pending;
    final task = _buildThumbnail(favorite);
    _thumbnails[key] = task;
    try {
      return await task;
    } finally {
      _thumbnails.remove(key);
    }
  }

  Future<File> _buildThumbnail(ImageFavorite favorite) async {
    final original = await originalFile(favorite);
    final target = _thumbnailFile(favorite.recordId);
    if (await WebpThumbnailEncoder.isValid(target)) return target;
    final temporary = File('${target.path}.tmp');
    await encoder.encode(original, temporary);
    // 原图可能在生成期间被取消收藏；不留下孤立缓存。
    return _access(() async {
      if (await _find(favorite.recordId) == null) {
        await _remove(temporary);
        throw StateError('图片收藏已删除');
      }
      await _remove(target);
      await temporary.rename(target.path);
      return target;
    });
  }

  File _thumbnailFile(String id) =>
      File(path.join(rootPath(), 'image_favorites', 'thumbnails', '$id.webp'));

  /// 后台生成失败仅记录日志，不影响收藏成功结果。
  Future<void> prepareThumbnail(ImageFavorite favorite) async {
    try {
      await thumbnail(favorite);
    } catch (error, stack) {
      Log.w('生成收藏缩略图失败：$error');
      Log.d('$stack');
    }
  }

  /// 清理可重建的缩略图；不接触原图和数据库。
  Future<void> clearThumbnails() async {
    await Future.wait(
      _thumbnails.values.map((task) async {
        try {
          await task;
        } catch (_) {}
      }),
    );
    await _access(() async {
      final directory = Directory(
        path.join(rootPath(), 'image_favorites', 'thumbnails'),
      );
      if (await directory.exists()) {
        await for (final file in directory.list()) {
          if (file is File) await file.delete();
        }
      }
      _notify();
    });
  }

  /// 只删除这一条收藏的缩略图，随后由可见卡片重新生成。
  Future<void> regenerateThumbnail(ImageFavorite favorite) async {
    final pending = _thumbnails['${rootPath()}/${favorite.recordId}'];
    if (pending != null) {
      try {
        await pending;
      } catch (_) {}
    }
    await _access(() async {
      await _remove(_thumbnailFile(favorite.recordId));
      _notify();
    });
  }

  /// 等待缩略图任务结束，关闭连接，并在目录操作期间阻止新访问。
  Future<T> changingRoot<T>(Future<T> Function() action) =>
      _rootLock.synchronized(() => _changeRoot(action));

  /// 串行切换根目录，先排空正在编码的任务再关闭数据库。
  Future<T> _changeRoot<T>(Future<T> Function() action) async {
    await _thumbnailPause;
    final resumed = Completer<void>();
    // 先阻止新生成任务，已有任务仍能完成最后的数据库检查。
    _thumbnailPause = resumed.future;
    try {
      await Future.wait(
        _thumbnails.values.toList().map((task) async {
          try {
            await task;
          } catch (_) {}
        }),
      );
      _pause = resumed.future;
      return await _lock.synchronized(() async {
        await _db?.close();
        _db = null;
        _openedRoot = null;
        return action();
      });
    } finally {
      _pause = null;
      _thumbnailPause = null;
      resumed.complete();
      _notify();
    }
  }

  /// 原子复制原图，失败时清理不完整临时文件。
  Future<void> _copy(File source, File destination) async {
    final temporary = File('${destination.path}.tmp');
    await destination.parent.create(recursive: true);
    try {
      await source.copy(temporary.path);
      if (await source.length() != await temporary.length()) {
        throw StateError('收藏图片复制不完整');
      }
      await temporary.rename(destination.path);
    } finally {
      await _remove(temporary);
    }
  }

  Future<void> _remove(File file) async {
    if (await file.exists()) await file.delete();
  }

  void _notify() {
    if (!_disposed) _changes.add(null);
  }

  /// 释放数据库与通知资源。
  Future<void> dispose() async {
    await changingRoot(() async {
      _disposed = true;
    });
    await _changes.close();
  }
}

/// 区分迁移期间的重试与可空业务返回值。
class _RepositoryResult<T> {
  const _RepositoryResult(this.value);
  final T value;
}
