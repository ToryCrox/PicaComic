import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/foundation/app_settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('命名设置缺失项使用默认值，快照不可变', () {
    final values = <String, String>{AppSettingKeys.readerTapToTurnPage: '0'};
    final repository = AppSettingsRepository(readValues: () => values);
    final snapshot = repository.snapshot();
    expect(snapshot.value(AppSettingKeys.readerTapToTurnPage), '0');
    expect(snapshot.value(AppSettingKeys.proxy), '0');
    expect(snapshot.value(AppSettingKeys.networkBackend), 'rhttp');
    expect(snapshot.value(AppSettingKeys.networkProtocol), 'auto');
    expect(values, {AppSettingKeys.readerTapToTurnPage: '0'});
    expect(
      () => snapshot.values[AppSettingKeys.readerTapToTurnPage] = '1',
      throwsUnsupportedError,
    );
    repository.setValue(AppSettingKeys.networkProtocol, 'http2');
    expect(repository.snapshot().value(AppSettingKeys.networkBackend), 'rhttp');
    expect(snapshot.value(AppSettingKeys.networkProtocol), 'auto');
    expect(() => repository.setValue('notASetting', '1'), throwsArgumentError);
  });

  test('滑块预览立即修改旧内存，结束时保存且完整数据入口独立', () async {
    final values = Map<String, String>.from(defaultAppSettings);
    final calls = <String>[];
    final changes = StreamController<void>.broadcast();
    addTearDown(changes.close);
    final repository = AppSettingsRepository(
      readValues: () => values,
      changes: changes.stream,
      notifyChanges: () => changes.add(null),
      saveSettings: (sync) async => calls.add('settings:$sync'),
      saveData: (sync) async => calls.add('data:$sync'),
    );
    final container = ProviderContainer(
      overrides: [appSettingsRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final controller = container.read(appSettingsProvider.notifier);
    await controller.setValue(
      AppSettingKeys.comicTileDisplay,
      '1,1.15',
      persist: false,
    );
    expect(values[AppSettingKeys.comicTileDisplay], '1,1.15');
    expect(container.read(appearanceSettingsProvider).comicTileScale, 1.15);
    expect(calls, isEmpty);
    await controller.save();
    await controller.setValue(
      AppSettingKeys.readerVolumeKeys,
      '0',
      fullData: true,
      sync: false,
    );
    expect(calls, ['settings:true', 'data:false']);
    expect(container.read(readerSettingsProvider).useVolumeKeys, isFalse);
  });

  test('非法阅读与外观值使用安全范围', () {
    final values = Map<String, String>.from(defaultAppSettings);
    values[AppSettingKeys.readingMode] = '100';
    values[AppSettingKeys.autoPageInterval] = 'invalid';
    values[AppSettingKeys.comicTileDisplay] = 'invalid,NaN';
    final snapshot = AppSettingsSnapshot(values);
    final reading = ReaderSettingsState(snapshot);
    expect(reading.readingMode, 6);
    expect(reading.autoPageSeconds, 5);
    expect(AppearanceSettingsState(snapshot).comicTileMode, 0);
    expect(AppearanceSettingsState(snapshot).comicTileScale, 1.0);
  });

  group('新格式存储与重载入口', () {
    late Directory directory;
    late Appdata original;
    late ProviderContainer container;

    setUpAll(() async {
      directory = await Directory.systemTemp.createTemp('pica_settings_');
      App.dataPath = directory.path;
    });

    tearDownAll(() async => directory.delete(recursive: true));

    setUp(() {
      original = appdata;
      SharedPreferences.setMockInitialValues({});
      appdata = Appdata();
      container = ProviderContainer();
      container.read(appSettingsProvider);
    });

    tearDown(() async {
      container.dispose();
      appdata = original;
      final file = File('${directory.path}/settings');
      if (await file.exists()) await file.delete();
    });

    test('后台与页面并发保存串行写入设置文件', () async {
      final gate = Completer<void>();
      final writer = _GatedSettingsFile(gate.future);
      var callsBeforeRelease = 0;
      await IOOverrides.runZoned(() async {
        final data = Appdata();
        final first = data.updateSettings(false);
        final second = data.updateSettings(false);
        await Future<void>.delayed(Duration.zero);
        callsBeforeRelease = writer.calls;
        gate.complete();
        await Future.wait([first, second]);
      }, createFile: (_) => writer);
      expect(callsBeforeRelease, 1);
      expect(writer.calls, 2);
    });

    test('启动加载命名文件，保存和导出均为 key-value 对象', () async {
      final file = File('${directory.path}/settings');
      final settings = Map<String, String>.from(appdata.settings);
      appdata.settings = settings;
      await appdata.updateSettings(false);
      await container.pump();
      expect(jsonDecode(await file.readAsString()), settings);
      expect(appdata.toJson()['settings'], settings);
      await container
          .read(appSettingsProvider.notifier)
          .setValue(AppSettingKeys.readingMode, '6', sync: false);
      final saved = jsonDecode(await file.readAsString()) as Map;
      expect(saved[AppSettingKeys.readingMode], '6');
      expect(saved.keys.every((key) => key is String), isTrue);
      expect(saved.length, defaultAppSettings.length);
      expect(container.read(readerSettingsProvider).readingMode, 6);
      await file.writeAsString(
        jsonEncode({AppSettingKeys.proxy: '127.0.0.1:7890'}),
      );
      appdata = Appdata();
      await appdata.readData();
      await container.pump();
      expect(
        container.read(appSettingsProvider).value(AppSettingKeys.proxy),
        '127.0.0.1:7890',
      );
      expect(
        container
            .read(appSettingsProvider)
            .value(AppSettingKeys.networkBackend),
        'rhttp',
      );
    });

    test('导入与 WebDAV 共用的 JSON 入口刷新快照，重置后恢复默认', () async {
      final imported = Map<String, String>.from(appdata.settings);
      imported[AppSettingKeys.readingMode] = '5';
      imported[AppSettingKeys.proxy] = '127.0.0.1:7890';
      imported[AppSettingKeys.downloadDirectory] = 'X:/remote-downloads';
      imported[AppSettingKeys.requireAuthentication] = '1';
      expect(
        appdata.readDataFromJson({
          'settings': imported,
          'firstUse': appdata.firstUse,
        }),
        isTrue,
      );
      // 等待旧同步导入入口内部的异步持久化完成。
      await _waitForImportedData().timeout(const Duration(seconds: 5));
      await container.pump();
      expect(container.read(readerSettingsProvider).readingMode, 5);
      expect(
        container.read(appSettingsProvider).value(AppSettingKeys.proxy),
        '127.0.0.1:7890',
      );
      expect(
        container
            .read(appSettingsProvider)
            .value(AppSettingKeys.requireAuthentication),
        '0',
      );
      expect(
        appdata.getSetting(AppSettingKeys.webdavVersion),
        imported[AppSettingKeys.webdavVersion],
      );
      expect(
        jsonDecode(
          await File('${directory.path}/settings').readAsString(),
        )[AppSettingKeys.readingMode],
        '5',
      );
      await File('${directory.path}/settings').delete();
      SharedPreferences.setMockInitialValues({});
      // clearAppdata 使用同样的实例替换与重新读取流程。
      appdata = Appdata();
      await appdata.readData();
      await container.pump();
      expect(container.read(readerSettingsProvider).readingMode, 1);
      expect(
        container.read(appSettingsProvider).value(AppSettingKeys.proxy),
        '0',
      );
    });
  });
}

/// 旧同步导入方法在最后一步写入 firstUse，以此等待真实持久化完成。
Future<void> _waitForImportedData() async {
  final prefs = await SharedPreferences.getInstance();
  while (prefs.getStringList('firstUse') == null) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

/// 通过显式等待点验证真实 Appdata 写入边界，避免依赖磁盘竞态概率。
class _GatedSettingsFile extends Fake implements File {
  _GatedSettingsFile(this.gate);
  final Future<void> gate;
  int calls = 0;

  @override
  Future<File> writeAsString(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) async {
    calls++;
    await gate;
    return this;
  }
}
