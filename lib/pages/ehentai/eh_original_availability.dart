import 'package:flutter/material.dart';

import '../../foundation/image_manager.dart';
import '../../network/eh_network/eh_models.dart';
import '../../network/res.dart';
import '../../tools/translations.dart';

/// EH 单页原图可用性提示。
class EhOriginalAvailabilityBadge extends StatefulWidget {
  const EhOriginalAvailabilityBadge({required this.gallery, super.key});

  final Gallery gallery;

  @override
  State<EhOriginalAvailabilityBadge> createState() =>
      _EhOriginalAvailabilityBadgeState();
}

class _EhOriginalAvailabilityBadgeState
    extends State<EhOriginalAvailabilityBadge> {
  late Future<Res<bool>> _future;

  @override
  void initState() {
    super.initState();
    _future = _check();
  }

  @override
  void didUpdateWidget(covariant EhOriginalAvailabilityBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gallery.link != widget.gallery.link) {
      _future = _check();
    }
  }

  Future<Res<bool>> _check() {
    return ImageManager().checkEhOriginalAvailability(widget.gallery);
  }

  void _retry() {
    setState(() => _future = _check());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Res<bool>>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return _buildChip(
            icon: const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            label: "检测第1页原图中".tl,
          );
        }

        final result = snapshot.data!;
        if (result.error) {
          return ActionChip(
            avatar: const Icon(Icons.refresh, size: 18),
            label: Text("第1页原图检测失败".tl),
            onPressed: _retry,
          );
        }

        final available = result.dataOrNull == true;
        return _buildChip(
          icon: Icon(
            available ? Icons.high_quality : Icons.image_not_supported,
            size: 18,
          ),
          label: available ? "第1页原图可用".tl : "第1页未检测到原图".tl,
        );
      },
    );
  }

  Widget _buildChip({required Widget icon, required String label}) {
    return Chip(avatar: icon, label: Text(label));
  }
}
