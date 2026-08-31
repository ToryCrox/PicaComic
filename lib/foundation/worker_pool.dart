import 'dart:async';

import 'package:worker_manager/worker_manager.dart';

/// 应用共享的 worker 资源。
///
/// worker_manager 的 worker 创建成本较高，因此不在应用启动阶段预热。所有
/// 调用方通过这里提交任务，首次使用时会共享同一个初始化 Future。
final class WorkerPoolService {
  WorkerPoolService._();

  static final instance = WorkerPoolService._();

  Future<void>? _initialization;

  Future<void> ensureInitialized() {
    final pending = _initialization;
    if (pending != null) return pending;

    final future = _initialize();
    _initialization = future;
    return future;
  }

  Future<void> _initialize() async {
    try {
      await workerManager.init(isolatesCount: 3, dynamicSpawning: false);
    } catch (_) {
      _initialization = null;
      rethrow;
    }
  }

  /// 等待 worker 资源就绪后执行任务。
  Future<R> execute<R>(FutureOr<R> Function() task) async {
    await ensureInitialized();
    return workerManager.execute<R>(task);
  }
}

final workerPool = WorkerPoolService.instance;
