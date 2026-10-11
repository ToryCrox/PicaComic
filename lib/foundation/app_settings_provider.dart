import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'app_settings_repository.dart';

export 'app_settings_repository.dart';

part 'app_settings_provider.g.dart';

/// 设置仓库可由测试替换，生产环境始终访问当前 appdata。
final appSettingsRepositoryProvider = Provider<AppSettingsRepository>(
  (ref) => AppSettingsRepository(),
);

/// 应用级设置快照，观察统一存储入口的变更通知。
@Riverpod(keepAlive: true)
class AppSettings extends _$AppSettings {
  @override
  AppSettingsSnapshot build() {
    final repository = ref.watch(appSettingsRepositoryProvider);
    final subscription = repository.changes.listen((_) {
      if (ref.mounted) state = repository.snapshot();
    });
    ref.onDispose(subscription.cancel);
    return repository.snapshot();
  }

  /// 更新内存并按调用方原有语义保存。
  Future<void> setValue(
    String key,
    String value, {
    bool fullData = false,
    bool persist = true,
    bool sync = true,
  }) async {
    final repository = ref.read(appSettingsRepositoryProvider);
    repository.setValue(key, value);
    state = repository.snapshot();
    if (persist) await repository.save(fullData: fullData, sync: sync);
  }

  /// 同时修改关联页面配置，并只保存一次。
  Future<void> setValues(
    Map<String, String> values, {
    bool persist = true,
  }) async {
    final repository = ref.read(appSettingsRepositoryProvider);
    repository.setValues(values);
    state = repository.snapshot();
    if (persist) await repository.save();
  }

  /// 保存滑块预览过程中累积的修改。
  Future<void> save({bool fullData = false, bool sync = true}) {
    return ref
        .read(appSettingsRepositoryProvider)
        .save(fullData: fullData, sync: sync);
  }
}

/// 阅读设置的类型化只读视图，页面不再维护重复的布尔状态。
class ReaderSettingsState {
  const ReaderSettingsState(this.snapshot);

  final AppSettingsSnapshot snapshot;

  bool get flipWithTap => snapshot.enabled(AppSettingKeys.readerTapToTurnPage);
  bool get useVolumeKeys => snapshot.enabled(AppSettingKeys.readerVolumeKeys);
  bool get reduceBrightness =>
      snapshot.enabled(AppSettingKeys.dimImagesInDarkMode);
  bool get reverseTap => snapshot.enabled(AppSettingKeys.reverseTapTurnPage);
  bool get doubleTapZoom => snapshot.enabled(AppSettingKeys.doubleTapZoom);
  bool get limitImageWidth =>
      snapshot.enabled(AppSettingKeys.limitReaderImageWidth);
  bool get longPressZoom => snapshot.enabled(AppSettingKeys.longPressZoom);
  bool get showPageInfo => snapshot.enabled(AppSettingKeys.showReaderPageInfo);
  int get readingMode =>
      snapshot.integer(AppSettingKeys.readingMode, 1).clamp(1, 6);
  int get autoPageSeconds =>
      snapshot.integer(AppSettingKeys.autoPageInterval, 5).clamp(1, 20);
  int get tapRange =>
      snapshot.integer(AppSettingKeys.tapTurnPageRange, 25).clamp(0, 40);
  int get screenOrientation =>
      snapshot.integer(AppSettingKeys.readerOrientation).clamp(0, 2);
  int get imageLayout =>
      snapshot.integer(AppSettingKeys.readerImageLayout).clamp(0, 2);
}

/// 阅读器设置的派生视图。
@riverpod
ReaderSettingsState readerSettings(Ref ref) {
  return ReaderSettingsState(ref.watch(appSettingsProvider));
}

/// 应用外观与漫画块显示设置，独立于已有主题 Provider。
class AppearanceSettingsState {
  const AppearanceSettingsState(this.snapshot);

  final AppSettingsSnapshot snapshot;

  bool get highRefreshRate => snapshot.enabled(AppSettingKeys.highRefreshRate);
  int get comicTileMode =>
      (int.tryParse(
                snapshot
                    .value(AppSettingKeys.comicTileDisplay)
                    .split(',')
                    .first,
              ) ??
              0)
          .clamp(0, 1);
  double get comicTileScale {
    final parts = snapshot.value(AppSettingKeys.comicTileDisplay).split(',');
    final value = parts.length > 1 ? double.tryParse(parts[1]) : null;
    return _safeScale(value);
  }

  double get imageFavoriteScale => _safeScale(
    double.tryParse(snapshot.value(AppSettingKeys.imageFavoriteScale)),
  );

  /// 防止损坏的旧数据生成 NaN 或无穷大的滑块数值。
  double _safeScale(double? value) {
    if (value == null || !value.isFinite) return 1.0;
    return value.clamp(0.75, 1.25);
  }
}

/// 漫画块及应用外观的派生视图。
@riverpod
AppearanceSettingsState appearanceSettings(Ref ref) {
  return AppearanceSettingsState(ref.watch(appSettingsProvider));
}
