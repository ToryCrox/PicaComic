import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/foundation/ui_mode.dart';
import 'package:pica_comic/tools/translations.dart';

import 'local_favorites.dart';
import 'local_favorites_providers.dart';

/// 收藏搜索，输入草稿留在页面，防抖和结果由 Riverpod 管理。
class LocalSearchPage extends ConsumerStatefulWidget {
  const LocalSearchPage({super.key});
  @override
  ConsumerState<LocalSearchPage> createState() => _LocalSearchPageState();
}

class _LocalSearchPageState extends ConsumerState<LocalSearchPage> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keyword = ref.watch(favoriteSearchInputProvider);
    final results = ref.watch(favoriteSearchProvider(keyword));
    return Material(
      child: Column(
        children: [
          SizedBox(
            height: UiMode.m1(context) ? MediaQuery.paddingOf(context).top : 0,
          ),
          SizedBox(
            height: 56,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.pop(context),
                ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    autofocus: true,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: '搜索'.tl,
                    ),
                    onChanged: ref
                        .read(favoriteSearchInputProvider.notifier)
                        .change,
                    onSubmitted: ref
                        .read(favoriteSearchInputProvider.notifier)
                        .submit,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: results.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: TextButton(
                  onPressed: () =>
                      ref.invalidate(favoriteSearchProvider(keyword)),
                  child: Text('搜索失败，点击重试: $error'),
                ),
              ),
              data: (items) => GridView.builder(
                gridDelegate: SliverGridDelegateWithComics(),
                itemCount: items.length,
                itemBuilder: (context, index) => LocalFavoriteTile(
                  items[index].comic,
                  items[index].folder,
                  true,
                  showFolderInfo: true,
                  key: ValueKey((
                    items[index].folder,
                    items[index].comic.identity,
                  )),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
