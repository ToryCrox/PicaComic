import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pica_comic/comic_source/comic_source.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/network/manhuagui/manhuagui_network.dart';
import 'package:pica_comic/network/manhuagui/manhuagui_parser.dart';
import 'package:pica_comic/tools/translations.dart';

/// 无需登录的漫画柜评论，支持最新、热门及引用回复链。
class ManhuaguiCommentsPage extends ConsumerStatefulWidget {
  const ManhuaguiCommentsPage({super.key, required this.comicId});
  final String comicId;

  @override
  ConsumerState<ManhuaguiCommentsPage> createState() =>
      _ManhuaguiCommentsPageState();
}

/// 排序切换后重新从第一页请求。
class _ManhuaguiCommentsPageState extends ConsumerState<ManhuaguiCommentsPage> {
  var _sort = ManhuaguiCommentSort.latest;
  final _scroll = ScrollController();
  final _threads = <ManhuaguiCommentThread>[];
  var _page = 0;
  var _generation = 0;
  var _loading = false;
  var _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_loadIfNearEnd);
    Future.microtask(_loadNext);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// 切换排序时废弃在途响应，从第一页开始。
  void _reset(ManhuaguiCommentSort sort) {
    _generation++;
    setState(() {
      _sort = sort;
      _threads.clear();
      _page = 0;
      _loading = false;
      _hasMore = true;
      _error = null;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _loadNext();
  }

  /// 接近列表末尾时预取一页，短列表自动填满视口。
  void _loadIfNearEnd() {
    if (_scroll.hasClients &&
        _scroll.position.extentAfter < 240 &&
        _error == null) {
      _loadNext();
    }
  }

  /// 以代次隔离排序请求，失败保留已加载评论并允许重试。
  Future<void> _loadNext() async {
    if (!mounted || _loading || !_hasMore) return;
    final generation = _generation;
    final page = _page + 1;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await ref
          .read(manhuaguiNetworkProvider)
          .comments(widget.comicId, page, _sort);
      if (!mounted || generation != _generation) return;
      if (response.error) throw StateError(response.errorMessageWithoutNull);
      setState(() {
        final ids = _threads.map((t) => t.comment.id).toSet();
        _threads.addAll(response.data.where((t) => ids.add(t.comment.id)));
        _page = page;
        _hasMore =
            response.data.isNotEmpty &&
            page < (response.subData as int? ?? page);
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = '$error');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _loadIfNearEnd();
        });
      }
    }
  }

  /// 评论内容使用文本渲染，不执行站点 HTML。
  Widget _comment(Comment comment, {bool quote = false}) => Container(
    padding: const EdgeInsets.all(12),
    margin: const EdgeInsets.only(bottom: 8),
    decoration: BoxDecoration(
      color: quote
          ? Theme.of(context).colorScheme.surfaceContainerHighest
          : null,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.person_outline, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                comment.userName.isEmpty ? '匿名'.tl : comment.userName,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SelectableText(comment.content.isEmpty ? '评论已删除'.tl : comment.content),
        const SizedBox(height: 8),
        Text(comment.time ?? '', style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );

  /// 排序控件与返回、标题同行，列表只负责评论及加载反馈。
  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      children: [
        SizedBox(
          height: 60,
          child: Row(
            children: [
              const BackButton(),
              Text('评论'.tl, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(width: 12),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: SegmentedButton<ManhuaguiCommentSort>(
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        padding: WidgetStatePropertyAll(
                          EdgeInsets.symmetric(horizontal: 10),
                        ),
                      ),
                      segments: [
                        ButtonSegment(
                          value: ManhuaguiCommentSort.latest,
                          label: Text('最新评论'.tl),
                        ),
                        ButtonSegment(
                          value: ManhuaguiCommentSort.hot,
                          label: Text('热门评论'.tl),
                        ),
                      ],
                      selected: {_sort},
                      showSelectedIcon: false,
                      onSelectionChanged: (values) => _reset(values.single),
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: '刷新'.tl,
                onPressed: () => _reset(_sort),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        Expanded(child: _body()),
      ],
    ),
  );

  /// 连续列表的错误入口保留当前滚动位置。
  Widget _body() {
    if (_threads.isEmpty) {
      if (_loading) return const Center(child: CircularProgressIndicator());
      if (_error != null) {
        return NetworkError(
          message: _error!,
          withAppbar: false,
          retry: _loadNext,
        );
      }
      return Center(child: Text('暂无评论'.tl));
    }
    return ListView.separated(
      controller: _scroll,
      padding: const EdgeInsets.all(12),
      itemCount: _threads.length + 1,
      separatorBuilder: (_, _) => const Divider(),
      itemBuilder: (context, index) {
        if (index == _threads.length) {
          if (_error != null) {
            return Column(
              children: [
                Text(_error!),
                TextButton(onPressed: _loadNext, child: Text('重试'.tl)),
              ],
            );
          }
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: _loading
                  ? const CircularProgressIndicator()
                  : _hasMore
                  ? const SizedBox.shrink()
                  : Text('没有更多了'.tl),
            ),
          );
        }
        final thread = _threads[index];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final quote in thread.quotes) _comment(quote, quote: true),
            _comment(thread.comment),
          ],
        );
      },
    );
  }
}
