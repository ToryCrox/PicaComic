import 'package:flutter/material.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/network/download.dart';
import 'package:pica_comic/network/models/download_tag.dart';
import 'package:pica_comic/tools/translations.dart';

/// 标签分配对话框
class TagAssignmentDialog extends StatefulWidget {
  final List<String> comicIds;

  const TagAssignmentDialog({
    Key? key,
    required this.comicIds,
  }) : super(key: key);

  @override
  State<TagAssignmentDialog> createState() => _TagAssignmentDialogState();
}

class _TagAssignmentDialogState extends State<TagAssignmentDialog> {
  List<DownloadTag> allTags = [];
  Set<int> selectedTagIds = {};
  bool loading = true;
  final TextEditingController _newTagController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadTags();
  }

  @override
  void dispose() {
    _newTagController.dispose();
    super.dispose();
  }

  Future<void> _loadTags() async {
    setState(() => loading = true);

    // 获取所有标签
    final tags = await downloadManager.getAllTags();

    // 获取第一个漫画的标签（用于显示初始状态）
    if (widget.comicIds.isNotEmpty) {
      final firstComicTags =
          await downloadManager.getComicTags(widget.comicIds.first);
      selectedTagIds = firstComicTags.map((e) => e.id).toSet();
    }

    setState(() {
      allTags = tags;
      loading = false;
    });
  }

  Future<void> _createNewTag() async {
    if (_newTagController.text.isEmpty) return;

    try {
      final tagId = await downloadManager.createTag(_newTagController.text);
      final newTag = DownloadTag(
        id: tagId,
        name: _newTagController.text,
        coverComicId: null,
        createdTime: DateTime.now(),
      );

      setState(() {
        allTags.insert(0, newTag);
        selectedTagIds.add(tagId);
        _newTagController.clear();
      });

      showToast(message: "标签创建成功".tl);
    } catch (e) {
      showToast(message: "标签创建失败: $e".tl);
    }
  }

  Future<void> _applyTags() async {
    try {
      // 为所有选中的漫画设置标签
      for (var comicId in widget.comicIds) {
        // 获取当前漫画的标签
        final currentTags = await downloadManager.getComicTags(comicId);
        final currentTagIds = currentTags.map((e) => e.id).toSet();

        // 添加新标签
        for (var tagId in selectedTagIds) {
          if (!currentTagIds.contains(tagId)) {
            await downloadManager.addTagToComic(comicId, tagId);
          }
        }

        // 移除取消选中的标签
        for (var tagId in currentTagIds) {
          if (!selectedTagIds.contains(tagId)) {
            await downloadManager.removeTagFromComic(comicId, tagId);
          }
        }
      }

      if (mounted) {
        showToast(message: "标签更新成功".tl);
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        showToast(message: "标签更新失败: $e".tl);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("管理标签".tl),
      content: SizedBox(
        width: 400,
        height: 500,
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  // 新建标签输入框
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _newTagController,
                          decoration: InputDecoration(
                            labelText: "新建标签".tl,
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                          onSubmitted: (_) => _createNewTag(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.add),
                        onPressed: _createNewTag,
                        tooltip: "创建".tl,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  // 标签列表
                  Expanded(
                    child: allTags.isEmpty
                        ? Center(
                            child: Text(
                              "暂无标签，请先创建标签".tl,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.outline,
                              ),
                            ),
                          )
                        : ListView.builder(
                            itemCount: allTags.length,
                            itemBuilder: (context, index) {
                              final tag = allTags[index];
                              final tagId = tag.id;
                              final tagName = tag.name;
                              final isSelected = selectedTagIds.contains(tagId);

                              return CheckboxListTile(
                                title: Text(tagName),
                                value: isSelected,
                                onChanged: (value) {
                                  setState(() {
                                    if (value == true) {
                                      selectedTagIds.add(tagId);
                                    } else {
                                      selectedTagIds.remove(tagId);
                                    }
                                  });
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text("取消".tl),
        ),
        TextButton(
          onPressed: _applyTags,
          child: Text("确认".tl),
        ),
      ],
    );
  }
}
