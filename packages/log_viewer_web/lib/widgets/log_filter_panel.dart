import 'package:flutter/material.dart';
import 'package:log_viewer_shared/log_viewer_shared.dart';

/// 日志过滤面板
class LogFilterPanel extends StatelessWidget {
  final Set<LogLevel> selectedLevels;
  final ValueChanged<Set<LogLevel>> onLevelsChanged;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  
  const LogFilterPanel({
    super.key,
    required this.selectedLevels,
    required this.onLevelsChanged,
    required this.searchQuery,
    required this.onSearchChanged,
  });
  
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 搜索框
            TextField(
              decoration: const InputDecoration(
                labelText: '搜索日志',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: onSearchChanged,
            ),
            const SizedBox(height: 16),
            // 日志级别过滤
            const Text(
              '日志级别:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: LogLevel.values.map((level) {
                final isSelected = selectedLevels.contains(level);
                return FilterChip(
                  label: Text(level.name.toUpperCase()),
                  selected: isSelected,
                  onSelected: (selected) {
                    final newLevels = Set<LogLevel>.from(selectedLevels);
                    if (selected) {
                      newLevels.add(level);
                    } else {
                      newLevels.remove(level);
                    }
                    onLevelsChanged(newLevels);
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

