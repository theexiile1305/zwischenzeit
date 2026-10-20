#!/usr/bin/env python3
"""Renders the Zwischenzeit app icons (iOS + watchOS) and the README logo.

    python3 scripts/make_app_icon.py

Needs Pillow. Writes 1024 px PNGs into the asset catalogs (iOS: any, dark and tinted
appearances), docs/assets/logo.png and docs/assets/social-preview.png. Drawn at 4x and downsampled for clean edges.

Motif: a stopwatch ("Zwischenzeit" is a split time) whose dial is the working day: three
treatment segments in the calendar's colours and one free gap, with the red now-hand
pointing into the gap - the moment between two patients.
"""
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
SIZE = 1024
S = 4                      # supersampling
W = SIZE * S

ACCENT = (0x1F, 0x63, 0xC9)
ACCENT_DEEP = (0x0B, 0x2E, 0x6E)
NOW = (0xD3, 0x2F, 0x2F)
SEGMENTS = [  # treatment colours from design/tokens.json: KG, MLD, Wärme
    (0x9C, 0xC4, 0x1A),
    (0x22, 0xB5, 0xCC),
    (0xEE, 0x6E, 0x6E),
]

# (start, end) in degrees, clockwise from 12 o'clock. The rest of the dial is the free gap.
SEGMENT_ANGLES = [(-4, 104), (112, 186), (194, 262)]
GAP = (270, 352)
HAND_ANGLE = 311

# theme: (case, face, knobs, gap dots, hub dot, segment colours, hand)
THEMES = {
    "light": ((255, 255, 255), (0xF2, 0xF5, 0xFA), (0xE3, 0xEA, 0xF5), (0xC9, 0xD4, 0xE4), (255, 255, 255),
              SEGMENTS, NOW),
    "dark": ((0x3A, 0x42, 0x52), (0x1E, 0x24, 0x2F), (0x4A, 0x53, 0x66), (0x4F, 0x5A, 0x6E), (0x1E, 0x24, 0x2F),
             [tuple(min(255, c + 25) for c in s) for s in SEGMENTS], (0xFF, 0x5A, 0x50)),
    # Grayscale; the system tints it.
    "tinted": ((0xD8, 0xD8, 0xD8), (0x30, 0x30, 0x30), (0xB0, 0xB0, 0xB0), (0x70, 0x70, 0x70), (0x30, 0x30, 0x30),
               [(0xF0, 0xF0, 0xF0), (0xC8, 0xC8, 0xC8), (0xA0, 0xA0, 0xA0)], (0xFF, 0xFF, 0xFF)),
}


def px(v: float) -> int:
    return round(v * S)


def gradient(top, bottom) -> Image.Image:
    """Diagonal gradient, lighter top-left."""
    g = Image.new("RGB", (W, W))
    d = ImageDraw.Draw(g)
    for i in range(0, 2 * W, S):
        t = i / (2 * W)
        c = tuple(round(a + (b - a) * t) for a, b in zip(top, bottom))
        d.line([(i, 0), (0, i)], fill=c, width=S * 2)
    return g


def polar(cx: float, cy: float, r: float, deg: float) -> tuple[float, float]:
    """Point at `deg` clockwise from 12 o'clock."""
    a = math.radians(deg - 90)
    return cx + r * math.cos(a), cy + r * math.sin(a)


def arc(d: ImageDraw.ImageDraw, cx, cy, r, start, end, width, fill) -> None:
    """Thick arc with round caps."""
    box = [px(cx - r), px(cy - r), px(cx + r), px(cy + r)]
    d.arc(box, start - 90, end - 90, fill=fill, width=px(width))
    for deg in (start, end):
        x, y = polar(cx, cy, r - width / 2, deg)
        d.ellipse([px(x - width / 2), px(y - width / 2), px(x + width / 2), px(y + width / 2)], fill=fill)


def background() -> Image.Image:
    img = gradient(tuple(min(255, c + 28) for c in ACCENT), ACCENT_DEEP)
    glow = Image.new("L", (W, W), 0)
    ImageDraw.Draw(glow).ellipse([px(-250), px(-300), px(650), px(560)], fill=70)
    glow = glow.filter(ImageFilter.GaussianBlur(px(120)))
    return Image.composite(Image.new("RGB", (W, W), (255, 255, 255)), img, glow).convert("RGBA")


def stopwatch(img: Image.Image, scale: float, theme: str = "light", shadow: bool = True) -> Image.Image:
    """Draws the stopwatch centred on `img`. theme: light | dark | tinted."""
    k = scale
    cx, cy = SIZE / 2, SIZE / 2 + 34 * k
    R = 318 * k
    case, face, knob, gap, hub_dot, segments, hand = THEMES[theme]

    layer = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)

    # Crown with its stem, and the lap button at 45 degrees.
    d.rounded_rectangle([px(cx - 30 * k), px(cy - R - 70 * k), px(cx + 30 * k), px(cy - R + 20 * k)],
                        radius=px(14 * k), fill=knob)
    d.rounded_rectangle([px(cx - 74 * k), px(cy - R - 118 * k), px(cx + 74 * k), px(cy - R - 58 * k)],
                        radius=px(30 * k), fill=case)
    bx, by = polar(cx, cy, R + 12 * k, 45)
    button = [polar(bx, by, 50 * k, a) for a in (45 - 90 + 30, 45 - 90 - 30, 45 + 90 + 30, 45 + 90 - 30)]
    d.polygon([(px(x), px(y)) for x, y in (button[1], button[0], button[3], button[2])], fill=case)

    # Case and face.
    d.ellipse([px(cx - R), px(cy - R), px(cx + R), px(cy + R)], fill=case)
    rf = R - 34 * k
    d.ellipse([px(cx - rf), px(cy - rf), px(cx + rf), px(cy + rf)], fill=face)

    # The day: three treatments and the free gap (dotted).
    ring, width = rf - 28 * k, 70 * k
    for (start, end), colour in zip(SEGMENT_ANGLES, segments):
        arc(d, cx, cy, ring, start, end, width, colour)
    for deg in range(GAP[0] + 8, GAP[1] - 4, 18):
        x, y = polar(cx, cy, ring - width / 2, deg)
        d.ellipse([px(x - 15 * k), px(y - 15 * k), px(x + 15 * k), px(y + 15 * k)], fill=gap)

    # Now-hand into the gap, with a short tail and the hub.
    tip = polar(cx, cy, ring - width - 4 * k, HAND_ANGLE)
    tail = polar(cx, cy, 52 * k, HAND_ANGLE + 180)
    d.line([px(tail[0]), px(tail[1]), px(tip[0]), px(tip[1])], fill=hand, width=px(30 * k))
    for x, y, r in ((tip[0], tip[1], 15), (tail[0], tail[1], 15)):
        d.ellipse([px(x - r * k), px(y - r * k), px(x + r * k), px(y + r * k)], fill=hand)
    d.ellipse([px(cx - 40 * k), px(cy - 40 * k), px(cx + 40 * k), px(cy + 40 * k)], fill=hand)
    d.ellipse([px(cx - 12 * k), px(cy - 12 * k), px(cx + 12 * k), px(cy + 12 * k)], fill=hub_dot)

    if shadow:
        alpha = layer.getchannel("A").filter(ImageFilter.GaussianBlur(px(30 * k)))
        offset = Image.new("L", (W, W), 0)
        offset.paste(alpha.point(lambda v: v * 0.45), (0, px(24 * k)))
        img = Image.composite(Image.new("RGBA", (W, W), (5, 20, 50, 255)), img, offset)
    return Image.alpha_composite(img, layer)


def finish(img: Image.Image, size: int = SIZE) -> Image.Image:
    return img.resize((size, size), Image.LANCZOS)


def write_ios(catalog: Path) -> None:
    icon_set = catalog / "AppIcon.appiconset"
    icon_set.mkdir(parents=True, exist_ok=True)
    finish(stopwatch(background(), 1.0)).convert("RGB").save(icon_set / "AppIcon.png")   # no alpha: App Store
    clear = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    finish(stopwatch(clear, 1.0, "dark", shadow=False)).save(icon_set / "AppIcon-Dark.png")
    finish(stopwatch(clear, 1.0, "tinted", shadow=False)).convert("LA").save(icon_set / "AppIcon-Tinted.png")
    (icon_set / "Contents.json").write_text("""{
  "images" : [
    {
      "filename" : "AppIcon.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    },
    {
      "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ],
      "filename" : "AppIcon-Dark.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    },
    {
      "appearances" : [ { "appearance" : "luminosity", "value" : "tinted" } ],
      "filename" : "AppIcon-Tinted.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
""")
    (catalog / "Contents.json").write_text('{\n  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  }\n}\n')


def write_watch(catalog: Path) -> None:
    icon_set = catalog / "AppIcon.appiconset"
    icon_set.mkdir(parents=True, exist_ok=True)
    # The watch masks to a circle: a smaller stopwatch keeps the crown inside.
    finish(stopwatch(background(), 0.84)).convert("RGB").save(icon_set / "AppIcon.png")
    (icon_set / "Contents.json").write_text(
        '{\n  "images" : [\n    {\n      "filename" : "AppIcon.png",\n      "idiom" : "universal",\n'
        '      "platform" : "watchos",\n      "size" : "1024x1024"\n    }\n  ],\n'
        '  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  }\n}\n')


def write_logo(path: Path) -> None:
    """The app icon as a rounded tile on transparency, for the README."""
    tile = stopwatch(background(), 1.0)
    mask = Image.new("L", (W, W), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, W - 1, W - 1], radius=px(225), fill=255)
    out = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    out.paste(tile, mask=mask)
    path.parent.mkdir(parents=True, exist_ok=True)
    finish(out, 512).save(path)


def write_social_preview(path: Path) -> None:
    """1280x640 card for GitHub's social preview (upload it in the repository settings)."""
    w, h = 1280, 640
    bg = background().resize((w, w), Image.LANCZOS).crop((0, (w - h) // 2, w, (w + h) // 2))
    watch = stopwatch(Image.new("RGBA", (W, W), (0, 0, 0, 0)), 1.0).resize((560, 560), Image.LANCZOS)
    bg.alpha_composite(watch, ((w - 560) // 2, (h - 560) // 2 + 6))
    bg.convert("RGB").save(path)


if __name__ == "__main__":
    write_ios(ROOT / "App/iOS/Assets.xcassets")
    write_watch(ROOT / "App/Watch/Assets.xcassets")
    write_logo(ROOT / "docs/assets/logo.png")
    write_social_preview(ROOT / "docs/assets/social-preview.png")
    print("App icons, logo and social preview written.")
