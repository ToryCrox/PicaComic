import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:pica_comic/comic_source/comic_source.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/foundation/image_loader/cached_image.dart';
import 'package:pica_comic/foundation/local_favorites.dart';
import 'package:pica_comic/network/kemono_network/models.dart';
import 'package:pica_comic/network/kemono_network/kemono_main_network.dart';
import 'package:pica_comic/network/res.dart';
import 'package:pica_comic/pages/comic_page.dart';
import 'package:pica_comic/tools/time.dart';

/// Kemono 漫画源配置
final kemono = ComicSource.named(
  name: 'Kemono',
  key: 'kemono',
  filePath: 'built-in',

  // 账号配置 (预留,暂不实现)
  account: AccountConfig.named(
    logout: () {
      KemonoNetwork().logout();
      var source = ComicSource.find('kemono');
      source?.data["account"] = null;
      source?.saveData();
    },
    loginWebsite: 'https://kemono.cr/account/login',
    registerWebsite: 'https://kemono.cr/account/register',
  ),

  // 探索页面配置
  explorePages: [
    // Tab 1: 最新图集
    ExplorePageData.named(
      title: '最新',
      type: ExplorePageType.multiPageComicList,
      loadPage: (page) async {
        final offset = (page - 1) * KemonoNetwork.pageSize;
        final res = await KemonoNetwork().getPosts(offset);
        if (res.error) {
          return Res.fromErrorRes(res);
        }
        return Res(res.data, subData: 10000); // 假设有很多页
      },
    ),
    // Tab 2: 热门图集
    ExplorePageData.named(
      title: '热门',
      type: ExplorePageType.multiPageComicList,
      loadPage: (page) async {
        if (page > 1) {
          // 热门只有一页
          return const Res([]);
        }
        final res = await KemonoNetwork().getPopularPosts();
        if (res.error) {
          return Res.fromErrorRes(res);
        }
        return Res(res.data, subData: 1);
      },
    ),
    // Tab 3: 作者列表
    ExplorePageData.named(
      title: '作者',
      type: ExplorePageType.multiPageComicList,
      loadPage: (page) async {
        // 获取所有作者 (缓存)
        final res = await KemonoNetwork().getCreators();
        if (res.error) {
          return Res.fromErrorRes(res);
        }
        // 按最近更新排序
        final sorted = KemonoNetwork().sortCreators(
          res.data,
          KemonoCreatorSort.updated,
        );
        // 客户端分页
        final paginated = KemonoNetwork().paginateCreators(
          sorted,
          page - 1,
        );
        // 估算总页数
        final maxPage = (res.data.length / KemonoNetwork.pageSize).ceil();
        return Res(paginated, subData: maxPage);
      },
    ),
  ],

  // 搜索页面配置
  searchPageData: SearchPageData.named(
    loadPage: (keyword, page, options) async {
      // 判断搜索类型
      final searchType = options.isNotEmpty ? options[0] : 'posts';
      
      if (searchType == 'creators') {
        // 搜索作者 (本地搜索)
        final res = await KemonoNetwork().getCreators();
        if (res.error) {
          return Res.fromErrorRes(res);
        }
        final filtered = KemonoNetwork().searchCreators(keyword, res.data);
        final paginated = KemonoNetwork().paginateCreators(filtered, page - 1);
        final maxPage = (filtered.length / KemonoNetwork.pageSize).ceil();
        return Res(paginated, subData: maxPage);
      } else {
        // 搜索图集 (API搜索)
        final offset = (page - 1) * KemonoNetwork.pageSize;
        final res = await KemonoNetwork().getPosts(offset, keyword: keyword);
        if (res.error) {
          return Res.fromErrorRes(res);
        }
        return Res(res.data, subData: 10000);
      }
    },
    searchOptions: [
      SearchOptions(
        LinkedHashMap.of({
          'posts': '图集',
          'creators': '作者',
        }),
        '搜索类型',
      ),
    ],
  ),

  // 漫画详情加载
  loadComicInfo: (id) async {
    // id格式: service/userId/postId
    final parts = id.split('/');
    if (parts.length != 3) {
      return const Res(null, errorMessage: 'Invalid ID format');
    }
    final [service, userId, postId] = parts;
    
    final res = await KemonoNetwork().getPostDetail(service, userId, postId);
    if (res.error) {
      return Res.fromErrorRes(res);
    }
    
    final post = res.data;
    
    // 构建标签信息
    final tags = <String, List<String>>{
      '作者': [post.userName],
      '平台': [post.service],
    };
    
    if (post.published != null) {
      final dt = post.published!;
      tags['发布时间'] = ['${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}'];
    }
    
    // 图片数量
    final imageCount = post.imageUrls.length;
    if (imageCount > 0) {
      tags['图片'] = ['$imageCount 张'];
    }
    
    // 附件数量
    final archiveCount = post.archiveAttachments.length;
    if (archiveCount > 0) {
      tags['附件'] = ['$archiveCount 个'];
    }
    
    return Res(ComicInfoData(
      post.title.isNotEmpty ? post.title : '无标题',
      post.userName,
      post.cover,
      stripHtml(post.content),
      tags,
      null, // 单章节,不需要章节列表
      post.imageUrls.map((url) => url.replaceFirst('img.kemono.cr/data', 'img.kemono.cr/thumbnail/data')).toList(),
      null,
      0,
      null,
      'kemono',
      id,
    ));
  },

  // 加载漫画页面 (图片列表)
  loadComicPages: (id, ep) async {
    final parts = id.split('/');
    if (parts.length != 3) {
      return const Res(null, errorMessage: 'Invalid ID format');
    }
    final [service, userId, postId] = parts;
    
    final res = await KemonoNetwork().getPostDetail(service, userId, postId);
    if (res.error) {
      return Res.fromErrorRes(res);
    }
    
    return Res(res.data.imageUrls);
  },

  // 图片加载配置
  getImageLoadingConfig: (imageKey, comicId, epId) {
    return {
      'headers': KemonoNetwork.getImageHeaders(),
    };
  },

  // 缩略图加载配置
  getThumbnailLoadingConfig: (imageKey) {
    return {
      'headers': KemonoNetwork.getImageHeaders(),
    };
  },

  // ID匹配正则 (用于从URL识别ID)
  idMatcher: RegExp(r'^(patreon|fanbox|fantia|gumroad|subscribestar|dlsite)/user/\d+/post/\d+$'),

  // 自定义ComicTile
  comicTileBuilderOverride: (context, comic, options) {
    if (comic is KemonoPostBrief) {
      return _KemonoPostTile(comic, addonMenuOptions: options);
    } else if (comic is KemonoCreator) {
      return _KemonoCreatorTile(comic, addonMenuOptions: options);
    }
    // 不支持的Comic类型返回默认Tile
    return const SizedBox();
  },

  // 初始化
  initData: (source) async {
    await KemonoNetwork().init();
  },
);



/// Kemono 图集 Tile
class _KemonoPostTile extends ComicTile {
  final KemonoPostBrief post;

  @override
  final List<ComicTileMenuOption>? addonMenuOptions;

  const _KemonoPostTile(this.post, {this.addonMenuOptions});

  @override
  String get title => post.title.isNotEmpty ? post.title : '无标题';

  @override
  String get subTitle => post.userName;

  @override
  String get description {
    if (post.published != null) {
      return timeToString(post.published!);
    }
    return post.service;
  }

  @override
  Widget get image => AnimatedImage(
        image: CachedImageProvider(
          post.cover,
          headers: KemonoNetwork.getImageHeaders(),
        ),
        fit: BoxFit.cover,
        height: double.infinity,
        width: double.infinity,
        filterQuality: FilterQuality.medium,
      );

  @override
  void onTap_() {
    final id = '${post.service}/${post.userId}/${post.id}';
    App.mainNavigatorKey!.currentContext!.to(
      () => ComicPage(
        sourceKey: 'kemono',
        id: id,
        cover: post.cover,
      ),
    );
  }

  @override
  String get comicID => '${post.service}/${post.userId}/${post.id}';

  @override
  String? get sourceKey => 'kemono';

  @override
  List<String>? get tags => [post.service];

  @override
  FavoriteItem? get favoriteItem => FavoriteItem(
        target: comicID,
        name: title,
        coverPath: post.cover,
        author: post.userName,
        type: FavoriteType('kemono'.hashCode),
        tags: [post.service],
      );
}

/// Kemono 作者 Tile
class _KemonoCreatorTile extends ComicTile {
  final KemonoCreator creator;

  @override
  final List<ComicTileMenuOption>? addonMenuOptions;

  const _KemonoCreatorTile(this.creator, {this.addonMenuOptions});

  @override
  String get title => creator.title;

  @override
  String get subTitle => creator.service;

  @override
  String get description {
    final parts = <String>[];
    if (creator.favorited > 0) {
      parts.add('收藏: ${creator.favorited}');
    }
    if (creator.updated != null) {
      parts.add('更新: ${timeToString(creator.updated!)}');
    }
    return parts.join(' | ');
  }

  @override
  Widget get image => AnimatedImage(
        image: CachedImageProvider(
          creator.cover,
          headers: KemonoNetwork.getImageHeaders(),
        ),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        filterQuality: FilterQuality.medium,
      );

  @override
  void onTap_() {
    // 进入作者页面,显示该作者的所有图集
    App.mainNavigatorKey!.currentContext!.to(
      () => _KemonoCreatorPage(creator),
    );
  }

  @override
  String get comicID => '${creator.service}/user/${creator.id}';

  @override
  String? get sourceKey => 'kemono';

  @override
  List<String>? get tags => [creator.service];
}

/// Kemono 作者页面
class _KemonoCreatorPage extends StatefulWidget {
  final KemonoCreator creator;

  const _KemonoCreatorPage(this.creator);

  @override
  State<_KemonoCreatorPage> createState() => _KemonoCreatorPageState();
}

class _KemonoCreatorPageState extends State<_KemonoCreatorPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.creator.title),
      ),
      body: _KemonoCreatorList(
        creator: widget.creator,
      ),
    );
  }
}

class _KemonoCreatorList extends ComicsPage<KemonoPostBrief> {
  final KemonoCreator creator;

  const _KemonoCreatorList({required this.creator});

  @override
  Future<Res<List<KemonoPostBrief>>> getComics(int i) {
    return KemonoNetwork().getCreatorPosts(
      creator.service,
      creator.id,
      (i - 1) * KemonoNetwork.pageSize,
    );
  }

  @override
  String get sourceKey => 'kemono';

  @override
  String? get tag => 'kemono_creator_${creator.service}_${creator.id}';

  @override
  String? get title => null;
}
