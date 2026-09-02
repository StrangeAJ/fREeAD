#!/usr/bin/env python3
"""Render the FreeAd app icon assets.

Outputs
-------
assets/icon/icon.png             1024x1024, background #0B0C0E, emerald glyph
assets/icon/icon_foreground.png  1024x1024, transparent, glyph inside the
                                 central 66 % adaptive-icon safe zone
assets/logo.png                  512x512 render used by the in-app logo
android .../drawable-*dpi/launch_logo.png
                                 transparent 96dp mark for the Android launch
                                 screen (drawn centred on #0B0C0E)

Glyph: a minimal monoline "feed" mark - three left-aligned rounded bars
(widths 100 / 68 / 40 % of the glyph box, thickness ~11 % of the glyph height,
gap ~9 %) plus a filled circle at the bottom-right whose diameter is the bar
thickness x 1.6.

Requires Pillow.  Run with:  python tool/gen_icon.py

Afterwards run `dart run flutter_launcher_icons` to refresh the Android
mipmaps, then remove the 16 % `<inset>` it re-adds to
android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml - the foreground
asset already respects the adaptive-icon safe zone.
"""

from __future__ import annotations

import os

from PIL import Image, ImageDraw

BACKGROUND = (0x0B, 0x0C, 0x0E, 255)
ACCENT = (0x10, 0xB9, 0x81, 255)

SIZE = 1024
SUPERSAMPLE = 4

BAR_WIDTHS = (1.00, 0.68, 0.40)
THICKNESS_RATIO = 0.11   # of glyph box height
GAP_RATIO = 0.09         # of glyph box height
DOT_SCALE = 1.6          # dot diameter = thickness * DOT_SCALE

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICON_DIR = os.path.join(ROOT, "assets", "icon")


def rounded_bar(draw: ImageDraw.ImageDraw, x: float, y: float, w: float,
                h: float, color) -> None:
    """A pill-shaped bar with fully rounded caps."""
    radius = h / 2.0
    if w <= h:
        draw.ellipse([x, y, x + w, y + h], fill=color)
        return
    draw.rounded_rectangle([x, y, x + w, y + h], radius=radius, fill=color)


def draw_glyph(draw: ImageDraw.ImageDraw, box: tuple[float, float, float,
                                                     float], color) -> None:
    """Draw the feed mark inside `box` = (left, top, width, height)."""
    left, top, width, height = box

    thickness = height * THICKNESS_RATIO
    gap = height * GAP_RATIO
    dot = thickness * DOT_SCALE

    # Vertical layout: 3 bars + 2 gaps, then a gap and the dot row.
    bars_height = 3 * thickness + 2 * gap
    total_height = bars_height + gap + dot
    y = top + (height - total_height) / 2.0

    for ratio in BAR_WIDTHS:
        rounded_bar(draw, left, y, width * ratio, thickness, color)
        y += thickness + gap

    # After the loop `y` already sits one gap below the last bar.
    # The dot sits on the trailing (right) edge of the mark.
    dot_x = left + width - dot
    draw.ellipse([dot_x, y, dot_x + dot, y + dot], fill=color)


def render(size: int, background, glyph_fraction: float) -> Image.Image:
    """Render an icon at `size` px with the glyph occupying `glyph_fraction`."""
    ss = size * SUPERSAMPLE
    image = Image.new("RGBA", (ss, ss), background)
    draw = ImageDraw.Draw(image)

    glyph_side = ss * glyph_fraction
    offset = (ss - glyph_side) / 2.0
    # The mark is slightly wider than tall; keep it in a square box so the
    # optical centre stays centred.
    draw_glyph(draw, (offset, offset, glyph_side, glyph_side), ACCENT)

    return image.resize((size, size), Image.LANCZOS)


def main() -> None:
    os.makedirs(ICON_DIR, exist_ok=True)

    # Full-bleed launcher icon: glyph at ~58 % of the canvas.
    icon = render(SIZE, BACKGROUND, 0.58)
    icon_path = os.path.join(ICON_DIR, "icon.png")
    icon.save(icon_path)
    print("wrote", icon_path)

    # Adaptive foreground: the safe zone is the central 66 % of the canvas, so
    # the glyph sits at 46 % - comfortably inside it with room for the launcher
    # to crop or zoom.
    foreground = render(SIZE, (0, 0, 0, 0), 0.46)
    fg_path = os.path.join(ICON_DIR, "icon_foreground.png")
    foreground.save(fg_path)
    print("wrote", fg_path)

    # Splash / in-app logo.
    logo = icon.resize((512, 512), Image.LANCZOS)
    logo_path = os.path.join(ROOT, "assets", "logo.png")
    logo.save(logo_path)
    print("wrote", logo_path)

    # Android launch screen mark: transparent, 96 dp across the densities.
    res_dir = os.path.join(ROOT, "android", "app", "src", "main", "res")
    densities = {
        "mdpi": 96,
        "hdpi": 144,
        "xhdpi": 192,
        "xxhdpi": 288,
        "xxxhdpi": 384,
    }
    for name, px in densities.items():
        target = os.path.join(res_dir, "drawable-" + name)
        os.makedirs(target, exist_ok=True)
        splash = render(px, (0, 0, 0, 0), 0.92)
        splash_path = os.path.join(target, "launch_logo.png")
        splash.save(splash_path)
        print("wrote", splash_path)


if __name__ == "__main__":
    main()
