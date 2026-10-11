import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/network/picacg_network/methods.dart';
import 'package:pica_comic/network/picacg_network/models.dart';
import 'package:pica_comic/tools/background_service.dart';

/// 当前账户会话状态。
///
/// 网络类仍然负责请求和持久化，Notifier 只负责把账户资料、刷新和签到
/// 的结果暴露给页面，避免首页初始化阶段主动请求账户接口。
class AccountSessionNotifier extends AsyncNotifier<Profile?> {
  @override
  Future<Profile?> build() async => network.user;

  /// 刷新账户资料，并在需要时执行签到。
  ///
  /// 返回值表示本次是否成功执行了桌面端签到；移动端签到交给后台服务。
  Future<bool> refreshAndCheckIn() async {
    state = const AsyncLoading<Profile?>();
    try {
      final result = await network.updateProfile();
      if (result.error) {
        throw StateError(result.errorMessageWithoutNull);
      }

      final profile = network.user;
      state = AsyncData(profile);
      if (profile?.isPunched != false ||
          appdata.getSetting(AppSettingKeys.picacgAutoCheckIn) != '1') {
        return false;
      }

      if (App.isMobile) {
        runBackgroundService();
        return false;
      }

      final punched = await network.punchIn();
      if (!punched) return false;

      final updated = network.user;
      if (updated != null) {
        network.user = updated.copyWith(isPunched: true, exp: updated.exp + 10);
        state = AsyncData(network.user);
      }
      return true;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  /// 重新读取账户资料，不执行签到逻辑。
  Future<void> refresh() async {
    state = const AsyncLoading<Profile?>();
    try {
      final result = await network.updateProfile();
      if (result.error) {
        throw StateError(result.errorMessageWithoutNull);
      }
      state = AsyncData(network.user);
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }
}

/// 应用级账户会话 Provider。
final accountSessionProvider =
    AsyncNotifierProvider<AccountSessionNotifier, Profile?>(
      AccountSessionNotifier.new,
    );
