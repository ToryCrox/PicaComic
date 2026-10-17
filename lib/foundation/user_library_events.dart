import 'dart:async';

/// 独立用户列表的存储变更通知，不依赖界面或 Provider 容器。
final _changes = StreamController<void>.broadcast();

/// 搜索历史、标签收藏和屏蔽词保存、导入或替换后的通知流。
Stream<void> get userLibraryChanges => _changes.stream;

/// 通知消费者重新读取已提交的数据。
void notifyUserLibraryChanged() => _changes.add(null);
