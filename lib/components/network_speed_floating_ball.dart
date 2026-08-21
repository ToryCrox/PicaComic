import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../foundation/app.dart';
import '../network/network_monitor_settings.dart';
import '../network/network_speed_monitor.dart';
import '../pages/network_log_page.dart';

/// 应用内网速悬浮球。
class NetworkSpeedFloatingBall extends ConsumerStatefulWidget {
  const NetworkSpeedFloatingBall({super.key});

  @override
  ConsumerState<NetworkSpeedFloatingBall> createState() =>
      _NetworkSpeedFloatingBallState();
}

class _NetworkSpeedFloatingBallState
    extends ConsumerState<NetworkSpeedFloatingBall> {
  double _x = 16.0;
  double _y = 0.0;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(networkMonitorSettingsProvider);
    _x = settings.ballX;
    _y = settings.ballY;
  }

  void _savePosition() {
    ref.read(networkMonitorSettingsProvider.notifier).setBallPosition(_x, _y);
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final speed = ref.watch(networkSpeedProvider).value;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 使用默认位置（左下角）。
    var displayY = _y > 0 ? _y : screenSize.height - 120;

    // 特殊值：-1.0 表示右贴边（会在运行时计算）。
    const snappedLeftValue = 8.0;

    var displayX = _x < 0
        ? screenSize.width - 88
        : _x > 0
        ? _x
        : snappedLeftValue;

    // 窗口大小变化时按照参考项目的规则调整位置。
    if (!_isDragging) {
      displayX = displayX.clamp(snappedLeftValue, screenSize.width - 88.0);
      displayY = displayY.clamp(0.0, screenSize.height - 80.0);

      if (_x >= 0 && (displayX != _x || displayY != _y)) {
        _x = displayX;
        _y = displayY;
        _savePosition();
      } else if (_y != displayY) {
        _y = displayY;
        _savePosition();
      }
    }

    return Positioned(
      left: displayX,
      bottom: screenSize.height - displayY - 60,
      child: GestureDetector(
        onPanStart: (_) {
          setState(() {
            if (_x < 0) {
              _x = screenSize.width - 88;
            }
          });
        },
        onPanUpdate: (details) {
          setState(() {
            _isDragging = true;
            _x += details.delta.dx;
            _y += details.delta.dy;
            _x = _x.clamp(0.0, screenSize.width - 80);
            _y = _y.clamp(0.0, screenSize.height - 80);
          });
        },
        onPanEnd: (_) {
          setState(() {
            _isDragging = false;
            final centerX = _x + 40;
            _x = centerX < screenSize.width / 2 ? 8.0 : -1.0;
            _savePosition();
          });
        },
        onTap: () {
          NetworkLogPage.show(App.globalContext ?? context);
        },
        child: _buildBall(isDark, speed),
      ),
    );
  }

  Widget _buildBall(bool isDark, NetworkSpeedData? speed) {
    final backgroundColor = isDark
        ? Colors.white.withValues(alpha: 0.9)
        : Colors.black.withValues(alpha: 0.75);
    final textColor = isDark ? Colors.black87 : Colors.white;
    final shadowColor = isDark
        ? Colors.white.withValues(alpha: 0.3)
        : Colors.black.withValues(alpha: 0.3);

    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: shadowColor,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: _isDragging
            ? _buildDraggingContent(textColor)
            : _buildSpeedContent(textColor, speed),
      ),
    );
  }

  Widget _buildSpeedContent(Color textColor, NetworkSpeedData? speed) {
    if (speed == null) return _buildPlaceholder(textColor);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSpeedRow(
          Icons.arrow_downward,
          speed.downloadSpeedText,
          Colors.green,
          textColor,
        ),
        const SizedBox(height: 4),
        _buildSpeedRow(
          Icons.arrow_upward,
          speed.uploadSpeedText,
          Colors.blue,
          textColor,
        ),
      ],
    );
  }

  Widget _buildSpeedRow(
    IconData icon,
    String text,
    Color iconColor,
    Color textColor,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: iconColor),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            color: textColor,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildDraggingContent(Color textColor) {
    return SizedBox(
      width: 60,
      height: 60,
      child: Icon(
        Icons.drag_indicator,
        color: textColor.withValues(alpha: 0.5),
      ),
    );
  }

  Widget _buildPlaceholder(Color textColor) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('↓ 0 B/s', style: TextStyle(color: textColor, fontSize: 11)),
        Text('↑ 0 B/s', style: TextStyle(color: textColor, fontSize: 11)),
      ],
    );
  }
}

/// 将网速悬浮球叠加到应用内容上。
class NetworkSpeedWrapper extends ConsumerWidget {
  const NetworkSpeedWrapper({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(networkSpeedBallEnabledProvider);
    if (!enabled) return child;
    return Stack(
      alignment: Alignment.topLeft,
      clipBehavior: Clip.none,
      children: [child, const NetworkSpeedFloatingBall()],
    );
  }
}
