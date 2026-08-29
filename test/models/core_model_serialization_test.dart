import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/ai/ai_models.dart';
import 'package:pica_comic/comic_source/comic_source.dart';
import 'package:pica_comic/foundation/cache_manager.dart';
import 'package:pica_comic/foundation/history.dart';
import 'package:pica_comic/foundation/local_favorites.dart';
import 'package:pica_comic/foundation/local_history.dart';
import 'package:pica_comic/foundation/local_repository_manager.dart';
import 'package:pica_comic/network/download/models/download_tag.dart';
import 'package:pica_comic/network/eh_network/eh_models.dart' as eh;
import 'package:pica_comic/network/hitomi_network/hitomi_models.dart' as hitomi;
import 'package:pica_comic/network/htmanga_network/models.dart' as ht;
import 'package:pica_comic/network/jm_network/jm_models.dart' as jm;
import 'package:pica_comic/network/kemono_network/models.dart' as kemono;
import 'package:pica_comic/network/nhentai_network/models.dart' as nh;
import 'package:pica_comic/network/picacg_network/models.dart' as pica;
import 'package:pica_comic/network/res.dart';

void main() {
  group('漫画源详情模型', () {
    test('Pica 模型支持嵌套 round-trip 和显式清空', () {
      const profile = pica.Profile(
        id: 'user-1',
        name: '作者',
        level: 4,
        exp: 12,
        frameUrl: 'frame',
        isPunched: true,
      );
      const brief = pica.ComicItemBrief(
        title: '推荐',
        author: '作者',
        likes: 8,
        path: 'cover',
        id: 'brief-1',
        tags: ['tag'],
        pages: 10,
      );
      const comic = pica.ComicItem(
        creator: profile,
        id: 'comic-1',
        title: '标题',
        description: '简介',
        thumbUrl: 'thumb',
        author: '作者',
        chineseTeam: '汉化组',
        categories: ['分类'],
        tags: ['标签'],
        likes: 3,
        comments: 2,
        isLiked: true,
        isFavourite: true,
        epsCount: 1,
        pagesCount: 10,
        time: '2026-08-29',
        eps: ['第一章'],
        recommendation: [brief],
      );

      expect(pica.Profile.fromJson(profile.toJson()), profile);
      expect(pica.ComicItem.fromJson(comic.toJson()), comic);
      expect(profile.copyWith(clearFrameUrl: true).frameUrl, isNull);
      expect(brief.copyWith(clearPages: true).pages, isNull);
    });

    test('EH 模型保留分页、评论和认证信息', () {
      const comment = eh.Comment(
        id: 'comment-1',
        name: '用户',
        content: '内容',
        time: 'now',
        score: 2,
        voteUP: true,
      );
      final gallery = eh.Gallery(
        title: '标题',
        subTitle: '副标题',
        type: 'Manga',
        time: 'now',
        uploader: '作者',
        stars: 4.5,
        rating: '4.5',
        coverPath: 'cover',
        tags: const {
          'artist': ['A'],
        },
        comments: const [comment],
        auth: const {'gid': '1', 'token': 'secret'},
        favorite: true,
        link: 'https://e-hentai.org/g/1/token/',
        maxPage: '20',
        pageSize: 20,
        thumbnails: const ['thumb'],
        ext: 'jpg',
        width: 100,
        fileSize: '1 MiB',
      );
      const page = eh.Galleries(
        galleries: [
          eh.EhGalleryBrief(title: '标题', link: 'link', tags: ['tag']),
        ],
        next: 'next',
      );

      expect(eh.Gallery.fromJson(gallery.toJson()), gallery);
      expect(eh.Galleries.fromJson(page.toJson()), page);
      expect(gallery.comments.single.voteUP, isTrue);
      expect(gallery.copyWith(clearSubTitle: true).subTitle, isNull);
      expect(gallery.copyWith(clearRating: true).rating, isNull);
      expect(gallery.copyWith(clearAuth: true).auth, isEmpty);
      expect(page.copyWith(galleries: const []).galleries, isEmpty);
      expect(page.galleries, hasLength(1));
    });

    test('JM、HT、Hitomi、NHentai 模型支持嵌套 round-trip', () {
      const jmBrief = jm.JmComicBrief(
        id: 'jm-brief',
        author: '作者',
        name: '标题',
        description: '简介',
        categories: [jm.ComicCategoryInfo(id: '1', name: '分类')],
      );
      const jmComic = jm.JmComicInfo(
        name: 'JM',
        id: 'jm-1',
        author: ['作者'],
        description: '简介',
        likes: 1,
        views: 2,
        comments: 3,
        series: {1: 'ep-1'},
        tags: ['tag'],
        works: ['work'],
        actors: ['actor'],
        relatedComics: [jmBrief],
        liked: true,
        favorite: true,
        epNames: ['第一章'],
      );
      const htComic = ht.HtComicInfo(
        id: 'ht-1',
        coverPath: 'cover',
        name: 'HT',
        category: 'Manga',
        pages: 12,
        tags: {'tag': 'link'},
        description: '简介',
        uploader: '作者',
        avatar: 'avatar',
        uploadNum: 2,
        thumbnails: ['thumb'],
      );
      const hitomiFile = hitomi.HitomiFile(
        name: '1.jpg',
        hash: 'hash',
        hasWebp: true,
        height: 100,
        width: 80,
        galleryId: 'hitomi-1',
      );
      const hitomiComic = hitomi.HitomiComic(
        id: 'hitomi-1',
        name: 'Hitomi',
        related: [1],
        type: 'manga',
        artists: ['作者'],
        lang: '中文',
        parodys: [hitomi.Tag(name: '系列', link: 'series')],
        characters: [hitomi.Tag(name: '角色', link: 'character')],
        tags: [hitomi.Tag(name: '标签', link: 'tag')],
        time: 'now',
        files: [hitomiFile],
        group: ['组'],
        cover: 'cover',
      );
      const nhBrief = nh.NhentaiComicBrief(
        title: '推荐',
        cover: 'cover',
        id: '2',
        lang: 'en',
        tags: ['tag'],
      );
      const nhComic = nh.NhentaiComic(
        id: '1',
        title: 'NH',
        subTitle: '副标题',
        cover: 'cover',
        tags: {
          'Tags': ['tag'],
        },
        favorite: true,
        thumbnails: ['thumb'],
        recommendations: [nhBrief],
        token: 'token',
      );

      expect(jm.JmComicBrief.fromJson(jmBrief.toJson()), jmBrief);
      expect(jm.JmComicInfo.fromJson(jmComic.toJson()), jmComic);
      expect(ht.HtComicInfo.fromJson(htComic.toJson()), htComic);
      expect(hitomi.HitomiComic.fromJson(hitomiComic.toJson()), hitomiComic);
      expect(nh.NhentaiComic.fromJson(nhComic.toJson()), nhComic);
      expect(
        jm.JmComicInfo.fromMap({
          'series': {'1': 2},
        }).series,
        {1: '2'},
      );
    });

    test('Kemono 兼容日期、附件和错误类型', () {
      final post = kemono.KemonoPost.fromMap({
        'id': 12,
        'title': 99,
        'service': 'patreon',
        'user': 7,
        'user_name': '作者',
        'file': {'name': 'main.jpg', 'path': '/main.jpg'},
        'attachments': [
          {'name': 'archive.zip', 'path': '/archive.zip'},
          'invalid',
        ],
        'content': '<p>内容</p>',
        'published': '1700000000',
        'added': 1700000000000,
        'embeds': [
          'invalid',
          {'kind': 'video'},
        ],
      });

      expect(post.id, '12');
      expect(post.title, '99');
      expect(post.attachments, hasLength(1));
      expect(
        post.published,
        DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );
      expect(post.added, DateTime.fromMillisecondsSinceEpoch(1700000000000));
      expect(kemono.KemonoPost.fromJson(post.toJson()), post);
      expect(post.copyWith(userName: '新作者').userName, '新作者');
      expect(
        kemono.KemonoFile.fromJson({'name': 1, 'path': 2}),
        const kemono.KemonoFile(name: '1', path: '2'),
      );
    });
  });

  group('通用、本地与 AI 模型', () {
    test('ComicInfoData 保留扁平 key 并忽略运行时 loader 比较', () {
      final loader = (String _, int __) async => const Res<List<String>>([]);
      final data = ComicInfoData(
        title: '标题',
        subTitle: '副标题',
        cover: 'cover',
        description: '简介',
        tags: const {
          'Group': ['tag'],
        },
        chapters: const {'1': '第一章'},
        thumbnails: const ['thumb'],
        thumbnailLoader: loader,
        thumbnailMaxPage: 1,
        suggestions: const [ComicInfoSuggestion(title: '推荐', id: '1')],
        sourceKey: 'source',
        comicId: '1',
        isFavorite: true,
        subId: 'sub-id',
      );
      final restored = ComicInfoData.fromJson(data.toJson());

      expect(restored, data);
      expect(restored.thumbnailLoader, isNull);
      expect(data.toMap(), isNot(contains('thumbnailLoader')));
      expect(data.copyWith(clearSubTitle: true).subTitle, isNull);
      expect(data.copyWith(clearChapters: true).chapters, isNull);
      expect(data.copyWith(clearSuggestions: true).suggestions, isNull);
      expect(data.copyWith(clearIsFavorite: true).isFavorite, isNull);
    });

    test('HistoryRecord 支持 JSON、SQLite 行和运行时包装转换', () {
      final record = HistoryRecord(
        type: HistoryType.jmComic,
        time: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        title: '标题',
        subtitle: '作者',
        cover: 'cover',
        ep: 2,
        page: 3,
        target: 'target',
        readEpisode: const {1, 2},
        maxPage: 20,
      );

      expect(HistoryRecord.fromJson(record.toJson()), record);
      expect(HistoryRecord.fromRow(record.toRow()), record);
      expect(record.copyWith(clearMaxPage: true).maxPage, isNull);
      expect(History.fromRecord(record).toRecord(), record);
      expect(
        HistoryRecord.fromMap({
          kHistoryType: '2',
          kHistoryTime: '1700000000000',
          kHistoryReadEpisode: '1,2',
        }).readEpisode,
        {1, 2},
      );
    });

    test('本地收藏、缓存、仓库、下载标签和本地历史支持宽松解析', () {
      final favorite = FavoriteItem(
        target: 'target',
        name: '标题',
        coverPath: 'cover',
        author: '作者',
        type: FavoriteType.picacg,
        tags: const ['tag'],
        time: 'time',
      );
      const image = ImageFavorite(
        id: 'image',
        imagePath: 'path',
        title: '标题',
        ep: 1,
        page: 2,
        otherInfo: {'url': 'url'},
      );
      const cache = CacheRecord(
        key: 'key',
        dir: 'dir',
        name: 'name',
        expires: 1,
        type: 'json',
      );
      const repository = RepositoryInfo(
        name: 'repo',
        path: '/tmp/repo',
        title: '仓库',
      );
      final tag = DownloadTag(
        id: 1,
        name: '标签',
        createdTime: DateTime.fromMillisecondsSinceEpoch(1),
        category: TagCategory.work,
      );
      const localHistory = LocalHistory(
        path: 'path',
        isReversed: 1,
        pageIndex: 2,
        time: 3,
        json: '{}',
        totalPages: 4,
      );

      expect(FavoriteItem.fromJson(favorite.toJson()), favorite);
      expect(ImageFavorite.fromJson(image.toJson()), image);
      expect(ImageFavorite.fromRow(image.toRow()), image);
      expect(CacheRecord.fromJson(cache.toJson()), cache);
      expect(RepositoryInfo.fromJson(repository.toJson()), repository);
      expect(DownloadTag.fromJson(tag.toJson()), tag);
      expect(LocalHistory.fromJson(localHistory.toMap()), localHistory);
      expect(
        DownloadTag.fromMap(<String, Object?>{
          'id': 'bad',
          'name': 1,
          'created_time': 'bad',
          'category': '2',
        }).id,
        0,
      );
      expect(favorite.copyWith(name: '新标题').name, '新标题');
      expect(tag.copyWith(clearCoverComicId: true).coverComicId, isNull);
    });

    test('AI 配置使用安全解析并保留重试限制', () {
      const provider = AiProviderConfig(
        id: 'provider',
        name: 'Provider',
        protocol: AiProtocolType.openAiResponses,
        baseUrl: 'https://example.com',
        apiKey: 'key',
        model: 'model',
        reasoningEffort: 'high',
        maxRetries: 3,
      );
      const prompt = AiPromptPreset(
        id: 'prompt',
        name: 'Prompt',
        sceneId: AiPromptScenes.comicMetadataTranslation,
        providerId: 'provider',
        systemPrompt: '{{text}} {{target_language}}',
        userTemplate: '{{text}}',
        isActive: true,
      );
      const document = AiSettingsDocument(
        providers: [provider],
        prompts: [prompt],
      );

      expect(AiProviderConfig.fromJson(provider.toJson()), provider);
      expect(AiPromptPreset.fromJson(prompt.toJson()), prompt);
      expect(AiSettingsDocument.decode(document.encode()), document);
      expect(AiProviderConfig.fromMap({'max_retries': '99'}).maxRetries, 10);
      expect(AiProviderConfig.fromMap({'max_retries': '-1'}).maxRetries, 0);
      expect(
        provider.copyWith(clearReasoningEffort: true).reasoningEffort,
        isNull,
      );
      expect(
        AiSettingsDocument.fromMap({'providers': 'bad', 'prompts': 1}),
        const AiSettingsDocument(providers: [], prompts: []),
      );
    });
  });
}
