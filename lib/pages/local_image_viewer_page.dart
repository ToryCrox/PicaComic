import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:pica_comic/foundation/theme/app_mouse_cursor.dart';
import 'package:pica_comic/tools/prefs_helper.dart';
import 'package:pica_comic/tools/translations.dart';

/// 本地图片查看器中的左右对照图片。
class LocalImageViewerComparison {
  /// 创建一组左右对照图片。
  const LocalImageViewerComparison({
    required this.leftImagePath,
    required this.rightImagePath,
    this.leftTitle,
    this.rightTitle,
    this.leftSubtitle,
    this.rightSubtitle,
  });

  /// 左侧图片路径。
  final String leftImagePath;

  /// 右侧图片路径。
  final String rightImagePath;

  /// 左侧图片标题。
  final String? leftTitle;

  /// 右侧图片标题。
  final String? rightTitle;

  /// 左侧图片副标题。
  final String? leftSubtitle;

  /// 右侧图片副标题。
  final String? rightSubtitle;
}

/// 本地图片查看器中的图片项。
class LocalImageViewerItem {
  /// 创建一个本地图片查看项。
  const LocalImageViewerItem({
    required this.imagePath,
    this.title,
    this.subtitle,
    this.heroTag,
    this.comparison,
  });

  /// 图片文件路径。
  final String imagePath;

  /// 顶部标题。
  final String? title;

  /// 顶部副标题。
  final String? subtitle;

  /// 可选的 Hero 标签。
  final String? heroTag;

  /// 可选的左右对照图片。
  final LocalImageViewerComparison? comparison;
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
    this.comparison,
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

  /// 单图模式下的左右对照图片。
  final LocalImageViewerComparison? comparison;

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
    LocalImageViewerComparison? comparison,
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
            comparison: comparison,
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
  static const _comparisonModePreferenceKey =
      'local_image_viewer_comparison_mode';
  static bool? _comparisonModeMemory;
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
  Size? _leftImagePixelSize;
  Size? _rightImagePixelSize;
  Size? _viewportSize;
  Size? _lastViewportSize;
  String? _loadError;

  bool _isFitMode = false;
  bool _showRightImage = false;
  bool _comparisonMode = false;
  double _comparisonSplit = 0.5;
  bool _initialScaleReady = false;
  double _currentDesiredScale = 1.0;

  @override
  void initState() {
    super.initState();
    _currentIndex = _initialIndex;
    _showRightImage = _isRightImage(_currentItem);
    _comparisonMode = _hasComparison && _readSavedComparisonMode();
    _file = File(_activeImagePath);
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
        comparison: widget.comparison,
      ),
    ];
  }

  int get _initialIndex =>
      widget.initialIndex.clamp(0, _items.length - 1).toInt();

  LocalImageViewerItem get _currentItem => _items[_currentIndex];

  /// 当前图片的对照数据。
  LocalImageViewerComparison? get _comparison => _currentItem.comparison;

  /// 当前图片是否支持切换和左右对比。
  bool get _hasComparison => _comparison != null;

  /// 当前查看的实际图片路径。
  String get _activeImagePath {
    final comparison = _comparison;
    if (comparison == null || !_showRightImage) {
      return comparison?.leftImagePath ?? _currentItem.imagePath;
    }
    return comparison.rightImagePath;
  }

  /// 当前图片是否为对照组右侧图片。
  bool _isRightImage(LocalImageViewerItem item) {
    final comparison = item.comparison;
    return comparison != null && item.imagePath == comparison.rightImagePath;
  }

  /// 读取上次使用的左右对比状态。
  bool _readSavedComparisonMode() {
    final memory = _comparisonModeMemory;
    if (memory != null) return memory;
    return _comparisonModeMemory = PrefsHelper.getBool(
      _comparisonModePreferenceKey,
    );
  }

  /// 保存左右对比状态。
  void _saveComparisonMode(bool enabled) {
    _comparisonModeMemory = enabled;
    unawaited(PrefsHelper.setBool(_comparisonModePreferenceKey, enabled));
  }

  /// 当前显示图片的标题。
  String? get _displayTitle {
    final comparison = _comparison;
    if (comparison == null) return _currentItem.title;
    return _showRightImage
        ? comparison.rightTitle ?? _currentItem.title
        : comparison.leftTitle ?? _currentItem.title;
  }

  /// 当前显示图片的副标题。
  String? get _displaySubtitle {
    final comparison = _comparison;
    if (comparison == null) return _currentItem.subtitle;
    return _showRightImage
        ? comparison.rightSubtitle ?? _currentItem.subtitle
        : comparison.leftSubtitle ?? _currentItem.subtitle;
  }

  /// 切换对照图片按钮的提示文字。
  String get _comparisonToggleTooltip => '切换原图和译图';

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
    final imageSize = await _resolveImagePixelSize(file);
    if (!mounted || generation != _loadGeneration) return;
    if (imageSize == null) {
      setState(() {
        _imagePixelSize = null;
        _loadError = file.existsSync() ? '读取图片失败'.tl : '文件不存在'.tl;
      });
      return;
    }

    setState(() {
      _imagePixelSize = imageSize;
      _leftImagePixelSize = null;
      _rightImagePixelSize = null;
      _loadError = null;
    });
    _initScaleForOpen();

    final comparison = _comparison;
    if (comparison == null) return;
    final comparisonSizes = await Future.wait([
      _resolveImagePixelSize(File(comparison.leftImagePath)),
      _resolveImagePixelSize(File(comparison.rightImagePath)),
    ]);
    if (!mounted || generation != _loadGeneration) return;
    setState(() {
      _leftImagePixelSize = comparisonSizes[0];
      _rightImagePixelSize = comparisonSizes[1];
    });
    if (_comparisonMode && _isFitMode) _setDesiredScale(_fitScale());
  }

  /// 读取本地图片尺寸；图片解码失败时返回 null。
  Future<Size?> _resolveImagePixelSize(File file) async {
    if (!await file.exists()) return null;

    final provider = FileImage(file);
    final stream = provider.resolve(const ImageConfiguration());
    final completer = Completer<Size?>();
    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (ImageInfo info, bool synchronousCall) {
        stream.removeListener(listener);
        if (!completer.isCompleted) {
          completer.complete(
            Size(info.image.width.toDouble(), info.image.height.toDouble()),
          );
        }
      },
      onError: (Object error, StackTrace? stackTrace) {
        stream.removeListener(listener);
        if (!completer.isCompleted) completer.complete();
      },
    );
    stream.addListener(listener);
    return completer.future;
  }

  void _showImageAt(int index) {
    if (index < 0 || index >= _items.length || index == _currentIndex) {
      _focusNode.requestFocus();
      return;
    }

    _loadGeneration++;
    setState(() {
      _currentIndex = index;
      _showRightImage = _isRightImage(_items[index]);
      _comparisonMode =
          _items[index].comparison != null && _readSavedComparisonMode();
      _comparisonSplit = 0.5;
      _file = File(_activeImagePath);
      _imagePixelSize = null;
      _leftImagePixelSize = null;
      _rightImagePixelSize = null;
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
    return _logicalImageSize(pixel);
  }

  Size? _logicalImageSize(Size? pixel) {
    if (pixel == null) return null;
    final dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 1.0;
    return Size(pixel.width / dpr, pixel.height / dpr);
  }

  Size? _comparisonLogicalImageSize() {
    final comparison = _comparison;
    if (comparison == null) return _actualLogicalImageSize();

    final active = _actualLogicalImageSize();
    final left = _logicalImageSize(_leftImagePixelSize) ?? active;
    final right = _logicalImageSize(_rightImagePixelSize) ?? active;
    if (left == null && right == null) return null;
    return Size(
      math.max(left?.width ?? 0, right?.width ?? 0),
      math.max(left?.height ?? 0, right?.height ?? 0),
    );
  }

  Size? _displayLogicalImageSize() {
    return _comparisonMode
        ? _comparisonLogicalImageSize()
        : _actualLogicalImageSize();
  }

  double _fitScale() {
    final viewport = _viewportSize;
    final image = _displayLogicalImageSize();
    if (viewport == null || image == null) return 1.0;
    if (image.width <= 0 || image.height <= 0) return 1.0;
    final byWidth = viewport.width / image.width;
    final byHeight = viewport.height / image.height;
    return math.min(1.0, math.min(byWidth, byHeight));
  }

  Size _interactionBoxForScale(double desiredScale) {
    final viewport = _viewportSize;
    final image = _displayLogicalImageSize();
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
    final image = _displayLogicalImageSize();
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

  /// 在对照组的左图和右图之间切换。
  void _toggleComparisonImage() {
    if (!_hasComparison) return;
    _loadGeneration++;
    setState(() {
      _comparisonMode = false;
      _comparisonSplit = 0.5;
      _showRightImage = !_showRightImage;
      _file = File(_activeImagePath);
      _imagePixelSize = null;
      _leftImagePixelSize = null;
      _rightImagePixelSize = null;
      _loadError = null;
      _initialScaleReady = false;
      _isFitMode = false;
      _currentDesiredScale = 1.0;
      _transformController.value = Matrix4.identity();
    });
    _resolveImageInfo();
  }

  /// 开启或退出左右对比模式。
  void _toggleComparisonMode() {
    if (!_hasComparison) return;
    setState(() {
      _comparisonMode = !_comparisonMode;
      _comparisonSplit = 0.5;
    });
    _saveComparisonMode(_comparisonMode);
    _setDesiredScale(_fitScale(), resetPosition: true);
  }

  /// 更新左右对比的分界线位置。
  void _updateComparisonSplit(double delta, double width) {
    if (width <= 0) return;
    setState(() {
      _comparisonSplit = (_comparisonSplit + delta / width)
          .clamp(0.0, 1.0)
          .toDouble();
    });
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

        final image = _displayLogicalImageSize();
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
            if (_displayTitle != null || _displaySubtitle != null)
              Positioned(
                top: MediaQuery.paddingOf(context).top + 10,
                left: 56,
                right: 20,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: _buildTitle(),
                ),
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
            child: _comparisonMode
                ? _buildComparisonCanvas(image)
                : _buildImageFile(),
          ),
        ),
      ),
    );
  }

  Widget _buildComparisonCanvas(Size canvasSize) {
    final comparison = _comparison;
    if (comparison == null) return _buildImageFile();

    final split = canvasSize.width * _comparisonSplit;
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: ClipRect(
            clipper: _ComparisonClipper(split: split, showLeft: true),
            child: _buildComparisonLayer(
              comparison.leftImagePath,
              _logicalImageSize(_leftImagePixelSize) ?? canvasSize,
            ),
          ),
        ),
        Positioned.fill(
          child: ClipRect(
            clipper: _ComparisonClipper(split: split, showLeft: false),
            child: _buildComparisonLayer(
              comparison.rightImagePath,
              _logicalImageSize(_rightImagePixelSize) ?? canvasSize,
            ),
          ),
        ),
        Positioned(
          left: 12,
          top: 12,
          child: _buildComparisonLabel(comparison.leftTitle ?? '左图'),
        ),
        Positioned(
          right: 12,
          top: 12,
          child: _buildComparisonLabel(comparison.rightTitle ?? '右图'),
        ),
        Positioned(
          left: (split - 1).clamp(0.0, math.max(0.0, canvasSize.width - 2)),
          top: 0,
          bottom: 0,
          width: 2,
          child: Container(color: Colors.white),
        ),
        Positioned(
          left: (split - 18).clamp(0.0, math.max(0.0, canvasSize.width - 36)),
          top: 0,
          bottom: 0,
          width: 36,
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeColumn,
            child: GestureDetector(
              key: const ValueKey('local-image-comparison-divider'),
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (details) => _updateComparisonSplit(
                details.delta.dx,
                canvasSize.width * _matrixScale(),
              ),
              child: Center(
                child: Container(
                  width: 24,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white70),
                  ),
                  child: const Icon(
                    Icons.drag_indicator,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildComparisonLayer(String imagePath, Size imageSize) {
    return Center(
      child: SizedBox(
        width: imageSize.width,
        height: imageSize.height,
        child: Image.file(
          File(imagePath),
          fit: BoxFit.fill,
          filterQuality: FilterQuality.high,
          errorBuilder: (_, _, _) => const Center(
            child: Icon(Icons.broken_image_outlined, color: Colors.white70),
          ),
        ),
      ),
    );
  }

  Widget _buildComparisonLabel(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontSize: 12),
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
          if (_displayTitle != null)
            Text(
              _displayTitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          if (_displaySubtitle != null)
            Text(
              _displaySubtitle!,
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
          if (_hasComparison) ...[
            const SizedBox(width: 4),
            _buildRoundButton(
              icon: Icons.swap_horiz,
              tooltip: _comparisonToggleTooltip.tl,
              onTap: _toggleComparisonImage,
            ),
            const SizedBox(width: 4),
            _buildRoundButton(
              icon: _comparisonMode ? Icons.compare_arrows : Icons.compare,
              tooltip: (_comparisonMode ? '退出左右对比' : '开启左右对比').tl,
              onTap: _toggleComparisonMode,
            ),
          ],
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
          mouseCursor: appClickableMouseCursor,
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
          mouseCursor: appClickableMouseCursor,
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

class _ComparisonClipper extends CustomClipper<Rect> {
  const _ComparisonClipper({required this.split, required this.showLeft});

  final double split;
  final bool showLeft;

  @override
  Rect getClip(Size size) {
    if (showLeft) {
      return Rect.fromLTWH(0, 0, split.clamp(0.0, size.width), size.height);
    }
    return Rect.fromLTWH(
      split.clamp(0.0, size.width),
      0,
      (size.width - split).clamp(0.0, size.width),
      size.height,
    );
  }

  @override
  bool shouldReclip(covariant _ComparisonClipper oldClipper) {
    return oldClipper.split != split || oldClipper.showLeft != showLeft;
  }
}
