import 'dart:async';

/// 设置持久化与数据替换入口使用的通知，不依赖 Riverpod 容器。
final _settingsChanges = StreamController<void>.broadcast();

/// 旧设置被修改、加载或替换后的通知流。
Stream<void> get settingsChanges => _settingsChanges.stream;

/// 通知设置消费者重新读取当前 appdata。
void notifySettingsChanged() => _settingsChanges.add(null);
