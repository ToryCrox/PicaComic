import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../base.dart';

part 'reader_layout_provider.g.dart';

/// 只适配原有阅读器隐式布局格式，不改变主设置及阅读会话生命周期。
class ReaderLayoutRepository {
  /// 读取双页模式的首页布局。
  bool get firstPageSingle => appdata.implicitData[1] == '1';

  /// 沿用隐式数据存储，保存失败恢复原值。
  Future<void> saveFirstPageSingle(bool value) async {
    final previous = appdata.implicitData[1];
    appdata.implicitData[1] = value ? '1' : '0';
    try {
      await appdata.writeImplicitData();
    } catch (_) {
      appdata.implicitData[1] = previous;
      rethrow;
    }
  }
}

/// 应用级阅读器布局存储。
@Riverpod(keepAlive: true)
ReaderLayoutRepository readerLayoutRepository(Ref ref) =>
    ReaderLayoutRepository();

/// 已提交的布局状态，设置变更不会重建整个阅读会话。
class ReaderLayoutState {
  const ReaderLayoutState({required this.firstPageSingle});
  final bool firstPageSingle;
}

/// 管理阅读器首页布局，保存完成后才发布状态。
@Riverpod(keepAlive: true)
class ReaderLayout extends _$ReaderLayout {
  @override
  ReaderLayoutState build() => ReaderLayoutState(
    firstPageSingle: ref.read(readerLayoutRepositoryProvider).firstPageSingle,
  );

  /// 提交布局修改。
  Future<void> setFirstPageSingle(bool value) async {
    await ref.read(readerLayoutRepositoryProvider).saveFirstPageSingle(value);
    if (ref.mounted) state = ReaderLayoutState(firstPageSingle: value);
  }
}
