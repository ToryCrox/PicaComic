import 'dart:async';
import 'package:flutter/material.dart';
import 'package:log_viewer_shared/log_viewer_shared.dart';
import '../services/log_service.dart';
import '../services/sse_client.dart';
import 'log_item_widget.dart';
import 'log_filter_panel.dart';

/// 日志查看器主内容
class LogViewerContent extends StatefulWidget {
  const LogViewerContent({super.key});

  @override
  State<LogViewerContent> createState() => _LogViewerContentState();
}

class _LogViewerContentState extends State<LogViewerContent> {
  final List<LogEntry> _logs = [];
  final Set<LogLevel> _selectedLevels = Set.from(LogLevel.values);
  String _searchQuery = '';
  bool _isLoading = true;
  String? _error;

  late LogService _logService;
  SSEClient? _sseClient;
  StreamSubscription<LogEntry>? _logSubscription;
  StreamSubscription<String>? _errorSubscription;

  // 从 URL 获取服务器地址，默认为 localhost:8080
  String get _baseUrl {
    final uri = Uri.base;
    return '${uri.scheme}://${uri.host}:${uri.hasPort ? uri.port : 8080}';
  }

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      _logService = LogService(_baseUrl);

      // 加载历史日志
      final history = await _logService.getHistory();
      setState(() {
        _logs.addAll(history);
        _isLoading = false;
      });

      // 连接 SSE 流
      _connectSSE();
    } catch (e) {
      setState(() {
        _error = 'Failed to initialize: $e';
        _isLoading = false;
      });
    }
  }

  void _connectSSE() {
    _sseClient = SSEClient();

    _logSubscription = _sseClient!.logStream.listen((entry) {
      setState(() {
        _logs.add(entry);
        // 限制日志数量
        if (_logs.length > 1000) {
          _logs.removeAt(0);
        }
      });
    });

    _errorSubscription = _sseClient!.errorStream.listen((error) {
      setState(() {
        _error = error;
      });
    });

    _sseClient!.connect(_baseUrl);
  }

  @override
  void dispose() {
    _logSubscription?.cancel();
    _errorSubscription?.cancel();
    _sseClient?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('日志查看器'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              setState(() {
                _isLoading = true;
                _error = null;
              });
              await _initialize();
            },
            tooltip: '刷新',
          ),
          IconButton(
            icon: const Icon(Icons.clear_all),
            onPressed: () async {
              try {
                await _logService.clear();
                setState(() {
                  _logs.clear();
                });
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('清空失败: $e')),
                );
              }
            },
            tooltip: '清空日志',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline,
                          size: 64, color: Colors.red),
                      const SizedBox(height: 16),
                      Text(_error!),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _initialize,
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // 过滤面板
                    LogFilterPanel(
                      selectedLevels: _selectedLevels,
                      onLevelsChanged: (levels) {
                        setState(() {
                          _selectedLevels.clear();
                          _selectedLevels.addAll(levels);
                        });
                      },
                      searchQuery: _searchQuery,
                      onSearchChanged: (query) {
                        setState(() {
                          _searchQuery = query;
                        });
                      },
                    ),
                    // 日志列表
                    Expanded(
                      child: _buildLogList(),
                    ),
                  ],
                ),
    );
  }

  Widget _buildLogList() {
    // 过滤日志
    final filteredLogs = _logs.where((entry) {
      // 级别过滤
      if (!_selectedLevels.contains(entry.level)) {
        return false;
      }

      // 搜索过滤
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final matchesMessage = entry.message.toLowerCase().contains(query);
        final matchesError =
            entry.error?.toLowerCase().contains(query) ?? false;
        final matchesStackTrace =
            entry.stackTrace?.toLowerCase().contains(query) ?? false;
        if (!matchesMessage && !matchesError && !matchesStackTrace) {
          return false;
        }
      }

      return true;
    }).toList();

    if (filteredLogs.isEmpty) {
      return const Center(
        child: Text('没有日志'),
      );
    }

    return ListView.builder(
      reverse: true, // 最新的日志在顶部
      itemCount: filteredLogs.length,
      itemBuilder: (context, index) {
        final entry = filteredLogs[filteredLogs.length - 1 - index];
        return LogItemWidget(entry: entry);
      },
    );
  }
}
