part of "components.dart";

/// 在指定的全局坐标显示 Flutter 原生右键菜单。
///
/// 菜单位置使用 Navigator overlay 的坐标计算，Flutter 会根据可用空间
/// 自动调整菜单的展开方向和屏幕边界。
Future<T?> showContextMenu<T>({
  required BuildContext context,
  required Offset globalPosition,
  required List<PopupMenuEntry<T>> items,
}) {
  final overlay = Navigator.of(context).overlay;
  final renderObject = overlay?.context.findRenderObject();
  if (renderObject is! RenderBox) {
    return Future<T?>.value(null);
  }

  final localPosition = renderObject.globalToLocal(globalPosition);
  final overlaySize = renderObject.size;

  return showMenu<T>(
    context: context,
    position: RelativeRect.fromLTRB(
      localPosition.dx,
      localPosition.dy,
      overlaySize.width - localPosition.dx,
      overlaySize.height - localPosition.dy,
    ),
    items: items,
  );
}

/// 构建带有统一图标占位的原生菜单项。
PopupMenuItem<T> popupMenuItem<T>({
  required String text,
  IconData? icon,
  T? value,
  VoidCallback? onTap,
  bool enabled = true,
}) {
  return PopupMenuItem<T>(
    value: value,
    enabled: enabled,
    onTap: onTap,
    child: Row(
      children: [
        SizedBox(width: 24, child: icon == null ? null : Icon(icon, size: 20)),
        const SizedBox(width: 12),
        Flexible(
          fit: FlexFit.loose,
          child: Text(text, overflow: TextOverflow.ellipsis),
        ),
      ],
    ),
  );
}
