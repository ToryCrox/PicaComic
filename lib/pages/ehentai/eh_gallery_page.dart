import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../foundation/def.dart';
import '../../foundation/state_controller.dart';
import '../../network/eh_network/eh_models.dart';
import '../comic_page.dart';

/// E-Hentai 画廊详情页兼容入口。
class EhGalleryPage extends StatelessWidget {
  EhGalleryPage(EhGalleryBrief brief, {super.key})
    : link = brief.link,
      comicCover = brief.coverPath,
      comicTitle = brief.title;

  const EhGalleryPage.fromLink(
    this.link, {
    super.key,
    this.comicCover,
    this.comicTitle,
  });

  final String link;
  final String? comicCover;
  final String? comicTitle;

  @override
  Widget build(BuildContext context) {
    return ComicPage(comicType: ComicType.ehentai, id: link, cover: comicCover);
  }
}

class RatingLogic extends StateController {
  double rating = 0;
  bool running = false;
}

class EhThumbnailLoader extends StatefulWidget {
  const EhThumbnailLoader({
    required this.image,
    required this.width,
    required this.pageSize,
    required this.index,
    super.key,
  });

  final ImageProvider image;

  final int pageSize;

  final int width;

  final int index;

  @override
  State<EhThumbnailLoader> createState() => _EhThumbnailLoaderState();
}

class _EhThumbnailLoaderState extends State<EhThumbnailLoader> {
  ui.Image? image;

  bool failed = false;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  Widget build(BuildContext context) {
    if (failed) {
      return const Center(child: Icon(Icons.error));
    }

    if (image == null) {
      return const SizedBox();
    } else {
      return CustomPaint(
        key: ValueKey('${widget.index}'),
        painter: _EhThumbnailPainter(
          widget.index,
          widget.pageSize,
          widget.width,
          image!,
        ),
        child: const SizedBox(width: double.infinity, height: double.infinity),
      );
    }
  }

  Future<void> _loadImage() async {
    final imageStream = widget.image.resolve(ImageConfiguration.empty);

    var listener = ImageStreamListener(
      (imageInfo, _) {
        if (mounted) {
          setState(() {
            image = imageInfo.image;
          });
        }
      },
      onError: (error, stack) {
        if (mounted) {
          setState(() {
            failed = true;
          });
        }
      },
    );

    imageStream.addListener(listener);
  }
}

class _EhThumbnailPainter extends CustomPainter {
  final int index;
  final int pageSize;
  final int width;
  final ui.Image image;

  _EhThumbnailPainter(this.index, this.pageSize, this.width, this.image);

  @override
  void paint(Canvas canvas, Size size) {
    final start = index % pageSize * width;
    final end = start + width;
    final rect = Rect.fromLTRB(0, 0, size.width, size.height);
    final srcRect = Rect.fromLTRB(
      start.toDouble(),
      0,
      end.toDouble(),
      image.height.toDouble(),
    );
    canvas.drawImageRect(image, srcRect, rect, Paint());
  }

  @override
  bool shouldRepaint(covariant _EhThumbnailPainter oldDelegate) {
    return image != oldDelegate.image ||
        index != oldDelegate.index ||
        pageSize != oldDelegate.pageSize ||
        width != oldDelegate.width;
  }
}

class RatingWidget extends StatefulWidget {
  /// star number
  final int count;

  /// Max score
  final double maxRating;

  /// Current score value
  final double value;

  /// Star size
  final double size;

  /// Space between the stars
  final double padding;

  /// Whether the score can be modified by sliding
  final bool selectAble;

  /// Callbacks when ratings change
  final ValueChanged<double> onRatingUpdate;

  const RatingWidget({
    super.key,
    this.maxRating = 10.0,
    this.count = 5,
    this.value = 10.0,
    this.size = 20,
    required this.padding,
    this.selectAble = false,
    required this.onRatingUpdate,
  });

  @override
  State<RatingWidget> createState() => _RatingWidgetState();
}

class _RatingWidgetState extends State<RatingWidget> {
  double value = 10;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (PointerDownEvent event) {
        double x = event.localPosition.dx;
        if (x < 0) x = 0;
        pointValue(x);
      },
      onPointerMove: (PointerMoveEvent event) {
        double x = event.localPosition.dx;
        if (x < 0) x = 0;
        pointValue(x);
      },
      onPointerUp: (_) {},
      behavior: HitTestBehavior.deferToChild,
      child: buildRowRating(),
    );
  }

  pointValue(double dx) {
    if (!widget.selectAble) {
      return;
    }
    if (dx >=
        widget.size * widget.count + widget.padding * (widget.count - 1)) {
      value = widget.maxRating;
    } else {
      for (double i = 1; i < widget.count + 1; i++) {
        if (dx > widget.size * i + widget.padding * (i - 1) &&
            dx < widget.size * i + widget.padding * i) {
          value = i * (widget.maxRating / widget.count);
          break;
        } else if (dx > widget.size * (i - 1) + widget.padding * (i - 1) &&
            dx < widget.size * i + widget.padding * i) {
          value =
              (dx - widget.padding * (i - 1)) /
              (widget.size * widget.count) *
              widget.maxRating;
          break;
        }
      }
    }
    if (value % 1 >= 0.5) {
      value = value ~/ 1 + 1;
    } else {
      value = (value ~/ 1).toDouble();
    }
    if (value < 0) {
      value = 0;
    } else if (value > 10) {
      value = 10;
    }
    setState(() {
      widget.onRatingUpdate(value);
    });
  }

  int fullStars() {
    return (value / (widget.maxRating / widget.count)).floor();
  }

  double star() {
    if (widget.count / fullStars() == widget.maxRating / value) {
      return 0;
    }
    return (value % (widget.maxRating / widget.count)) /
        (widget.maxRating / widget.count);
  }

  List<Widget> buildRow() {
    int full = fullStars();
    List<Widget> children = [];
    for (int i = 0; i < full; i++) {
      children.add(
        Icon(Icons.star, size: widget.size, color: const Color(0xffffbf00)),
      );
      if (i < widget.count - 1) {
        children.add(SizedBox(width: widget.padding));
      }
    }
    if (full < widget.count) {
      children.add(
        ClipRect(
          clipper: SMClipper(rating: star() * widget.size),
          child: Icon(
            Icons.star,
            size: widget.size,
            color: const Color(0xffffbf00),
          ),
        ),
      );
    }

    return children;
  }

  List<Widget> buildNormalRow() {
    List<Widget> children = [];
    for (int i = 0; i < widget.count; i++) {
      children.add(
        Icon(
          Icons.star_border,
          size: widget.size,
          color: const Color(0xffffbf00),
        ),
      );
      if (i < widget.count - 1) {
        children.add(SizedBox(width: widget.padding));
      }
    }
    return children;
  }

  Widget buildRowRating() {
    return Stack(
      children: <Widget>[
        Row(children: buildNormalRow()),
        Row(children: buildRow()),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    value = widget.value;
  }
}

class SMClipper extends CustomClipper<Rect> {
  final double rating;

  SMClipper({required this.rating});

  @override
  Rect getClip(Size size) {
    return Rect.fromLTRB(0.0, 0.0, rating, size.height);
  }

  @override
  bool shouldReclip(SMClipper oldClipper) {
    return rating != oldClipper.rating;
  }
}
