import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/foundation/theme/app_mouse_cursor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  for (final platform in <TargetPlatform>[
    TargetPlatform.windows,
    TargetPlatform.macOS,
    TargetPlatform.linux,
  ]) {
    test('$platform 启用态使用手型，禁用态使用普通箭头', () {
      debugDefaultTargetPlatformOverride = platform;

      expect(
        appClickableMouseCursor.resolve(<WidgetState>{}),
        same(SystemMouseCursors.click),
      );
      expect(
        appClickableMouseCursor.resolve(<WidgetState>{WidgetState.disabled}),
        same(SystemMouseCursors.basic),
      );
    });
  }

  test('Android 启用态和禁用态都使用普通箭头', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    expect(
      appClickableMouseCursor.resolve(<WidgetState>{}),
      same(SystemMouseCursors.basic),
    );
    expect(
      appClickableMouseCursor.resolve(<WidgetState>{WidgetState.disabled}),
      same(SystemMouseCursors.basic),
    );
  });
}
