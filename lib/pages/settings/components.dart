part of pica_settings;

/// 通过统一设置入口读写布尔值。
class SwitchSetting extends ConsumerWidget {
  const SwitchSetting({
    required this.title,
    this.subTitle,
    required this.icon,
    required this.settingKey,
    super.key,
  });

  final String title;
  final String? subTitle;
  final Widget icon;
  final String settingKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(
      appSettingsProvider.select((s) => s.enabled(settingKey)),
    );
    return ListTile(
      title: Text(title),
      subtitle: subTitle == null ? null : Text(subTitle!),
      leading: icon,
      trailing: Switch(
        value: enabled,
        onChanged: (value) => _saveSetting(ref, settingKey, value ? '1' : '0'),
      ),
    );
  }
}

/// 设置页统一处理持久化错误，空值表示只保存滑块预览。
Future<void> _saveSetting(
  WidgetRef ref,
  String key,
  String? value, {
  bool fullData = false,
  bool persist = true,
}) async {
  try {
    final controller = ref.read(appSettingsProvider.notifier);
    if (value == null) {
      await controller.save(fullData: fullData);
    } else {
      await controller.setValue(
        key,
        value,
        fullData: fullData,
        persist: persist,
      );
    }
  } catch (error, stack) {
    Log.e('保存设置失败', error: error, stackTrace: stack);
    showToast(message: '保存设置失败');
  }
}

/// 保存已经通过统一入口修改的设置，处理异步持久化错误。
Future<void> _persistSettings(WidgetRef ref, {bool fullData = false}) async {
  try {
    await ref.read(appSettingsProvider.notifier).save(fullData: fullData);
  } catch (error, stack) {
    Log.e('保存设置失败', error: error, stackTrace: stack);
    showToast(message: '保存设置失败');
  }
}

/// 从当前弹窗所属的容器读取统一设置控制器。
AppSettings _settingsController(BuildContext context) {
  return ProviderScope.containerOf(
    context,
    listen: false,
  ).read(appSettingsProvider.notifier);
}

/// 普通函数中的设置弹窗复用统一写入，并展示持久化错误。
Future<void> _saveSettingContext(
  BuildContext context,
  String key,
  String value, {
  bool fullData = false,
}) async {
  try {
    await _settingsController(context).setValue(key, value, fullData: fullData);
  } catch (error, stack) {
    Log.e('保存设置失败', error: error, stackTrace: stack);
    if (context.mounted) showToast(message: '保存设置失败');
  }
}

class SettingsTitle extends StatelessWidget {
  const SettingsTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return ListTile(title: Text(text));
  }
}

class NewPageSetting extends StatelessWidget {
  const NewPageSetting({
    required this.title,
    required this.onTap,
    required this.icon,
    super.key,
  });

  final String title;

  final VoidCallback onTap;

  final Widget icon;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: icon,
      title: Text(title),
      onTap: onTap,
      trailing: const Icon(Icons.arrow_right),
    );
  }
}

/// 保留原调用接口的索引选择控件，通过 Provider 读写设置。
class SelectSettingWithAppdata extends ConsumerWidget {
  const SelectSettingWithAppdata({
    super.key,
    required this.icon,
    required this.title,
    required this.settingKey,
    required this.options,
    this.onChanged,
  });

  final Widget icon;

  final String title;

  final String settingKey;

  final List<String> options;

  final void Function()? onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SelectSetting(
      leading: icon,
      title: title,
      values: options,
      onChanged: (i) {
        _saveSetting(ref, settingKey, i.toString());
        onChanged?.call();
      },
      initialValue: ref.watch(
        appSettingsProvider.select((s) => s.integer(settingKey)),
      ),
    );
  }
}

class SelectSetting extends StatelessWidget {
  const SelectSetting({
    super.key,
    required this.leading,
    required this.title,
    required this.values,
    required this.onChanged,
    required this.initialValue,
  });

  final Widget leading;

  final String title;

  final List<String> values;

  final void Function(int i) onChanged;

  final int initialValue;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constrains) {
        bool small = constrains.maxWidth < 400;
        if (small) {
          return _SelectTile(
            icon: leading,
            title: title,
            options: values,
            onChange: onChanged,
            initialValue: initialValue,
          );
        }
        return ListTile(
          leading: leading,
          title: Text(title),
          trailing: Select(
            width: 136,
            initialValue: initialValue,
            onChange: onChanged,
            values: values,
          ),
        );
      },
    );
  }
}

class _SelectTile extends StatefulWidget {
  const _SelectTile({
    required this.icon,
    required this.title,
    required this.initialValue,
    required this.options,
    this.onChange,
  });

  final Widget icon;

  final String title;

  final int initialValue;

  final List<String> options;

  final void Function(int i)? onChange;

  @override
  State<_SelectTile> createState() => _SelectTileState();
}

class _SelectTileState extends State<_SelectTile> {
  var value = -1;

  @override
  void initState() {
    value = widget.initialValue;
    super.initState();
  }

  /// 外部设置重载后同步选中项。
  @override
  void didUpdateWidget(covariant _SelectTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue) {
      value = widget.initialValue;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: widget.icon,
      title: Text(widget.title),
      subtitle: Text(
        value < 0 || value >= widget.options.length
            ? "无".tl
            : widget.options[value],
      ),
      onTap: showOptions,
      trailing: const Icon(Icons.arrow_drop_down),
    );
  }

  void showOptions() {
    final renderBox = context.findRenderObject() as RenderBox;
    var offset = renderBox.localToGlobal(Offset.zero);
    showMenu<int>(
      context: App.globalContext!,
      initialValue: value == -1 ? null : value,
      position: RelativeRect.fromLTRB(
        offset.dx + renderBox.size.width,
        offset.dy,
        offset.dx + renderBox.size.width,
        offset.dy,
      ),
      color: context.colorScheme.surfaceContainerLowest,
      items: [
        for (int i = 0; i < widget.options.length; i++)
          PopupMenuItem(
            value: i,
            height: 42,
            onTap: () {
              setState(() {
                value = i;
              });
              widget.onChange?.call(i);
            },
            child: Text(widget.options[i]),
          ),
      ],
    );
  }
}
