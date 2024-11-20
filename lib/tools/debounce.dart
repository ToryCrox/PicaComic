import 'dart:async';

/// 防抖类：在触发事件时，不立即执行目标操作，而是给出一个延迟的时间，在该时间范围内
/// 如果再次触发了事件，则重置延迟时间，直到延迟时间结束才会执行目标操作。
/// [func] 行为方法
/// 可选 [duration] 单位时间
class Debounce {
  final Duration _duration;
  Timer? _timer;

  // 是否立即执行第一次调用
  bool firstCallImmediately = false;

  // 是否是第一次调用
  bool _isFirstCall = true;

  final List<FutureOr Function()> _taskQueue = [];

  bool _isPause = false;

  bool get isPause => _isPause;

  set isPause(bool value) {
    _isPause = value;
    if (!_isPause) {
      // 如果暂停状态变为非暂停状态，则执行暂停时的行为
      _processTaskQueue();
    }
  }

  Debounce({
    Duration duration = const Duration(milliseconds: 800),
    this.firstCallImmediately = false,
  }) : _duration = duration;

  void call(FutureOr Function()? func) {
    if (func == null) return;
    if (_isFirstCall && firstCallImmediately) {
      _isFirstCall = false;
      _doCallTask(func);
      return;
    }
    if (_timer?.isActive ?? false) {
      _timer?.cancel();
    }
    _timer = Timer(_duration, () {
      _doCallTask(func);
    });
  }

  /// 添加任务
  /// [func] 行为方法
  /// 如果任务队列中没有任务，则立即执行
  /// 如果任务队列中有任务，则等待任务队列中的任务执行完毕后，再执行
  void _doCallTask(FutureOr Function() func) {
    final isTaskEmpty = _taskQueue.isEmpty;
    _taskQueue.add(func);
    // 如果任务队列中没有任务，则立即执行
    if (isTaskEmpty) {
      _processTaskQueue();
    }
  }

  /// 执行任务队列中的任务
  /// 如果任务队列中没有任务，则不执行
  /// 如果任务队列中有任务，则执行第一个任务，执行完毕后，再执行下一个任务
  /// 以此类推，直到任务队列中的任务全部执行完毕
  Future _processTaskQueue() async {
    if (_taskQueue.isEmpty) return;
    if (_isPause) return;
    final task = _taskQueue.first;
    await task.call();
    _taskQueue.remove(task);
    _processTaskQueue();
  }

  void dispose() {
    _taskQueue.clear();
    _timer?.cancel();
    _timer = null;
  }
}
