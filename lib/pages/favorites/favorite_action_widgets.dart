import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/foundation/local_favorites.dart';
import 'package:pica_comic/tools/translations.dart';

import 'favorite_jobs.dart';
import 'local_favorites_providers.dart';

/// 无 WidgetRef 的菜单从当前界面作用域读取同一操作入口。
LocalFavorites favoriteActionsOf(BuildContext context) =>
    ProviderScope.containerOf(
      context,
      listen: false,
    ).read(localFavoritesProvider.notifier);

/// 操作成功后才关闭弹窗，错误保持当前界面。
Future<bool> performFavoriteAction(Future<void> Function() action) async {
  try {
    await action();
    return true;
  } catch (error) {
    showToast(message: '收藏操作失败: $error');
    return false;
  }
}

/// 通用卡片收藏弹窗，选择为本地草稿，持久化走统一 Notifier。
class FavoriteAddDialog extends ConsumerStatefulWidget {
  const FavoriteAddDialog({required this.item, this.initialFolder, super.key});
  final FavoriteItem item;
  final String? initialFolder;
  @override
  ConsumerState<FavoriteAddDialog> createState() => _FavoriteAddDialogState();
}

class _FavoriteAddDialogState extends ConsumerState<FavoriteAddDialog> {
  String? _folder;
  @override
  void initState() {
    super.initState();
    _folder = widget.initialFolder;
  }

  @override
  Widget build(BuildContext context) {
    final folders = ref.watch(localFavoritesProvider);
    final pending = ref.watch(favoriteActionStatusProvider).isLoading;
    return SimpleDialog(
      title: Text('添加收藏'.tl),
      children: [
        folders.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => TextButton(
            onPressed: () => ref.invalidate(localFavoritesProvider),
            child: Text('加载失败，点击重试: $error'),
          ),
          data: (data) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (data.folderNames.isNotEmpty)
                ListTile(
                  title: Text('收藏夹'.tl),
                  trailing: Select(
                    outline: true,
                    width: 156,
                    values: data.folderNames,
                    initialValue: data.folderNames.contains(_folder)
                        ? data.folderNames.indexOf(_folder!)
                        : null,
                    onChange: (index) =>
                        setState(() => _folder = data.folderNames[index]),
                  ),
                ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: pending || !data.folderNames.contains(_folder)
                    ? null
                    : () async {
                        final actions = ref.read(
                          localFavoritesProvider.notifier,
                        );
                        if (await performFavoriteAction(
                              () => actions.addComic(_folder!, widget.item),
                            ) &&
                            context.mounted) {
                          Navigator.pop(context);
                        }
                      },
                child: Text('确认'.tl),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

/// 在构建之前启动任务，进度界面只观察 Provider。
Future<void> showFavoriteJobDialog(
  BuildContext context, {
  required String folder,
  required String title,
  required Future<FavoriteJobState> Function(FavoriteJob job) start,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final controller = container.read(favoriteJobProvider(folder).notifier);
  unawaited(start(controller));
  await showDialog<void>(
    context: context,
    builder: (_) => _FavoriteJobDialog(folder: folder, title: title),
  );
  controller.cancel();
}

/// 任务取消与提交阶段的退出行为。
class _FavoriteJobDialog extends ConsumerWidget {
  const _FavoriteJobDialog({required this.folder, required this.title});
  final String folder;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final job = ref.watch(favoriteJobProvider(folder));
    return PopScope(
      canPop: job.phase != FavoriteJobPhase.committing,
      child: AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (job.running)
                LinearProgressIndicator(
                  value: job.total == null || job.total == 0
                      ? null
                      : job.completed / job.total!,
                ),
              const SizedBox(height: 12),
              Text('${job.completed}/${job.total ?? "?"}'),
              if (job.phase == FavoriteJobPhase.committing) Text('正在保存'.tl),
              if (!job.running)
                Text(
                  '成功: ${job.success}  失败: ${job.failures}  失效: ${job.unavailable}',
                ),
              if (job.phase == FavoriteJobPhase.cancelled) Text('已取消'.tl),
              if (job.error != null) Text(job.error!),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: job.phase == FavoriteJobPhase.committing
                ? null
                : () {
                    ref.read(favoriteJobProvider(folder).notifier).cancel();
                    Navigator.pop(context);
                  },
            child: Text(job.running ? '取消'.tl : '关闭'.tl),
          ),
        ],
      ),
    );
  }
}
