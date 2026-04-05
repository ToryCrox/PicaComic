import 'dart:convert';
import 'dart:html' as html;
import 'package:log_viewer_shared/log_viewer_shared.dart';

/// 日志服务
/// 
/// 处理与服务器的 API 通信
class LogService {
  final String baseUrl;
  
  LogService(this.baseUrl);
  
  /// 获取历史日志
  Future<List<LogEntry>> getHistory() async {
    try {
      final response = await html.HttpRequest.getString(
        '$baseUrl${ApiProtocol.logsHistoryPath}',
      );
      
      final json = jsonDecode(response) as List<dynamic>;
      return json
          .map((e) => LogEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw Exception('Failed to fetch history: $e');
    }
  }
  
  /// 清空日志
  Future<void> clear() async {
    try {
      await html.HttpRequest.request(
        '$baseUrl${ApiProtocol.logsClearPath}',
        method: 'POST',
      );
    } catch (e) {
      throw Exception('Failed to clear logs: $e');
    }
  }
  
  /// 获取服务器状态
  Future<Map<String, dynamic>> getStatus() async {
    try {
      final response = await html.HttpRequest.getString(
        '$baseUrl${ApiProtocol.statusPath}',
      );
      
      return jsonDecode(response) as Map<String, dynamic>;
    } catch (e) {
      throw Exception('Failed to fetch status: $e');
    }
  }
}



