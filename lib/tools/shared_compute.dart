
import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';


/// 复用型 Isolate 计算器 (线程池风格)
/// 使用示例: final result = await sharedCompute(complexCalculation, 42);
Future<R> sharedCompute<Q, R>(ComputeFunc<Q, R> function, Q parameter, {
  String sharedKey = 'defaultIsolate', // 可选的共享键
}) async {
  // 使用单例模式管理复用 Isolate
  return await _IsolatePool.shared().execute(
    function as dynamic,
    parameter,
    sharedKey, // 通过函数签名区分不同任务
  );
}

typedef ComputeFunc<Q, R> = FutureOr<R> Function(Q arg);

/// Isolate 线程池管理
class _IsolatePool {
  static final _instance = _IsolatePool._internal();
  factory _IsolatePool() => _instance;
  _IsolatePool._internal();

  static _IsolatePool shared() => _instance;

  final Map<String, _Worker> _workers = {};
  final Duration _timeout = const Duration(seconds: 30);
  final int _maxWorkers = math.max(1, Platform.numberOfProcessors - 1); // 按 CPU 核数优化

  /// 核心执行方法
  Future<R> execute<Q, R>(Function function, Q parameter, String functionSignature) async {
    // 获取或创建 Worker
    final worker = await _getWorker(functionSignature);

    try {
      // 通过 ReceivePort 进行通信
      final responsePort = ReceivePort();
      worker.sendPort(_IsolateTask(
        function: function,
        argument: parameter,
        responsePort: responsePort.sendPort,
      ));

      return await responsePort.first.timeout(_timeout) as R;
    } on TimeoutException catch (_) {
      // 超时处理：重启 Isolate
      _workers.remove(functionSignature)?.dispose();
      return execute(function, parameter, functionSignature);
    } catch (e) {
      rethrow;
    }
  }

  /// 获取可用 Worker (自动负载均衡)
  Future<_Worker> _getWorker(String functionSignature) async {
    if (_workers.containsKey(functionSignature)) {
      return _workers[functionSignature]!;
    }

    // 创建新 Worker (限制最大数量)
    if (_workers.length >= _maxWorkers) {
      // 回收最久未使用的 Worker
      final oldestKey = _workers.keys.first;
      _workers.remove(oldestKey)?.dispose();
    }

    print('start new isolate: $functionSignature');
    // 启动新 Worker
    final t1 = DateTime.now().millisecondsSinceEpoch;
    final worker = _Worker(functionSignature);
    _workers[functionSignature] = worker;
    await worker.start();
    final t2 = DateTime.now().millisecondsSinceEpoch;
    print('start end new isolate: $functionSignature, cost time: ${t2 - t1} ms');
    return worker;
  }

  /// 销毁所有资源 (应用退出时调用)
  void dispose() {
    for (final worker in _workers.values) {
      worker.dispose();
    }
    _workers.clear();
  }
}

/// 被发送到 Isolate 的任务打包结构
class _IsolateTask {
  final Function function;
  final dynamic argument;
  final SendPort responsePort;

  _IsolateTask({
    required this.function,
    required this.argument,
    required this.responsePort,
  });
}

/// Isolate 工作者封装
class _Worker {
  late final Isolate _isolate;
  late final SendPort _sendPort;
  final ReceivePort _receivePort = ReceivePort();
  final String _name;

  final Completer<void> _completer = Completer<void>();

  _Worker(this._name);

  /// 启动 Isolate
  Future<void> start() async {
    final completer = Completer<SendPort>();

    _isolate = await Isolate.spawn(
      _entryPoint,
      _receivePort.sendPort,
      debugName: 'SharedIsolate-$_name',
    );

    _receivePort.listen((message) {
      if (message is SendPort) {
        completer.complete(message);
      }
    });

    _sendPort = await completer.future;
    if (!_completer.isCompleted) {
      _completer.complete();
    }
  }

  /// Isolate 入口函数
  static void _entryPoint(SendPort mainSendPort) {
    final commandPort = ReceivePort();
    mainSendPort.send(commandPort.sendPort);

    commandPort.listen((message) async {
      if (message is _IsolateTask) {
        try {
          final result = await message.function(message.argument);
          message.responsePort.send(result);
        } catch (e, stack) {
          debugPrint('IsolateError: $e');
          debugPrintStack(stackTrace: stack);
          // 异常捕获处理
          message.responsePort.send(IsolateError(e.toString(), stack.toString()));
        }
      }
    });
  }

  /// 发送任务
  Future<void> sendPort(dynamic data) async {
    if (!_completer.isCompleted) {
      await _completer.future;
    }
    _sendPort.send(data);
  }

  /// 销毁资源
  Future<void> dispose() async {
    if (!_completer.isCompleted) {
      await _completer.future;
    }
    _isolate.kill(priority: Isolate.beforeNextEvent);
    _receivePort.close();
  }
}

/// 自定义 Isolate 异常封装
class IsolateError implements Exception {
  final String message;
  final String stackTrace;

  IsolateError(this.message, this.stackTrace);

  @override
  String toString() => 'IsolateError: $message\nStackTrace: $stackTrace';
}
