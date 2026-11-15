import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../foundation/image_manager.dart';
import '../../network/download/download_manager.dart';
import '../../network/eh_network/eh_models.dart';

part 'eh_original_availability_provider.g.dart';

/// EH 原图可用性检测状态。
enum EhOriginalCheckStatus {
  /// 尚未检测（进入页面时的初始状态，不会发起任何请求）。
  idle,

  /// 正在检测中。
  checking,

  /// 指定页存在原图。
  available,

  /// 指定页没有原图。
  unavailable,

  /// 检测请求失败，可重试。
  failed,
}

/// EH 画廊原图检测状态。
///
/// 以画廊链接作为 key，进入详情页时停留在 [EhOriginalCheckStatus.idle]，
/// 只有显式调用 [check] 才会真正发起网络请求。页面/画廊切换时由 autoDispose
/// 自动回收，无需手动维护状态。
@Riverpod(keepAlive: false, name: 'ehOriginalAvailabilityProvider')
class EhOriginalAvailabilityNotifier extends _$EhOriginalAvailabilityNotifier {
  @override
  EhOriginalCheckStatus build(String galleryLink) => EhOriginalCheckStatus.idle;

  /// 检测指定画廊第 [page] 页是否提供原图，重复调用会被忽略。
  Future<void> check(Gallery gallery, {int page = 1}) async {
    if (state == EhOriginalCheckStatus.checking) return;
    state = EhOriginalCheckStatus.checking;

    final manager = ref.read(downloadManagerProvider.notifier);
    final result = await ImageManager(
      manager,
    ).checkEhOriginalAvailability(gallery, page: page);
    // Provider 可能在检测期间被回收（例如页面已关闭），此时丢弃结果。
    if (!ref.mounted) return;

    if (result.error) {
      state = EhOriginalCheckStatus.failed;
    } else {
      state = result.dataOrNull == true
          ? EhOriginalCheckStatus.available
          : EhOriginalCheckStatus.unavailable;
    }
  }
}
