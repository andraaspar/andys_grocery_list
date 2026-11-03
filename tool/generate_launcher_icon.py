#!/usr/bin/env python3
"""Generates the Android launcher icon from one description of the artwork.

The artwork: the app's three item states as big, chunky 3D tiles, tossed
at playful angles on a sunflower-yellow background:
  - DONE: a green tile with a tick,
  - FAILED: a coral tile with a cross,
  - NEW: a plain white tile (an empty box).

Writes:
  - the adaptive icon (Android 8+): a colour vector foreground on a colour
    background, plus a flat outline version as the monochrome layer for
    themed icons (Android 13+);
  - round legacy PNGs for older Android versions, rasterized here.

Uses only the standard library. Run from the project root:
    python3 tool/generate_launcher_icon.py
"""

import math
import os
import struct
import zlib
from dataclasses import dataclass

RES = 'android/app/src/main/res'

# These colours and the tile geometry are mirrored in lib/ui/theme.dart
# (BrandColors) and lib/ui/tiles_logo.dart; change them together.
BACKGROUND = '#FFC21A'
WHITE = '#FFFFFF'

# Everything is in the adaptive icon's 108 x 108 viewport, and stays inside
# the 66-unit safe circle in the middle.
TILE = 23  # tile size
RADIUS = 6  # tile corner radius
DEPTH = 4  # how far the tile's side shows below it
GLYPH = 4.25  # tick and cross stroke width


@dataclass
class Tile:
    cx: float
    cy: float
    angle: float  # degrees, clockwise
    face: str
    side: str
    glyph: str  # 'tick', 'cross' or 'none'


# Back to front, in the shape of an A: the white tile on top, partly covered
# by the two at the bottom.
TILES = [
    Tile(54, 41, 6, face='#FFFFFF', side='#E3B04B', glyph='none'),
    Tile(42, 62, -12, face='#3DD35F', side='#21924A', glyph='tick'),
    Tile(66, 63, 10, face='#FF5E62', side='#C2343F', glyph='cross'),
]

# The flat themed icon can't hide what's behind a tile, so its outlines
# would cross. There the tiles are moved apart by these offsets.
MONO_OFFSETS = [(0, -3), (-2, 2), (2, 2)]


def glyph_strokes(t):
    """The tile's tick or cross, as polylines in unrotated coordinates."""
    x, y = t.cx, t.cy
    if t.glyph == 'tick':
        return [[(x - 6, y + 0.5), (x - 1.75, y + 4.75), (x + 6.25, y - 4.5)]]
    if t.glyph == 'cross':
        d = 5
        return [[(x - d, y - d), (x + d, y + d)],
                [(x + d, y - d), (x - d, y + d)]]
    return []


# ---------------------------------------------------------------------------
# Shapes shared by the vector drawable and the rasterizer.
#
# ('rrect', (l, t, r, b, radius), fill, alpha, rotation)
# ('poly', points, stroke width, colour, alpha, rotation)
# rotation is (angle, pivot x, pivot y).


def color_shapes():
    out = []
    for t in TILES:
        h = TILE / 2
        rot = (t.angle, t.cx, t.cy)
        side_rot = (t.angle, t.cx, t.cy + DEPTH)
        out.append(('rrect', (t.cx - h, t.cy - h + DEPTH, t.cx + h,
                              t.cy + h + DEPTH, RADIUS), t.side, 1, side_rot))
        out.append(('rrect', (t.cx - h, t.cy - h, t.cx + h, t.cy + h, RADIUS),
                    t.face, 1, rot))
        # A soft shine along the top edge.
        out.append(('rrect', (t.cx - h + 4, t.cy - h + 2.5, t.cx + 2,
                              t.cy - h + 5, 1.25), WHITE, 0.35, rot))
        for pts in glyph_strokes(t):
            out.append(('poly', pts, GLYPH, WHITE, 1, rot))
    return out


def monochrome_shapes():
    """Flat outlines: themed icons are tinted to a single colour."""
    out = []
    for tile, (dx, dy) in zip(TILES, MONO_OFFSETS):
        t = Tile(tile.cx + dx, tile.cy + dy, tile.angle, tile.face, tile.side,
                 tile.glyph)
        h = TILE / 2 - 2.5
        rot = (t.angle, t.cx, t.cy)
        out.append(('outline', (t.cx - h, t.cy - h, t.cx + h, t.cy + h,
                                RADIUS - 2.5), 3, WHITE, 1, rot))
        for pts in glyph_strokes(t):
            out.append(('poly', pts, GLYPH, WHITE, 1, rot))
    return out


# ---------------------------------------------------------------------------
# Vector drawable


def fmt(v):
    return ('%.2f' % v).rstrip('0').rstrip('.')


def rrect_path(l, t, r, b, rad):
    return (
        'M{a},{t} H{c} A{r},{r} 0 0 1 {R},{d} V{e} A{r},{r} 0 0 1 {c},{B} '
        'H{a} A{r},{r} 0 0 1 {L},{e} V{d} A{r},{r} 0 0 1 {a},{t} Z'
    ).format(
        a=fmt(l + rad), c=fmt(r - rad), d=fmt(t + rad), e=fmt(b - rad),
        t=fmt(t), B=fmt(b), L=fmt(l), R=fmt(r), r=fmt(rad),
    )


def poly_path(pts):
    return 'M%s,%s' % (fmt(pts[0][0]), fmt(pts[0][1])) + ''.join(
        ' L%s,%s' % (fmt(x), fmt(y)) for x, y in pts[1:])


def path_xml(shape):
    kind = shape[0]
    if kind == 'rrect':
        _, geo, color, alpha, _ = shape
        attrs = [('pathData', rrect_path(*geo)), ('fillColor', color)]
        if alpha != 1:
            attrs.append(('fillAlpha', fmt(alpha)))
    else:
        _, geo, width, color, alpha, _ = shape
        data = rrect_path(*geo) if kind == 'outline' else poly_path(geo)
        attrs = [('pathData', data), ('strokeColor', color),
                 ('strokeWidth', fmt(width)), ('strokeLineCap', 'round'),
                 ('strokeLineJoin', 'round')]
    lines = ''.join('\n            android:%s="%s"' % a for a in attrs)
    return '        <path%s />\n' % lines


def vector_drawable(shapes):
    # Each shape gets its own group, which rotates it around its pivot.
    body = ''
    for shape in shapes:
        angle, px, py = shape[-1]
        body += (
            '    <group\n'
            '        android:rotation="%s"\n'
            '        android:pivotX="%s"\n'
            '        android:pivotY="%s">\n%s    </group>\n'
            % (fmt(angle), fmt(px), fmt(py), path_xml(shape))
        )
    return (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<!-- Generated by tool/generate_launcher_icon.py -->\n'
        '<vector xmlns:android="http://schemas.android.com/apk/res/android"\n'
        '    android:width="108dp"\n'
        '    android:height="108dp"\n'
        '    android:viewportWidth="108"\n'
        '    android:viewportHeight="108">\n'
        + body +
        '</vector>\n'
    )


ADAPTIVE = '''<?xml version="1.0" encoding="utf-8"?>
<!-- Generated by tool/generate_launcher_icon.py -->
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@drawable/ic_launcher_foreground" />
    <monochrome android:drawable="@drawable/ic_launcher_monochrome" />
</adaptive-icon>
'''

COLORS = '''<?xml version="1.0" encoding="utf-8"?>
<!-- Generated by tool/generate_launcher_icon.py -->
<resources>
    <color name="ic_launcher_background">%s</color>
</resources>
''' % BACKGROUND

# ---------------------------------------------------------------------------
# Rasterizing the legacy icon


def rgb(hex_color):
    return tuple(int(hex_color[i:i + 2], 16) for i in (1, 3, 5))


def unrotate(x, y, rotation):
    angle, px, py = rotation
    a = math.radians(-angle)
    dx, dy = x - px, y - py
    return (px + dx * math.cos(a) - dy * math.sin(a),
            py + dx * math.sin(a) + dy * math.cos(a))


def seg_dist(px, py, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay
    t = ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)
    t = max(0.0, min(1.0, t))
    return math.hypot(px - ax - t * dx, py - ay - t * dy)


def rounded_rect_dist(px, py, l, t, r, b, rad):
    """Signed distance to a rounded rectangle (negative inside)."""
    cx, cy = (l + r) / 2, (t + b) / 2
    qx = abs(px - cx) - ((r - l) / 2 - rad)
    qy = abs(py - cy) - ((b - t) / 2 - rad)
    outside = math.hypot(max(qx, 0), max(qy, 0))
    return outside + min(max(qx, qy), 0) - rad


def hits(shape, x, y):
    x, y = unrotate(x, y, shape[-1])
    kind, geo = shape[0], shape[1]
    if kind == 'rrect':
        return rounded_rect_dist(x, y, *geo) <= 0
    width = shape[2]
    if kind == 'outline':
        return abs(rounded_rect_dist(x, y, *geo)) <= width / 2
    return any(seg_dist(x, y, ax, ay, bx, by) <= width / 2
               for (ax, ay), (bx, by) in zip(geo, geo[1:]))


def paint(shapes, x, y):
    """The colour at (x, y), painting the shapes over the background."""
    c = rgb(BACKGROUND)
    for shape in shapes:
        if hits(shape, x, y):
            color, alpha = (shape[2], shape[3]) if shape[0] == 'rrect' \
                else (shape[3], shape[4])
            c = tuple(a + (b - a) * alpha for a, b in zip(c, rgb(color)))
    return c


# The legacy icon shows the adaptive icon's middle 72 units (what a launcher
# shows of it), masked to a circle.
VISIBLE = 72
MASK_RADIUS = 35.5
SAMPLES = 4


def render(size, shapes):
    rows = []
    n = SAMPLES * SAMPLES
    for py in range(size):
        row = bytearray()
        for px in range(size):
            total = [0.0, 0.0, 0.0]
            covered = 0
            for sy in range(SAMPLES):
                for sx in range(SAMPLES):
                    x = (px + (sx + 0.5) / SAMPLES) / size * VISIBLE + 18
                    y = (py + (sy + 0.5) / SAMPLES) / size * VISIBLE + 18
                    if math.hypot(x - 54, y - 54) > MASK_RADIUS:
                        continue
                    covered += 1
                    for i, v in enumerate(paint(shapes, x, y)):
                        total[i] += v
            if covered == 0:
                row += bytes(4)
                continue
            row += bytes([round(v / covered) for v in total]
                         + [round(covered / n * 255)])
        rows.append(bytes(row))
    return png(size, size, rows)


def png(w, h, rows):
    def chunk(kind, data):
        c = kind + data
        return struct.pack('>I', len(data)) + c + struct.pack(
            '>I', zlib.crc32(c) & 0xFFFFFFFF)

    raw = b''.join(b'\x00' + r for r in rows)
    return (
        b'\x89PNG\r\n\x1a\n'
        + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0))
        + chunk(b'IDAT', zlib.compress(raw, 9))
        + chunk(b'IEND', b'')
    )


LEGACY_SIZES = {
    'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192,
}


def write(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    mode = 'wb' if isinstance(data, bytes) else 'w'
    with open(path, mode) as f:
        f.write(data)
    print('wrote', path)


def main():
    shapes = color_shapes()
    write(f'{RES}/drawable/ic_launcher_foreground.xml', vector_drawable(shapes))
    write(f'{RES}/drawable/ic_launcher_monochrome.xml',
          vector_drawable(monochrome_shapes()))
    write(f'{RES}/mipmap-anydpi-v26/ic_launcher.xml', ADAPTIVE)
    write(f'{RES}/values/ic_launcher_colors.xml', COLORS)
    for density, size in LEGACY_SIZES.items():
        write(f'{RES}/mipmap-{density}/ic_launcher.png', render(size, shapes))


if __name__ == '__main__':
    main()
