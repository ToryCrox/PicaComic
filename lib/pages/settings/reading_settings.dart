part of pica_settings;

/// 设置页与欢迎页共用的阅读器偏好面板。
class ReadingSettings extends ConsumerWidget {
  const ReadingSettings(this.popUp, {super.key});

  final bool popUp;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final reading = ref.watch(readerSettingsProvider);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SelectSetting(
          leading: const Icon(Icons.chrome_reader_mode),
          title: "阅读模式".tl,
          initialValue: reading.readingMode - 1,
          values: [
            "从左至右".tl,
            "从右至左".tl,
            "从上至下".tl,
            "从上至下(连续)".tl,
            "双页".tl,
            "双页(反向)".tl,
          ],
          onChanged: (i) {
            _saveSetting(ref, AppSettingKeys.readingMode, (i + 1).toString());
          },
        ),
        SwitchSetting(
          title: "点按翻页".tl,
          settingKey: AppSettingKeys.readerTapToTurnPage,
          icon: const Icon(Icons.touch_app_outlined),
        ),
        SwitchSetting(
          title: "反转点按翻页".tl,
          settingKey: AppSettingKeys.reverseTapTurnPage,
          icon: const Icon(Icons.swap_horiz),
        ),
        if (App.isAndroid)
          SwitchSetting(
            title: "使用音量键翻页".tl,
            settingKey: AppSettingKeys.readerVolumeKeys,
            icon: const Icon(Icons.volume_mute),
          ),
        ListTile(
          leading: const Icon(Icons.timer_sharp),
          subtitle: SizedBox(
            height: 25,
            child: Stack(
              children: [
                Positioned(
                  top: 0,
                  bottom: 0,
                  left: -20,
                  right: 0,
                  child: Slider(
                    max: 20,
                    min: 0,
                    divisions: 20,
                    value: reading.autoPageSeconds.toDouble(),
                    overlayColor: WidgetStateColor.resolveWith(
                      (states) => Colors.transparent,
                    ),
                    onChanged: (v) {
                      if (v == 0) return;
                      _saveSetting(
                        ref,
                        AppSettingKeys.autoPageInterval,
                        v.toInt().toString(),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          trailing: SizedBox(
            width: 40,
            child: Text(
              "${settings.value(AppSettingKeys.autoPageInterval)}s",
              style: const TextStyle(fontSize: 14),
            ),
          ),
          title: Text("自动翻页时间间隔".tl),
        ),
        SwitchSetting(
          title: "宽屏时显示控制按钮".tl,
          settingKey: AppSettingKeys.showReaderButtons,
          icon: const Icon(Icons.control_camera),
        ),
        SwitchSetting(
          title: "深色模式下降低图片亮度".tl,
          settingKey: AppSettingKeys.dimImagesInDarkMode,
          icon: const Icon(Icons.brightness_4),
        ),
        if (App.isAndroid)
          SelectSetting(
            leading: const Icon(Icons.screen_lock_rotation),
            title: "固定屏幕方向".tl,
            initialValue: reading.screenOrientation,
            values: ["禁用".tl, "横屏".tl, "竖屏".tl],
            onChanged: (i) {
              _saveSetting(ref, AppSettingKeys.readerOrientation, i.toString());
            },
          ),
        SelectSetting(
          leading: const Icon(Icons.image_outlined),
          title: "图片预加载".tl,
          initialValue: [
            "0",
            "1",
            "2",
            "3",
            "4",
            "5",
            "10",
            "15",
          ].indexOf(settings.value(AppSettingKeys.preloadPages)),
          values: const ["0", "1", "2", "3", "4", "5", "10", "15"],
          onChanged: (i) {
            _saveSetting(
              ref,
              AppSettingKeys.preloadPages,
              ["0", "1", "2", "3", "4", "5", "10", "15"][i],
            );
          },
        ),
        SwitchSetting(
          title: "双击缩放".tl,
          settingKey: AppSettingKeys.doubleTapZoom,
          icon: const Icon(Icons.zoom_out_map),
        ),
        SwitchSetting(
          title: "长按缩放".tl,
          settingKey: AppSettingKeys.longPressZoom,
          icon: const Icon(Icons.zoom_in),
        ),
        SwitchSetting(
          title: "显示页面信息".tl,
          settingKey: AppSettingKeys.showReaderPageInfo,
          icon: const Icon(Icons.insert_drive_file_outlined),
        ),
        SwitchSetting(
          title: "使用深色背景".tl,
          settingKey: AppSettingKeys.readerDarkBackground,
          icon: const Icon(Icons.dark_mode),
        ),
        Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).padding.bottom,
          ),
        ),
      ],
    );
  }
}
