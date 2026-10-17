part of pica_settings;

/// 屏蔽词列表观察统一用户数据，排序仅属于当前页面。
class BlockingKeywordPage extends ConsumerStatefulWidget {
  const BlockingKeywordPage({this.popUp = false, super.key});

  final bool popUp;

  @override
  ConsumerState<BlockingKeywordPage> createState() =>
      _BlockingKeywordPageState();
}

/// 页面只保存未持久化的排序方向。
class _BlockingKeywordPageState extends ConsumerState<BlockingKeywordPage> {
  bool _down = true;

  /// 保存失败时提示，保持现有列表和弹窗可继续操作。
  Future<void> _save(Future<void> Function() operation) async {
    try {
      await operation();
    } catch (_) {
      if (mounted) showToast(message: '保存失败，请重试'.tl);
    }
  }

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(userLibraryProvider);
    final actions = ref.read(userLibraryPreferencesActionsProvider.notifier);
    final busy = ref.watch(userLibraryPreferencesActionsProvider).isLoading;
    final keywords = _down
        ? library.blockingKeywords
        : library.blockingKeywords.reversed.toList();
    return PopUpWidgetScaffold(
      title: '关键词屏蔽'.tl,
      tailing: [
        Tooltip(
          message: '添加'.tl,
          child: IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => const _BlockingKeywordDialog(),
            ),
          ),
        ),
        Tooltip(
          message: '排序'.tl,
          child: IconButton(
            icon: Icon(_down ? Icons.arrow_downward : Icons.arrow_upward),
            onPressed: () => setState(() => _down = !_down),
          ),
        ),
      ],
      body: ListView.builder(
        itemCount: keywords.length + 1,
        padding: EdgeInsets.zero,
        itemBuilder: (context, index) {
          if (index == 0) {
            if (!library.showBlockingHint) return const SizedBox.shrink();
            return MaterialBanner(
              forceActionsBelow: true,
              padding: const EdgeInsets.all(15),
              leading: Icon(
                Icons.info_outline,
                color: Theme.of(context).colorScheme.primary,
                size: 30,
              ),
              content: Text('关键词屏蔽不会生效于收藏夹和历史记录, 屏蔽的依据仅限加载漫画列表时能够获取到的信息'.tl),
              actions: [
                TextButton(
                  onPressed: busy
                      ? null
                      : () => _save(actions.dismissBlockingHint),
                  child: Text('关闭'.tl),
                ),
              ],
            );
          }
          final keyword = keywords[index - 1];
          return ListTile(
            title: Text(keyword),
            trailing: IconButton(
              icon: Icon(
                Icons.close,
                color: Theme.of(context).colorScheme.secondary,
              ),
              onPressed: busy
                  ? null
                  : () => _save(() => actions.removeBlockedWord(keyword)),
            ),
          );
        },
      ),
    );
  }
}

/// 添加屏蔽词的草稿只在弹窗内保留。
class _BlockingKeywordDialog extends ConsumerStatefulWidget {
  const _BlockingKeywordDialog();

  @override
  ConsumerState<_BlockingKeywordDialog> createState() =>
      _BlockingKeywordDialogState();
}

/// 弹窗销毁时释放输入控制器。
class _BlockingKeywordDialogState
    extends ConsumerState<_BlockingKeywordDialog> {
  final _controller = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 等待保存成功后再关闭，失败保留用户输入。
  Future<void> _submit() async {
    final word = _controller.text.trim();
    if (word.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(userLibraryPreferencesActionsProvider.notifier)
          .addBlockedWords([word]);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) showToast(message: '保存失败，请重试'.tl);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => SimpleDialog(
    title: Text('添加屏蔽关键词'.tl),
    children: [
      const SizedBox(width: 300),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        child: TextField(
          controller: _controller,
          enabled: !_saving,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            hintText: '添加关键词'.tl,
          ),
          onEditingComplete: _submit,
        ),
      ),
      const SizedBox(height: 8),
      Center(
        child: FilledButton(
          onPressed: _saving ? null : _submit,
          child: Text('提交'.tl),
        ),
      ),
    ],
  );
}
