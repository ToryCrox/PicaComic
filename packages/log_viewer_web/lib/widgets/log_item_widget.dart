import 'package:flutter/material.dart';
import 'package:log_viewer_shared/log_viewer_shared.dart';

/// 日志条目 Widget
class LogItemWidget extends StatelessWidget {
  final LogEntry entry;
  
  const LogItemWidget({
    super.key,
    required this.entry,
  });
  
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    // 根据日志级别选择颜色
    final backgroundColor = _getBackgroundColor(colorScheme);
    final textColor = _getTextColor(colorScheme);
    
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: backgroundColor,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 日志级别和时间戳
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getLevelColor(colorScheme),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    entry.level.name.toUpperCase(),
                    style: TextStyle(
                      color: textColor,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _formatTimestamp(entry.timestamp),
                  style: TextStyle(
                    color: colorScheme.onSurface.withOpacity(0.6),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 日志消息
            SelectableText(
              entry.message,
              style: TextStyle(
                color: textColor,
                fontSize: 14,
              ),
            ),
            // 错误信息
            if (entry.error != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: SelectableText(
                  entry.error!,
                  style: TextStyle(
                    color: colorScheme.onErrorContainer,
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
            // 堆栈跟踪
            if (entry.stackTrace != null) ...[
              const SizedBox(height: 8),
              ExpansionTile(
                title: const Text('Stack Trace'),
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: SelectableText(
                      entry.stackTrace!,
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
  
  Color _getBackgroundColor(ColorScheme colorScheme) {
    switch (entry.level) {
      case LogLevel.error:
      case LogLevel.fatal:
        return colorScheme.errorContainer;
      case LogLevel.warning:
        return colorScheme.errorContainer.withOpacity(0.5);
      case LogLevel.debug:
        return colorScheme.primaryContainer;
      default:
        return colorScheme.surface;
    }
  }
  
  Color _getTextColor(ColorScheme colorScheme) {
    switch (entry.level) {
      case LogLevel.error:
      case LogLevel.fatal:
        return colorScheme.onErrorContainer;
      case LogLevel.warning:
        return colorScheme.onErrorContainer;
      case LogLevel.debug:
        return colorScheme.onPrimaryContainer;
      default:
        return colorScheme.onSurface;
    }
  }
  
  Color _getLevelColor(ColorScheme colorScheme) {
    switch (entry.level) {
      case LogLevel.error:
      case LogLevel.fatal:
        return colorScheme.error;
      case LogLevel.warning:
        return colorScheme.error;
      case LogLevel.debug:
        return colorScheme.primary;
      default:
        return colorScheme.primary;
    }
  }
  
  String _formatTimestamp(DateTime timestamp) {
    return '${timestamp.year}-'
        '${timestamp.month.toString().padLeft(2, '0')}-'
        '${timestamp.day.toString().padLeft(2, '0')} '
        '${timestamp.hour.toString().padLeft(2, '0')}:'
        '${timestamp.minute.toString().padLeft(2, '0')}:'
        '${timestamp.second.toString().padLeft(2, '0')}.'
        '${timestamp.millisecond.toString().padLeft(3, '0')}';
  }
}

