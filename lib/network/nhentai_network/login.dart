import 'dart:io' as io;

import 'package:pica_comic/base.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/pages/webview.dart';
import 'package:pica_comic/network/nhentai_network/nhentai_main_network.dart';
import 'package:pica_comic/tools/translations.dart';

void nhLogin(NhentaiNetwork network, void Function() onFinished) async {
  if (App.isDesktop && (await DesktopWebview.isAvailable())) {
    var webview = DesktopWebview(
      initialUrl: "${network.baseUrl}/login/?next=/",
      onTitleChange: (title, controller) async {
        print(title);
        if (title == "nhentai.net") return;
        if (!title.contains("Login") &&
            !title.contains("Register") &&
            title.contains("nhentai")) {
          var ua = controller.userAgent;
          if (ua != null) {
            appdata.implicitData[3] = ua;
            appdata.writeImplicitData();
          }
          var cookies = await controller.getCookies("${network.baseUrl}/");
          List<io.Cookie> cookiesList = [];
          cookies.forEach((key, value) {
            var cookie = io.Cookie(key, value);
            if (key == "sessionid" || key == "XSRF-TOKEN") {
              network.logged = true;
            }
            cookie.domain = ".nhentai.net";
            if (key != "cf_clearance") {
              cookiesList.add(cookie);
            }
          });
          await network.cookieJar!.saveFromResponse(
            Uri.parse(network.baseUrl),
            cookiesList,
          );
          onFinished();
          controller.close();
        }
      },
    );
    webview.open();
  } else if (App.isMobile) {
    App.globalTo(
      () => AppWebview(
        initialUrl: "${network.baseUrl}/login/?next=/",
        singlePage: true,
        onTitleChange: (title, controller) async {
          if (!title.contains("Login") &&
              !title.contains("Register") &&
              title.contains("nhentai")) {
            var ua = await controller.getUA();
            if (ua != null) {
              appdata.implicitData[3] = ua;
              appdata.writeImplicitData();
            }
            var cookies =
                await controller.getCookies("${network.baseUrl}/") ?? {};
            List<io.Cookie> cookiesList = [];
            cookies.forEach((key, value) {
              var cookie = io.Cookie(key, value);
              if (key == "sessionid" || key == "XSRF-TOKEN") {
                network.logged = true;
              }
              cookie.domain = ".nhentai.net";
              if (key != "cf_clearance") {
                cookiesList.add(cookie);
              }
            });
            await network.cookieJar!.saveFromResponse(
              Uri.parse(network.baseUrl),
              cookiesList,
            );
            onFinished();
            App.globalBack();
          }
        },
      ),
    );
  } else {
    showToast(message: "当前设备不支持".tl);
  }
}
