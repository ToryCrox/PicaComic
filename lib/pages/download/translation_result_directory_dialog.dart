import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/tools/translations.dart';

/// 设置外部漫画翻译结果的根目录。
Future<bool> showTranslationResultDirectoryDialog(BuildContext context) async {
  final directory = await showDialog<String>(
    context: context,
    builder: (_) => const _TranslationResultDirectoryDialog(),
  );
  if (directory == null) return false;
  appdata.appSettings.translationResultDirectory = directory;
  await appdata.updateSettings();
  return true;
}

class _TranslationResultDirectoryDialog extends StatefulWidget {
  const _TranslationResultDirectoryDialog();

  @override
  State<_TranslationResultDirectoryDialog> createState() =>
      _TranslationResultDirectoryDialogState();
}

class _TranslationResultDirectoryDialogState
    extends State<_TranslationResultDirectoryDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: appdata.appSettings.translationResultDirectory,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickDirectory() async {
    if (!App.isDesktop) return;
    final selectedPath = await getDirectoryPath(confirmButtonText: '选择'.tl);
    if (selectedPath == null || !mounted) return;
    setState(() => _controller.text = selectedPath);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('漫画翻译结果目录'.tl),
      content: SizedBox(
        width: 560,
        child: TextField(
          controller: _controller,
          autofocus: true,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: '目录路径'.tl,
            hintText: '留空则使用漫画目录内的 result 目录'.tl,
            helperText: '结果目录中应包含与原漫画同名的漫画目录'.tl,
            border: const OutlineInputBorder(),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_controller.text.isNotEmpty)
                  IconButton(
                    onPressed: () => setState(_controller.clear),
                    tooltip: '清空'.tl,
                    icon: const Icon(Icons.clear),
                  ),
                IconButton(
                  onPressed: App.isDesktop ? _pickDirectory : null,
                  tooltip: '选择目录'.tl,
                  icon: const Icon(Icons.folder_open),
                ),
              ],
            ),
          ),
          onChanged: (_) => setState(() {}),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('取消'.tl),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: Text('确认'.tl),
        ),
      ],
    );
  }
}
