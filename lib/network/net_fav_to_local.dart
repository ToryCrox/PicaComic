import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/foundation/app_settings_provider.dart';
import 'package:pica_comic/foundation/local_favorites.dart';
import 'package:pica_comic/foundation/log.dart';
import 'package:pica_comic/network/download/download_manager.dart';
import 'package:pica_comic/network/comic_source_services.dart';
import 'package:pica_comic/pages/favorites/local_favorites_providers.dart';
import 'package:pica_comic/pages/favorites/favorite_action_widgets.dart';
import 'package:pica_comic/pages/favorites/network_favorites_providers.dart';
import 'package:pica_comic/tools/translations.dart';

/// 导入网络收藏，完整抓取后创建本地收藏夹。
Future<void> startConvert(
  BuildContext context, {
  required String sourceKey,
  required String? folderId,
  required String folderName,
  bool agreeSync = false,
}) => _runImport(
  context,
  sourceKey: sourceKey,
  folderId: folderId,
  folder: folderName,
  create: true,
  sync: agreeSync
      ? FolderSync(
          folderName: folderName,
          key: sourceKey,
          syncData: jsonEncode({'folderId': folderId}),
        )
      : null,
);

/// 同步已有收藏夹；页数沿用用户设置。
Future<void> startFolderSync(BuildContext context, FolderSync? sync) async {
  if (sync == null) return;
  final container = ProviderScope.containerOf(context, listen: false);
  final pages = container
      .read(appSettingsProvider)
      .integer(AppSettingKeys.favoriteSyncPages, 1);
  await _runImport(
    context,
    sourceKey: sync.key,
    folderId: sync.syncDataObj['folderId'] as String?,
    folder: sync.folderName,
    create: false,
    sync: sync,
    pageLimit: pages,
  );
}

/// 临时持有独立分页会话，弹窗关闭后释放，任务自行完成取消检查。
Future<void> _runImport(
  BuildContext context, {
  required String sourceKey,
  required String? folderId,
  required String folder,
  required bool create,
  FolderSync? sync,
  int? pageLimit,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final query = (
    sourceKey: sourceKey,
    folderId: folderId,
    sessionId: UniqueKey().toString(),
  );
  final provider = networkFavoriteLoaderProvider(query);
  final subscription = container.listen(provider, (_, __) {});
  final generation = container
      .read(networkFavoriteRevisionProvider(sourceKey))
      .session;
  try {
    final loader = subscription.read();
    final repository = container.read(localFavoritesRepositoryProvider);
    final manager = container.read(downloadManagerProvider.notifier);
    final ehNetwork = sourceKey == 'ehentai'
        ? container.read(ehNetworkProvider)
        : null;
    // 服务闭包只持有持久化和网络依赖，不持有页面 Ref。
    Future<void> prepareCovers(List<FavoriteItem> items) async {
      await manager.init();
      final cookie = ehNetwork == null ? '' : await ehNetwork.getCookies(false);
      for (final item in items) {
        try {
          await repository.getCover(
            item,
            manager: manager,
            loadDownloadedCover: manager.getCover,
            ehCookie: cookie,
          );
        } catch (error, stack) {
          Log.w('收藏封面准备失败', error: error, stackTrace: stack);
        }
      }
    }

    await showFavoriteJobDialog(
      context,
      folder: folder,
      title: create ? '导入收藏'.tl : '同步收藏'.tl,
      start: (job) => job.importNetwork(
        loadPage: loader.load,
        convert: FavoriteItem.fromBaseComic,
        targetFolder: folder,
        create: create,
        sync: sync,
        pageLimit: pageLimit,
        prepareCovers: prepareCovers,
        isSessionCurrent: () =>
            container
                .read(networkFavoriteRevisionProvider(sourceKey))
                .session ==
            generation,
      ),
    );
  } catch (error) {
    showToast(message: '收藏导入失败: $error');
  } finally {
    subscription.close();
  }
}
