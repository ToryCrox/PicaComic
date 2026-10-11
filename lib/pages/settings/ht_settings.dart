part of pica_settings;

class HtSettings extends ConsumerStatefulWidget {
  const HtSettings(this.popUp, {super.key});

  final bool popUp;

  @override
  ConsumerState<HtSettings> createState() => _HtSettingsState();
}

class _HtSettingsState extends ConsumerState<HtSettings> {
  @override
  Widget build(BuildContext context) {
    ref.watch(appSettingsProvider);
    return Column(
      children: [
        ListTile(title: Text("绅士漫画".tl)),
        ListTile(
          leading: const Icon(Icons.dns),
          title: Text("域名".tl),
          subtitle: Text(
            appdata
                .getSetting(AppSettingKeys.htmangaDomain)
                .replaceFirst("https://", ""),
          ),
          trailing: IconButton(
            onPressed: () => changeDomain(context),
            icon: const Icon(Icons.edit),
          ),
        ),
      ],
    );
  }

  void changeDomain(BuildContext context) {
    final FocusNode focusNode = FocusNode();
    var controller = TextEditingController(
      text: appdata
          .getSetting(AppSettingKeys.htmangaDomain)
          .replaceFirst("https://", ""),
    );

    void onFinished() {
      var text = controller.text;
      if (!text.contains("https://")) {
        text = "https://$text";
      }
      App.globalBack();
      if (!text.isURL) {
        showToast(message: "Invalid URL");
      } else {
        _saveSetting(ref, AppSettingKeys.htmangaDomain, text, persist: false);
        _persistSettings(ref);
        setState(() {});
      }
    }

    showDialog(
      context: context,
      builder: (context) {
        focusNode.requestFocus();
        return SimpleDialog(
          title: Text("更改域名".tl),
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              width: 400,
              child: TextField(
                focusNode: focusNode,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  label: Text("域名".tl),
                ),
                controller: controller,
                onEditingComplete: onFinished,
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: onFinished, child: Text("完成".tl)),
                const SizedBox(width: 16),
              ],
            ),
          ],
        );
      },
    );
  }
}
