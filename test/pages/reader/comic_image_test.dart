import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/components/scrollable_list/src/scrollable_positioned_list.dart';
import 'package:pica_comic/foundation/app_settings_provider.dart';
import 'package:pica_comic/pages/reader/image.dart';

const _imageColor = Color(0xff402030);
const _backgroundColor = Color(0xfff5fafc);

void main() {
  setUp(ComicImage.clear);

  testWidgets('漫画图片首次加载、重建和宽度变化均保持精确比例高度', (tester) async {
    final provider = await tester.runAsync(_createImageProvider);
    final repository = _createSettingsRepository();
    await _precacheImage(tester, provider!, repository);

    for (final width in [100.0, 100.0, 125.0]) {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appSettingsRepositoryProvider.overrideWithValue(repository),
          ],
          child: MaterialApp(
            home: Align(
              alignment: Alignment.topLeft,
              child: ComicImage(
                image: provider,
                width: width,
                fit: BoxFit.contain,
                isShowOriginSize: true,
              ),
            ),
          ),
        ),
      );

      final expectedHeight = width * 1.234;
      expect(
        tester.getSize(find.byType(ComicImage)).height,
        closeTo(expectedHeight, 1e-9),
      );
      expect(
        tester.widget<RawImage>(find.byType(RawImage)).height,
        closeTo(expectedHeight, 1e-9),
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('连续列表在不同像素比和滚动位置下拼接图片不露出背景', (tester) async {
    final provider = await tester.runAsync(_createImageProvider);
    final repository = _createSettingsRepository();
    await _precacheImage(tester, provider!, repository);
    final boundaryKey = GlobalKey();
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final pixelRatio in [1.0, 1.25, 2.0]) {
      tester.view.devicePixelRatio = pixelRatio;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appSettingsRepositoryProvider.overrideWithValue(repository),
          ],
          child: MaterialApp(
            home: Align(
              alignment: Alignment.topLeft,
              child: RepaintBoundary(
                key: boundaryKey,
                child: ColoredBox(
                  color: _backgroundColor,
                  child: SizedBox(
                    width: 100,
                    height: 180,
                    child: ScrollablePositionedList.builder(
                      scrollController: scrollController,
                      padding: EdgeInsets.zero,
                      itemCount: 2,
                      itemBuilder: (context, index) => Stack(
                        alignment: Alignment.center,
                        children: [
                          ComicImage(
                            image: provider,
                            width: 100,
                            fit: BoxFit.contain,
                            isShowOriginSize: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      for (final offset in [0.0, 0.3, 10.25]) {
        scrollController.jumpTo(offset);
        await tester.pump();
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final output = await boundary.toImage(pixelRatio: pixelRatio);
          try {
            final data = await output.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            );
            final pixels = data!.buffer.asUint8List();
            final seam = ((123.4 - offset) * pixelRatio).floor();
            for (var y = seam - 2; y <= seam + 2; y++) {
              for (
                var x = (20 * pixelRatio).floor();
                x < (80 * pixelRatio).floor();
                x++
              ) {
                final start = (y * output.width + x) * 4;
                expect(pixels.sublist(start, start + 4), [
                  64,
                  32,
                  48,
                  255,
                ], reason: '像素比 $pixelRatio、滚动位置 $offset 的接缝 ($x, $y)');
              }
            }
          } finally {
            output.dispose();
          }
        });
      }
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
  });
}

/// 创建无白边的纯色图片，用于检测拼接处是否露出底色。
Future<MemoryImage> _createImageProvider() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    const Rect.fromLTWH(0, 0, 1000, 1234),
    Paint()..color = _imageColor,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(1000, 1234);
  picture.dispose();
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return MemoryImage(data!.buffer.asUint8List());
  } finally {
    image.dispose();
  }
}

/// 使用独立设置数据，避免测试读写应用的持久化配置。
AppSettingsRepository _createSettingsRepository() {
  return AppSettingsRepository(
    readValues: () => defaultAppSettings,
    changes: const Stream<void>.empty(),
  );
}

/// 提前解码图片，让测试覆盖组件首次收到图片帧时的布局。
Future<void> _precacheImage(
  WidgetTester tester,
  MemoryImage provider,
  AppSettingsRepository repository,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appSettingsRepositoryProvider.overrideWithValue(repository)],
      child: const MaterialApp(home: SizedBox()),
    ),
  );
  await tester.runAsync(
    () => precacheImage(provider, tester.element(find.byType(SizedBox).first)),
  );
  await tester.pump();
}
