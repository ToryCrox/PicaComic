import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/foundation/app_settings_provider.dart';
import 'package:pica_comic/pages/download/components/download_card_size_dialog.dart';
import 'package:pica_comic/tools/translations.dart';

void main() {
  late Map<String, String> originalSettings;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await AppTranslation.init();
  });

  setUp(() {
    originalSettings = Map<String, String>.from(appdata.settings);
    appdata.setSetting(AppSettingKeys.language, 'cn');
  });

  tearDown(() {
    appdata.settings = originalSettings;
  });

  /// 用纯内存仓库替换真实设置存储，避免测试触碰文件与同步。
  ({ProviderContainer container, Map<String, String> values}) buildContainer(
    String initialScale,
  ) {
    final values = <String, String>{
      AppSettingKeys.downloadCardScale: initialScale,
    };
    final changes = StreamController<void>.broadcast();
    addTearDown(changes.close);
    final container = ProviderContainer(
      overrides: [
        appSettingsRepositoryProvider.overrideWithValue(
          AppSettingsRepository(
            readValues: () => values,
            changes: changes.stream,
            saveSettings: (_) async {},
            saveData: (_) async {},
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    return (container: container, values: values);
  }

  Future<void> pumpDialog(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: DownloadCardSizeDialog()),
        ),
      ),
    );
    await tester.pump();
  }

  test('默认缩放系数对应的宽度区间为 140–240', () {
    expect(DownloadCardSizeDialog.previewWidthText(1), '140–240');
    expect(DownloadCardSizeDialog.previewWidthText(1.5), '210–360');
    expect(DownloadCardSizeDialog.previewWidthText(0.75), '105–180');
  });

  testWidgets('拖动滑块写入缩放系数并同步更新宽度区间', (tester) async {
    final state = buildContainer('1.0');
    await pumpDialog(tester, state.container);

    expect(find.text('卡片大小'), findsOneWidget);
    expect(find.text('卡片宽度 140–240'), findsOneWidget);

    // 拖到最右端，滑块应停在 1.50× 并持久化。
    await tester.drag(find.byType(Slider), const Offset(600, 0));
    await tester.pumpAndSettle();

    expect(state.values[AppSettingKeys.downloadCardScale], '1.50');
    expect(find.text('卡片宽度 210–360'), findsOneWidget);
  });

  testWidgets('恢复默认按钮在默认值下不可用，调节后可一键还原', (tester) async {
    final state = buildContainer('1.25');
    await pumpDialog(tester, state.container);

    expect(find.text('卡片宽度 175–300'), findsOneWidget);

    await tester.tap(find.text('恢复默认'));
    await tester.pumpAndSettle();

    expect(state.values[AppSettingKeys.downloadCardScale], '1.00');
    expect(find.text('卡片宽度 140–240'), findsOneWidget);
  });
}
