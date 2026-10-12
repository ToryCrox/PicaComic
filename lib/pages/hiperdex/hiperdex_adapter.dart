import 'package:pica_comic/comic_source/comic_source.dart';
import 'package:pica_comic/foundation/def.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/network/download/download_manager.dart';
import 'package:pica_comic/network/download/download_model.dart';
import 'package:pica_comic/network/hiperdex_network/hiperdex_downloaded_item.dart';
import 'package:pica_comic/pages/comic_page/default_comic_page_adapter.dart';

/// HiperDEX 详情适配器，连接独立下载模型和下载任务。
class HiperdexAdapter extends DefaultComicPageAdapter {
  HiperdexAdapter() : super(ComicType.hiperdex);

  @override
  ComicInfoData? dataFromDownloadedItem(DownloadedItem item) =>
      item is HiperdexDownloadedItem ? item.comic : null;

  @override
  DownloadedItem? mergeDownloadedItem(
    DownloadedItem item,
    ComicInfoData data,
  ) => item is HiperdexDownloadedItem ? item.withComicInfo(data) : null;

  @override
  void addDownload(
    ComicInfoData data,
    List<int> selectedEps,
    DownloadManager manager,
  ) => manager.addHiperdexDownload(data, selectedEps);
}
