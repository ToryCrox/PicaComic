import 'package:flutter/material.dart';

import 'ai.dart';

/// 仅查询本地缓存的漫画标题构建器。
///
/// 下载列表使用它展示详情页已经生成的译名，绝不会因此发起 AI 请求。
class AiCachedTitleBuilder extends StatefulWidget {
  const AiCachedTitleBuilder({
    required this.resource,
    required this.title,
    required this.builder,
    super.key,
  });

  final AiComicResource resource;
  final String title;
  final Widget Function(BuildContext context, String? translatedTitle) builder;

  @override
  State<AiCachedTitleBuilder> createState() => _AiCachedTitleBuilderState();
}

class _AiCachedTitleBuilderState extends State<AiCachedTitleBuilder> {
  String? _translatedTitle;
  String? _requestKey;

  @override
  void initState() {
    super.initState();
    aiTranslationService.addListener(_load);
    _load();
  }

  @override
  void didUpdateWidget(covariant AiCachedTitleBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    _load();
  }

  @override
  void dispose() {
    aiTranslationService.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final requestKey =
        '${widget.resource.sourceKey}\u0000${widget.resource.downloadId}\u0000'
        '${widget.resource.targetLanguage}\u0000${widget.title}';
    _requestKey = requestKey;
    final title = await aiTranslationService.cachedComicTitle(
      resource: widget.resource,
      title: widget.title,
    );
    if (!mounted || _requestKey != requestKey || title == _translatedTitle) {
      return;
    }
    setState(() => _translatedTitle = title);
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _translatedTitle);
}
