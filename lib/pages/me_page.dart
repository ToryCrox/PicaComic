import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pica_comic/comic_source/comic_source.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/foundation/history.dart';
import 'package:pica_comic/foundation/history_providers.dart';
import 'package:pica_comic/foundation/theme/app_mouse_cursor.dart';
import 'package:pica_comic/pages/download/download_providers.dart';
import 'package:pica_comic/pages/account_providers.dart';
import 'package:pica_comic/network/picacg_network/models.dart';
import 'accounts_page.dart';
import 'package:pica_comic/pages/download/download_page.dart';
import 'package:pica_comic/pages/tools.dart';
import 'package:pica_comic/foundation/app.dart';
import 'history_page.dart';
import 'package:pica_comic/tools/translations.dart';
import 'image_favorites.dart';

class MePage extends ConsumerStatefulWidget {
  const MePage({super.key});

  @override
  ConsumerState<MePage> createState() => _MePageState();
}

class _MePageState extends ConsumerState<MePage> {
  @override
  void initState() {
    super.initState();
    // 只有用户进入“我的”页时才刷新账户，避免账户请求参与启动阶段。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_refreshAccount());
    });
  }

  Future<void> _refreshAccount() async {
    try {
      final punched = await ref
          .read(accountSessionProvider.notifier)
          .refreshAndCheckIn();
      if (punched && mounted) {
        showToast(message: "打卡成功".tl);
      }
    } catch (_) {
      // 错误由账户卡片中的 AsyncValue 局部展示。
    }
  }

  @override
  Widget build(BuildContext context) {
    final recentHistory = ref.watch(recentHistoryProvider);
    final historySummary = ref.watch(historySummaryProvider);
    final downloadSummary = ref.watch(downloadSummaryProvider);
    final accountSession = ref.watch(accountSessionProvider);

    return SizedBox.expand(
      child: LayoutBuilder(
        builder: (context, constrains) {
          final width = constrains.maxWidth;
          bool shouldShowTwoPanel = width > 600;
          return SafeArea(
            top: true,
            bottom: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  buildHistory(context, recentHistory, historySummary, ref),
                  if (shouldShowTwoPanel)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            children: [
                              const SizedBox(height: 12),
                              buildAccount(width, accountSession, ref),
                              const SizedBox(height: 12),
                              buildDownload(
                                context,
                                width,
                                downloadSummary,
                                ref,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            children: [
                              const SizedBox(height: 12),
                              buildImageFavorite(
                                context,
                                width,
                                historySummary,
                                ref,
                              ),
                              const SizedBox(height: 12),
                              buildTools(width),
                            ],
                          ),
                        ),
                      ],
                    )
                  else ...[
                    const SizedBox(height: 12),
                    buildAccount(width, accountSession, ref),
                    const SizedBox(height: 12),
                    buildDownload(context, width, downloadSummary, ref),
                    const SizedBox(height: 12),
                    buildImageFavorite(context, width, historySummary, ref),
                    const SizedBox(height: 12),
                    buildTools(width),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget buildHistory(
    BuildContext context,
    AsyncValue<List<History>> recentHistory,
    AsyncValue<HistorySummary> historySummary,
    WidgetRef ref,
  ) {
    final history = recentHistory.asData?.value ?? const <History>[];
    final title = recentHistory.hasError
        ? Row(
            children: [
              Expanded(child: Text("历史记录加载失败".tl)),
              TextButton(
                onPressed: () {
                  ref.invalidate(recentHistoryProvider);
                  ref.invalidate(historySummaryProvider);
                },
                child: Text("重试".tl),
              ),
            ],
          )
        : historySummary.when(
            data: (summary) => Text("${"历史记录".tl}(${summary.historyCount})"),
            loading: () => Text("${"历史记录".tl}(…)"),
            error: (_, __) => Row(
              children: [
                Expanded(child: Text("历史记录加载失败".tl)),
                TextButton(
                  onPressed: () {
                    ref.invalidate(recentHistoryProvider);
                    ref.invalidate(historySummaryProvider);
                  },
                  child: Text("重试".tl),
                ),
              ],
            ),
          );
    return InkWell(
      mouseCursor: appClickableMouseCursor,
      onTap: () => context.to(() => const HistoryPage()),
      borderRadius: BorderRadius.circular(12),
      child: Card.outlined(
        margin: EdgeInsets.zero,
        color: Colors.transparent,
        child: Container(
          margin: EdgeInsets.zero,
          width: double.infinity,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.history),
                title: title,
                trailing: const Icon(Icons.chevron_right),
                mouseCursor: appClickableMouseCursor,
              ),
              SizedBox(
                height: 128,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: history.length,
                  itemBuilder: (context, index) {
                    return InkWell(
                      mouseCursor: appClickableMouseCursor,
                      onTap: () =>
                          toComicPageWithHistory(context, history[index]),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: 96,
                        height: 128,
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: Theme.of(
                            context,
                          ).colorScheme.secondaryContainer,
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: PicaImage(
                          url: history[index].cover,
                          sourceKey: history[index].type.comicSource?.key.name,
                          isThumbnail: true,
                          width: 96,
                          height: 128,
                          fit: BoxFit.cover,
                        ),
                      ),
                    );
                  },
                ),
              ).paddingHorizontal(8),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildAccount(
    double width,
    AsyncValue<Profile?> accountSession,
    WidgetRef ref,
  ) {
    var accounts = findAccounts();

    Widget buildItem(String name) {
      return Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Theme.of(App.globalContext!).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(name, style: const TextStyle(fontSize: 12)).paddingTop(4),
      );
    }

    final description = accountSession.when(
      data: (_) =>
          Text("已登录 @a 个账号".tlParams({"a": accounts.length.toString()})),
      loading: () => Text("账号信息加载中…".tl),
      error: (_, __) => Row(
        children: [
          Expanded(child: Text("账号信息加载失败".tl)),
          TextButton(
            onPressed: () => unawaited(
              ref.read(accountSessionProvider.notifier).refreshAndCheckIn(),
            ),
            child: Text("重试".tl),
          ),
        ],
      ),
    );

    return _MePageCard(
      icon: const Icon(Icons.switch_account),
      title: "账号管理".tl,
      description: description,
      onTap: () => showPopUpWidget(App.globalContext!, const AccountsPage()),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: accounts.map((e) => buildItem(e)).toList(),
      ).paddingHorizontal(12).paddingBottom(12),
    );
  }

  Widget buildDownload(
    BuildContext context,
    double width,
    AsyncValue<DownloadSummary> summary,
    WidgetRef ref,
  ) {
    return _MePageCard(
      icon: const Icon(Icons.download_for_offline),
      title: "已下载".tl,
      description: summary.when(
        data: (value) => Text(
          value.pending == 0
              ? "共 @a 部漫画".tlParams({"a": "${value.total}"})
              : "共 @a 部漫画，@b 项未完成".tlParams({
                  "a": "${value.total}",
                  "b": "${value.pending}",
                }),
        ),
        loading: () => Text("下载数据加载中…".tl),
        error: (_, __) => _RetryDescription(
          text: "下载数据加载失败".tl,
          onRetry: () => ref.invalidate(downloadSummaryProvider),
        ),
      ),
      onTap: () => context.to(() => const DownloadPage()),
    );
  }

  Widget buildImageFavorite(
    BuildContext context,
    double width,
    AsyncValue<HistorySummary> summary,
    WidgetRef ref,
  ) {
    return _MePageCard(
      icon: const Icon(Icons.image),
      title: "图片收藏".tl,
      description: summary.when(
        data: (value) =>
            Text("@a 条图片收藏".tlParams({"a": "${value.imageCount}"})),
        loading: () => Text("图片收藏加载中…".tl),
        error: (_, __) => _RetryDescription(
          text: "图片收藏加载失败".tl,
          onRetry: () => ref.invalidate(historySummaryProvider),
        ),
      ),
      onTap: () => context.to(() => const ImageFavoritesPage()),
    );
  }

  Widget buildTools(double width) {
    Widget buildItem(String name) {
      return Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Theme.of(App.globalContext!).colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(name, style: const TextStyle(fontSize: 12)).paddingTop(4),
      );
    }

    return _MePageCard(
      icon: const Icon(Icons.build_circle),
      title: "工具".tl,
      description: Text("使用工具发现更多漫画".tl),
      onTap: openTool,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          buildItem("EH订阅".tl),
          buildItem("图片搜索".tl),
          buildItem("打开链接".tl),
        ],
      ).paddingHorizontal(12).paddingBottom(12),
    );
  }

  List<String> findAccounts() {
    var result = <String>[];
    for (var source in ComicSource.sources) {
      if (source.isLogin) {
        result.add(source.name.tl);
      }
    }
    return result;
  }
}

class _RetryDescription extends StatelessWidget {
  const _RetryDescription({required this.text, required this.onRetry});

  final String text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(text)),
        TextButton(onPressed: onRetry, child: Text("重试".tl)),
      ],
    );
  }
}

class _MePageCard extends StatelessWidget {
  const _MePageCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
    this.child,
  });

  final Widget icon;
  final String title;
  final Widget description;
  final VoidCallback onTap;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      mouseCursor: appClickableMouseCursor,
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Card.outlined(
        margin: EdgeInsets.zero,
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: icon,
              title: Text(title),
              trailing: const Icon(Icons.chevron_right),
              mouseCursor: appClickableMouseCursor,
            ),
            DefaultTextStyle(
              style:
                  Theme.of(context).textTheme.bodyMedium ?? const TextStyle(),
              child: description,
            ).paddingHorizontal(16).paddingBottom(16).paddingTop(8),
            if (child != null) child!,
          ],
        ),
      ),
    );
  }
}
