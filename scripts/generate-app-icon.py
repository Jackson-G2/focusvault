#!/usr/bin/env python3
"""Generate Vaulty's original Tideglass safe app icon."""

from __future__ import annotations

import math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / "AppResources"
ICONSET = RESOURCES / "Vaulty.iconset"
MASTER = RESOURCES / "Vaulty-AppIcon-1024.png"
SCALE = 3
SIZE = 1024
CANVAS = SIZE * SCALE


def sc(value: float) -> int:
    return round(value * SCALE)


def rounded_mask(box: tuple[int, int, int, int], radius: int) -> Image.Image:
    mask = Image.new("L", (CANVAS, CANVAS), 0)
    ImageDraw.Draw(mask).rounded_rectangle(tuple(sc(v) for v in box), radius=sc(radius), fill=255)
    return mask


def vertical_gradient(top: tuple[int, ...], bottom: tuple[int, ...]) -> Image.Image:
    image = Image.new("RGBA", (CANVAS, CANVAS))
    pixels = image.load()
    for y in range(CANVAS):
        ratio = y / max(1, CANVAS - 1)
        color = tuple(round(top[i] * (1 - ratio) + bottom[i] * ratio) for i in range(4))
        for x in range(CANVAS):
            pixels[x, y] = color
    return image


def composite_gradient(base: Image.Image, box, radius, top, bottom) -> None:
    base.alpha_composite(Image.composite(vertical_gradient(top, bottom), Image.new("RGBA", base.size), rounded_mask(box, radius)))


def line(draw: ImageDraw.ImageDraw, points, fill, width) -> None:
    draw.line([(sc(x), sc(y)) for x, y in points], fill=fill, width=sc(width), joint="curve")
    radius = width / 2
    for x, y in (points[0], points[-1]):
        draw.ellipse((sc(x - radius), sc(y - radius), sc(x + radius), sc(y + radius)), fill=fill)


def build_master() -> Image.Image:
    icon = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))

    # Deep Tideglass tile, with enough inset for the macOS icon mask.
    tile_shadow = Image.new("RGBA", icon.size, (0, 0, 0, 0))
    ImageDraw.Draw(tile_shadow).rounded_rectangle(
        (sc(66), sc(76), sc(958), sc(968)), radius=sc(210), fill=(0, 0, 0, 115)
    )
    tile_shadow = tile_shadow.filter(ImageFilter.GaussianBlur(sc(26)))
    icon.alpha_composite(tile_shadow)
    composite_gradient(icon, (52, 46, 972, 966), 210, (8, 49, 58, 255), (4, 23, 30, 255))

    tile_highlight = Image.new("RGBA", icon.size, (0, 0, 0, 0))
    td = ImageDraw.Draw(tile_highlight)
    td.ellipse((sc(-120), sc(610), sc(520), sc(1240)), fill=(126, 204, 184, 28))
    td.ellipse((sc(680), sc(-180), sc(1180), sc(320)), fill=(255, 184, 106, 30))
    icon.alpha_composite(tile_highlight)

    # Safe shadow and body.
    safe_shadow = Image.new("RGBA", icon.size, (0, 0, 0, 0))
    ImageDraw.Draw(safe_shadow).rounded_rectangle(
        (sc(167), sc(156), sc(856), sc(880)), radius=sc(108), fill=(0, 0, 0, 145)
    )
    safe_shadow = safe_shadow.filter(ImageFilter.GaussianBlur(sc(22)))
    icon.alpha_composite(safe_shadow)
    composite_gradient(icon, (150, 126, 846, 852), 110, (66, 119, 124, 255), (20, 61, 68, 255))

    draw = ImageDraw.Draw(icon)
    draw.rounded_rectangle(
        (sc(150), sc(126), sc(846), sc(852)), radius=sc(110),
        outline=(174, 224, 211, 150), width=sc(8)
    )
    # Top/left bevels give depth without copying the photographic perspective.
    line(draw, [(214, 171), (782, 171)], (218, 242, 232, 88), 7)
    line(draw, [(194, 202), (194, 773)], (190, 230, 218, 56), 7)

    # Door panel.
    door_shadow = Image.new("RGBA", icon.size, (0, 0, 0, 0))
    ImageDraw.Draw(door_shadow).rounded_rectangle(
        (sc(226), sc(210), sc(772), sc(795)), radius=sc(74), fill=(0, 0, 0, 125)
    )
    door_shadow = door_shadow.filter(ImageFilter.GaussianBlur(sc(12)))
    icon.alpha_composite(door_shadow)
    composite_gradient(icon, (216, 192, 770, 782), 74, (20, 71, 79, 255), (8, 38, 45, 255))
    draw = ImageDraw.Draw(icon)
    draw.rounded_rectangle(
        (sc(216), sc(192), sc(770), sc(782)), radius=sc(74),
        outline=(159, 214, 198, 125), width=sc(7)
    )

    # Combination dial: bold rings and sparse ticks survive at 16px.
    cx, cy = 492, 394
    for radius, color in [
        (128, (0, 0, 0, 90)),
        (116, (247, 179, 99, 255)),
        (101, (7, 32, 39, 255)),
        (72, (32, 87, 91, 255)),
    ]:
        draw.ellipse((sc(cx - radius), sc(cy - radius), sc(cx + radius), sc(cy + radius)), fill=color)
    draw.ellipse((sc(cx - 111), sc(cy - 111), sc(cx + 111), sc(cy + 111)), outline=(255, 229, 185, 175), width=sc(5))
    for index in range(24):
        angle = math.radians(index * 15 - 90)
        outer = 94
        inner = 82 if index % 3 else 76
        x1, y1 = cx + math.cos(angle) * inner, cy + math.sin(angle) * inner
        x2, y2 = cx + math.cos(angle) * outer, cy + math.sin(angle) * outer
        line(draw, [(x1, y1), (x2, y2)], (244, 238, 211, 210), 3 if index % 3 else 5)
    draw.ellipse((sc(cx - 54), sc(cy - 54), sc(cx + 54), sc(cy + 54)), fill=(207, 226, 214, 255))
    draw.ellipse((sc(cx - 38), sc(cy - 38), sc(cx + 38), sc(cy + 38)), fill=(108, 163, 158, 255))
    draw.ellipse((sc(cx - 29), sc(cy - 34), sc(cx + 12), sc(cy + 7)), fill=(232, 246, 237, 115))

    # Three-spoke handle with apricot metal, simplified for icon scale.
    hx, hy = 492, 628
    for degrees in (-20, 100, 220):
        angle = math.radians(degrees)
        end = (hx + math.cos(angle) * 156, hy + math.sin(angle) * 156)
        line(draw, [(hx, hy), end], (3, 25, 31, 135), 30)
        line(draw, [(hx, hy), end], (248, 180, 101, 255), 20)
        highlight_end = (hx + math.cos(angle) * 148, hy + math.sin(angle) * 148)
        line(draw, [(hx, hy), highlight_end], (255, 228, 181, 105), 5)
    draw.ellipse((sc(hx - 55), sc(hy - 55), sc(hx + 55), sc(hy + 55)), fill=(7, 34, 40, 255))
    draw.ellipse((sc(hx - 42), sc(hy - 42), sc(hx + 42), sc(hy + 42)), fill=(247, 180, 102, 255))
    draw.ellipse((sc(hx - 24), sc(hy - 28), sc(hx + 12), sc(hy + 8)), fill=(255, 235, 201, 100))

    # Three hinges are an immediate safe-door cue at tiny sizes.
    for hinge_y in (272, 480, 690):
        draw.rounded_rectangle(
            (sc(745), sc(hinge_y - 37), sc(820), sc(hinge_y + 37)),
            radius=sc(18), fill=(151, 203, 190, 255), outline=(224, 245, 235, 135), width=sc(4)
        )
        line(draw, [(779, hinge_y - 24), (779, hinge_y + 24)], (8, 39, 45, 90), 4)

    return icon.resize((SIZE, SIZE), Image.Resampling.LANCZOS)


def write_iconset(master: Image.Image) -> None:
    ICONSET.mkdir(parents=True, exist_ok=True)
    outputs = [
        (16, "icon_16x16.png"),
        (32, "icon_16x16@2x.png"),
        (32, "icon_32x32.png"),
        (64, "icon_32x32@2x.png"),
        (128, "icon_128x128.png"),
        (256, "icon_128x128@2x.png"),
        (256, "icon_256x256.png"),
        (512, "icon_256x256@2x.png"),
        (512, "icon_512x512.png"),
        (1024, "icon_512x512@2x.png"),
    ]
    for pixels, name in outputs:
        master.resize((pixels, pixels), Image.Resampling.LANCZOS).save(ICONSET / name)


def main() -> None:
    RESOURCES.mkdir(parents=True, exist_ok=True)
    master = build_master()
    master.save(MASTER)
    write_iconset(master)
    print(MASTER)
    print(ICONSET)


if __name__ == "__main__":
    main()
