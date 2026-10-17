import 'package:pica_comic/network/comic_source_services.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pica_comic/comic_source/comic_source.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/foundation/ui_mode.dart';
import 'package:pica_comic/foundation/app_settings_provider.dart';
import 'package:pica_comic/network/net_fav_to_local.dart';
import 'package:pica_comic/tools/translations.dart';

import 'network_favorites_providers.dart';

/// 网络收藏选择弹窗，展开和未提交选择为局部草稿。
class _ChooseNetworkFolderWidget extends ConsumerStatefulWidget {
  const _ChooseNetworkFolderWidget();
  @override
  ConsumerState<_ChooseNetworkFolderWidget> createState() =>
      _ChooseNetworkFolderWidgetState();
}

class _ChooseNetworkFolderWidgetState
    extends ConsumerState<_ChooseNetworkFolderWidget> {
  final _expanded = <String>{};
  ({String sourceKey, String? folderId, String title})? _selected;
  bool _sync = false;

  @override
  Widget build(BuildContext context) {
    ref.watch(comicSourceRegistryProvider);
    final folders = ref
        .watch(appSettingProvider(AppSettingKeys.networkFavoritePages))
        .split(',')
        .map(getFavoriteDataOrNull)
        .whereType<FavoriteData>()
        .toList();
    return Scaffold(
      appBar: Appbar(
        title: Text('选择收藏夹'.tl),
        actions: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: ExpansionPanelList(
                materialGapSize: 0,
                expandedHeaderPadding: EdgeInsets.zero,
                expansionCallback: (index, expanded) => setState(() {
                  final key = folders[index].key;
                  if (!_expanded.remove(key)) _expanded.add(key);
                }),
                children: [
                  for (final source in folders)
                    ExpansionPanel(
                      canTapOnHeader: true,
                      isExpanded: _expanded.contains(source.key),
                      headerBuilder: (_, __) =>
                          ListTile(title: Text(source.title)),
                      body: _folderBody(source),
                    ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          SizedBox(
            height: 56,
            child: Row(
              children: [
                const SizedBox(width: 8),
                Checkbox(
                  value: _sync,
                  onChanged: (value) => setState(() => _sync = value ?? false),
                ),
                Text('支持下拉更新'.tl),
                const Spacer(),
                FilledButton(
                  onPressed: _selected == null
                      ? null
                      : () {
                          final selected = _selected!;
                          final target = App.globalContext!;
                          Navigator.pop(context);
                          unawaited(
                            startConvert(
                              target,
                              sourceKey: selected.sourceKey,
                              folderId: selected.folderId,
                              folderName: selected.title,
                              agreeSync: _sync,
                            ),
                          );
                        },
                  child: Text('继续'.tl),
                ),
                const SizedBox(width: 24),
              ],
            ),
          ),
          if (UiMode.m1(context))
            SizedBox(height: MediaQuery.paddingOf(context).bottom),
        ],
      ),
    );
  }

  /// 未展开的来源不触发网络加载。
  Widget _folderBody(FavoriteData source) {
    if (!source.multiFolder) return _tile(source.key, null, source.title);
    if (_expanded.contains(source.key)) return _networkFolders(source);
    return const SizedBox.shrink();
  }

  /// 查询只在展开后创建 Provider，失败支持重试。
  Widget _networkFolders(FavoriteData source) {
    final query = (sourceKey: source.key, comicId: null as String?);
    return ref
        .watch(networkFavoriteFoldersProvider(query))
        .when(
          loading: () => const SizedBox(
            height: 56,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => TextButton(
            onPressed: () =>
                ref.invalidate(networkFavoriteFoldersProvider(query)),
            child: Text('加载失败，点击重试: $error'),
          ),
          data: (data) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final entry in data.folders.entries)
                _tile(source.key, entry.key, entry.value),
            ],
          ),
        );
  }

  /// 收藏夹选择保持为未提交草稿。
  Widget _tile(String sourceKey, String? folderId, String title) =>
      RadioListTile<String>(
        title: Text(title),
        value: '$sourceKey:$folderId',
        groupValue: _selected == null
            ? null
            : '${_selected!.sourceKey}:${_selected!.folderId}',
        onChanged: (_) => setState(
          () => _selected = (
            sourceKey: sourceKey,
            folderId: folderId,
            title: title,
          ),
        ),
      );
}

/// 从当前应用界面打开网络收藏导入入口。
void networkToLocal() =>
    showPopUpWidget(App.globalContext!, const _ChooseNetworkFolderWidget());
