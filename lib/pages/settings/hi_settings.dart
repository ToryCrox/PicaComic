part of pica_settings;

class HitomiSettings extends ConsumerStatefulWidget {
  const HitomiSettings(this.popUp, {super.key});

  final bool popUp;

  @override
  ConsumerState<HitomiSettings> createState() => _HitomiSettingsState();
}

class _HitomiSettingsState extends ConsumerState<HitomiSettings> {
  @override
  Widget build(BuildContext context) {
    ref.watch(appSettingsProvider);
    return Column(
      children: [
        ListTile(title: Text("Hitomi".tl)),
        ListTile(
          leading: const Icon(Icons.dns),
          title: Text("CDN ${"域名".tl}"),
          subtitle: Text(appdata.getSetting(AppSettingKeys.hitomiCdnDomain)),
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
      text: appdata.getSetting(AppSettingKeys.hitomiCdnDomain),
    );

    void onFinished() {
      var text = controller.text;
      App.globalBack();
      if (!text.isURL) {
        showToast(message: "Invalid Domain");
      } else {
        _saveSetting(ref, AppSettingKeys.hitomiCdnDomain, text, persist: false);
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
