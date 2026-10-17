import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/foundation/file_utils.dart';
import 'package:pica_comic/foundation/history_providers.dart';
import 'package:pica_comic/foundation/local_history.dart';
import 'package:pica_comic/tools/translations.dart';

import '../reader/comic_reading_page.dart';
import 'local_comic_page.dart';
import 'local_comic_tile.dart';
import 'local_thumbs_page.dart';

/// 本地阅读历史，持久化列表由 Riverpod 管理。
class LocalHistoryPage extends ConsumerWidget {
  const LocalHistoryPage({super.key});

  /// 操作失败时保持现有数据并给出提示。
  Future<void> _perform(Future<void> Function() operation) async {
    try {
      await operation();
    } catch (error) {
      showToast(message: '操作失败: $error');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(allLocalHistoryProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text('历史记录'.tl),
        actions: [
          IconButton(
            tooltip: '清理失效记录'.tl,
            icon: const Icon(Icons.cleaning_services),
            onPressed: () => _perform(() async {
              final count = await ref
                  .read(historyActionsProvider.notifier)
                  .clearInvalidLocal();
              showToast(message: '已清理 $count 条失效记录'.tl);
            }),
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            onPressed: () => showConfirmDialog(
              context,
              '清除历史记录'.tl,
              '确认清除所有历史记录?'.tl,
              () => _perform(
                ref.read(historyActionsProvider.notifier).clearLocal,
              ),
            ),
          ),
        ],
      ),
      body: history.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: TextButton(
            onPressed: () => ref.invalidate(allLocalHistoryProvider),
            child: Text('加载失败，点击重试: $error'),
          ),
        ),
        data: (items) => items.isEmpty
            ? Center(child: Text('暂无记录'.tl))
            : _buildGrid(context, ref, items),
      ),
    );
  }

  /// 虚拟网格按目录标识复用卡片。
  Widget _buildGrid(
    BuildContext context,
    WidgetRef ref,
    List<LocalHistory> items,
  ) {
    final paths = items.map((e) => e.path).toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / 180).floor().clamp(2, 100);
        return GridView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.7,
          ),
          itemBuilder: (context, index) {
            final item = items[index];
            final model = LocalComicModel(
              path: item.path,
              title: path.basename(item.path),
              cover: '',
            );
            return LocalComicTile(
              key: ValueKey(item.path),
              model: model,
              onReload: () {},
              allDirPaths: paths,
              onTap: (_) async {
                final record = await ref.read(
                  localHistoryEntryProvider(item.path).future,
                );
                await App.globalTo(
                  () => ComicReadingPage.localComic(
                    item.path,
                    model.title,
                    initialPage: record?.pageIndex ?? 1,
                    isReversed: record?.isReversed == 1,
                  ),
                );
              },
              onSecondaryTap: (details) =>
                  _showMenu(context, ref, model, paths, details.globalPosition),
              onLongPress: () => _showMenu(
                context,
                ref,
                model,
                paths,
                Offset(
                  constraints.maxWidth / 2,
                  MediaQuery.sizeOf(context).height / 2,
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// 桌面右键与移动端长按使用相同操作。
  void _showMenu(
    BuildContext context,
    WidgetRef ref,
    LocalComicModel model,
    List<String> paths,
    Offset position,
  ) {
    showContextMenu(
      context: context,
      globalPosition: position,
      items: [
        popupMenuItem(
          text: '查看详情'.tl,
          icon: Icons.info_outline,
          onTap: () => App.globalTo(
            () => LocalThumbsPage(dirPath: model.path, allDirPaths: paths),
          ),
        ),
        popupMenuItem(
          text: '清除此条历史记录'.tl,
          icon: Icons.history_toggle_off,
          onTap: () => _perform(
            () => ref
                .read(historyActionsProvider.notifier)
                .removeLocal(model.path),
          ),
        ),
        popupMenuItem(
          text: '打开文件夹'.tl,
          icon: Icons.folder_open,
          onTap: () => FileUtils.openFileOrDirectory(model.path),
        ),
      ],
    );
  }
}
