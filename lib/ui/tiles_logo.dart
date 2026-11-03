import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

/// The launcher icon, drawn in Flutter: the three item states as 3D tiles on
/// a sunflower-yellow circle. The geometry mirrors `tool/generate_launcher_icon.py`;
/// change both together.
class TilesLogo extends StatelessWidget {
  const TilesLogo({super.key, this.size = 96});

  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    excludeSemantics: true,
    child: CustomPaint(size: Size.square(size), painter: const _TilesPainter()),
  );
}

enum _Glyph { tick, cross, none }

class _Tile {
  const _Tile(this.cx, this.cy, this.angle, this.face, this.side, this.glyph);
  final double cx, cy, angle;
  final Color face, side;
  final _Glyph glyph;
}

// In the adaptive icon's 108 x 108 viewport, back to front: an A, with the
// white tile on top partly covered by the two at the bottom.
const _tiles = [
  _Tile(54, 41, 6, BrandColors.newFace, BrandColors.newSide, _Glyph.none),
  _Tile(42, 62, -12, BrandColors.doneFace, BrandColors.doneSide, _Glyph.tick),
  _Tile(
    66,
    63,
    10,
    BrandColors.failedFace,
    BrandColors.failedSide,
    _Glyph.cross,
  ),
];
const _tileSize = 23.0;
const _radius = 6.0;
const _depth = 4.0;
const _glyphWidth = 4.25;

class _TilesPainter extends CustomPainter {
  const _TilesPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // Like a launcher: the middle 72 units, masked to a circle.
    canvas.scale(size.width / 72);
    canvas.translate(-18, -18);
    canvas.drawCircle(
      const Offset(54, 54),
      35.5,
      Paint()..color = BrandColors.sunflower,
    );
    for (final t in _tiles) {
      _rotated(canvas, t, Offset(t.cx, t.cy + _depth), () {
        _rrect(canvas, Offset(t.cx, t.cy + _depth), t.side);
      });
      _rotated(canvas, t, Offset(t.cx, t.cy), () {
        _rrect(canvas, Offset(t.cx, t.cy), t.face);
        const h = _tileSize / 2;
        canvas.drawRRect(
          RRect.fromLTRBR(
            t.cx - h + 4,
            t.cy - h + 2.5,
            t.cx + 2,
            t.cy - h + 5,
            const Radius.circular(1.25),
          ),
          Paint()..color = Colors.white.withValues(alpha: 0.35),
        );
        _glyph(canvas, t);
      });
    }
  }

  void _rotated(Canvas canvas, _Tile t, Offset pivot, VoidCallback draw) {
    canvas
      ..save()
      ..translate(pivot.dx, pivot.dy)
      ..rotate(t.angle * math.pi / 180)
      ..translate(-pivot.dx, -pivot.dy);
    draw();
    canvas.restore();
  }

  void _rrect(Canvas canvas, Offset center, Color color) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: _tileSize, height: _tileSize),
        const Radius.circular(_radius),
      ),
      Paint()..color = color,
    );
  }

  void _glyph(Canvas canvas, _Tile t) {
    final x = t.cx, y = t.cy;
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = _glyphWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    switch (t.glyph) {
      case _Glyph.tick:
        canvas.drawPath(
          Path()
            ..moveTo(x - 6, y + 0.5)
            ..lineTo(x - 1.75, y + 4.75)
            ..lineTo(x + 6.25, y - 4.5),
          paint,
        );
      case _Glyph.cross:
        const d = 5.0;
        canvas
          ..drawLine(Offset(x - d, y - d), Offset(x + d, y + d), paint)
          ..drawLine(Offset(x + d, y - d), Offset(x - d, y + d), paint);
      case _Glyph.none:
        break;
    }
  }

  @override
  bool shouldRepaint(_TilesPainter oldDelegate) => false;
}
