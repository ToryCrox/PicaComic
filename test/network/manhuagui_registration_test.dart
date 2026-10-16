import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/comic_source/built_in/manhuagui.dart';
import 'package:pica_comic/comic_source/comic_source.dart';
import 'package:pica_comic/foundation/app_settings_provider.dart';
import 'package:pica_comic/foundation/def.dart';

/// 用内存模拟来源持久化，避免触碰用户设置和本地目录。
class _MemorySource extends ComicSource {
  _MemorySource()
    : super.named(name: '漫画柜', key: ComicType.manhuagui, filePath: 'built-in');
  var saves = 0;

  @override
  Future<void> saveData() async => saves++;
}

void main() {
  test('已有探索入口升级时追加分类一次，保留后续隐藏和排序', () async {
    final values = {
      AppSettingKeys.explorePages: '最近更新',
      AppSettingKeys.categoryPages: 'nhentai,jm',
    };
    final source = _MemorySource()..data['exploreRegistered'] = true;
    final repository = AppSettingsRepository(
      readValues: () => values,
      changes: const Stream.empty(),
      notifyChanges: () {},
      saveSettings: (_) async {},
    );
    final container = ProviderContainer(
      overrides: [appSettingsRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final initialize = FutureProvider<void>((ref) async {
      // 模拟应用首帧后的初始化，避免在 Provider 构建期间修改设置。
      await Future<void>.value();
      await manhuagui.initData!(source, ref);
    });
    await container.read(initialize.future);
    expect(values[AppSettingKeys.categoryPages], 'nhentai,jm,manhuagui');
    expect(values[AppSettingKeys.explorePages], '最近更新');
    expect(source.data['categoryRegistered'], true);
    expect(source.saves, 1);

    await container
        .read(appSettingsProvider.notifier)
        .setValue(AppSettingKeys.categoryPages, 'jm,nhentai');
    container.invalidate(initialize);
    await container.read(initialize.future);
    expect(values[AppSettingKeys.categoryPages], 'jm,nhentai');
    expect(values[AppSettingKeys.explorePages], '最近更新');
    expect(source.saves, 1);
  });
}
