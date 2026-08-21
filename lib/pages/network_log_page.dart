import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/network_log.dart';
import 'network_log_detail_page.dart';

/// 网络请求日志列表页面。
class NetworkLogPage extends ConsumerStatefulWidget {
  const NetworkLogPage({super.key});

  /// 以参考项目的 BottomSheet 样式打开网络日志页面，占屏幕高度的 80%。
  static Future<void> show(BuildContext context) {
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
    final logs = ref.watch(networkLogsProvider);
    final isCollecting = ref.watch(networkLogCollectingProvider);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down),
          onPressed: () => Navigator.pop(context),
        ),
        title: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: '搜索请求...',
              border: InputBorder.none,
              hintStyle: TextStyle(
                color: Colors.grey.withValues(alpha: 0.7),
                fontSize: 13,
              ),
              isDense: true,
            ),
            style: const TextStyle(fontSize: 13),
            onChanged: (value) {
              ref
                  .read(networkLogControllerProvider.notifier)
                  .setSearchQuery(value);
            },
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
            onPressed: () =>
                ref.read(networkLogControllerProvider.notifier).clear(),
          ),
        ],
      ),
      body: logs.isEmpty
          ? const Center(
              child: Text(
                '暂无请求日志',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            )
          : ListView.separated(
              itemCount: logs.length,
              separatorBuilder: (context, index) =>
                  const Divider(height: 1, thickness: 0.5),
              itemBuilder: (context, index) =>
                  _buildLogItem(context, logs[index]),
            ),
    );
  }

  Widget _buildLogItem(BuildContext context, NetworkLog log) {
    final statusColor = _getStatusColor(log.statusCode);
    return InkWell(
      onTap: () => NetworkLogDetailPage.show(context, log),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 50,
              padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                log.method,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    log.url,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        log.formattedRequestTime,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.grey,
                        ),
                      ),
                      if (log.duration != null) ...[
                        const Text(
                          ' • ',
                          style: TextStyle(fontSize: 10, color: Colors.grey),
                        ),
                        Text(
                          '${log.duration!.inMilliseconds}ms',
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
                      Text(
                        log.protocolInfo.displayText,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (log.statusCode != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  log.statusCode.toString(),
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

  Color _getStatusColor(int? statusCode) {
    if (statusCode == null) return Colors.grey;
    if (statusCode >= 200 && statusCode < 300) return Colors.green;
    if (statusCode >= 400) return Colors.red;
    if (statusCode >= 300) return Colors.orange;
    return Colors.grey;
  }
}
