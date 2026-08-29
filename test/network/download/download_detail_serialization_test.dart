import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/comic_source/comic_source.dart';
import 'package:pica_comic/foundation/def.dart';
import 'package:pica_comic/foundation/database/download_database.dart';
import 'package:pica_comic/network/download/custom_download_model.dart';
import 'package:pica_comic/network/download/download_manager.dart';
import 'package:pica_comic/network/eh_network/eh_models.dart' as eh;
import 'package:pica_comic/network/hitomi_network/hitomi_models.dart';
import 'package:pica_comic/network/jm_network/jm_models.dart';
import 'package:pica_comic/network/nhentai_network/download.dart';
import 'package:pica_comic/network/nhentai_network/models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  group('详情模型序列化', () {
    test('E-Hentai 保留评论数据', () {
      final gallery = eh.Gallery(
        title: 'title',
        type: 'Manga',
        time: 'time',
        uploader: 'uploader',
        stars: 4.5,
        rating: '4.5',
        coverPath: 'cover',
        tags: {
          'artist': ['author'],
        },
        comments: const [
          eh.Comment(
            id: '1',
            name: 'name',
            content: 'content',
            time: 'time',
            score: 2,
            voteUP: true,
          ),
        ],
        auth: {'gid': '1', 'token': 'token'},
        favorite: true,
        link: 'https://e-hentai.org/g/1/token/',
        maxPage: '10',
        pageSize: 10,
        thumbnails: const ['thumb'],
        ext: 'jpg',
        width: 100,
        subTitle: 'subtitle',
        fileSize: '309.2 MiB',
      );

      final restored = eh.Gallery.fromJson(gallery.toJson());
      expect(restored.comments.single.content, 'content');
      expect(restored.comments.single.voteUP, isTrue);
      expect(restored.auth?['token'], 'token');
      expect(restored.fileSize, '309.2 MiB');
    });

    test('JM 保留计数与收藏状态并兼容旧空字符串', () {
      final comic = JmComicInfo(
        name: 'name',
        id: '1',
        author: const ['author'],
        description: 'description',
        likes: 12,
        views: 34,
        series: const {1: '1'},
        tags: const ['tag'],
        works: const ['work'],
        actors: const ['actor'],
        relatedComics: const [],
        liked: true,
        favorite: true,
        comments: 56,
        epNames: const ['EP1'],
      );
      final restored = JmComicInfo.fromMap(comic.toJson());
      expect((restored.likes, restored.views, restored.comments), (12, 34, 56));
      expect((restored.liked, restored.favorite), (true, true));

      final legacy = comic.toJson()
        ..['likes'] = ''
        ..['views'] = ''
        ..['liked'] = ''
        ..['favorite'] = ''
        ..remove('comments');
      final legacyRestored = JmComicInfo.fromMap(legacy);
      expect(legacyRestored.likes, 0);
      expect(legacyRestored.favorite, isFalse);
    });

    test('Hitomi 保留标签、关联漫画、分组和封面', () {
      final comic = HitomiComic(
        id: '1',
        name: 'name',
        related: const [2],
        type: 'manga',
        artists: const ['artist'],
        lang: 'chinese',
        parodys: const [Tag(name: 'series', link: '/series')],
        characters: const [Tag(name: 'character', link: '/character')],
        tags: const [Tag(name: 'tag', link: '/tag')],
        time: 'time',
        files: const [
          HitomiFile(
            name: '1.jpg',
            hash: 'hash',
            hasWebp: true,
            height: 100,
            width: 100,
            galleryId: '1',
          ),
        ],
        group: const ['group'],
        cover: 'cover',
      );
      final restored = HitomiComic.fromMap(comic.toMap());
      expect(restored.related, [2]);
      expect(restored.parodys?.single.name, 'series');
      expect(restored.characters?.single.name, 'character');
      expect(restored.tags.single.link, '/tag');
      expect(restored.group, ['group']);
      expect(restored.cover, 'cover');
    });

    test('Nhentai 下载记录保存完整详情并兼容旧摘要', () {
      final comic = NhentaiComic(
        id: '1',
        title: 'title',
        subTitle: 'subtitle',
        cover: 'cover',
        tags: {
          'Tags': ['tag'],
        },
        favorite: true,
        thumbnails: const ['thumb'],
        recommendations: const [
          NhentaiComicBrief(
            title: 'rec',
            cover: 'rec-cover',
            id: '2',
            lang: 'en',
            tags: ['tag'],
          ),
        ],
        token: 'token',
      );
      final restored = NhentaiDownloadedComic.fromJson(
        NhentaiDownloadedComic(comic, 1.5).toJson(),
      );
      expect(restored.comic.subTitle, 'subtitle');
      expect(restored.comic.thumbnails, ['thumb']);
      expect(restored.comic.recommendations.single.title, 'rec');

      final legacy = NhentaiDownloadedComic.fromJson({
        'comicID': 'nhentai1',
        'title': 'legacy',
        'size': 1.0,
        'cover': 'cover',
        'tags': ['tag'],
      });
      expect(legacy.id, 'nhentai1');
      expect(legacy.tags, ['tag']);
    });

    test('通用下载记录保存详情字段并兼容旧扁平结构', () {
      const suggestion = ComicInfoSuggestion(
        title: 'suggestion',
        subTitle: 'sub',
        cover: 'cover2',
        id: '2',
        tags: ['tag2'],
        description: 'description2',
      );
      const comic = ComicInfoData(
        title: 'title',
        subTitle: 'subtitle',
        cover: 'cover',
        description: 'description',
        tags: {
          'Group': ['tag'],
        },
        chapters: const {'1': 'EP1'},
        thumbnails: const ['thumb'],
        thumbnailMaxPage: 2,
        suggestions: const [suggestion],
        sourceKey: 'source',
        comicId: '1',
        subId: 'sub-id',
      );
      final item = CustomDownloadedItem(1, [0], 'source-1', comic, 'Source');
      final restored = CustomDownloadedItem.fromJson(item.toJson());
      expect(restored.comic.description, 'description');
      expect(restored.comic.thumbnails, ['thumb']);
      expect(restored.comic.thumbnailMaxPage, 2);
      expect(restored.comic.suggestions?.single.title, 'suggestion');
      expect(restored.comic.subId, 'sub-id');

      final legacy = CustomDownloadedItem.fromJson({
        'comicSize': 1.0,
        'downloadedEps': [0],
        'chapters': {'1': 'EP1'},
        'id': 'source-1',
        'name': 'legacy',
        'subTitle': 'sub',
        'tags': ['tag'],
        'sourceKey': 'source',
        'sourceName': 'Source',
        'cover': 'cover',
        'comicId': '1',
      });
      expect(legacy.comic.title, 'legacy');
      expect(legacy.downloadedEps, [0]);
    });
  });

  test('下载 ID 映射支持详情页链接', () {
    expect(
      downloadManager.getDownloadIdFromComicId(
        ComicType.ehentai,
        'https://e-hentai.org/g/123/token/',
      ),
      '123',
    );
    expect(
      downloadManager.getDownloadIdFromComicId(
        ComicType.hitomi,
        'https://hitomi.la/galleries/456.html',
      ),
      'hitomi456',
    );
    expect(
      downloadManager.getDownloadIdFromComicId(ComicType.nhentai, '789'),
      'nhentai789',
    );
  });

  test('详情专用更新不会修改下载元数据', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final directory = await Directory.systemTemp.createTemp('pica_detail_test');
    final database = DownloadDatabase();
    await database.init(dbPath: '${directory.path}/download.db');
    await database.addToDownload(
      'id',
      'old title',
      'old subtitle',
      123,
      'directory',
      45.6,
      '{"downloadedEps":[0]}',
      color: 'red',
    );

    await database.updateDownloadDetails(
      id: 'id',
      title: 'new title',
      subtitle: 'new subtitle',
      json: '{"downloadedEps":[0],"description":"new"}',
    );
    final row = await database.getDownloadById('id');

    expect(row?[kDownloadTitle], 'new title');
    expect(row?[kDownloadSubtitle], 'new subtitle');
    expect(row?[kDownloadTime], 123);
    expect(row?[kDownloadDirectory], 'directory');
    expect(row?[kDownloadSize], 45.6);
    expect(row?[kDownloadColor], 'red');
    expect(row?[kDownloadJson], contains('"downloadedEps":[0]'));

    await database.updateAiTranslationCompletedAt('id', 123456);
    final markedRow = await database.getDownloadById('id');
    expect(markedRow?[kDownloadAiTranslationCompletedAt], 123456);

    await database.updateAiTranslationCompletedAt('id', null);
    final unmarkedRow = await database.getDownloadById('id');
    expect(unmarkedRow?[kDownloadAiTranslationCompletedAt], isNull);
  });
}
