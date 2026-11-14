import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/components/windows_glass_panel.dart';

void main() {
  testWidgets('旧面板调用使用普通 Material 内容', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: WindowsGlassPanel(fallback: Text('普通面板'), child: Text('旧面板')),
        ),
      ),
    );
    expect(find.text('普通面板'), findsOneWidget);
    expect(find.text('旧面板'), findsNothing);
  });
}
