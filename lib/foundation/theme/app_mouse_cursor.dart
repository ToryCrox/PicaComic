import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// 应用统一的可点击鼠标指针。
///
/// 桌面端和 Web 的可点击控件使用手型，移动端保持系统默认箭头；
/// 控件处于禁用状态时始终使用普通箭头。
const WidgetStateMouseCursor appClickableMouseCursor =
    WidgetStateMouseCursor.resolveWith(
      _resolveAppClickableMouseCursor,
      debugDescription: 'WidgetStateMouseCursor(appClickableMouseCursor)',
    );

MouseCursor _resolveAppClickableMouseCursor(Set<WidgetState> states) {
  if (states.contains(WidgetState.disabled)) {
    return SystemMouseCursors.basic;
  }

  if (kIsWeb) {
    return SystemMouseCursors.click;
  }

  return switch (defaultTargetPlatform) {
    TargetPlatform.windows || TargetPlatform.macOS || TargetPlatform.linux =>
      SystemMouseCursors.click,
    _ => SystemMouseCursors.basic,
  };
}
