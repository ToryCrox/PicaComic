import 'package:flutter/material.dart';
import 'package:pica_comic/foundation/def.dart';

/// 飞行期间包裹图片的作用域。
///
/// Hero 的 shuttle 会把源侧的图片子树重新 inflate 到 Overlay 里，此时图片
/// 拿到的是每帧插值的 tight 约束。如果图片仍按约束重新分配解码宽度，就会
/// 在飞行途中不断生成新的 provider，导致封面反复重解码（白闪）；而
/// `CachedNetworkImage` 的淡入也会在缓存命中时从全透明重新播放一次。
///
/// 进入该作用域的图片会：关闭淡入、锁定解码宽度。
class HeroImageScope extends InheritedWidget {
  const HeroImageScope({super.key, required super.child});

  static HeroImageScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HeroImageScope>();

  @override
  bool updateShouldNotify(HeroImageScope oldWidget) => false;
}

/// 飞行期间统一使用列表侧（pop 时为详情侧）的封面，避免另一端尚未解码时
/// 闪成占位图；同时把源上下文的 MediaQuery 带进 Overlay，保证图片按相同
/// 的设备像素比解码。
Widget comicCoverFlightShuttle(
  BuildContext flightContext,
  Animation<double> animation,
  HeroFlightDirection direction,
  BuildContext fromHeroContext,
  BuildContext toHeroContext,
) {
  final source = direction == HeroFlightDirection.push
      ? fromHeroContext
      : toHeroContext;
  final hero = source.widget as Hero;
  final mediaQuery = MediaQuery.maybeOf(source);
  final child = HeroImageScope(
    child: Material(type: MaterialType.transparency, child: hero.child),
  );
  return mediaQuery == null
      ? child
      : MediaQuery(data: mediaQuery, child: child);
}

/// 参与 Hero 飞行的标题文本。
///
/// 列表卡与详情页各自使用自己最终的字号/颜色，飞行过程中由
/// [comicTitleFlightShuttle] 在两端样式之间插值，避免中途换字导致跳动。
class ComicTitleHero extends StatelessWidget {
  const ComicTitleHero({
    super.key,
    required this.text,
    required this.style,
    this.maxLines = 2,
    this.textAlign = TextAlign.start,
  });

  final String text;
  final TextStyle style;
  final int maxLines;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: style,
      maxLines: maxLines,
      textAlign: textAlign,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// 标题的飞行实现：字号、颜色、字重随进度插值，并叠一层柔和阴影，
/// 保证飞行途中白色标题落在图片上时依然可读。
Widget comicTitleFlightShuttle(
  BuildContext flightContext,
  Animation<double> animation,
  HeroFlightDirection direction,
  BuildContext fromHeroContext,
  BuildContext toHeroContext,
) {
  final from = _comicTitleOf(fromHeroContext);
  final to = _comicTitleOf(toHeroContext);
  // push 时展示列表侧文案，pop 时展示详情侧文案，与封面 shuttle 保持一致。
  final textSource = direction == HeroFlightDirection.push ? from : to;
  final styleFrom = from?.style ?? to?.style ?? const TextStyle();
  final styleTo = to?.style ?? from?.style ?? styleFrom;
  final text = textSource?.text ?? to?.text ?? from?.text ?? "";

  return AnimatedBuilder(
    animation: animation,
    builder: (context, _) {
      final t = Curves.easeOutCubic.transform(animation.value);
      final style = TextStyle.lerp(styleFrom, styleTo, t) ?? styleFrom;
      return Material(
        type: MaterialType.transparency,
        child: Text(
          text,
          style: style.copyWith(
            shadows: const [Shadow(color: Color(0x66000000), blurRadius: 8)],
          ),
          maxLines: textSource?.maxLines ?? 2,
          textAlign: textSource?.textAlign ?? TextAlign.start,
          overflow: TextOverflow.ellipsis,
        ),
      );
    },
  );
}

/// 读取 Hero 子节点中的标题数据；结构不符时返回 null 以退化为纯封面飞行。
ComicTitleHero? _comicTitleOf(BuildContext heroContext) {
  final widget = heroContext.widget;
  if (widget is! Hero) return null;
  final child = widget.child;
  return child is ComicTitleHero ? child : null;
}

/// 用 [tag] 包装标题，实现列表页到详情页的标题飞行。
///
/// [tag] 为空时直接返回普通文本，不参与任何飞行。
Widget buildComicTitleHero({
  required String? tag,
  required String text,
  required TextStyle style,
  required int maxLines,
}) {
  final content = ComicTitleHero(text: text, style: style, maxLines: maxLines);
  if (tag == null) return content;
  return Hero(
    tag: tag,
    flightShuttleBuilder: comicTitleFlightShuttle,
    child: content,
  );
}
