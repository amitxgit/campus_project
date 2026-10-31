"""Renders the Batchwise app icon source images into assets/icon/.

Same geometry as BrandMark in lib/features/common/widgets/ui_kit.dart:
three stacked rounded bars, the middle one blue. Run, then
`dart run flutter_launcher_icons` to produce the platform icons.

    python tool/make_icons.py
"""
from pathlib import Path

from PIL import Image, ImageDraw

INK = (11, 11, 13, 255)
PAPER = (255, 255, 255, 255)
ACCENT = (42, 91, 255, 255)
OUT = Path(__file__).resolve().parent.parent / "assets" / "icon"
SIZE = 1024
SS = 4  # supersampling for smooth edges


def bars(draw, size, box, colors):
    """Draws the mark inside the square `box` (x0, y0, side)."""
    x0, y0, s = box
    h = s * 0.18
    gap = s * 0.11
    top = y0 + (s - (3 * h + 2 * gap)) / 2
    for i, w in enumerate((0.86, 0.62, 0.38)):
        y = top + i * (h + gap)
        draw.rounded_rectangle(
            (x0 + s * 0.07, y, x0 + s * (0.07 + w), y + h), radius=h / 2, fill=colors[i]
        )


def render(bg, mark_fraction, rounded):
    big = SIZE * SS
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    if bg is not None:
        if rounded:
            d.rounded_rectangle((0, 0, big, big), radius=big * 0.225, fill=bg)
        else:
            d.rectangle((0, 0, big, big), fill=bg)
    s = big * mark_fraction
    # Optical centring: the bars taper to the right, so nudge them right a touch.
    x0 = (big - s) / 2 + s * 0.04
    bars(d, big, (x0, (big - s) / 2, s), (PAPER, ACCENT, PAPER))
    return img.resize((SIZE, SIZE), Image.LANCZOS)


OUT.mkdir(parents=True, exist_ok=True)
# Legacy / iOS / web icon: full-bleed ink square (platforms apply their own mask).
render(INK, 0.56, rounded=False).save(OUT / "app_icon.png")
# Android adaptive foreground: transparent, mark inside the 66% safe zone.
render(None, 0.44, rounded=False).save(OUT / "logo_foreground.png")
print("wrote", OUT / "app_icon.png", "and", OUT / "logo_foreground.png")
