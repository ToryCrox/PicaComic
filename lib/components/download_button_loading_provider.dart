import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'download_button_loading_provider.g.dart';

/// 下载按钮的全局加载状态。
///
/// 同一部漫画可能同时出现在多个列表中，点击任意一个下载按钮后，所有指向同一
/// 漫画 ID 的按钮都应显示加载态并阻止重复点击，因此状态按漫画 ID 收敛在
/// 应用级 Provider 中。
@Riverpod(keepAlive: true)
class DownloadButtonLoading extends _$DownloadButtonLoading {
  @override
  Set<String> build() => const {};

  /// 标记该漫画开始下载。
  void add(String comicId) {
    if (state.contains(comicId)) return;
    state = {...state, comicId};
  }

  /// 标记该漫画下载结束。
  void remove(String comicId) {
    if (!state.contains(comicId)) return;
    state = {...state}..remove(comicId);
  }
}

/// 单部漫画的下载按钮加载态。
///
/// 按漫画 ID 派生，集合变化时只有本 ID 对应的实例会重新计算；结果值不变时
/// 订阅方不会重建，因此按钮直接 watch 即可，无需在集合上做 select。
@riverpod
bool downloadButtonIsLoading(Ref ref, String comicId) =>
    ref.watch(downloadButtonLoadingProvider).contains(comicId);
