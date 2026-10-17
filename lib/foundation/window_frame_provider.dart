import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'window_frame_provider.g.dart';

/// 应用窗口栏的不可变显示状态，侧栏动画由 Widget 自己管理。
class WindowFrameState {
  const WindowFrameState({this.useDarkTheme = false, this.hidden = false});

  final bool useDarkTheme;
  final bool hidden;
}

/// 跨页面共享窗口栏显示状态，保持应用级生命周期。
@Riverpod(keepAlive: true, name: 'windowFrameProvider')
class WindowFrameNotifier extends _$WindowFrameNotifier {
  @override
  WindowFrameState build() => const WindowFrameState();

  /// 阅读器使用深色窗口栏。
  void setDarkTheme() {
    if (ref.mounted) {
      state = WindowFrameState(useDarkTheme: true, hidden: state.hidden);
    }
  }

  /// 恢复跟随应用主题。
  void resetTheme() {
    if (ref.mounted) state = WindowFrameState(hidden: state.hidden);
  }

  /// 全屏时隐藏窗口栏。
  void hideWindowFrame() {
    if (ref.mounted) {
      state = WindowFrameState(useDarkTheme: state.useDarkTheme, hidden: true);
    }
  }

  /// 退出全屏时恢复窗口栏。
  void showWindowFrame() {
    if (ref.mounted) {
      state = WindowFrameState(useDarkTheme: state.useDarkTheme);
    }
  }
}
