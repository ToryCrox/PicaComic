import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/foundation/app_settings_provider.dart';
import 'package:pica_comic/foundation/log.dart';
import 'package:pica_comic/tools/translations.dart';

import 'download_comic_card.dart';

/// 下载页「卡片大小」调节对话框。
///
/// 只调整卡片宽度缩放系数 [AppSettingKeys.downloadCardScale]：网格代理据此
/// 缩放卡片宽度区间，列数与卡片高度会随之自动变化。拖动过程中只更新内存
/// 以便实时预览，松手后才落盘，避免频繁写文件。
class DownloadCardSizeDialog extends ConsumerWidget {
  const DownloadCardSizeDialog({super.key});

  /// 缩放系数下限。
  static const double minScale = 0.75;

  /// 缩放系数上限。
  static const double maxScale = 1.5;

  /// 默认缩放系数，与 [downloadCardScale] 默认值保持一致。
  static const double defaultScale = 1;

  /// 滑块步进。
  static const double step = 0.05;

  /// 打开对话框。
  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (context) => const DownloadCardSizeDialog(),
    );
  }

  /// 预览当前缩放后的卡片宽度区间（1.0× 时为 140–240）。
  static String previewWidthText(double scale) {
    final min =
        SliverGridDelegateWithDownloadComics.defaultMinChildWidth * scale;
    final max =
        SliverGridDelegateWithDownloadComics.defaultMaxChildWidth * scale;
    return '${min.round()}–${max.round()}';
  }

  /// 更新缩放系数；[persist] 为 false 时只改内存，供滑块实时预览。
  Future<void> _saveScale(
    WidgetRef ref,
    double scale, {
    bool persist = false,
  }) async {
    final controller = ref.read(appSettingsProvider.notifier);
    try {
      if (persist) {
        await controller.setValue(
          AppSettingKeys.downloadCardScale,
          scale.toStringAsFixed(2),
        );
      } else {
        await controller.setValue(
          AppSettingKeys.downloadCardScale,
          scale.toStringAsFixed(2),
          persist: false,
        );
      }
    } catch (error, stack) {
      Log.e('保存下载卡片大小失败', error: error, stackTrace: stack);
      showToast(message: '保存设置失败'.tl);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final scale = ref.watch(
      appearanceSettingsProvider.select(
        (settings) => settings.downloadCardScale,
      ),
    );

    return AlertDialog(
      title: Text('卡片大小'.tl),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '拖动滑块调整下载页卡片的宽度，设置立即生效。'.tl,
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.crop_square, size: 16, color: colorScheme.secondary),
                Expanded(
                  child: Slider(
                    min: minScale,
                    max: maxScale,
                    divisions: ((maxScale - minScale) / step).round(),
                    value: scale,
                    overlayColor: WidgetStateColor.resolveWith(
                      (states) => Colors.transparent,
                    ),
                    label: '${scale.toStringAsFixed(2)}×',
                    onChanged: (value) => _saveScale(ref, value),
                    onChangeEnd: (value) =>
                        _saveScale(ref, value, persist: true),
                  ),
                ),
                Icon(
                  Icons.crop_portrait,
                  size: 22,
                  color: colorScheme.secondary,
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${'卡片宽度'.tl} ${previewWidthText(scale)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  '${scale.toStringAsFixed(2)}×',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.primary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: scale == defaultScale
              ? null
              : () => _saveScale(ref, defaultScale, persist: true),
          child: Text('恢复默认'.tl),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: Text('完成'.tl),
        ),
      ],
    );
  }
}
