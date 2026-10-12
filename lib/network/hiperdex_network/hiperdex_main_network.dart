import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:pica_comic/foundation/def.dart';
import 'package:pica_comic/foundation/disk_cache.dart';
import 'package:pica_comic/foundation/log.dart';
import 'package:pica_comic/network/base_comic.dart';
import 'package:pica_comic/network/cookie_jar.dart';
import 'package:pica_comic/network/network_client_manager.dart';
import 'package:pica_comic/network/res.dart';

part 'hiperdex_main_network.g.dart';

/// HiperDEX 网络请求与数据解析。
@Riverpod(keepAlive: true)
class HiperdexNetwork extends _$HiperdexNetwork {
  @override
  HiperdexNetwork build() {
    clientManager = ref.watch(networkClientManagerProvider);
    return this;
  }

  late NetworkClientManager clientManager;

  static const String baseUrl = 'https://hiperdex.com';

  /// 阅读、封面和下载共用的图片请求头。
  static Map<String, String> get imageHeaders => {
    'User-Agent': webUA,
    'Referer': '$baseUrl/',
  };
  static const int pageSize = 30;

  Future<String>? _apiKeyFuture;
  final Map<String, Future<Res<dynamic>>> _pendingQueries = {};

  Dio get _dio => clientManager.apiDio;

  /// 漫画列表项。
  Future<Res<List<BaseComic>>> search({
    String keyword = '',
    int page = 1,
    String sort = 'relevance',
    String? type,
    String? status,
    String? contentRating,
    String? genre,
    String? year,
    bool forceRefresh = false,
  }) async {
    final input = _searchInput(
      keyword: keyword,
      page: page,
      sort: sort,
      type: type,
      status: status,
      contentRating: contentRating,
      genre: genre,
      year: year,
    );
    final result = await _query(
      'search.query',
      input,
      forceRefresh: forceRefresh,
    );
    if (result.error) return Res.fromErrorRes(result);
    return _searchResult(result.dataOrNull);
  }

  /// 读取同一关键词和筛选条件的首屏磁盘缓存。
  Future<List<BaseComic>> searchCache({
    String keyword = '',
    String sort = 'relevance',
    String? type,
    String? status,
    String? contentRating,
    String? genre,
    String? year,
  }) async {
    final input = _searchInput(
      keyword: keyword,
      page: 1,
      sort: sort,
      type: type,
      status: status,
      contentRating: contentRating,
      genre: genre,
      year: year,
    );
    final cached = await _readQueryCache('search.query', input);
    return cached == null ? [] : _searchResult(cached['data']).data;
  }

  /// 按站点接口构建可组合的搜索参数。
  Map<String, dynamic> _searchInput({
    required String keyword,
    required int page,
    required String sort,
    String? type,
    String? status,
    String? contentRating,
    String? genre,
    String? year,
  }) {
    final filters = <String, dynamic>{
      if (type?.isNotEmpty ?? false) 'type': type,
      if (status?.isNotEmpty ?? false) 'status': status,
      if (contentRating?.isNotEmpty ?? false) 'contentRating': contentRating,
      if (genre?.isNotEmpty ?? false) 'genres': [genre],
    };
    final parsedYear = int.tryParse(year ?? '');
    if (parsedYear != null) filters['year'] = parsedYear;
    return {
      'q': keyword,
      'sort': sort,
      'filters': filters,
      'limit': pageSize,
      'offset': (page - 1) * pageSize,
      'maxRating': 'pornographic',
    };
  }

  /// 搜索响应使用 hits，不能把目录总数误当成空列表。
  Res<List<BaseComic>> _searchResult(dynamic payload) {
    final data = _asMap(payload);
    final comics = _asList(
      data?['hits'] ?? data?['items'] ?? payload,
    ).map(_comicFrom).whereType<BaseComic>().toList();
    final totalHits = _int(data?['totalHits']) ?? comics.length;
    return Res(comics, subData: (totalHits / pageSize).ceil());
  }

  /// 首页最新章节。
  Map<String, dynamic> _latestInput(int page) => {
    'limit': pageSize,
    'page': page,
    'maxRating': 'pornographic',
    'seriesType': 'all',
    'hasSponsoredSlot': false,
  };

  Future<Res<List<BaseComic>>> getLatest(
    int page, {
    bool forceRefresh = false,
  }) async {
    final result = await _query(
      'recommendations.latestChapters',
      _latestInput(page),
      forceRefresh: forceRefresh,
    );
    if (result.error) return Res.fromErrorRes(result);
    final comics = _comicsFrom(result.dataOrNull);
    return Res(comics, subData: comics.length < pageSize ? page : 10000);
  }

  /// 热门漫画。
  Map<String, dynamic> _trendingInput(int page, String period) => {
    'limit': 20,
    'page': page,
    'maxRating': 'pornographic',
    'period': period,
  };

  Future<Res<List<BaseComic>>> getTrending(
    int page, {
    String period = 'week',
    bool forceRefresh = false,
  }) async {
    final result = await _query(
      'recommendations.trending',
      _trendingInput(page, period),
      forceRefresh: forceRefresh,
    );
    if (result.error) return Res.fromErrorRes(result);
    final comics = _comicsFrom(result.dataOrNull);
    return Res(comics, subData: comics.length < 20 ? page : 10000);
  }

  /// 最新页缓存与网络请求使用相同的分页参数。
  Future<List<BaseComic>> latestCache(int page) async => _comicsFrom(
    (await _readQueryCache(
      'recommendations.latestChapters',
      _latestInput(page),
    ))?['data'],
  );

  /// 热门榜缓存按天、周、月分别存储。
  Future<List<BaseComic>> trendingCache(
    int page, {
    String period = 'week',
  }) async => _comicsFrom(
    (await _readQueryCache(
      'recommendations.trending',
      _trendingInput(page, period),
    ))?['data'],
  );

  List<BaseComic> _comicsFrom(dynamic payload) => _asList(payload)
      .map((row) {
        final map = _asMap(row);
        return _comicFrom(map?['series'] ?? row);
      })
      .whereType<BaseComic>()
      .toList();

  /// 获取站点可用的题材列表。
  Future<Res<List<String>>> getGenres() async {
    final result = await _query(
      'search.genres',
      const {},
      cacheAge: const Duration(days: 1),
    );
    if (result.error) return Res.fromErrorRes(result);
    return Res(_asList(result.dataOrNull).map(_genreName).toList());
  }

  /// 加载漫画详情与章节目录。
  Future<Res<Map<String, dynamic>>> getSeries(
    String slug, {
    bool forceRefresh = false,
  }) async {
    final result = await _query(
      'series.bySlugWithGenres',
      {'slug': slug},
      forceRefresh: forceRefresh,
      cacheAge: const Duration(minutes: 10),
    );
    if (result.error) return Res.fromErrorRes(result);
    final series = _asMap(result.dataOrNull);
    if (series == null) return const Res.error('Series not found');

    final chapterResult = await _query(
      'series.chapters',
      {'seriesId': _int(series['id']) ?? 0},
      forceRefresh: forceRefresh,
      cacheAge: const Duration(minutes: 10),
    );
    if (chapterResult.error) return Res.fromErrorRes(chapterResult);
    final chapters =
        _asList(
          chapterResult.dataOrNull,
        ).map(_asMap).whereType<Map<String, dynamic>>().toList()..sort((a, b) {
          final numberCompare = (_double(b['number']) ?? 0).compareTo(
            _double(a['number']) ?? 0,
          );
          if (numberCompare != 0) return numberCompare;
          return _string(b['id']).compareTo(_string(a['id']));
        });
    return Res({...series, '_chapters': chapters});
  }

  /// 加载某一章节的图片地址。
  Future<Res<List<String>>> getChapterPages(
    String slug,
    String chapterKey,
  ) async {
    final parts = chapterKey.split('|');
    if (parts.isEmpty) return const Res.error('Invalid chapter ID');
    final chapterNumber = double.tryParse(parts.first);
    if (chapterNumber == null) return const Res.error('Invalid chapter number');
    final chapterId = parts.length > 1 ? int.tryParse(parts[1]) : null;
    if (parts.length > 1 && chapterId == null) {
      return const Res.error('Invalid chapter ID');
    }

    final result = await _query('reader.chapterPages', {
      'seriesSlug': slug,
      'chapterNumber': chapterNumber,
      if (chapterId != null) 'chapterId': chapterId,
    }, cacheAge: const Duration(days: 1));
    if (result.error) return Res.fromErrorRes(result);
    final pages = _asList(result.dataOrNull)
        .map((page) {
          if (page is String) return _absoluteUrl(page);
          final map = _asMap(page);
          return _absoluteUrl(
            _string(map?['webpUrl'] ?? map?['imageUrl'] ?? map?['url']),
          );
        })
        .where((url) => url.isNotEmpty)
        .toList();
    return Res(pages);
  }

  Future<Res<dynamic>> _query(
    String procedure,
    Map<String, dynamic> input, {
    bool forceRefresh = false,
    Duration cacheAge = const Duration(minutes: 5),
  }) async {
    final cache = await _readQueryCache(procedure, input);
    final savedAt = _int(cache?['savedAt']) ?? 0;
    if (!forceRefresh &&
        cache != null &&
        DateTime.now().millisecondsSinceEpoch - savedAt <
            cacheAge.inMilliseconds) {
      Log.d('HiperDEX 磁盘缓存命中：$procedure');
      return Res(cache['data']);
    }

    final key = _queryCacheKey(procedure, input);
    final pending = _pendingQueries[key];
    if (pending != null) return pending;
    final request = _queryNetwork(procedure, input);
    _pendingQueries[key] = request;
    try {
      final result = await request;
      if (result.success && result.dataOrNull != null) {
        await DiskCache.writeModel(key, {
          'savedAt': DateTime.now().millisecondsSinceEpoch,
          'data': result.data,
        });
      } else if (cache != null) {
        Log.w('HiperDEX 更新失败，使用磁盘缓存：$procedure');
        return Res(cache['data']);
      }
      return result;
    } finally {
      _pendingQueries.remove(key);
    }
  }

  /// 缓存键包含完整分页、关键词、筛选项和榜单周期。
  String _queryCacheKey(String procedure, Map<String, dynamic> input) =>
      'hiperdex-v2-$procedure-${sha256.convert(utf8.encode(jsonEncode(input)))}';

  Future<Map<String, dynamic>?> _readQueryCache(
    String procedure,
    Map<String, dynamic> input,
  ) async {
    final cache = await DiskCache.readModel(
      _queryCacheKey(procedure, input),
      (map) => map,
    );
    if (cache == null ||
        cache['data'] == null ||
        _int(cache['savedAt']) == null) {
      return null;
    }
    return cache;
  }

  Future<Res<dynamic>> _queryNetwork(
    String procedure,
    Map<String, dynamic> input,
  ) async {
    try {
      late Response<dynamic> response;
      for (var attempt = 0; attempt < 2; attempt++) {
        final apiKey = await _getApiKey(forceRefresh: attempt > 0);
        try {
          response = await _dio.get<dynamic>(
            '$baseUrl/api/trpc/$procedure',
            queryParameters: {
              'batch': '1',
              'input': jsonEncode({
                '0': {'json': input},
              }),
            },
            options: Options(
              headers: {
                'Accept': 'application/json',
                'Referer': '$baseUrl/',
                'User-Agent': webUA,
                'x-cfg-auth': apiKey,
              },
              extra: {
                NetworkCookieInterceptor.cookieJarKey:
                    SingleInstanceCookieJar.instance!,
                'cloudflare': true,
              },
            ),
          );
          break;
        } on DioException catch (error) {
          if (attempt == 0 && error.response?.statusCode == 401) continue;
          rethrow;
        }
      }
      dynamic callResponse = response.data;
      if (callResponse is List && callResponse.isNotEmpty) {
        callResponse = callResponse.first;
      } else {
        final batch = _asMap(callResponse);
        if (batch?.containsKey('0') == true) callResponse = batch!['0'];
      }
      final payload = _asMap(callResponse);
      final apiError = _asMap(payload?['error']);
      if (apiError != null) {
        final details = _asMap(apiError['json']) ?? apiError;
        return Res.error(
          _string(details['message']).isEmpty
              ? 'HiperDEX 接口返回错误'
              : _string(details['message']),
        );
      }
      final result = _asMap(payload?['result']);
      final data = _asMap(result?['data']);
      final value = data?.containsKey('json') == true
          ? data!['json']
          : result?['data'];
      if (value == null) return const Res.error('HiperDEX 接口未返回数据');
      return Res(value);
    } on DioException catch (error) {
      final responseData = _asMap(error.response?.data);
      final message = _string(responseData?['error']);
      return Res.error(
        message.isNotEmpty ? message : error.message ?? 'Network error',
      );
    } catch (error) {
      return Res.error(error.toString());
    }
  }

  Future<String> _getApiKey({bool forceRefresh = false}) async {
    if (forceRefresh) _apiKeyFuture = null;
    try {
      return await (_apiKeyFuture ??= _loadApiKey());
    } catch (_) {
      _apiKeyFuture = null;
      rethrow;
    }
  }

  Future<String> _loadApiKey() async {
    const htmlAccept =
        'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8';
    final pageResponse = await _dio.get<String>(
      '$baseUrl/',
      options: _siteOptions(accept: htmlAccept),
    );
    final html = pageResponse.data ?? '';
    final scriptPath = RegExp(
      r'''<script[^>]+src=["']([^"']*index-[^"']+\.js)["']''',
    ).firstMatch(html)?.group(1);
    if (scriptPath == null) {
      throw const FormatException('HiperDEX client script not found');
    }

    final scriptResponse = await _dio.get<String>(
      Uri.parse('$baseUrl/').resolve(scriptPath).toString(),
      options: _siteOptions(accept: '*/*'),
    );
    final key = _extractApiKey(scriptResponse.data ?? '');
    if (key == null || key.isEmpty) {
      throw const FormatException(
        'HiperDEX API key not found in client script',
      );
    }
    return key;
  }

  Options _siteOptions({required String accept}) => Options(
    responseType: ResponseType.plain,
    headers: {'Accept': accept, 'Referer': '$baseUrl/', 'User-Agent': webUA},
    extra: {
      NetworkCookieInterceptor.cookieJarKey: SingleInstanceCookieJar.instance!,
      'cloudflare': true,
    },
  );

  String? _extractApiKey(String script) {
    final literal = RegExp(
      r'''(?:["']x-cfg-auth["']|x-cfg-auth|\[\s*["']x-cfg-auth["']\s*\])\s*:\s*["']([A-Za-z0-9._~-]{8,128})["']''',
      caseSensitive: false,
    ).firstMatch(script)?.group(1);
    if (literal != null) return literal;

    final headerIndex = script.toLowerCase().indexOf('x-cfg-auth');
    final keyExpressions = RegExp(
      r'''(?:window\.)?atob\(\s*["']([A-Za-z0-9+/=]+)["']\s*\)(?:\s*\+\s*["']([^"']*)["'])?''',
    ).allMatches(script);
    String? closestKey;
    var closestDistance = script.length + 1;
    for (final match in keyExpressions) {
      try {
        final decoded = utf8.decode(base64.decode(match.group(1)!));
        final key = decoded + (match.group(2) ?? '');
        if (!RegExp(r'^[A-Za-z0-9._~-]{8,128}$').hasMatch(key)) continue;
        final distance = headerIndex < 0
            ? match.start
            : (match.start - headerIndex).abs();
        if (distance < closestDistance) {
          closestDistance = distance;
          closestKey = key;
        }
      } on FormatException {
        continue;
      }
    }
    return closestKey;
  }

  BaseComic? _comicFrom(dynamic value) {
    final map = _asMap(value);
    if (map == null) return null;
    final slug = _string(map['slug'] ?? map['seriesSlug']);
    final title = _string(map['title'] ?? map['seriesTitle']);
    if (slug.isEmpty || title.isEmpty) return null;
    return HiperdexComic.fromMap(map);
  }

  static Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return value.map((key, value) => MapEntry('$key', value));
    return null;
  }

  static List<dynamic> _asList(dynamic value) {
    if (value is List) return value;
    final map = _asMap(value);
    for (final key in [
      'hits',
      'items',
      'results',
      'series',
      'chapters',
      'pages',
    ]) {
      if (map?[key] is List) return map![key] as List<dynamic>;
    }
    return const [];
  }

  static String _genreName(dynamic value) {
    if (value is String) return value;
    final map = _asMap(value);
    return _string(map?['name'] ?? map?['genre'] ?? map?['slug']);
  }

  static int? _int(dynamic value) =>
      value is int ? value : int.tryParse(value?.toString() ?? '');

  static double? _double(dynamic value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '');

  static String _string(dynamic value) => value?.toString() ?? '';

  static String _absoluteUrl(String url) {
    if (url.isEmpty || url.startsWith('http')) return url;
    return '$baseUrl${url.startsWith('/') ? '' : '/'}$url';
  }
}

/// HiperDEX 漫画列表项，兼容现有通用漫画卡片的数据接口。
// ignore: deprecated_member_use_from_same_package
class HiperdexComic extends CustomComic {
  final List<String> authors;
  final List<String> artists;
  final double? score;
  final int? views;
  final String? latestChapter;

  const HiperdexComic({
    required String title,
    required String subTitle,
    required String cover,
    required String id,
    required List<String> tags,
    required String description,
    this.authors = const [],
    this.artists = const [],
    this.score,
    this.views,
    this.latestChapter,
  }) : super(title, subTitle, cover, id, tags, description, 'hiperdex');

  /// 兼容目录、热门和最新章节接口的实际字段。
  factory HiperdexComic.fromMap(Map<String, dynamic> map) {
    final genres = HiperdexNetwork._asList(
      map['genres'] ?? map['seriesGenres'],
    ).map(HiperdexNetwork._genreName).toList();
    final rating = HiperdexNetwork._string(
      map['contentRating'] ?? map['seriesContentRating'],
    );
    final chapters = HiperdexNetwork._asList(map['chapters']);
    final latest =
        HiperdexNetwork._asMap(map['latestChapter']) ??
        (chapters.isEmpty ? null : HiperdexNetwork._asMap(chapters.first));
    final subtitle =
        [
              map['type'] ?? map['seriesType'],
              map['status'] ?? map['seriesStatus'],
              map['year'],
            ]
            .where((value) => value != null && value.toString().isNotEmpty)
            .join(' · ');
    return HiperdexComic(
      id: HiperdexNetwork._string(
        map['slug'] ?? map['seriesSlug'] ?? map['id'],
      ),
      title: HiperdexNetwork._string(map['title'] ?? map['seriesTitle']),
      subTitle: subtitle.isEmpty
          ? HiperdexNetwork._string(map['subTitle'])
          : subtitle,
      cover: HiperdexNetwork._absoluteUrl(
        HiperdexNetwork._string(
          map['coverUrl'] ?? map['seriesCoverUrl'] ?? map['cover'],
        ),
      ),
      tags: [...genres, if (rating.isNotEmpty) rating],
      description: HiperdexNetwork._string(
        map['synopsis'] ?? map['description'],
      ),
      authors: HiperdexNetwork._asList(
        map['authors'],
      ).map(HiperdexNetwork._genreName).toList(),
      artists: HiperdexNetwork._asList(
        map['artists'],
      ).map(HiperdexNetwork._genreName).toList(),
      score: HiperdexNetwork._double(map['score']),
      views: HiperdexNetwork._int(map['views']),
      latestChapter:
          latest?['number']?.toString() ??
          map['latestChapterNumber']?.toString(),
    );
  }

  /// 保存列表元数据，避免缓存后丢失作者、评分和浏览数。
  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'slug': id,
    'genres': tags,
    'authors': authors,
    'artists': artists,
    'score': score,
    'views': views,
    'latestChapterNumber': latestChapter,
  };
}
