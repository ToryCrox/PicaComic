import 'package:flutter/foundation.dart';
import 'package:synchronized/synchronized.dart';

import '../base.dart';
import 'settings_events.dart';

export 'app_setting_keys.dart';

/// 命名设置的不可变快照，缺失 key 使用集中定义的默认值。
class AppSettingsSnapshot {
  AppSettingsSnapshot(Map<String, String> values)
    : values = Map.unmodifiable({...defaultAppSettings, ...values});

  final Map<String, String> values;

  /// 读取字符串设置。
  String value(String key, [String fallback = '']) => values[key] ?? fallback;

  /// 读取布尔设置，1 表示启用。
  bool enabled(String key) => value(key) == '1';

  /// 读取整数设置，非法值使用调用方默认值。
  int integer(String key, [int fallback = 0]) =>
      int.tryParse(value(key)) ?? fallback;

  @override
  bool operator ==(Object other) =>
      other is AppSettingsSnapshot && mapEquals(values, other.values);

  @override
  int get hashCode => Object.hashAllUnordered(
    values.entries.map((e) => Object.hash(e.key, e.value)),
  );
}

/// 设置持久化仓库，页面和后台共用命名 key 的写入与保存边界。
/// 此处 appdata 是存储适配边界，无须引入 Ref；业务层优先注入仓库或配置。
class AppSettingsRepository {
  AppSettingsRepository({
    Map<String, String> Function()? readValues,
    void Function(String key, String value)? writeValue,
    Future<void> Function(bool sync)? saveSettings,
    Future<void> Function(bool sync)? saveData,
    Stream<void>? changes,
    void Function()? notifyChanges,
  }) : _readValues = readValues ?? (() => appdata.settings),
       _writeValue =
           writeValue ??
           (readValues == null
               ? ((key, value) => appdata.setSetting(key, value))
               : ((key, value) => readValues()[key] = value)),
       _saveSettings = saveSettings ?? ((sync) => appdata.updateSettings(sync)),
       _saveData = saveData ?? ((sync) => appdata.writeData(sync)),
       changes = changes ?? settingsChanges,
       _notifyChanges = notifyChanges ?? notifySettingsChanged;

  final Map<String, String> Function() _readValues;
  final void Function(String key, String value) _writeValue;
  final Future<void> Function(bool sync) _saveSettings;
  final Future<void> Function(bool sync) _saveData;
  final void Function() _notifyChanges;
  final Lock _saveLock = Lock();
  final Stream<void> changes;

  /// 读取当前数据实例，避免清空数据后继续持有旧 Map。
  AppSettingsSnapshot snapshot() => AppSettingsSnapshot(_readValues());

  /// 同步更新内存，供阅读器立即读取及滑块预览。
  void setValue(String key, String value) {
    if (!defaultAppSettings.containsKey(key)) {
      throw ArgumentError.value(key, 'key', '未知设置项');
    }
    _writeValue(key, value);
    _notifyChanges();
  }

  /// 一次更新关联设置，先校验所有 key，防止写入部分成功。
  void setValues(Map<String, String> values) {
    for (final key in values.keys) {
      if (!defaultAppSettings.containsKey(key)) {
        throw ArgumentError.value(key, 'key', '未知设置项');
      }
    }
    for (final entry in values.entries) {
      _writeValue(entry.key, entry.value);
    }
    _notifyChanges();
  }

  /// 串行保存，保留完整数据保存与 WebDAV 同步语义。
  Future<void> save({bool fullData = false, bool sync = true}) {
    return _saveLock.synchronized(() async {
      if (fullData) {
        await _saveData(sync);
      } else {
        await _saveSettings(sync);
      }
    });
  }
}
