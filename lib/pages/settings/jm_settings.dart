part of pica_settings;

class SetJmComicsOrderController extends StateController{
  int settingsOrder;
  SetJmComicsOrderController(this.settingsOrder);
  late String value = appdata.settings[settingsOrder];

  void set(String v){
    value = v;
    appdata.settings[settingsOrder] = v;
    appdata.writeData();
    App.globalBack();
  }
}


class JmSettings extends StatefulWidget {
  const JmSettings(this.popUp, {Key? key}) : super(key: key);
  final bool popUp;

  @override
  State<JmSettings> createState() => _JmSettingsState();

  static const builtInDomains = <String>[
    "www.jmapiproxyxxx.vip",
    "www.jmapiproxyxxx.me",
    "www.cdnblackmyth.xyz",
    "www.cdnxxx-proxy.co"
  ];

  static void updateApiDomains([bool showLoading = false]) async {
    var controller = showLoading ? showLoadingDialog(App.globalContext!) : null;
    List<String>? domains = await JmNetwork().getDomains();
    controller?.close();
    var title = domains != null ? "更新成功".tl : "更新失败".tl;
    var msg = domains != null ? "" : "${"使用内置域名:".tl}\n";
    domains = domains ?? builtInDomains;
    for (String domain in domains) {
        msg += "${"分流".tl}${domains.indexOf(domain) + 1}: $domain\n";
    }
    msg = msg.trim();
    showConfirmDialog(App.globalContext!, title, msg, () {
      appdata.appSettings.jmApiDomains = domains!;
      JmNetwork().loginFromAppdata();
    });
  }
}

class _JmSettingsState extends State<JmSettings> {
  bool autoSelectStream = appdata.settings[15] == "1";

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          title: Text("禁漫天堂".tl),
        ),
        ListTile(
          leading: const Icon(Icons.track_changes),
          title: Text("自动选择域名".tl),
          subtitle: Text("登录时自动选择API域名".tl),
          trailing: Switch(
            value: autoSelectStream,
            onChanged: (b){
              b ? appdata.settings[15] = "1" : appdata.settings[15] = "0";
              setState(() {
                autoSelectStream = b;
              });
              appdata.updateSettings();
              if (autoSelectStream) JmNetwork().loginFromAppdata();
            },
          ),
        ),
        ListTile(
          leading: const Icon(Icons.dns),
          title: Text("API域名".tl),
          trailing: IgnorePointer(
            ignoring: autoSelectStream,
            child: Opacity(
              opacity: !autoSelectStream ? 1.0 : 0.5,
              child: Select(
                initialValue: int.parse(appdata.settings[17]),
                values: [
                  "分流1".tl,"分流2".tl,"分流3".tl,"分流4".tl,
                ],
                onChange: (i){
                  appdata.settings[17] = i.toString();
                  appdata.updateSettings();
                  JmNetwork().loginFromAppdata();
                },
              ),
            ),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.dns_outlined),
          title: Text("图片分流".tl),
          trailing: Select(
            initialValue: int.parse(appdata.settings[37]),
            values: [
              "分流1".tl,"分流2".tl,"分流3".tl,"分流4".tl, "分流5".tl, "分流6".tl
            ],
            onChange: (i){
              appdata.settings[37] = i.toString();
              appdata.updateSettings();
            },
          ),
        ),
        ListTile(
          leading: const Icon(Icons.favorite_border),
          title: Text("收藏夹漫画排序模式".tl),
          trailing: Select(
            initialValue: int.parse(appdata.settings[42]),
            width: App.locale.languageCode == "en" ? 130 : 120,
            values: [
              "最新收藏".tl, "最新更新".tl
            ],
            onChange: (i){
              appdata.settings[42] = i.toString();
              appdata.updateSettings();
            },
          ),
        ),
        ListTile(
          leading: const Icon(Icons.update_outlined),
          title: Text("更新分流域名列表".tl),
          onTap: () => JmSettings.updateApiDomains(true),
          trailing: const Icon(Icons.arrow_right),
        ),
      ],
    );
  }

  // void changeDomain(BuildContext context){
  //   var controller = TextEditingController();
  //
  //   void onFinished() {
  //     var text = controller.text;
  //     if(!text.contains("https://")){
  //       text = "https://$text";
  //     }
  //     App.globalBack();
  //     if(!text.isURL){
  //       showToast(message: "Invalid URL");
  //     }else {
  //       appdata.settings[56] = text;
  //       appdata.updateSettings();
  //       setState(() {});
  //       JmNetwork().loginFromAppdata();
  //     }
  //   }
  //
  //   showDialog(context: context, builder: (context){
  //     return SimpleDialog(
  //       title: const Text("Change Domain"),
  //       children: [
  //         Container(
  //           padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
  //           width: 400,
  //           child: TextField(
  //             decoration: const InputDecoration(
  //                 border: OutlineInputBorder(),
  //                 label: Text("Domain")
  //             ),
  //             controller: controller,
  //             onEditingComplete: onFinished,
  //           ),
  //         ),
  //         Row(
  //           mainAxisAlignment: MainAxisAlignment.end,
  //           children: [
  //             TextButton(onPressed: onFinished, child: Text("完成".tl)),
  //             const SizedBox(width: 16,),
  //           ],
  //         )
  //       ],
  //     );
  //   });
  // }
}