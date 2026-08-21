import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/network_log.dart';

/// 网络请求详情页面。
class NetworkLogDetailPage extends ConsumerWidget {
  const NetworkLogDetailPage({required this.log, super.key});

  final NetworkLog log;

  /// 以参考项目的 BottomSheet 样式打开请求详情，占屏幕高度的 90%。
  static Future<void> show(BuildContext context, NetworkLog log) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: 900),
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.9,
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        clipBehavior: Clip.antiAliasWithSaveLayer,
        child: NetworkLogDetailPage(log: log),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        AppBar(
          automaticallyImplyLeading: false,
          title: const Text('请求详情', style: TextStyle(fontSize: 16)),
          leading: IconButton(
            icon: const Icon(Icons.keyboard_arrow_down),
            onPressed: () => Navigator.pop(context),
          ),
          elevation: 0,
        ),
        Expanded(
          child: SelectionArea(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSection(context, '基本信息', [
                    _buildInfoRow('URL', log.url),
                    _buildInfoRow('Method', log.method),
                    _buildInfoRow('Protocol', log.protocolInfo.displayText),
                    _buildInfoRow('Backend', log.backend ?? 'Unknown'),
                    _buildInfoRow(
                      'Status',
                      log.statusCode?.toString() ?? 'Pending',
                      valueColor: _getStatusColor(log.statusCode),
                    ),
                    _buildInfoRow('Time', log.formattedRequestTime),
                    if (log.duration != null)
                      _buildInfoRow(
                        'Duration',
                        '${log.duration!.inMilliseconds} ms',
                      ),
                    if (log.fallback != null)
                      _buildInfoRow('Fallback', log.fallback!),
                  ]),
                  if (log.error != null)
                    _buildSection(context, '错误信息', [
                      Text(
                        log.error!,
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ]),
                  _buildSection(context, '请求头 (Request Headers)', [
                    _buildHeaders(log.requestHeaders),
                  ]),
                  if (log.requestBody != null)
                    _buildSection(context, '请求体 (Request Body)', [
                      _buildFormattedBodyView(context, log.requestBody!),
                    ]),
                  _buildSection(context, '响应头 (Response Headers)', [
                    _buildHeaders(log.responseHeaders),
                  ]),
                  if (log.responseBody != null)
                    _buildSection(context, '响应体 (Response Body)', [
                      _buildFormattedBodyView(context, log.responseBody!),
                    ]),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSection(
    BuildContext context,
    String title,
    List<Widget> children,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Theme.of(context).dividerColor.withValues(alpha: 0.05),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 12, color: valueColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaders(Map<String, dynamic>? headers) {
    if (headers == null || headers.isEmpty) {
      return const Text(
        '无',
        style: TextStyle(fontSize: 12, color: Colors.grey),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: headers.entries
          .map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${entry.key}: ',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '${entry.value}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildFormattedBodyView(BuildContext context, NetworkLogBody body) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (body.isTruncated)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Text(
                  '内容过长已截断显示',
                  style: TextStyle(color: Colors.orange, fontSize: 10),
                ),
              ),
            IconButton(
              icon: const Icon(Icons.copy, size: 16),
              tooltip: '复制显示内容',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: body.content));
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('已复制显示内容到剪贴板')));
              },
            ),
          ],
        ),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF282C34) : const Color(0xFFF9F9F9),
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.all(8),
          child: Text(
            body.content,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        ),
      ],
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
