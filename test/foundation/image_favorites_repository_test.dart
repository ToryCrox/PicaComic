import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:path/path.dart' as path;
import 'package:pica_comic/foundation/image_favorites.dart';
import 'package:pica_comic/foundation/image_favorites_repository.dart';
import 'package:pica_comic/tools/download_directory_migration.dart';
import 'package:pica_comic/tools/webp_thumbnail_encoder.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 创建不含本机路径的收藏草稿。
ImageFavorite draft(String comicId, {int page = 1, int ep = 1}) =>
    ImageFavorite(
      sourceKey: 'test',
      comicId: comicId,
      title: '测试漫画',
      ep: ep,
      page: page,
      imagePath: '',
      imageUrl: 'https://example.com/image.jpg',
      otherInfo: const {
        'eps': ['one'],
        'url': 'file://C:/old/image.jpg',
        'nested': {'path': 'C:\\old\\comic', 'link': 'https://example.com'},
      },
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Directory workspace;
  late String root;
  late ImageFavoritesRepository repository;
  final directories = <String, String>{};

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('pica_image_favorites_');
    root = path.join(workspace.path, '下载目录');
    directories.clear();
    repository = ImageFavoritesRepository(
      rootPath: () => root,
      comicDirectory: (id) async => directories[id] ?? '',
      ensureReady: () async {},
    );
  });
  tearDown(() async {
    await repository.dispose();
    await workspace.delete(recursive: true);
  });

  /// 在测试目录生成文件。
  Future<File> file(String relative, List<int> bytes) async {
    final result = File(path.join(root, relative));
    await result.parent.create(recursive: true);
    return result.writeAsBytes(bytes);
  }

  test('下载引用使用真实文件名，删除收藏不删除下载原图', () async {
    directories['download-id'] = path.join(root, 'comics', '漫画');
    final original = await file('comics/漫画/11/33 %.webp', [1, 2, 3]);
    final favorite = await repository.add(
      draft('comic', ep: 11),
      original,
      downloadId: 'download-id',
    );
    expect(favorite.storage, ImageFavoriteStorage.download);
    expect(favorite.downloadId, 'download-id');
    expect(favorite.imagePath, '11/33 %.webp');
    expect(
      (await repository.originalFile(favorite)).path,
      path.normalize(original.path),
    );
    expect(favorite.otherInfo, {
      'eps': ['one'],
      'nested': {'link': 'https://example.com'},
    });
    await repository.delete(favorite.recordId);
    expect(await original.exists(), isTrue);
    expect(await repository.getAll(), isEmpty);
  });

  test('独立图片同名不覆盖，重复收藏不新增文件', () async {
    final first = await file('cache/a/33.webp', [1, 2]);
    final second = await file('cache/b/33.webp', [3, 4]);
    final a = await repository.add(draft('a'), first);
    final b = await repository.add(draft('b'), second);
    await repository.add(draft('a'), second);
    expect(a.imagePath, isNot(b.imagePath));
    expect(await (await repository.originalFile(a)).readAsBytes(), [1, 2]);
    expect(await (await repository.originalFile(b)).readAsBytes(), [3, 4]);
    expect((await repository.getAll()).length, 2);
    await repository.delete(a.recordId);
    expect(await (await repository.originalFile(b)).exists(), isTrue);
  });

  test('已下载漫画中的未下载图片仍保存独立副本', () async {
    directories['comic'] = path.join(root, 'comics', '漫画');
    final cache = await file('cache/image.jpg', [1]);
    final favorite = await repository.add(
      draft('a'),
      cache,
      downloadId: 'comic',
    );
    expect(favorite.storage, ImageFavoriteStorage.standalone);
    expect(favorite.downloadId, isEmpty);
    expect(favorite.imageUrl, 'https://example.com/image.jpg');
  });

  test('删除下载前转存原图，旧记录也能解析新的独立文件', () async {
    final directory = path.join(root, 'comics', '漫画');
    directories['comic'] = directory;
    final original = await file('comics/漫画/1/0.webp', [1, 3, 5]);
    final favorite = await repository.add(
      draft('a'),
      original,
      downloadId: 'comic',
    );
    await repository.preservingDownload('comic', () async {
      await Directory(directory).delete(recursive: true);
      directories.remove('comic');
    });
    expect(
      (await repository.getAll()).single.storage,
      ImageFavoriteStorage.standalone,
    );
    expect(await (await repository.originalFile(favorite)).readAsBytes(), [
      1,
      3,
      5,
    ]);
  });

  test('章节转存只处理指定章节，相邻章节继续保留下载引用', () async {
    directories['comic'] = path.join(root, 'comics', '漫画');
    final first = await file('comics/漫画/chapter-a/0.webp', [1]);
    final second = await file('comics/漫画/chapter-b/0.webp', [2]);
    await repository.add(draft('a', ep: 1), first, downloadId: 'comic');
    await repository.add(draft('a', ep: 2), second, downloadId: 'comic');
    await repository.preservingDownload(
      'comic',
      () async => first.delete(),
      episodeDirectory: 'chapter-a',
    );
    final records = await repository.getAll();
    expect(records[0].storage, ImageFavoriteStorage.standalone);
    expect(records[1].storage, ImageFavoriteStorage.download);
  });

  test('任一原图转存失败，不执行下载删除且回滚转存文件', () async {
    directories['comic'] = path.join(root, 'comics', '漫画');
    final first = await file('comics/漫画/1.webp', [1]);
    final second = await file('comics/漫画/2.webp', [2]);
    await repository.add(draft('a', page: 1), first, downloadId: 'comic');
    await repository.add(draft('a', page: 2), second, downloadId: 'comic');
    await second.delete();
    var deleted = false;
    await expectLater(
      repository.preservingDownload('comic', () async {
        deleted = true;
      }),
      throwsStateError,
    );
    expect(deleted, isFalse);
    expect(
      (await repository.getAll()).every(
        (record) => record.storage == ImageFavoriteStorage.download,
      ),
      isTrue,
    );
    expect(
      await Directory(
        path.join(root, 'image_favorites', 'originals'),
      ).list().isEmpty,
      isTrue,
    );
  });

  test('下载目录迁移后重新打开新库，取消收藏写入新位置', () async {
    final original = await file('cache/image.jpg', [1, 4]);
    final favorite = await repository.add(draft('a'), original);
    final previous = root;
    final next = path.join(workspace.path, '新目录');
    await repository.changingRoot(() async {
      await copyDownloadDirectory(Directory(previous), Directory(next));
      root = next;
    });
    expect(await (await repository.originalFile(favorite)).readAsBytes(), [
      1,
      4,
    ]);
    await repository.delete(favorite.recordId);
    expect(await repository.getAll(), isEmpty);
    final oldDb = await databaseFactory.openDatabase(
      path.join(previous, 'image_favorites.db'),
    );
    expect((await oldDb.query('image_favorites')).length, 1);
    await oldDb.close();
  });

  test('目录重命名后引用自动解析新目录', () async {
    final oldDirectory = path.join(root, 'comics', '旧名');
    directories['comic'] = oldDirectory;
    final original = await file('comics/旧名/0.webp', [5]);
    final favorite = await repository.add(
      draft('a'),
      original,
      downloadId: 'comic',
    );
    final next = path.join(root, 'comics', '新名');
    await Directory(oldDirectory).rename(next);
    directories['comic'] = next;
    expect(await (await repository.originalFile(favorite)).readAsBytes(), [5]);
  });

  test('拒绝绝对地址、越界路径和 Windows 盘符', () {
    for (final invalid in [
      'C:\\images\\1.jpg',
      '/images/1.jpg',
      '../1.jpg',
      'file://x',
      'a/../../x',
    ]) {
      expect(
        () => ImageFavoritesRepository.relativePath(invalid),
        throwsArgumentError,
      );
    }
    expect(ImageFavoritesRepository.relativePath('1\\19.webp'), '1/19.webp');
  });

  test('缩略图被删除或损坏后自动重建，同一收藏不重复生成', () async {
    final bytes = image.encodePng(image.Image(width: 180, height: 320));
    final original = await file('cache/image.png', bytes);
    final favorite = await repository.add(draft('a'), original);
    final results = await Future.wait([
      repository.thumbnail(favorite),
      repository.thumbnail(favorite),
    ]);
    expect(results[0].path, results[1].path);
    expect(await WebpThumbnailEncoder.isValid(results[0]), isTrue);
    await results[0].delete();
    final regenerated = await repository.thumbnail(favorite);
    expect(await WebpThumbnailEncoder.isValid(regenerated), isTrue);
    await regenerated.writeAsBytes([1, 2, 3]);
    expect(
      await WebpThumbnailEncoder.isValid(await repository.thumbnail(favorite)),
      isTrue,
    );
    await repository.clearThumbnails();
    expect(await regenerated.exists(), isFalse);
    expect(await (await repository.originalFile(favorite)).exists(), isTrue);
    expect((await repository.getAll()).length, 1);
  }, skip: !Platform.isWindows);

  test('写入数据库失败时删除独立副本，原文件保持完整', () async {
    await repository.getAll();
    final db = await databaseFactory.openDatabase(
      path.join(root, 'image_favorites.db'),
    );
    await db.execute(
      "CREATE TRIGGER reject_favorite BEFORE INSERT ON image_favorites BEGIN SELECT RAISE(ABORT,'test'); END",
    );
    final original = await file('cache/source.jpg', [1, 3]);
    await expectLater(
      repository.add(draft('a'), original),
      throwsA(isA<DatabaseException>()),
    );
    expect(await original.readAsBytes(), [1, 3]);
    expect(
      await Directory(
        path.join(root, 'image_favorites', 'originals'),
      ).list().isEmpty,
      isTrue,
    );
    expect(await repository.getAll(), isEmpty);
  });

  test('目录迁移失败恢复连接，原收藏与原文件仍可访问', () async {
    final original = await file('cache/source.jpg', [3, 7]);
    final favorite = await repository.add(draft('a'), original);
    final target = Directory(path.join(workspace.path, '目标'));
    await target.create();
    await File(path.join(target.path, 'existing.txt')).writeAsString('不要覆盖');
    await expectLater(
      repository.changingRoot(
        () => copyDownloadDirectory(Directory(root), target),
      ),
      throwsStateError,
    );
    expect(await (await repository.originalFile(favorite)).readAsBytes(), [
      3,
      7,
    ]);
    expect(
      await File(path.join(target.path, 'existing.txt')).readAsString(),
      '不要覆盖',
    );
  });
}
