import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../foundation/app.dart';
import '../network/network_artifact_preview.dart';
import '../network/network_log.dart';
import 'network_log_detail_page.dart';

/// 网络请求日志列表页面。
class NetworkLogPage extends ConsumerStatefulWidget {
  const NetworkLogPage({super.key});

  /// 打开网络日志面板。
  static Future<void> show(BuildContext context) {
    if (App.isDesktop) {
      final size = MediaQuery.sizeOf(context);
      return showDialog<void>(
        context: context,
        barrierColor: Colors.black54,
        builder: (context) => Dialog(
          insetPadding: const EdgeInsets.all(24),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: math.min(size.width - 48, 1280),
            height: math.min(size.height - 48, 900),
            child: const NetworkLogPage(),
          ),
        ),
      );
    }
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: 900),
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        clipBehavior: Clip.antiAliasWithSaveLayer,
        child: const NetworkLogPage(),
      ),
    );
  }

  @override
  ConsumerState<NetworkLogPage> createState() => _NetworkLogPageState();
}

class _NetworkLogPageState extends ConsumerState<NetworkLogPage> {
  late final TextEditingController _searchController;
  String? _selectedEntryId;
  double _desktopSplit = 0.46;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(networkLogControllerProvider);
    final entries = ref.watch(networkLogEntriesProvider);
    final isDesktop = App.isDesktop;
    final selectedEntry = entries.cast<NetworkLogEntry?>().firstWhere(
      (entry) => entry?.id == _selectedEntryId,
      orElse: () => null,
    );

    return Scaffold(
      appBar: _buildAppBar(context, state.isCollecting, isDesktop),
      body: Column(
        children: [
          _buildFilterBar(context, state.requestKindFilter),
          Expanded(
            child: isDesktop
                ? _buildDesktopBody(context, entries, selectedEntry)
                : _buildLogList(context, entries, compact: false),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    bool isCollecting,
    bool isDesktop,
  ) {
    return AppBar(
      automaticallyImplyLeading: false,
      titleSpacing: 0,
      leading: IconButton(
        icon: Icon(isDesktop ? Icons.close : Icons.keyboard_arrow_down),
        onPressed: () => Navigator.pop(context),
      ),
      title: Padding(
        padding: const EdgeInsets.only(right: 8),
        child: TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: '搜索请求、Host 或类型...',
            border: InputBorder.none,
            hintStyle: TextStyle(
              color: Colors.grey.withValues(alpha: 0.7),
              fontSize: 13,
            ),
            isDense: true,
          ),
          style: const TextStyle(fontSize: 13),
          onChanged: (value) => ref
              .read(networkLogControllerProvider.notifier)
              .setSearchQuery(value),
        ),
      ),
      actions: [
        Row(
          children: [
            const Text(
              '采集',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
            Transform.scale(
              scale: 0.7,
              child: Switch(
                value: isCollecting,
                activeThumbColor: Theme.of(context).primaryColor,
                onChanged: (value) => ref
                    .read(networkLogControllerProvider.notifier)
                    .setCollecting(value),
              ),
            ),
          ],
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline, size: 20),
          tooltip: '清空日志',
          onPressed: () {
            ref.read(networkLogControllerProvider.notifier).clear();
            setState(() => _selectedEntryId = null);
          },
        ),
      ],
    );
  }

  Widget _buildFilterBar(
    BuildContext context,
    NetworkRequestKind? selectedKind,
  ) {
    return SizedBox(
      height: 40,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        scrollDirection: Axis.horizontal,
        children: [
          _buildFilterChip(context, 'All', null, selectedKind),
          ...NetworkRequestKind.values.map(
            (kind) => _buildFilterChip(context, kind.label, kind, selectedKind),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(
    BuildContext context,
    String label,
    NetworkRequestKind? kind,
    NetworkRequestKind? selectedKind,
  ) {
    final selected =
        kind == selectedKind || (kind == null && selectedKind == null);
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 10)),
        selected: selected,
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        onSelected: (_) => ref
            .read(networkLogControllerProvider.notifier)
            .setRequestKindFilter(kind),
      ),
    );
  }

  Widget _buildDesktopBody(
    BuildContext context,
    List<NetworkLogEntry> entries,
    NetworkLogEntry? selectedEntry,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final maxLeftWidth = math.max(280.0, availableWidth - 360.0);
        final leftWidth = (availableWidth * _desktopSplit)
            .clamp(280.0, maxLeftWidth)
            .toDouble();
        return Row(
          children: [
            SizedBox(
              width: leftWidth,
              child: _buildLogList(context, entries, compact: true),
            ),
            _buildResizeHandle(context, availableWidth),
            Expanded(
              child: selectedEntry == null
                  ? const Center(
                      child: Text(
                        '选择一个请求查看详情',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    )
                  : NetworkLogDetailPage(entry: selectedEntry, embedded: true),
            ),
          ],
        );
      },
    );
  }

  Widget _buildResizeHandle(BuildContext context, double availableWidth) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) {
          if (availableWidth <= 0) return;
          final minLeftWidth = math.min(280.0, availableWidth * 0.5);
          final maxLeftWidth = math.max(
            minLeftWidth,
            availableWidth - 360.0,
          );
          setState(() {
            final targetWidth = (_desktopSplit * availableWidth) +
                details.delta.dx;
            _desktopSplit =
                (targetWidth.clamp(minLeftWidth, maxLeftWidth) /
                        availableWidth)
                    .toDouble();
          });
        },
        child: SizedBox(
          width: 9,
          child: Center(
            child: Container(width: 1, color: Theme.of(context).dividerColor),
          ),
        ),
      ),
    );
  }

  Widget _buildLogList(
    BuildContext context,
    List<NetworkLogEntry> entries, {
    required bool compact,
  }) {
    if (entries.isEmpty) {
      return const Center(
        child: Text(
          '暂无请求日志',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
      );
    }
    return ListView.separated(
      itemCount: entries.length,
      separatorBuilder: (context, index) =>
          const Divider(height: 1, thickness: 0.5),
      itemBuilder: (context, index) =>
          _buildLogItem(context, entries[index], compact: compact),
    );
  }

  Widget _buildLogItem(
    BuildContext context,
    NetworkLogEntry entry, {
    required bool compact,
  }) {
    final statusColor = _getStatusColor(entry.statusCode);
    final selected = entry.id == _selectedEntryId;
    final thumbnail = entry.isImageResponse && entry.artifactPath != null;
    return InkWell(
      onTap: () {
        if (App.isDesktop) {
          setState(() => _selectedEntryId = entry.id);
        } else {
          NetworkLogDetailPage.showEntry(context, entry);
        }
      },
      child: Container(
        color: selected
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.08)
            : null,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 12,
          vertical: compact ? 6 : 8,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (thumbnail) ...[
              SizedBox(
                width: 36,
                height: 36,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: InkWell(
                    onTap: () => openNetworkImagePreview(
                      context,
                      entry.artifactPath!,
                      title: entry.url,
                    ),
                    child: buildNetworkArtifactPreview(
                      entry.artifactPath!,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
            ],
            _buildKindBadge(context, entry.requestKind),
            const SizedBox(width: 6),
            Container(
              width: compact ? 42 : 50,
              padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 3),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                entry.method,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.url,
                    maxLines: compact ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Text(
                        entry.formattedRequestTime,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.grey,
                        ),
                      ),
                      if (entry.duration != null) ...[
                        const Text(
                          ' • ',
                          style: TextStyle(fontSize: 10, color: Colors.grey),
                        ),
                        Text(
                          '${entry.duration!.inMilliseconds}ms',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                      const Text(
                        ' • ',
                        style: TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                      Flexible(
                        child: Text(
                          entry.protocolDisplayText,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                      if (entry.isGrouped) ...[
                        const Text(
                          ' • ',
                          style: TextStyle(fontSize: 10, color: Colors.grey),
                        ),
                        Text(
                          '${entry.logs.length} 分片',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            if (entry.statusCode != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  entry.statusCode.toString(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildKindBadge(BuildContext context, NetworkRequestKind kind) {
    final color = switch (kind) {
      NetworkRequestKind.api => Colors.indigo,
      NetworkRequestKind.html => Colors.orange,
      NetworkRequestKind.image => Colors.green,
      NetworkRequestKind.file => Colors.brown,
      NetworkRequestKind.ai => Colors.purple,
      NetworkRequestKind.other => Colors.grey,
    };
    return Container(
      width: 42,
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        kind.label,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 9,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Color _getStatusColor(int? statusCode) {
    if (statusCode == null) return Colors.grey;
    if (statusCode >= 200 && statusCode < 300) return Colors.green;
    if (statusCode >= 400) return Colors.red;
    if (statusCode >= 300) return Colors.orange;
    return Colors.grey;
  }
}
