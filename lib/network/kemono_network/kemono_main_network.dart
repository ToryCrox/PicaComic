import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:pica_comic/foundation/cache_manager.dart';
import 'package:pica_comic/foundation/log.dart';
import 'package:pica_comic/network/cookie_jar.dart';
import 'package:pica_comic/network/network_client_manager.dart';
import 'package:pica_comic/network/res.dart';
import 'models.dart';

export 'models.dart';

/// Kemono 网络请求类
///
/// 基于 kemono.cr 的 API 实现
class KemonoNetwork {
  factory KemonoNetwork() => _cache ?? (_cache = KemonoNetwork._create());

  KemonoNetwork._create();

  static KemonoNetwork? _cache;

  /// Cookie 管理器
  SingleInstanceCookieJar? cookieJar;

  /// 是否已登录
  bool logged = false;

  /// API 基础URL
  static const String baseUrl = 'https://kemono.cr';

  /// API 地址
  static const String apiUrl = '$baseUrl/api/v1';

  /// 图片CDN地址
  static const String imgCdn = 'https://img.kemono.cr';

  /// 分页步长
  static const int pageSize = 50;

  /// Dio 实例
  Dio get dio => networkClientManager.apiDio;

  /// 作者列表缓存 (creators.txt返回全量数据)
  List<KemonoCreator>? _creatorsCache;

  /// 根据 service 和 userId 从缓存中查找作者名称
  ///
  /// 如果找不到返回 null
  String? getCreatorName(String service, String userId) {
    if (_creatorsCache == null) return null;
    for (var creator in _creatorsCache!) {
      if (creator.service == service && creator.id == userId) {
        return creator.title;
      }
    }
    return null;
  }

  /// 初始化网络模块
  Future<void> init() async {
    cookieJar = SingleInstanceCookieJar.instance;

    // 检查是否已登录 (通过session cookie)
    final cookies = await cookieJar!.loadForRequest(Uri.parse(baseUrl));
    for (var cookie in cookies) {
      if (cookie.name == 'session') {
        logged = true;
        break;
      }
    }
  }

  /// 登出
  void logout() async {
    logged = false;
    cookieJar?.delete(Uri.parse(baseUrl), 'session');
  }

  /// 通用GET请求
  Future<Res<String>> get(String path) async {
    if (cookieJar == null) {
      await init();
    }
    try {
      final url = path.startsWith('http') ? path : '$apiUrl$path';
      final res = await dio.get<String>(
        url,
        options: Options(
          headers: {
            // 使用 text/css 绕过 Cloudflare/DDG 保护
            'Accept': 'text/css',
            'Accept-Language': 'zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7',
            'Referer': '$baseUrl/',
          },
          validateStatus: (i) => i == 200 || i == 304,
          extra: {
            NetworkCookieInterceptor.cookieJarKey: cookieJar!,
            'cloudflare': true,
          },
        ),
      );
      return Res(res.data);
    } catch (e, s) {
      Log.e('Kemono GET error: $path\n$e\n$s');
      return Res(null, errorMessage: e.toString());
    }
  }

  /// 获取图集列表
  ///
  /// [offset] 分页偏移量 (必须是50的倍数)
  /// [keyword] 搜索关键词 (可选)
  /// [tags] 标签列表 (可选)
  Future<Res<List<KemonoPostBrief>>> getPosts(
    int offset, {
    String? keyword,
    List<String>? tags,
  }) async {
    try {
      var queryParams = <String, String>{'o': offset.toString()};
      if (keyword != null && keyword.isNotEmpty) {
        queryParams['q'] = keyword;
      }
      if (tags != null && tags.isNotEmpty) {
        // 按文档,tag参数可以多次传递
        // 这里简化处理,只用第一个tag
        queryParams['tags'] = tags.first;
      }

      final queryString = queryParams.entries
          .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
          .join('&');

      final res = await get('/posts?$queryString');
      if (res.error) {
        return Res.fromErrorRes(res);
      }

      final jsonData = jsonDecode(res.data);
      // API返回的是 { "count": ..., "posts": [...] } 结构
      final List postsData;
      if (jsonData is Map && jsonData.containsKey('posts')) {
        postsData = jsonData['posts'] as List;
      } else if (jsonData is List) {
        postsData = jsonData;
      } else {
        return const Res(null, errorMessage: 'Unexpected API response format');
      }
      final posts = postsData
          .map((e) => KemonoPostBrief.fromJson(e as Map))
          .toList();

      return Res(posts);
    } catch (e, s) {
      Log.e('Kemono getPosts error: $e\n$s');
      return Res(null, errorMessage: 'Failed to parse data: $e');
    }
  }

  /// 获取热门图集
  Future<Res<List<KemonoPostBrief>>> getPopularPosts() async {
    try {
      final res = await get('/posts/popular');
      if (res.error) {
        return Res.fromErrorRes(res);
      }

      final jsonData = jsonDecode(res.data);
      // API可能返回 { "posts": [...] } 或直接返回 [...]
      final List postsData;
      if (jsonData is Map && jsonData.containsKey('posts')) {
        postsData = jsonData['posts'] as List;
      } else if (jsonData is List) {
        postsData = jsonData;
      } else {
        return const Res(null, errorMessage: 'Unexpected API response format');
      }
      final posts = postsData
          .map((e) => KemonoPostBrief.fromJson(e as Map))
          .toList();

      return Res(posts);
    } catch (e, s) {
      Log.e('Kemono getPopularPosts error: $e\n$s');
      return Res(null, errorMessage: 'Failed to parse data: $e');
    }
  }

  /// 获取图集详情
  ///
  /// [service] 服务类型 (patreon/fanbox/fantia等)
  /// [creatorId] 作者ID
  /// [postId] 图集ID
  /// [useCache] 是否使用缓存，默认为true
  Future<Res<KemonoPost>> getPostDetail(
    String service,
    String creatorId,
    String postId, {
    bool useCache = true,
  }) async {
    final cacheKey = 'kemono_post_$service/$creatorId/$postId';

    // 尝试从缓存读取
    if (useCache) {
      try {
        var cached = await CacheManager().findCacheModel<KemonoPost>(
          cacheKey,
          (map) => KemonoPost.fromJson(map),
        );
        if (cached != null) {
          Log.d('Kemono getPostDetail cache hit: $cacheKey');
          // 同样尝试从作者缓存中获取真实的作者名称
          if (cached.userName == cached.userId || cached.userName.isEmpty) {
            if (_creatorsCache == null) {
              await getCreators();
            }
            final creatorName = getCreatorName(service, creatorId);
            if (creatorName != null && creatorName.isNotEmpty) {
              cached = cached.copyWith(userName: creatorName);
            }
          }
          return Res(cached);
        }
      } catch (e) {
        Log.e('Kemono cache read error: $e');
      }
    }

    try {
      final res = await get('/$service/user/$creatorId/post/$postId');
      if (res.error) {
        return Res.fromErrorRes(res);
      }

      final jsonData = jsonDecode(res.data) as Map;
      // API 返回 {"post": {...}} 结构
      final postData = jsonData['post'] as Map? ?? jsonData;
      var post = KemonoPost.fromJson(postData);

      // 尝试从作者缓存中获取真实的作者名称
      // 因为 API 返回的详情中可能没有 user_name 字段，只有 user (userId)
      if (post.userName == post.userId || post.userName.isEmpty) {
        if (_creatorsCache == null) {
          await getCreators();
        }
        final creatorName = getCreatorName(service, creatorId);
        if (creatorName != null && creatorName.isNotEmpty) {
          post = post.copyWith(userName: creatorName);
        }
      }

      // 写入缓存
      try {
        final cacheData = jsonEncode(postData);
        await CacheManager().writeString(cacheKey, cacheData);
      } catch (e) {
        Log.e('Kemono cache write error: $e');
      }

      return Res(post);
    } catch (e, s) {
      Log.e('Kemono getPostDetail error: $e\n$s');
      return Res(null, errorMessage: 'Failed to parse data: $e');
    }
  }

  /// 获取所有作者列表
  ///
  /// 注意: /creators 返回全量数据,建议缓存后使用本地搜索和分页
  Future<Res<List<KemonoCreator>>> getCreators({
    bool forceRefresh = false,
  }) async {
    // 如果有缓存且不强制刷新,直接返回
    if (_creatorsCache != null && !forceRefresh) {
      return Res(_creatorsCache!);
    }

    const cacheKey = 'kemono_creators_list';

    // 尝试读取磁盘缓存
    if (!forceRefresh) {
      try {
        final cache = await CacheManager().findCache(cacheKey);
        if (cache != null && await cache.file.exists()) {
          final data = await cache.file.readAsString();
          final jsonData = jsonDecode(data) as List;
          final creators = jsonData
              .map((e) => KemonoCreator.fromJson(e as Map))
              .toList();
          if (creators.isNotEmpty) {
            _creatorsCache = creators;
            Log.d('Kemono getCreators cache hit');
            return Res(creators);
          }
        }
      } catch (e) {
        Log.e('Kemono getCreators cache read error: $e');
      }
    }

    try {
      final res = await get('/creators');
      if (res.error) {
        return Res.fromErrorRes(res);
      }

      final jsonData = jsonDecode(res.data) as List;
      final creators = jsonData
          .map((e) => KemonoCreator.fromJson(e as Map))
          .toList();

      // 缓存结果
      _creatorsCache = creators;

      // 写入磁盘缓存
      CacheManager().writeString(cacheKey, res.data);

      return Res(creators);
    } catch (e, s) {
      Log.e('Kemono getCreators error: $e\n$s');
      return Res(null, errorMessage: 'Failed to parse data: $e');
    }
  }

  /// 获取作者的图集列表
  ///
  /// [service] 服务类型
  /// [creatorId] 作者ID
  /// [offset] 分页偏移量 (必须是50的倍数)
  /// [useCache] 是否使用缓存，默认为true
  Future<Res<List<KemonoPostBrief>>> getCreatorPosts(
    String service,
    String creatorId,
    int offset, {
    bool useCache = true,
  }) async {
    final cacheKey = 'kemono_creator_posts_$service/$creatorId/$offset';

    // 尝试从缓存读取
    if (useCache) {
      try {
        final cached = await CacheManager().findCache(cacheKey);
        if (cached != null) {
          final file = File(cached.filePath);
          if (file.existsSync()) {
            final dataStr = await file.readAsString();
            final jsonData = jsonDecode(dataStr);
            final List postsData;
            if (jsonData is Map && jsonData.containsKey('posts')) {
              postsData = jsonData['posts'] as List;
            } else if (jsonData is List) {
              postsData = jsonData;
            } else {
              postsData = [];
            }
            if (postsData.isNotEmpty) {
              Log.d('Kemono getCreatorPosts cache hit: $cacheKey');
              final posts = postsData
                  .map((e) => KemonoPostBrief.fromJson(e as Map))
                  .toList();
              return Res(posts);
            }
          }
        }
      } catch (e) {
        Log.e('Kemono getCreatorPosts cache read error: $e');
      }
    }

    try {
      if (service == 'discord') {
        return await _getDiscordPosts(creatorId, offset);
      }

      final res = await get('/$service/user/$creatorId/posts?o=$offset');
      if (res.error) {
        return Res.fromErrorRes(res);
      }

      final jsonData = jsonDecode(res.data);
      // API可能返回 { "posts": [...] } 或直接返回 [...]
      final List postsData;
      if (jsonData is Map && jsonData.containsKey('posts')) {
        postsData = jsonData['posts'] as List;
      } else if (jsonData is List) {
        postsData = jsonData;
      } else {
        return const Res(null, errorMessage: 'Unexpected API response format');
      }
      final posts = postsData
          .map((e) => KemonoPostBrief.fromJson(e as Map))
          .toList();

      // 写入缓存 (1小时过期)
      try {
        await CacheManager().writeString(cacheKey, res.data);
      } catch (e) {
        Log.e('Kemono getCreatorPosts cache write error: $e');
      }

      return Res(posts);
    } catch (e, s) {
      Log.e('Kemono getCreatorPosts error: $e\n$s');
      return Res(null, errorMessage: 'Failed to parse data: $e');
    }
  }

  /// 本地搜索作者
  ///
  /// 在已缓存的作者列表中搜索,支持模糊匹配
  List<KemonoCreator> searchCreators(
    String keyword,
    List<KemonoCreator> allCreators,
  ) {
    if (keyword.isEmpty) {
      return allCreators;
    }

    final lowerKeyword = keyword.toLowerCase();
    return allCreators.where((creator) {
      return creator.title.toLowerCase().contains(lowerKeyword);
    }).toList();
  }

  /// 本地排序作者
  List<KemonoCreator> sortCreators(
    List<KemonoCreator> creators,
    KemonoCreatorSort sortType, {
    bool descending = true,
  }) {
    final sorted = List<KemonoCreator>.from(creators);

    int compare(KemonoCreator a, KemonoCreator b) {
      switch (sortType) {
        case KemonoCreatorSort.updated:
          final aTime = a.updated ?? DateTime(0);
          final bTime = b.updated ?? DateTime(0);
          return aTime.compareTo(bTime);
        case KemonoCreatorSort.favorited:
          return a.favorited.compareTo(b.favorited);
        case KemonoCreatorSort.indexed:
          final aTime = a.indexed ?? DateTime(0);
          final bTime = b.indexed ?? DateTime(0);
          return aTime.compareTo(bTime);
        case KemonoCreatorSort.name:
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      }
    }

    sorted.sort((a, b) {
      final result = compare(a, b);
      return descending ? -result : result;
    });

    return sorted;
  }

  /// 本地分页作者列表
  List<KemonoCreator> paginateCreators(
    List<KemonoCreator> creators,
    int page, {
    int pageSize = 50,
  }) {
    final start = page * pageSize;
    if (start >= creators.length) {
      return [];
    }
    final end = (start + pageSize).clamp(0, creators.length);
    return creators.sublist(start, end);
  }

  /// 清除作者缓存
  void clearCreatorsCache() {
    _creatorsCache = null;
  }

  /// 获取图片加载配置
  ///
  /// 用于 ComicSource 的 getImageLoadingConfig
  static Map<String, String> getImageHeaders() {
    return {
      'Referer': '$baseUrl/',
      // 使用 text/css 绕过某些过滤器的限制
      'Accept': 'text/css',
    };
  }

  /// 处理 Discord 特殊逻辑: 获取服务器内所有频道的帖子并合并
  Future<Res<List<KemonoPostBrief>>> _getDiscordPosts(
    String serverId,
    int offset,
  ) async {
    try {
      // 1. 获取服务器信息和频道列表
      final serverRes = await get('/discord/server/$serverId');
      if (serverRes.error) return Res.fromErrorRes(serverRes);

      final serverData = jsonDecode(serverRes.data) as Map;
      final channels = serverData['channels'] as List?;
      if (channels == null || channels.isEmpty) {
        return const Res([]);
      }

      // 2. 抓取所有频道的帖子 (由于 Discord 接口限制,暂时只取前几个频道或合并后的部分)
      // 注意: 这里为了简单起见,我们并发请求所有频道的第一页
      final allPosts = <KemonoPostBrief>[];
      final futures = channels.map(
        (c) => get('/discord/channel/${c['id']}?o=$offset'),
      );
      final results = await Future.wait(futures);

      for (var res in results) {
        if (!res.error) {
          final jsonData = jsonDecode(res.data) as List;
          allPosts.addAll(
            jsonData.map((e) => KemonoPostBrief.fromJson(e as Map)),
          );
        }
      }

      // 3. 按时间排序 (从新到旧)
      allPosts.sort((a, b) {
        if (a.published == null) return 1;
        if (b.published == null) return -1;
        return b.published!.compareTo(a.published!);
      });

      return Res(allPosts);
    } catch (e, s) {
      Log.e('Kemono _getDiscordPosts error: $e\n$s');
      return Res(null, errorMessage: e.toString());
    }
  }
}
