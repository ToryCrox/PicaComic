import 'package:flutter/material.dart';
import 'package:pica_comic/comic_source/comic_chapter_group.dart';
import 'package:pica_comic/tools/translations.dart';

/// 按网站模块展示章节，各模块独立展开和倒序，操作始终使用章节 ID。
class GroupedChapters extends StatefulWidget {
  const GroupedChapters({
    super.key,
    required this.chapters,
    required this.groups,
    required this.onTap,
    this.currentId,
    this.visitedIds = const {},
    this.downloadedIds = const {},
    this.selectedIds = const {},
    this.onDownloadGroup,
    this.sliver = false,
  });
  final Map<String, String> chapters;
  final List<ComicChapterGroup> groups;
  final ValueChanged<String> onTap;
  final String? currentId;
  final Set<String> visitedIds;
  final Set<String> downloadedIds;
  final Set<String> selectedIds;
  final ValueChanged<ComicChapterGroup>? onDownloadGroup;
  final bool sliver;

  @override
  State<GroupedChapters> createState() => _GroupedChaptersState();
}

/// 展开和显示顺序按分组保存，不改变完整目录及下载选择。
class _GroupedChaptersState extends State<GroupedChapters> {
  final _expanded = <String>{};
  final _reversed = <String>{};

  /// 构建单个章节按钮。
  Widget _chapter(String id) {
    final selected = widget.selectedIds.contains(id) || widget.currentId == id;
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Material(
        color: selected
            ? Theme.of(context).colorScheme.primaryContainer
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => widget.onTap(id),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.chapters[id]!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: widget.visitedIds.contains(id) && !selected
                          ? Theme.of(context).colorScheme.outline
                          : null,
                    ),
                  ),
                ),
                if (widget.downloadedIds.contains(id))
                  Icon(Icons.download_done, size: 18, semanticLabel: '已下载'.tl),
                if (widget.selectedIds.contains(id))
                  const Icon(Icons.check, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 每组默认展示二十章，展开后仍使用惰性网格。
  Iterable<Widget> _group(ComicChapterGroup group) sync* {
    var ids = group.chapterIds.where(widget.chapters.containsKey).toList();
    if (_reversed.contains(group.id)) ids = ids.reversed.toList();
    final expanded = _expanded.contains(group.id);
    final count = expanded || ids.length <= 20 ? ids.length : 20;
    yield SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '${group.title.tl} (${ids.length})',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (widget.onDownloadGroup != null)
              IconButton(
                key: ValueKey('download-${group.id}'),
                tooltip: '下载当前分组'.tl,
                onPressed: () => widget.onDownloadGroup!(group),
                icon: const Icon(Icons.download_outlined),
              ),
            IconButton(
              key: ValueKey('sort-${group.id}'),
              tooltip: '排序'.tl,
              onPressed: () => setState(() {
                if (!_reversed.add(group.id)) _reversed.remove(group.id);
              }),
              icon: const Icon(Icons.swap_vert),
            ),
          ],
        ),
      ),
    );
    yield SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 240,
          mainAxisExtent: 58,
        ),
        delegate: SliverChildBuilderDelegate(
          (_, index) => _chapter(ids[index]),
          childCount: count,
        ),
      ),
    );
    if (ids.length > 20) {
      yield SliverToBoxAdapter(
        child: Center(
          child: TextButton.icon(
            key: ValueKey('expand-${group.id}'),
            onPressed: () => setState(() {
              if (!_expanded.add(group.id)) _expanded.remove(group.id);
            }),
            icon: Icon(expanded ? Icons.expand_less : Icons.expand_more),
            label: Text((expanded ? '收起' : '显示全部').tl),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final slivers = [for (final group in widget.groups) ..._group(group)];
    return widget.sliver
        ? SliverMainAxisGroup(slivers: slivers)
        : CustomScrollView(slivers: slivers);
  }
}

/// 按模块展示下载选章，展开或倒序后保留跨组选择。
class GroupedDownloadChapters extends StatefulWidget {
  const GroupedDownloadChapters({
    super.key,
    required this.chapters,
    required this.groups,
    required this.onDownload,
    this.downloadedIds = const {},
    this.onDelete,
  });
  final Map<String, String> chapters;
  final List<ComicChapterGroup> groups;
  final Set<String> downloadedIds;
  final ValueChanged<List<String>> onDownload;
  final Future<void> Function(String)? onDelete;

  @override
  State<GroupedDownloadChapters> createState() =>
      _GroupedDownloadChaptersState();
}

/// 下载选择不以显示位置为标识，避免倒序或切组导致错章。
class _GroupedDownloadChaptersState extends State<GroupedDownloadChapters> {
  final _selected = <String>{};
  late final _downloaded = Set<String>.of(widget.downloadedIds);

  /// 点击已下载章节时沿用删除确认流程。
  Future<void> _tap(String id) async {
    if (_downloaded.contains(id)) {
      if (widget.onDelete == null) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('删除'.tl),
          content: Text('确认删除已下载的章节?'.tl),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('取消'.tl),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('删除'.tl),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      try {
        await widget.onDelete!(id);
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.maybeOf(
            context,
          )?.showSnackBar(SnackBar(content: Text('${'删除失败'.tl}: $error')));
        }
        return;
      }
      if (mounted) setState(() => _downloaded.remove(id));
    } else {
      setState(() {
        if (!_selected.add(id)) _selected.remove(id);
      });
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text('下载漫画'.tl, style: Theme.of(context).textTheme.titleLarge),
        ),
        Expanded(
          child: GroupedChapters(
            chapters: widget.chapters,
            groups: widget.groups,
            downloadedIds: _downloaded,
            selectedIds: _selected,
            onTap: _tap,
            onDownloadGroup: (group) => widget.onDownload(
              group.chapterIds
                  .where((id) => !_downloaded.contains(id))
                  .toList(),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: _selected.isEmpty
                    ? null
                    : () => widget.onDownload(_selected.toList()),
                child: Text('${'下载选择'.tl} (${_selected.length})'),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
