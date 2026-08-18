import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:pica_comic/tools/translations.dart';

/// 本地图片查看器中的图片项。
class LocalImageViewerItem {
  /// 创建一个本地图片查看项。
  const LocalImageViewerItem({
    required this.imagePath,
    this.title,
    this.subtitle,
    this.heroTag,
  });

  /// 图片文件路径。
  final String imagePath;

  /// 顶部标题。
  final String? title;

  /// 顶部副标题。
  final String? subtitle;

  /// 可选的 Hero 标签。
  final String? heroTag;
}

/// 构建查看器底部扩展操作的回调。
typedef LocalImageViewerBottomBuilder =
    Widget Function(BuildContext context, LocalImageViewerItem item, int index);

/// 参考 PixEz 风格的本地图片全屏查看器。
class LocalImageViewerPage extends StatefulWidget {
  /// 创建本地图片查看器。
  const LocalImageViewerPage({
    super.key,
    required this.imagePath,
    this.title,
    this.subtitle,
    this.heroTag,
    this.gallery = const [],
    this.initialIndex = 0,
    this.bottomBuilder,
  });

  /// 首张图片路径；当 [gallery] 为空时作为唯一图片。
  final String imagePath;

  /// 单图模式下的顶部标题。
  final String? title;

  /// 单图模式下的顶部副标题。
  final String? subtitle;

  /// 单图模式下的 Hero 标签。
  final String? heroTag;

  /// 图片图集。
  final List<LocalImageViewerItem> gallery;

  /// 初始显示的图集索引。
  final int initialIndex;

  /// 可选的底部扩展操作构建器。
  final LocalImageViewerBottomBuilder? bottomBuilder;

  /// 以透明淡入路由打开本地图片查看器。
  static Future<T?> open<T>(
    BuildContext context, {
    required String imagePath,
    String? title,
    String? subtitle,
    String? heroTag,
    List<LocalImageViewerItem> gallery = const [],
    int initialIndex = 0,
    LocalImageViewerBottomBuilder? bottomBuilder,
  }) {
    return Navigator.of(context).push<T>(
      PageRouteBuilder<T>(
        opaque: false,
        transitionDuration: const Duration(milliseconds: 220),
        reverseTransitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (_, __, ___) {
          return LocalImageViewerPage(
            imagePath: imagePath,
            title: title,
            subtitle: subtitle,
            heroTag: heroTag,
            gallery: gallery,
            initialIndex: initialIndex,
            bottomBuilder: bottomBuilder,
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  State<LocalImageViewerPage> createState() => _LocalImageViewerPageState();
}

class _ToggleScaleIntent extends Intent {
  const _ToggleScaleIntent();
}

class _PreviousImageIntent extends Intent {
  const _PreviousImageIntent();
}

class _NextImageIntent extends Intent {
  const _NextImageIntent();
}

class _LocalImageViewerPageState extends State<LocalImageViewerPage> {
  static const double _minScale = 0.1;
  static const double _maxScale = 8.0;
  static const double _stepScale = 1.25;
  static const double _epsilon = 0.0001;

  final FocusNode _focusNode = FocusNode();
  final TransformationController _transformController =
      TransformationController();

  late File _file;
  int _currentIndex = 0;
  int _loadGeneration = 0;

  Size? _imagePixelSize;
  Size? _viewportSize;
  Size? _lastViewportSize;
  String? _loadError;

  bool _isFitMode = false;
  bool _initialScaleReady = false;
  double _currentDesiredScale = 1.0;

  @override
  void initState() {
    super.initState();
    _currentIndex = _initialIndex;
    _file = File(_currentItem.imagePath);
    _resolveImageInfo();
  }

  List<LocalImageViewerItem> get _items {
    if (widget.gallery.isNotEmpty) return widget.gallery;
    return [
      LocalImageViewerItem(
        imagePath: widget.imagePath,
        title: widget.title,
        subtitle: widget.subtitle,
        heroTag: widget.heroTag,
      ),
    ];
  }

  int get _initialIndex =>
      widget.initialIndex.clamp(0, _items.length - 1).toInt();

  LocalImageViewerItem get _currentItem => _items[_currentIndex];

  bool get _hasPrevious => _currentIndex > 0;

  bool get _hasNext => _currentIndex < _items.length - 1;

  @override
  void dispose() {
    _focusNode.dispose();
    _transformController.dispose();
    super.dispose();
  }

  Future<void> _resolveImageInfo() async {
    final generation = _loadGeneration;
    final file = _file;
    if (!await file.exists()) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _loadError = '文件不存在'.tl);
      return;
    }

    final provider = FileImage(file);
    final stream = provider.resolve(const ImageConfiguration());
    ImageStreamListener? listener;
    listener = ImageStreamListener(
      (ImageInfo info, bool synchronousCall) {
        stream.removeListener(listener!);
        if (!mounted || generation != _loadGeneration) return;
        setState(() {
          _imagePixelSize = Size(
            info.image.width.toDouble(),
            info.image.height.toDouble(),
          );
        });
        _initScaleForOpen();
      },
      onError: (Object error, StackTrace? stackTrace) {
        stream.removeListener(listener!);
        if (!mounted || generation != _loadGeneration) return;
        setState(() => _loadError = '${'读取图片失败'.tl}: $error');
      },
    );
    stream.addListener(listener);
  }

  void _showImageAt(int index) {
    if (index < 0 || index >= _items.length || index == _currentIndex) {
      _focusNode.requestFocus();
      return;
    }

    _loadGeneration++;
    setState(() {
      _currentIndex = index;
      _file = File(_currentItem.imagePath);
      _imagePixelSize = null;
      _loadError = null;
      _initialScaleReady = false;
      _isFitMode = false;
      _currentDesiredScale = 1.0;
      _transformController.value = Matrix4.identity();
    });
    _focusNode.requestFocus();
    _resolveImageInfo();
  }

  void _showPreviousImage() => _showImageAt(_currentIndex - 1);

  void _showNextImage() => _showImageAt(_currentIndex + 1);

  Size? _actualLogicalImageSize() {
    final pixel = _imagePixelSize;
    if (pixel == null) return null;
    final dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 1.0;
    return Size(pixel.width / dpr, pixel.height / dpr);
  }

  double _fitScale() {
    final viewport = _viewportSize;
    final image = _actualLogicalImageSize();
    if (viewport == null || image == null) return 1.0;
    if (image.width <= 0 || image.height <= 0) return 1.0;
    final byWidth = viewport.width / image.width;
    final byHeight = viewport.height / image.height;
    return math.min(1.0, math.min(byWidth, byHeight));
  }

  Size _interactionBoxForScale(double desiredScale) {
    final viewport = _viewportSize;
    final image = _actualLogicalImageSize();
    if (viewport == null || image == null) return Size.zero;
    final scaledWidth = image.width * desiredScale;
    final scaledHeight = image.height * desiredScale;
    return Size(
      math.min(viewport.width, scaledWidth),
      math.min(viewport.height, scaledHeight),
    );
  }

  Matrix4 _centeredMatrix({
    required Size boxSize,
    required Size imageSize,
    required double scale,
  }) {
    final scaledWidth = imageSize.width * scale;
    final scaledHeight = imageSize.height * scale;
    final offsetX = (boxSize.width - scaledWidth) / 2;
    final offsetY = (boxSize.height - scaledHeight) / 2;
    return Matrix4.identity()
      ..setEntry(0, 0, scale)
      ..setEntry(1, 1, scale)
      ..setEntry(0, 3, offsetX)
      ..setEntry(1, 3, offsetY);
  }

  double _matrixScale() => _transformController.value.getMaxScaleOnAxis();

  void _setDesiredScale(double desired, {bool resetPosition = true}) {
    final image = _actualLogicalImageSize();
    if (image == null || _viewportSize == null) return;

    final next = desired.clamp(_minScale, _maxScale).toDouble();
    final box = _interactionBoxForScale(next);
    if (resetPosition) {
      _transformController.value = _centeredMatrix(
        boxSize: box,
        imageSize: image,
        scale: next,
      );
    } else {
      final current = _matrixScale();
      if (current <= 0) {
        _transformController.value = _centeredMatrix(
          boxSize: box,
          imageSize: image,
          scale: next,
        );
      } else {
        final ratio = next / current;
        final matrix = _transformController.value.clone();
        final centerX = box.width / 2;
        final centerY = box.height / 2;
        final tx = matrix.storage[12];
        final ty = matrix.storage[13];
        matrix.storage[0] = matrix.storage[0] * ratio;
        matrix.storage[5] = matrix.storage[5] * ratio;
        matrix.storage[12] = centerX - (centerX - tx) * ratio;
        matrix.storage[13] = centerY - (centerY - ty) * ratio;
        _transformController.value = matrix;
      }
    }

    if (!mounted) return;
    setState(() => _currentDesiredScale = next);
  }

  void _initScaleForOpen() {
    if (_initialScaleReady) return;
    if (_viewportSize == null || _actualLogicalImageSize() == null) return;
    final fit = _fitScale();
    _isFitMode = true;
    _initialScaleReady = true;
    _setDesiredScale(fit);
  }

  void _toggleFitAndActual() {
    setState(() => _isFitMode = !_isFitMode);
    _setDesiredScale(_isFitMode ? _fitScale() : 1.0);
  }

  void _zoomIn() {
    final next = (_currentDesiredScale * _stepScale).clamp(
      _minScale,
      _maxScale,
    );
    _setDesiredScale(next.toDouble());
    if (_isFitMode && next > _fitScale() + _epsilon) {
      setState(() => _isFitMode = false);
    }
  }

  void _zoomOut() {
    final next = (_currentDesiredScale / _stepScale).clamp(
      _minScale,
      _maxScale,
    );
    _setDesiredScale(next.toDouble());
    if (_isFitMode && next < _fitScale() - _epsilon) {
      setState(() => _isFitMode = false);
    }
  }

  void _onDoubleTap() {
    final fit = _fitScale();
    if (_currentDesiredScale > fit + 0.01) {
      setState(() => _isFitMode = true);
      _setDesiredScale(fit);
      return;
    }

    final target = fit < 1.0 ? 1.0 : math.min(2.0, _maxScale);
    setState(() => _isFitMode = false);
    _setDesiredScale(target);
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.digit1): _ToggleScaleIntent(),
        SingleActivator(LogicalKeyboardKey.numpad1): _ToggleScaleIntent(),
        SingleActivator(LogicalKeyboardKey.arrowLeft): _PreviousImageIntent(),
        SingleActivator(LogicalKeyboardKey.arrowUp): _PreviousImageIntent(),
        SingleActivator(LogicalKeyboardKey.arrowRight): _NextImageIntent(),
        SingleActivator(LogicalKeyboardKey.arrowDown): _NextImageIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _ToggleScaleIntent: CallbackAction<_ToggleScaleIntent>(
            onInvoke: (_) {
              _toggleFitAndActual();
              return null;
            },
          ),
          _PreviousImageIntent: CallbackAction<_PreviousImageIntent>(
            onInvoke: (_) {
              _showPreviousImage();
              return null;
            },
          ),
          _NextImageIntent: CallbackAction<_NextImageIntent>(
            onInvoke: (_) {
              _showNextImage();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          focusNode: _focusNode,
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: _buildBody(),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    return LayoutBuilder(
      builder: (context, constraints) {
        _viewportSize = Size(constraints.maxWidth, constraints.maxHeight);
        final viewportChanged =
            _lastViewportSize == null || _lastViewportSize != _viewportSize;
        _lastViewportSize = _viewportSize;

        final image = _actualLogicalImageSize();
        final hasImage = _loadError == null && image != null;
        final boxSize = image == null
            ? Size(constraints.maxWidth * 0.8, constraints.maxHeight * 0.8)
            : _interactionBoxForScale(_currentDesiredScale);

        if (!_initialScaleReady && hasImage) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _initScaleForOpen();
          });
        }
        if (_initialScaleReady && _isFitMode && hasImage && viewportChanged) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _setDesiredScale(_fitScale());
          });
        }

        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).pop(),
                child: Container(color: Colors.black.withValues(alpha: 0.55)),
              ),
            ),
            Center(
              child: hasImage ? _buildImage(image, boxSize) : _buildFallback(),
            ),
            Positioned(
              top: MediaQuery.paddingOf(context).top + 8,
              left: 8,
              child: _buildRoundButton(
                icon: Icons.close,
                tooltip: '关闭'.tl,
                onTap: () => Navigator.of(context).pop(),
              ),
            ),
            if (_currentItem.title != null || _currentItem.subtitle != null)
              Positioned(
                top: MediaQuery.paddingOf(context).top + 10,
                left: 56,
                right: 20,
                child: _buildTitle(),
              ),
            if (_items.length > 1) ...[
              Positioned(
                left: 16,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _buildNavigationButton(
                    icon: Icons.chevron_left,
                    tooltip: '${'上一张'.tl} (← / ↑)',
                    enabled: _hasPrevious,
                    onTap: _showPreviousImage,
                  ),
                ),
              ),
              Positioned(
                right: 16,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _buildNavigationButton(
                    icon: Icons.chevron_right,
                    tooltip: '${'下一张'.tl} (→ / ↓)',
                    enabled: _hasNext,
                    onTap: _showNextImage,
                  ),
                ),
              ),
            ],
            Positioned(
              left: 16,
              bottom: MediaQuery.paddingOf(context).bottom + 18,
              child: _buildScaleBadge(),
            ),
            if (widget.bottomBuilder != null)
              Positioned(
                left: 16,
                right: 16,
                bottom: MediaQuery.paddingOf(context).bottom + 18,
                child: Center(
                  child: widget.bottomBuilder!(
                    context,
                    _currentItem,
                    _currentIndex,
                  ),
                ),
              ),
            Positioned(
              right: 16,
              bottom: MediaQuery.paddingOf(context).bottom + 16,
              child: _buildActionBar(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildImage(Size image, Size boxSize) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      onDoubleTap: _onDoubleTap,
      child: SizedBox(
        width: boxSize.width,
        height: boxSize.height,
        child: InteractiveViewer(
          transformationController: _transformController,
          minScale: _minScale,
          maxScale: _maxScale,
          constrained: false,
          clipBehavior: Clip.hardEdge,
          onInteractionUpdate: (_) {
            final scale = _matrixScale();
            if ((scale - _currentDesiredScale).abs() < _epsilon) return;
            setState(() {
              _currentDesiredScale = scale;
              _isFitMode = (scale - _fitScale()).abs() < 0.01;
            });
          },
          child: SizedBox(
            width: image.width,
            height: image.height,
            child: _buildImageFile(),
          ),
        ),
      ),
    );
  }

  Widget _buildImageFile() {
    final image = Image.file(
      _file,
      fit: BoxFit.fill,
      filterQuality: FilterQuality.high,
    );
    final heroTag = _currentItem.heroTag;
    return heroTag == null ? image : Hero(tag: heroTag, child: image);
  }

  Widget _buildFallback() {
    final error = _loadError;
    if (error == null) {
      return const SizedBox(
        width: 64,
        height: 64,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return Container(
      constraints: const BoxConstraints(maxWidth: 480),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.broken_image_outlined, color: Colors.white70),
          const SizedBox(height: 12),
          Text(
            error,
            style: const TextStyle(color: Colors.white70),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildTitle() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_currentItem.title != null)
            Text(
              _currentItem.title!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          if (_currentItem.subtitle != null)
            Text(
              _currentItem.subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
        ],
      ),
    );
  }

  Widget _buildActionBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildRoundButton(
            icon: _isFitMode ? Icons.fit_screen : Icons.filter_center_focus,
            tooltip:
                '${'当前'.tl}: '
                '${(_isFitMode ? '适应窗口' : '实际大小').tl} (1)',
            onTap: _toggleFitAndActual,
          ),
          const SizedBox(width: 4),
          _buildRoundButton(
            icon: Icons.zoom_out,
            tooltip: '缩小'.tl,
            onTap: _zoomOut,
          ),
          const SizedBox(width: 4),
          _buildRoundButton(
            icon: Icons.zoom_in,
            tooltip: '放大'.tl,
            onTap: _zoomIn,
          ),
        ],
      ),
    );
  }

  Widget _buildScaleBadge() {
    final percent = (_currentDesiredScale * 100)
        .clamp(1, 9999)
        .toStringAsFixed(0);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        '$percent%',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildNavigationButton({
    required IconData icon,
    required String tooltip,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: enabled ? onTap : null,
          child: Container(
            width: 44,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: enabled ? 0.55 : 0.25),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: enabled ? Colors.white24 : Colors.white12,
              ),
            ),
            child: Icon(
              icon,
              size: 32,
              color: enabled ? Colors.white : Colors.white38,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRoundButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white24),
            ),
            child: Icon(icon, size: 20, color: Colors.white),
          ),
        ),
      ),
    );
  }
}
