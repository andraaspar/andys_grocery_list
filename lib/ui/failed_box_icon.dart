import 'package:flutter/material.dart';

/// The FAILED state icon: a filled box with a cross cut out of it, the
/// counterpart of [Icons.check_box] (same box, corners and stroke weight),
/// like the launcher icon's coral tile. Material has no such icon.
///
/// Takes its colour and size from the ambient [IconTheme], like [Icon].
class FailedBoxIcon extends StatelessWidget {
  const FailedBoxIcon({super.key});

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    final size = iconTheme.size ?? 24;
    final color = (iconTheme.color ?? const Color(0xFF000000)).withValues(
      alpha: (iconTheme.color?.a ?? 1) * (iconTheme.opacity ?? 1),
    );
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _FailedBoxPainter(color)),
    );
  }
}

class _FailedBoxPainter extends CustomPainter {
  const _FailedBoxPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Drawn on the Material icons' 24-unit grid.
    canvas.scale(size.width / 24, size.height / 24);
    canvas.saveLayer(const Rect.fromLTWH(0, 0, 24, 24), Paint());
    // The box of check_box: 18 units square, 2-unit corners.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTRB(3, 3, 21, 21),
        const Radius.circular(2),
      ),
      Paint()..color = color,
    );
    // The cross of disabled_by_default: 2-unit strokes, cut out like
    // check_box's tick.
    final cut = Paint()
      ..blendMode = BlendMode.clear
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.butt;
    const a = 7.705, b = 16.295;
    canvas.drawLine(const Offset(a, a), const Offset(b, b), cut);
    canvas.drawLine(const Offset(b, a), const Offset(a, b), cut);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FailedBoxPainter old) => old.color != color;
}
