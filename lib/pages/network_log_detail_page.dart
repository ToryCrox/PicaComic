import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/network_artifact_preview.dart';
import '../network/network_log.dart';

/// 网络请求详情页面。
class NetworkLogDetailPage extends ConsumerWidget {
  const NetworkLogDetailPage({
    this.log,
    this.entry,
    this.embedded = false,
    super.key,
  }) : assert(log != null || entry != null);

  final NetworkLog? log;
  final NetworkLogEntry? entry;
  final bool embedded;

  NetworkLogEntry get displayEntry =>
      entry ?? NetworkLogEntry(List<NetworkLog>.unmodifiable([log!]));

  /// 以参考项目的 BottomSheet 样式打开请求详情。
  static Future<void> show(BuildContext context, NetworkLog log) {
    return showEntry(context, NetworkLogEntry([log]));
  }

  /// 打开单条或合并后的网络详情。
  static Future<void> showEntry(BuildContext context, NetworkLogEntry entry) {
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
        child: NetworkLogDetailPage(entry: entry),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final displayEntry = this.displayEntry;
    final primary = displayEntry.primary;
    final detail = SelectionArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(bottom: embedded ? 12 : 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSection(context, '基本信息', [
              _buildInfoRow('Type', primary.requestKind.label),
              _buildInfoRow('URL', primary.url),
              _buildInfoRow('Method', primary.method),
              _buildInfoRow('Protocol', primary.protocolInfo.displayText),
              _buildInfoRow('Backend', primary.backend ?? 'Unknown'),
              if (primary.contentType != null)
                _buildInfoRow('Content-Type', primary.contentType!),
              _buildInfoRow(
                'Status',
                displayEntry.hasError
                    ? '${displayEntry.statusCode?.toString() ?? 'HTTP'} · 应用失败'
                    : displayEntry.statusCode?.toString() ?? 'Pending',
                valueColor: _getStatusColor(
                  displayEntry.statusCode,
                  hasError: displayEntry.hasError,
                ),
              ),
              _buildInfoRow('Time', displayEntry.formattedRequestTime),
              if (displayEntry.duration != null)
                _buildInfoRow(
                  'Duration',
                  '${displayEntry.duration!.inMilliseconds} ms',
                ),
              if (displayEntry.byteLength > 0)
                _buildInfoRow('Size', _formatBytes(displayEntry.byteLength)),
              if (primary.transferId != null)
                _buildInfoRow('Transfer ID', primary.transferId!),
              if (displayEntry.artifactPath != null)
                _buildInfoRow('File', displayEntry.artifactPath!),
              if (primary.fallback != null)
                _buildInfoRow('Fallback', primary.fallback!),
            ]),
            if (displayEntry.isImageResponse &&
                displayEntry.artifactPath != null)
              _buildSection(context, '图片预览', [
                Container(
                  constraints: const BoxConstraints(maxHeight: 420),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).dividerColor.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.all(8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () => openNetworkImagePreview(
                      context,
                      displayEntry.artifactPath!,
                      title: primary.url,
                    ),
                    child: SizedBox(
                      height: 360,
                      child: buildNetworkArtifactPreview(
                        displayEntry.artifactPath!,
                        memCacheWidth: networkArtifactPreviewMemCacheWidth,
                      ),
                    ),
                  ),
                ),
              ]),
            if (displayEntry.isGrouped)
              _buildSection(
                context,
                '${displayEntry.isRangeSegmented ? '分片请求' : '关联请求'} (${displayEntry.logs.length})',
                [...displayEntry.logs.map(_buildChildRequest)],
              ),
            if (displayEntry.error != null)
              _buildSection(context, '错误信息', [
                Text(
                  displayEntry.error!,
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
              ]),
            _buildSection(context, '请求头 (Request Headers)', [
              _buildHeaders(primary.requestHeaders),
            ]),
            if (primary.requestBody != null)
              _buildSection(context, '请求体 (Request Body)', [
                _buildFormattedBodyView(context, primary.requestBody!),
              ]),
            _buildSection(context, '响应头 (Response Headers)', [
              _buildHeaders(primary.responseHeaders),
            ]),
            if (primary.responseBody != null)
              _buildSection(context, '响应体 (Response Body)', [
                _buildFormattedBodyView(context, primary.responseBody!),
              ]),
          ],
        ),
      ),
    );

    if (embedded) {
      return Column(
        children: [
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.centerLeft,
            child: Text(
              displayEntry.isGrouped
                  ? displayEntry.isRangeSegmented
                        ? '请求详情 · 分片下载'
                        : '请求详情 · 关联请求'
                  : '请求详情',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
          const Divider(height: 1),
          Expanded(child: detail),
        ],
      );
    }

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
        Expanded(child: detail),
      ],
    );
  }

  Widget _buildChildRequest(NetworkLog child) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 42,
            child: Text(
              child.method,
              style: const TextStyle(
                fontSize: 10,
                color: Colors.blue,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: Text(
              '${child.statusCode ?? '-'}  ${child.url}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11),
            ),
          ),
          Text(
            child.protocolInfo.displayText,
            style: const TextStyle(fontSize: 10, color: Colors.grey),
          ),
        ],
      ),
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
            width: 84,
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

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Color _getStatusColor(int? statusCode, {bool hasError = false}) {
    if (hasError) return Colors.red;
    if (statusCode == null) return Colors.grey;
    if (statusCode >= 200 && statusCode < 300) return Colors.green;
    if (statusCode >= 400) return Colors.red;
    if (statusCode >= 300) return Colors.orange;
    return Colors.grey;
  }
}

/// 以翻译结果预览使用的本地图片查看器打开网络产物。
Future<void> openNetworkImagePreview(
  BuildContext context,
  String imagePath, {
  String? title,
}) {
  final viewport = MediaQuery.sizeOf(context);
  final width = math.min(1100.0, math.max(280.0, viewport.width - 40));
  final height = math.min(800.0, math.max(220.0, viewport.height - 80));
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: SizedBox(
        width: width,
        height: height,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: ColoredBox(
            color: Colors.black,
            child: Stack(
              children: [
                Positioned.fill(
                  child: InteractiveViewer(
                    minScale: 0.2,
                    maxScale: 8,
                    child: Center(
                      child: buildNetworkArtifactPreview(
                        imagePath,
                        memCacheWidth: networkArtifactPreviewMemCacheWidth,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  left: 12,
                  right: 52,
                  child: Text(
                    title ?? '图片预览',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
                Positioned(
                  top: 2,
                  right: 2,
                  child: IconButton(
                    tooltip: '关闭',
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
