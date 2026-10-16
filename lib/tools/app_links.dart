import '../pages/comic_page.dart';
import '../foundation/def.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/foundation/log.dart';
import 'package:pica_comic/tools/extensions.dart';
import '../foundation/app.dart';
import '../pages/ehentai/eh_gallery_page.dart';
import '../pages/hitomi/hitomi_comic_page.dart';
import '../pages/nhentai/comic_page.dart';

bool canHandle(String text) {
  if (!text.isURL) {
    return false;
  }
  var uri = Uri.parse(text);

  const acceptedHosts = [
    "e-hentai.org",
    "exhentai.org",
    "nhentai.net",
    "hitomi.la",
    "www.manhuagui.com",
    "manhuagui.com",
  ];

  return acceptedHosts.contains(uri.host);
}

bool handleAppLinks(Uri uri, {bool showMessageWhenError = true}) {
  Log.i("App Link Open Link $uri");
  var context = App.mainNavigatorKey!.currentContext!;
  switch (uri.host) {
    case "e-hentai.org":
    case "exhentai.org":
      if (uri.path.contains("/g/")) {
        context.to(
          () => EhGalleryPage.fromLink("https://${uri.host}${uri.path}"),
        );
      }
    case "nhentai.net":
      if (uri.path.contains("/g/")) {
        context.to(
          () => NhentaiComicPage(
            uri.pathSegments.firstWhere((element) => element.isNum),
          ),
        );
      }
    case "www.manhuagui.com":
    case "manhuagui.com":
      final match = RegExp(
        r'^/comic/(\d+)/?(?:\d+\.html)?$',
      ).firstMatch(uri.path);
      if (match == null) return false;
      context.to(
        () => ComicPage(comicType: ComicType.manhuagui, id: match[1]!),
      );
      break;
    case "hitomi.la":
      if (["doujinshi", "cg", "manga"].contains(uri.pathSegments[0])) {
        context.to(
          () => HitomiComicPage.fromLink("https://${uri.host}${uri.path}"),
        );
      } else {
        showToast(message: "Unknown Link");
        return false;
      }
    default:
      return false;
  }
  return true;
}
