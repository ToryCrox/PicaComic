import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pica_comic/comic_source/comic_source.dart';
import 'package:pica_comic/foundation/def.dart';
import 'package:pica_comic/foundation/disk_cache.dart';
import 'package:pica_comic/foundation/log.dart';
import 'package:pica_comic/network/base_comic.dart';
import 'package:pica_comic/network/network_client_manager.dart';
import 'package:pica_comic/network/res.dart';

import 'manhuagui_parser.dart';

/// 漫画柜网络服务，由应用 ProviderScope 共享。
final manhuaguiNetworkProvider = Provider<ManhuaguiNetwork>(
  (ref) => ManhuaguiNetwork(ref.watch(networkClientManagerProvider).apiDio),
);

/// 未登录的评论排序。
enum ManhuaguiCommentSort { latest, hot }

/// 漫画柜请求与磁盘缓存，复用应用网络配置及 Cookie。
class ManhuaguiNetwork {
  ManhuaguiNetwork(this.dio, {this.cacheEnabled = true});

  final Dio dio;
  final bool cacheEnabled;
  static const baseUrl = ManhuaguiParser.baseUrl;

  /// 图片管理器会补充连接请求头，因此每次提供可变副本。
  static Map<String, String> get imageHeaders => {
    'User-Agent': webUA,
    'Referer': '$baseUrl/',
  };
  final _pending = <String, Future<String>>{};

  /// 合并相同 URL 的在途请求，成功后保存 HTML 供首屏缓存使用。
  Future<String> _html(String path) => _pending.putIfAbsent(path, () async {
    try {
      final response = await dio.get<String>(
        '$baseUrl$path',
        options: Options(
          responseType: ResponseType.plain,
          headers: imageHeaders,
        ),
      );
      final body = response.data;
      if (body == null || body.isEmpty) throw const FormatException('漫画柜返回空响应');
      if (cacheEnabled &&
          (path.startsWith('/list/') ||
              path.startsWith('/s/') ||
              path == '/update/')) {
        await DiskCache.writeModel('manhuagui-html-$path', {'html': body});
      }
      return body;
    } finally {
      _pending.remove(path);
    }
  });

  /// 统一将请求和解析异常转换为可重试错误。
  Future<Res<T>> _request<T>(Future<Res<T>> Function() action) async {
    try {
      return await action();
    } catch (error, stack) {
      Log.w('漫画柜请求失败', error: error, stackTrace: stack);
      return Res.error('漫画柜加载失败：$error');
    }
  }

  /// 构建分类筛选、排序与分页地址。
  static String catalogPath(
    Map<String, String> filters,
    String sort,
    int page,
  ) {
    final values = [
      'area',
      'genre',
      'age',
      'year',
      'letter',
      'status',
    ].map((key) => filters[key] ?? '').where((value) => value.isNotEmpty);
    final category = values.join('_');
    final folder = '/list/${category.isEmpty ? '' : '$category/'}';
    final order = const {'index', 'update', 'view', 'rate'}.contains(sort)
        ? sort
        : 'index';
    if (page == 1 && order == 'index') return folder;
    return '$folder$order${page > 1 ? '_p$page' : ''}.html';
  }

  /// 加载分类目录。
  Future<Res<List<BaseComic>>> catalog({
    Map<String, String> filters = const {},
    String sort = 'update',
    int page = 1,
  }) => _request(
    () async =>
        ManhuaguiParser.comics(await _html(catalogPath(filters, sort, page))),
  );

  /// 网站最近更新页一次包含最近七天，作为一个可虚拟滚动的列表。
  Future<Res<List<BaseComic>>> updates(int page) => _request(
    () async => page > 1
        ? const Res(<BaseComic>[], subData: 1)
        : ManhuaguiParser.comics(await _html('/update/'), updates: true),
  );

  /// 加载搜索结果，关键词作为单一路径段编码。
  Future<Res<List<BaseComic>>> search(
    String keyword,
    int page, {
    String sort = '',
  }) => _request(() async {
    final order = const {'', '1', '2', '3'}.contains(sort) ? sort : '';
    final path =
        '/s/${Uri.encodeComponent(keyword.trim())}${order.isEmpty ? '' : '_o$order'}${page > 1 ? '_p$page' : ''}.html';
    return ManhuaguiParser.comics(await _html(path), search: true);
  });

  /// 读取已缓存详情。
  Future<ComicInfoData?> infoCache(String id) =>
      DiskCache.readModel('manhuagui-info-$id', ComicInfoData.fromMap);

  /// 加载分组详情并缓存完整元数据。
  Future<Res<ComicInfoData>> info(String id) => _request(() async {
    final result = ManhuaguiParser.info(await _html('/comic/$id/'), id);
    if (cacheEnabled) {
      await DiskCache.writeModel('manhuagui-info-$id', result.toMap());
    }
    return Res(result);
  });

  /// 图片签名不跨请求缓存，每次重试重新获取章节数据。
  Future<Res<List<String>>> pages(String id, String chapterId) =>
      _request(() async {
        if (!RegExp(r'^\d+$').hasMatch(id) ||
            !RegExp(r'^\d+$').hasMatch(chapterId)) {
          throw const FormatException('漫画柜章节 ID 无效');
        }
        return Res(
          ManhuaguiParser.pages(await _html('/comic/$id/$chapterId.html')),
        );
      });

  /// 分页读取最新或热门评论；两个排序使用独立 URL 与在途请求。
  Future<Res<List<ManhuaguiCommentThread>>> comments(
    String id,
    int page,
    ManhuaguiCommentSort sort,
  ) => _request(
    () async => ManhuaguiParser.comments(
      await _html(
        '/tools/submit_ajax.ashx?action=comment_list&book_id=${Uri.encodeQueryComponent(id)}&page_index=$page${sort == ManhuaguiCommentSort.hot ? '&hot=1' : ''}',
      ),
    ),
  );

  /// 从分类页面读取完整筛选项，以网站实际可用值为准。
  Future<Res<Map<String, Map<String, String>>>> filters() => _request(() async {
    final document = ManhuaguiParser.filters(await _html('/list/'));
    return Res(document);
  });

  /// 读取列表首屏缓存，失败时仍可继续网络加载。
  Future<List<BaseComic>> listCache({
    int section = 0,
    Map<String, String> filters = const {},
    String sort = 'update',
  }) async {
    final path = section == 0 ? '/update/' : catalogPath(filters, sort, 1);
    final cached = await DiskCache.readModel(
      'manhuagui-html-$path',
      (map) => map['html'] as String,
    );
    if (cached == null) return [];
    try {
      return ManhuaguiParser.comics(cached, updates: section == 0).data;
    } on FormatException {
      return [];
    }
  }
}
