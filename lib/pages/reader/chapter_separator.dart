import 'package:flutter/material.dart';

import '../../tools/translations.dart';
import 'continuous_reader_data.dart';
import 'touch_control.dart';

/// 章节分隔、加载状态和局部重试入口，不占用漫画页码。
class ChapterSeparator extends StatelessWidget {
  const ChapterSeparator({
    required this.item,
    required this.title,
    required this.previousTitle,
    required this.onRetry,
    required this.onSkip,
    super.key,
  });

  final ReaderItem item;
  final String title;
  final String? previousTitle;
  final VoidCallback onRetry;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isHeader = item.kind == ReaderItemKind.header;
    String status;
    switch (item.kind) {
      case ReaderItemKind.error:
        status = '章节加载失败'.tl;
      case ReaderItemKind.empty:
        status = '本章暂无图片'.tl;
      default:
        status = '正在加载章节'.tl;
    }
    return Listener(
      onPointerDown: (_) => TapController.ignoreNextTap = true,
      child: Container(
        constraints: const BoxConstraints(minHeight: 72),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: colors.surfaceContainer,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isHeader && previousTitle != null)
              Text(
                '$previousTitle · ${'章节结束'.tl}',
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
            Text(
              '${item.episode} · $title',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.onSurface),
            ),
            if (!isHeader) ...[
              const SizedBox(height: 4),
              Text(status, style: TextStyle(color: colors.onSurfaceVariant)),
              if (item.kind == ReaderItemKind.loading)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              if (item.kind == ReaderItemKind.error ||
                  item.kind == ReaderItemKind.empty)
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(onPressed: onRetry, child: Text('重试'.tl)),
                    TextButton(onPressed: onSkip, child: Text('跳过本章'.tl)),
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }
}
