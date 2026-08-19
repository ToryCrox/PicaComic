import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pica_comic/components/theme_color_picker.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/foundation/theme/theme_provider.dart';
import 'package:pica_comic/tools/translations.dart';

/// 统一的主题设置页面。
class ThemePage extends ConsumerWidget {
  const ThemePage({super.key});

  /// 在移动端打开完整页面，在桌面端打开 PixEz 风格的受限尺寸对话框。
  static void open({BuildContext? context}) {
    final targetContext = context ?? App.globalContext;
    if (targetContext == null) return;

    if (App.isDesktop) {
      showDialog<void>(
        context: targetContext,
        builder: (dialogContext) {
          final height = MediaQuery.sizeOf(dialogContext).height * 0.72;
          return Dialog(
            clipBehavior: Clip.antiAlias,
            insetPadding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 460, maxHeight: height),
              child: const ThemePage(),
            ),
          );
        },
      );
    } else if (context != null) {
      App.to(context, () => const ThemePage());
    } else {
      App.globalTo(() => const ThemePage());
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(themeSettingsProvider);
    return DefaultTabController(
      key: ValueKey(settings.themeMode),
      initialIndex: settings.themeMode.index,
      length: ThemeMode.values.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text('主题设置'.tl),
          bottom: TabBar(
            tabs: [
              Tab(text: '跟随系统'.tl),
              Tab(text: '浅色'.tl),
              Tab(text: '深色'.tl),
            ],
            onTap: (index) {
              ref
                  .read(themeSettingsProvider.notifier)
                  .setThemeMode(ThemeMode.values[index]);
            },
          ),
        ),
        body: _ThemeOptions(settings: settings),
      ),
    );
  }
}

class _ThemeOptions extends ConsumerWidget {
  const _ThemeOptions({required this.settings});

  final ThemeSettingsState settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(themeSettingsProvider.notifier);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          clipBehavior: Clip.antiAlias,
          child: SwitchListTile(
            secondary: const Icon(Icons.dark_mode_outlined),
            title: Text('AMOLED'.tl),
            subtitle: Text('深色模式下使用纯黑背景'.tl),
            value: settings.isAmoled,
            onChanged: notifier.setAmoled,
          ),
        ),
        Card(
          clipBehavior: Clip.antiAlias,
          child: SwitchListTile(
            secondary: const Icon(Icons.auto_awesome_outlined),
            title: Text('动态颜色'.tl),
            subtitle: Text('使用系统提供的动态配色'.tl),
            value: settings.useDynamicColor,
            onChanged: notifier.setUseDynamicColor,
          ),
        ),
        if (!settings.useDynamicColor)
          Card(
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              leading: _ColorPreview(color: settings.seedColor),
              title: Text('种子颜色'.tl),
              subtitle: Text(_hexColor(settings.seedColor)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final color = await showThemeColorPickerDialog(
                  context,
                  settings.seedColor,
                );
                if (color != null) {
                  await notifier.setSeedColor(color);
                }
              },
            ),
          ),
      ],
    );
  }
}

class _ColorPreview extends StatelessWidget {
  const _ColorPreview({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
    );
  }
}

/// 打开种子颜色选择器并返回确认后的 RGB 颜色。
Future<Color?> showThemeColorPickerDialog(
  BuildContext context,
  Color initialColor,
) {
  return showDialog<Color>(
    context: context,
    builder: (_) => _ThemeColorPickerDialog(initialColor: initialColor),
  );
}

class _ThemeColorPickerDialog extends StatefulWidget {
  const _ThemeColorPickerDialog({required this.initialColor});

  final Color initialColor;

  @override
  State<_ThemeColorPickerDialog> createState() =>
      _ThemeColorPickerDialogState();
}

class _ThemeColorPickerDialogState extends State<_ThemeColorPickerDialog> {
  late Color _draftColor;

  @override
  void initState() {
    super.initState();
    _draftColor = _normalizeColor(widget.initialColor);
  }

  void _reset() {
    setState(() {
      _draftColor = Colors.blue[400]!;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('选择种子颜色'.tl),
      content: SizedBox(
        width: 320,
        child: SingleChildScrollView(
          child: ThemeColorPicker(
            color: _draftColor,
            onColorChanged: (color) => setState(() => _draftColor = color),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _reset, child: Text('还原'.tl)),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('取消'.tl),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_draftColor),
          child: Text('确定'.tl),
        ),
      ],
    );
  }
}

Color _normalizeColor(Color color) {
  return Color(0xff000000 | (color.toARGB32() & 0x00ffffff));
}

String _hexColor(Color color) {
  return '#${(color.toARGB32() & 0x00ffffff).toRadixString(16).padLeft(6, '0').toUpperCase()}';
}
