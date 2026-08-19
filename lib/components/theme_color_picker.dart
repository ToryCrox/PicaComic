import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// PixEz 风格的 HSV 颜色选择器，不包含透明度选择。
class ThemeColorPicker extends StatefulWidget {
  const ThemeColorPicker({
    required this.color,
    required this.onColorChanged,
    super.key,
  });

  final Color color;
  final ValueChanged<Color> onColorChanged;

  @override
  State<ThemeColorPicker> createState() => _ThemeColorPickerState();
}

class _ThemeColorPickerState extends State<ThemeColorPicker> {
  late HSVColor _hsvColor;
  late final TextEditingController _hexController;

  @override
  void initState() {
    super.initState();
    _hsvColor = HSVColor.fromColor(widget.color);
    _hexController = TextEditingController(
      text: _hexColor(_hsvColor.toColor()),
    );
  }

  @override
  void didUpdateWidget(covariant ThemeColorPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.color != widget.color) {
      _hsvColor = HSVColor.fromColor(widget.color);
      _setHexText(_hsvColor.toColor());
    }
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  void _setHexText(Color color) {
    final text = _hexColor(color);
    if (_hexController.text == text) return;
    _hexController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _setColor(Color color, {bool updateHex = true}) {
    final normalized = Color(0xff000000 | (color.toARGB32() & 0x00ffffff));
    setState(() {
      _hsvColor = HSVColor.fromColor(normalized);
      if (updateHex) _setHexText(normalized);
    });
    widget.onColorChanged(normalized);
  }

  void _updateSaturationValue(Offset offset, Size size) {
    final saturation = (offset.dx / size.width).clamp(0.0, 1.0);
    final value = (1 - offset.dy / size.height).clamp(0.0, 1.0);
    _setColor(_hsvColor.withSaturation(saturation).withValue(value).toColor());
  }

  void _updateHue(Offset offset, Size size) {
    final hue = (offset.dx / size.width * 360).clamp(0.0, 360.0);
    _setColor(_hsvColor.withHue(hue).toColor());
  }

  void _onHexChanged(String value) {
    final parsed = _parseHexColor(value);
    if (parsed != null) _setColor(parsed, updateHex: false);
  }

  @override
  Widget build(BuildContext context) {
    final color = _hsvColor.toColor();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '当前颜色',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Container(
              width: 56,
              height: 36,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 220,
          child: Builder(
            builder: (context) {
              return GestureDetector(
                key: const ValueKey('theme-color-sv-picker'),
                onTapDown: (details) {
                  final size = context.size;
                  if (size != null) {
                    _updateSaturationValue(details.localPosition, size);
                  }
                },
                onPanUpdate: (details) {
                  final size = context.size;
                  if (size != null) {
                    _updateSaturationValue(details.localPosition, size);
                  }
                },
                child: CustomPaint(
                  painter: _SaturationValuePainter(_hsvColor),
                  foregroundPainter: _SaturationValueIndicator(_hsvColor),
                  child: const SizedBox.expand(),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 24,
          child: Builder(
            builder: (context) {
              return GestureDetector(
                key: const ValueKey('theme-color-hue-picker'),
                onTapDown: (details) {
                  final size = context.size;
                  if (size != null) _updateHue(details.localPosition, size);
                },
                onPanUpdate: (details) {
                  final size = context.size;
                  if (size != null) _updateHue(details.localPosition, size);
                },
                child: CustomPaint(
                  painter: const _HuePainter(),
                  foregroundPainter: _HueIndicator(_hsvColor.hue),
                  child: const SizedBox.expand(),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final preset in Colors.primaries)
              _PresetColor(
                color: preset,
                selected: preset.toARGB32() == color.toARGB32(),
                onTap: () => _setColor(preset),
              ),
          ],
        ),
        const SizedBox(height: 14),
        TextField(
          key: const ValueKey('theme-color-hex-input'),
          controller: _hexController,
          maxLength: 7,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[#0-9a-fA-F]')),
          ],
          decoration: const InputDecoration(
            labelText: '十六进制颜色',
            hintText: '#42A5F5',
            counterText: '',
            prefixIcon: Icon(Icons.tag),
            border: OutlineInputBorder(),
          ),
          onChanged: _onHexChanged,
          onSubmitted: _onHexChanged,
        ),
        const SizedBox(height: 4),
        Text(
          '#${_hexColor(color).substring(1).toUpperCase()}',
          textAlign: TextAlign.end,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _PresetColor extends StatelessWidget {
  const _PresetColor({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '预设颜色 ${_hexColor(color)}',
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected
                  ? Theme.of(context).colorScheme.onSurface
                  : Colors.transparent,
              width: 3,
            ),
            boxShadow: const [
              BoxShadow(
                blurRadius: 3,
                spreadRadius: 1,
                color: Color(0x40000000),
              ),
            ],
          ),
          child: selected
              ? const Icon(Icons.check, color: Colors.white, size: 18)
              : null,
        ),
      ),
    );
  }
}

class _SaturationValuePainter extends CustomPainter {
  const _SaturationValuePainter(this.color);

  final HSVColor color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final hueColor = color.withSaturation(1).withValue(1).toColor();
    final saturationShader = LinearGradient(
      colors: [Colors.white, hueColor],
    ).createShader(rect);
    final valueShader = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Colors.transparent, Colors.black],
    ).createShader(rect);
    canvas.drawRect(rect, Paint()..shader = saturationShader);
    canvas.drawRect(rect, Paint()..shader = valueShader);
  }

  @override
  bool shouldRepaint(_SaturationValuePainter oldDelegate) =>
      oldDelegate.color != color;
}

class _SaturationValueIndicator extends CustomPainter {
  const _SaturationValueIndicator(this.color);

  final HSVColor color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(
      color.saturation * size.width,
      (1 - color.value) * size.height,
    );
    canvas.drawCircle(
      center,
      9,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white,
    );
    canvas.drawCircle(
      center,
      10.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.black54,
    );
  }

  @override
  bool shouldRepaint(_SaturationValueIndicator oldDelegate) =>
      oldDelegate.color != color;
}

class _HuePainter extends CustomPainter {
  const _HuePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shader = const LinearGradient(
      colors: <Color>[
        Colors.red,
        Colors.yellow,
        Colors.green,
        Colors.cyan,
        Colors.blue,
        Color(0xffff00ff),
        Colors.red,
      ],
    ).createShader(rect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(12)),
      Paint()..shader = shader,
    );
  }

  @override
  bool shouldRepaint(_HuePainter oldDelegate) => false;
}

class _HueIndicator extends CustomPainter {
  const _HueIndicator(this.hue);

  final double hue;

  @override
  void paint(Canvas canvas, Size size) {
    final x = hue / 360 * size.width;
    final center = Offset(x.clamp(5, size.width - 5), size.height / 2);
    canvas.drawCircle(center, 8, Paint()..color = Colors.white);
    canvas.drawCircle(
      center,
      8,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.black54,
    );
  }

  @override
  bool shouldRepaint(_HueIndicator oldDelegate) => oldDelegate.hue != hue;
}

String _hexColor(Color color) {
  return '#${(color.toARGB32() & 0x00ffffff).toRadixString(16).padLeft(6, '0')}';
}

Color? _parseHexColor(String value) {
  final normalized = value.trim().replaceFirst('#', '');
  if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(normalized)) return null;
  return Color(int.parse('ff$normalized', radix: 16));
}
