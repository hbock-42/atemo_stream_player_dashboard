#!/usr/bin/env python3
"""Regenerates the launcher icons for Android and iOS.

The glyph is the same music note painted in lib/ui/widgets/app_icon.dart, on
the same 24-unit grid, so the launcher icon and the in-app icon cannot drift
apart. Colours come from lib/ui/theme/app_theme.dart.

Run:  python3 tool/generate_icons.py
"""
import json
import pathlib

from PIL import Image, ImageDraw

ROOT = pathlib.Path(__file__).resolve().parent.parent
BACKGROUND = (0x0E, 0x0E, 0x11, 255)   # AppColors.dark.background
ACCENT = (0x6F, 0xD3, 0xA8, 255)       # AppColors.dark.accent

# AppIconData.note, on the 24x24 grid used by app_icon.dart.
STEM = [(10, 17), (10, 5), (19, 3), (19, 15)]
HEADS = [((7.5, 17), 2.8), ((16.5, 15), 2.8)]
STROKE = 2.0


def draw_glyph(size: int, scale: float, background=None) -> Image.Image:
    """Renders the note centred on a `size` square.

    `scale` is the fraction of the square the 24-unit grid should occupy;
    Android's adaptive icons need the glyph inside a safe zone, so it is
    smaller there than on iOS.
    """
    # Supersample, then downscale: PIL has no antialiased primitives.
    ss = 4
    canvas = size * ss
    img = Image.new("RGBA", (canvas, canvas), background or (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    unit = canvas * scale / 24.0
    offset = (canvas - 24 * unit) / 2.0
    at = lambda p: (offset + p[0] * unit, offset + p[1] * unit)

    d.line([at(p) for p in STEM], fill=ACCENT, width=max(1, round(STROKE * unit)),
           joint="curve")
    # Round the stroke ends, which PIL's line() does not do on its own.
    for p in (STEM[0], STEM[-1]):
        r = STROKE * unit / 2
        x, y = at(p)
        d.ellipse([x - r, y - r, x + r, y + r], fill=ACCENT)
    for centre, radius in HEADS:
        x, y = at(centre)
        r = radius * unit
        d.ellipse([x - r, y - r, x + r, y + r], fill=ACCENT)

    return img.resize((size, size), Image.LANCZOS)


def write(path: pathlib.Path, img: Image.Image, drop_alpha: bool = False) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if drop_alpha:
        flat = Image.new("RGB", img.size, BACKGROUND[:3])
        flat.paste(img, mask=img.split()[3])
        img = flat
    img.save(path)


def android() -> None:
    res = ROOT / "android/app/src/main/res"

    # Legacy square icon, for API < 26.
    for density, px in [("mdpi", 48), ("hdpi", 72), ("xhdpi", 96),
                        ("xxhdpi", 144), ("xxxhdpi", 192)]:
        write(res / f"mipmap-{density}/ic_launcher.png",
              draw_glyph(px, 0.62, background=BACKGROUND))

    # Adaptive icon foreground: 108dp canvas, glyph kept inside the 66dp safe
    # zone so the launcher can mask it to any shape without clipping the note.
    for density, px in [("mdpi", 108), ("hdpi", 162), ("xhdpi", 216),
                        ("xxhdpi", 324), ("xxxhdpi", 432)]:
        write(res / f"mipmap-{density}/ic_launcher_foreground.png",
              draw_glyph(px, 0.38))

    write_text(res / "mipmap-anydpi-v26/ic_launcher.xml", """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
    <monochrome android:drawable="@mipmap/ic_launcher_foreground" />
</adaptive-icon>
""")
    write_text(res / "values/ic_launcher_background.xml", """<?xml version="1.0" encoding="utf-8"?>
<resources>
    <!-- AppColors.dark.background -->
    <color name="ic_launcher_background">#0E0E11</color>
</resources>
""")


def ios() -> None:
    appicon = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    contents = json.loads((appicon / "Contents.json").read_text())
    for image in contents["images"]:
        size = float(image["size"].split("x")[0])
        scale = int(image["scale"].rstrip("x"))
        px = round(size * scale)
        # iOS rejects icons with an alpha channel.
        write(appicon / image["filename"], draw_glyph(px, 0.60), drop_alpha=True)


def write_text(path: pathlib.Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)


if __name__ == "__main__":
    android()
    ios()
    print("icons regenerated")
