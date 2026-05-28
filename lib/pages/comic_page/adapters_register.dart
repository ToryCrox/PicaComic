import '../../pages/ehentai/eh_adapter.dart';
import '../../pages/hitomi/hitomi_adapter.dart';
import '../../pages/htmanga/ht_adapter.dart';
import '../../pages/jm/jm_adapter.dart';
import '../../pages/kemono/kemono_adapter.dart';
import '../../pages/nhentai/nhentai_adapter.dart';
import '../../pages/picacg/picacg_adapter.dart';
import 'comic_page_adapter.dart';

/// 注册所有镜像适配器。
///
/// 应在 [main] 函数中尽早调用。
void registerAllComicPageAdapters() {
  ComicPageAdapterRegistry.register(PicacgAdapter());
  ComicPageAdapterRegistry.register(EhAdapter());
  ComicPageAdapterRegistry.register(JmAdapter());
  ComicPageAdapterRegistry.register(HtAdapter());
  ComicPageAdapterRegistry.register(HitomiAdapter());
  ComicPageAdapterRegistry.register(NhentaiAdapter());
  ComicPageAdapterRegistry.register(KemonoAdapter());
}
