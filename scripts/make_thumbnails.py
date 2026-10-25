"""Compose the store-page thumbnails (1920x1080) from raw Studio captures.

Usage: python -I scripts/make_thumbnails.py <font.ttf>
Reads docs/screenshots/raw/*.jpg, writes docs/screenshots/thumb2-*.jpg.
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "docs" / "screenshots" / "raw"
OUT = ROOT / "docs" / "screenshots"
W, H = 1920, 1080
FONT = sys.argv[1]


def font(size):
    return ImageFont.truetype(FONT, size)


def load(name):
    img = Image.open(RAW / name).convert("RGB").resize((W, H), Image.LANCZOS)
    img = ImageEnhance.Color(img).enhance(1.15)
    return ImageEnhance.Contrast(img).enhance(1.06)


def shade(img, top=0.0, bottom=0.0):
    """Dark gradients at the top/bottom so text pops."""
    overlay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(overlay)
    for y in range(H):
        a = 0
        if top and y < H * 0.38:
            a = max(a, int(top * 255 * (1 - y / (H * 0.38)) ** 1.6))
        if bottom and y > H * 0.62:
            a = max(a, int(bottom * 255 * ((y - H * 0.62) / (H * 0.38)) ** 1.6))
        if a:
            d.line([(0, y), (W, y)], fill=(8, 6, 20, a))
    return Image.alpha_composite(img.convert("RGBA"), overlay)


def title(img, text, xy, size, fill, stroke=(20, 10, 30), sw=12, anchor="mm", glow=None):
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    f = font(size)
    if glow:
        g = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        ImageDraw.Draw(g).text(xy, text, font=f, fill=glow, anchor=anchor, stroke_width=sw + 10, stroke_fill=glow)
        layer = Image.alpha_composite(layer, g.filter(ImageFilter.GaussianBlur(18)))
        d = ImageDraw.Draw(layer)
    # drop shadow
    d.text((xy[0] + 6, xy[1] + 9), text, font=f, fill=(0, 0, 0, 150), anchor=anchor, stroke_width=sw, stroke_fill=(0, 0, 0, 150))
    d.text(xy, text, font=f, fill=fill, anchor=anchor, stroke_width=sw, stroke_fill=stroke)
    return Image.alpha_composite(img, layer)


def pill(img, text, center, size, bg, fg=(255, 255, 255)):
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    f = font(size)
    l, t, r, b = d.textbbox((0, 0), text, font=f)
    pw, ph = r - l + size * 1.1, b - t + size * 0.6
    x0, y0 = center[0] - pw / 2, center[1] - ph / 2
    d.rounded_rectangle([x0, y0 + 6, x0 + pw, y0 + ph + 6], radius=ph / 2, fill=(0, 0, 0, 120))
    d.rounded_rectangle([x0, y0, x0 + pw, y0 + ph], radius=ph / 2, fill=bg, outline=(20, 10, 30), width=6)
    d.text(center, text, font=f, fill=fg, anchor="mm", stroke_width=4, stroke_fill=(20, 10, 30))
    return Image.alpha_composite(img, layer)


def save(img, name):
    img.convert("RGB").save(OUT / name, quality=92)
    print("wrote", name)


# 1. Titanic cores
img = shade(load("1-titanic.jpg"), top=0.75, bottom=0.55)
img = title(img, "HATCH TITANIC CORES!", (W / 2, 120), 132, (255, 120, 235), glow=(255, 60, 220, 170))
img = pill(img, "TINY  ·  BIG  ·  HUGE  ·  TITANIC x10", (W / 2, 960), 56, (130, 60, 220, 235))
save(img, "thumb2-1-titanic.jpg")

# 2. Boss night
img = shade(load("2-boss.jpg"), top=0.8, bottom=0.5)
img = title(img, "BOSS NIGHTS!", (W / 2, 125), 150, (200, 140, 255), glow=(150, 60, 255, 180))
img = pill(img, "LIGHT THE BEACONS  ·  BANISH THE WARDEN", (W / 2, 965), 54, (230, 140, 40, 235))
save(img, "thumb2-2-boss.jpg")

# 3. Zones collage (2x2)
zones = [
    ("z-crystal.jpg", "CRYSTAL HOLLOW", (120, 220, 255)),
    ("z-mire.jpg", "SPORE MIRE", (160, 240, 100)),
    ("z-shrine.jpg", "RUINED SHRINE", (255, 205, 120)),
    ("z-frost.jpg", "FROSTFALL", (200, 240, 255)),
]
canvas = Image.new("RGBA", (W, H), (12, 10, 24, 255))
gap = 10
cw, ch = (W - gap) // 2, (H - gap) // 2
for i, (name, label, color) in enumerate(zones):
    tile = Image.open(RAW / name).convert("RGB")
    # center-crop to the tile aspect, slightly zoomed so the monsters read
    tw, th = tile.size
    zoom = 1.25
    cropw, croph = tw / zoom, tw / zoom * ch / cw
    left, top = (tw - cropw) / 2, (th - croph) / 2 + th * 0.05
    tile = tile.crop((left, top, left + cropw, top + croph)).resize((cw, ch), Image.LANCZOS)
    tile = ImageEnhance.Color(tile).enhance(1.15)
    x, y = (i % 2) * (cw + gap), (i // 2) * (ch + gap)
    canvas.paste(tile, (x, y))
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    f = font(62)
    d.text((x + 36 + 4, y + ch - 52 + 6), label, font=f, fill=(0, 0, 0, 160), anchor="ls", stroke_width=8, stroke_fill=(0, 0, 0, 160))
    d.text((x + 36, y + ch - 52), label, font=f, fill=color, anchor="ls", stroke_width=8, stroke_fill=(20, 10, 30))
    canvas = Image.alpha_composite(canvas, layer)
canvas = title(canvas, "4 WILD ZONES TO EXPLORE!", (W / 2, H / 2), 104, (255, 255, 255), sw=12, glow=(0, 0, 0, 200))
save(canvas, "thumb2-3-zones.jpg")

# 4. The island
img = shade(load("5-aerial.jpg"), top=0.6, bottom=0.6)
img = title(img, "GROW · STEAL · SURVIVE", (W / 2, 120), 120, (255, 220, 90), glow=(255, 160, 40, 150))
img = pill(img, "STEAL CORES  ·  DEFEND YOUR PLOT  ·  8 PLAYERS", (W / 2, 965), 52, (40, 170, 160, 235))
save(img, "thumb2-4-island.jpg")
