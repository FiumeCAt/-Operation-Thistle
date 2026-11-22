#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把 image2.5 生成的四视图角色图，导出成 1024 / 512 / 256 / 128 像素四个尺寸。

只做抠白底、切分四视图、按比例重采样与排版，不重绘、不镜像、不做任何美术改动。
"""

from pathlib import Path

from PIL import Image

from sprite_utils import clean_auto, cut_transparent, resize_premultiplied

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "assets/art/characters/doll_b/sizes/source/grid_magenta_1024.png"
OUT_DIR = ROOT / "assets/art/characters/doll_b/sizes"
SIZES = [1024, 512, 256, 128]
BODY_RATIO = 0.94


def split_views(img: Image.Image) -> list:
    w, h = img.size
    px = img.load()
    occupied = [any(px[x, y][3] > 8 for y in range(h)) for x in range(w)]
    groups = []
    start = None
    for x in range(w):
        if occupied[x] and start is None:
            start = x
        elif not occupied[x] and start is not None:
            if x - start > 20:
                groups.append((start, x))
            start = None
    if start is not None:
        groups.append((start, w))
    if len(groups) != 4:
        raise SystemExit(f"期望 4 个视图，实际 {len(groups)} 个：{groups}")
    return [img.crop((x0, 0, x1, h)).crop(img.crop((x0, 0, x1, h)).getbbox()) for x0, x1 in groups]


def export(views: list, target: int) -> None:
    body_h = int(round(target * BODY_RATIO))
    scaled = []
    for view in views:
        scale = body_h / float(view.height)
        size = (max(1, round(view.width * scale)), body_h)
        resized = cut_transparent(resize_premultiplied(view, size))
        scaled.append(resized)

    gap = max(4, target // 12)
    total_w = sum(v.width for v in scaled) + gap * (len(scaled) + 1)
    sheet = Image.new("RGBA", (total_w, target), (0, 0, 0, 0))
    x = gap
    for view in scaled:
        sheet.paste(view, (x, target - body_h), view)
        x += view.width + gap
    path = OUT_DIR / f"doll_{target}.png"
    sheet.save(path)
    print(f"{path.relative_to(ROOT)}  {sheet.size[0]}x{sheet.size[1]}")


def main() -> None:
    views = split_views(clean_auto(Image.open(SRC)))
    for size in SIZES:
        export(views, size)


if __name__ == "__main__":
    main()
