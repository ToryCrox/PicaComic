import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pica_comic/network/picacg_network/methods.dart';
import 'package:pica_comic/tools/translations.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/foundation/def.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'collections_page.g.dart';

/// 推荐页面数据。
class CollectionPageState {
  const CollectionPageState({required this.c1, required this.c2});

  final List<ComicItemBrief> c1;
  final List<ComicItemBrief> c2;
}

/// 推荐页面加载异常。
class _CollectionPageException implements Exception {
  const _CollectionPageException(this.message);

  final String message;
}

/// 推荐页面逻辑。
@Riverpod(keepAlive: false)
class CollectionPageLogic extends _$CollectionPageLogic {
  @override
  Future<CollectionPageState> build() async {
    final collections = await network.getCollection();
    if (!collections.success) {
      throw _CollectionPageException(collections.errorMessageWithoutNull);
    }
    final data = collections.data;
    return CollectionPageState(
      c1: List.unmodifiable(data.isNotEmpty ? data[0] : const []),
      c2: List.unmodifiable(data.length > 1 ? data[1] : const []),
    );
  }

  /// 重新加载推荐数据。
  void refresh() {
    ref.invalidateSelf();
  }
}

class CollectionsPage extends ConsumerWidget {
  const CollectionsPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pageState = ref.watch(collectionPageLogicProvider);
    final logic = ref.read(collectionPageLogicProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: Text("推荐".tl)),
      body: pageState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => NetworkError(
          message: error is _CollectionPageException
              ? error.message
              : error.toString(),
          retry: logic.refresh,
          withAppbar: false,
        ),
        data: (data) => CustomScrollView(
          slivers: [
            SliverGridComics(
              comics: data.c1 + data.c2,
              comicType: ComicType.picacg,
            ),
            SliverPadding(
              padding: EdgeInsets.only(
                top: MediaQuery.of(App.globalContext!).padding.bottom,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
