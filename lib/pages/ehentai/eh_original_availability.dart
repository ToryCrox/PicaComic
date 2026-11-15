import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pica_comic/foundation/theme/app_mouse_cursor.dart';

import '../../network/eh_network/eh_models.dart';
import '../../tools/translations.dart';
import 'eh_original_availability_provider.dart';

/// EH 单页原图可用性提示。
///
/// 进入页面时不会自动检测（Provider 初始态为 [EhOriginalCheckStatus.idle]），
/// 需用户点击后才会请求原图链接。
class EhOriginalAvailabilityBadge extends ConsumerWidget {
  const EhOriginalAvailabilityBadge({required this.gallery, super.key});

  final Gallery gallery;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = ehOriginalAvailabilityProvider(gallery.link);
    final status = ref.watch(provider);

    switch (status) {
      case EhOriginalCheckStatus.idle:
        return _actionChip(
          icon: Icons.high_quality,
          label: "检测第1页原图".tl,
          onPressed: () => _startCheck(ref),
        );
      case EhOriginalCheckStatus.checking:
        return _buildChip(
          icon: const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          label: "检测第1页原图中".tl,
        );
      case EhOriginalCheckStatus.failed:
        return _actionChip(
          icon: Icons.refresh,
          label: "第1页原图检测失败".tl,
          onPressed: () => _startCheck(ref),
        );
      case EhOriginalCheckStatus.available:
        return _buildChip(
          icon: const Icon(Icons.high_quality, size: 18),
          label: "第1页原图可用".tl,
        );
      case EhOriginalCheckStatus.unavailable:
        return _buildChip(
          icon: const Icon(Icons.image_not_supported, size: 18),
          label: "第1页未检测到原图".tl,
        );
    }
  }

  void _startCheck(WidgetRef ref) {
    ref
        .read(ehOriginalAvailabilityProvider(gallery.link).notifier)
        .check(gallery);
  }

  Widget _actionChip({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return ActionChip(
      mouseCursor: appClickableMouseCursor,
      avatar: Icon(icon, size: 18),
      label: Text(label),
      onPressed: onPressed,
    );
  }

  Widget _buildChip({required Widget icon, required String label}) {
    return Chip(
      avatar: icon,
      label: Text(label),
      mouseCursor: SystemMouseCursors.basic,
    );
  }
}
