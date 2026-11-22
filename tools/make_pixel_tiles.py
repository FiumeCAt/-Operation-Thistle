#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""程序化生成俯视像素风场景贴图（灰褐地砖 / 混凝土墙块 / 货架 / 木箱 / 铁桶）。

风格参考：俯视 2D 像素生存射击，低饱和灰褐主色，砖缝与脏污密集，硬边无抗锯齿。
所有贴图按 64 px 网格设计，运行时可被 64 px 整数倍重复铺设。
"""

import random
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "art" / "env"
TILE = 64
rng = random.Random(20261114)


def _noise(img: Image.Image, area, amount: int, palette) -> None:
    draw = ImageDraw.Draw(img)
    x0, y0, x1, y1 = area
    for _ in range(amount):
        x = rng.randrange(x0, x1)
        y = rng.randrange(y0, y1)
        draw.point((x, y), fill=rng.choice(palette))


def make_floor(path: Path) -> None:
    """4×4 块地砖，带砖缝、明暗随机与脏污。"""
    size = TILE * 4
    img = Image.new("RGB", (size, size), (58, 53, 47))
    draw = ImageDraw.Draw(img)
    base_colors = [
        (95, 88, 79), (98, 91, 82), (92, 85, 77),
        (100, 93, 84), (90, 84, 76), (96, 89, 81),
    ]
    for ty in range(4):
        for tx in range(4):
            x0, y0 = tx * TILE, ty * TILE
            base = rng.choice(base_colors)
            draw.rectangle([x0, y0, x0 + TILE - 1, y0 + TILE - 1], fill=base)
            # 砖面内高光 / 暗角，模拟轻微起伏
            draw.rectangle([x0 + 2, y0 + 2, x0 + TILE - 3, y0 + TILE - 3],
                           outline=(base[0] + 8, base[1] + 8, base[2] + 7))
            draw.rectangle([x0 + 3, y0 + TILE - 5, x0 + TILE - 4, y0 + TILE - 4],
                           fill=(base[0] - 14, base[1] - 13, base[2] - 12))
            # 砖缝
            draw.line([x0, y0, x0 + TILE - 1, y0], fill=(44, 40, 36))
            draw.line([x0, y0, x0, y0 + TILE - 1], fill=(44, 40, 36))
            draw.line([x0 + 1, y0 + 1, x0 + TILE - 1, y0 + 1], fill=(70, 64, 58))
            _noise(img, (x0 + 3, y0 + 3, x0 + TILE - 3, y0 + TILE - 3), 90,
                   [(base[0] + 12, base[1] + 11, base[2] + 10),
                    (base[0] - 18, base[1] - 17, base[2] - 15)])

    # 裂纹与油污
    for _ in range(26):
        x = rng.randrange(4, size - 4)
        y = rng.randrange(4, size - 4)
        length = rng.randrange(4, 16)
        for i in range(length):
            draw.point((x + i, y + rng.choice([0, 0, 1, -1])), fill=(66, 60, 54))
    for _ in range(14):
        cx = rng.randrange(8, size - 8)
        cy = rng.randrange(8, size - 8)
        for _ in range(rng.randrange(10, 32)):
            px = cx + rng.randint(-9, 9)
            py = cy + rng.randint(-6, 6)
            draw.point((px, py), fill=(72, 66, 59))
    img.save(path)


def make_wall(path: Path) -> None:
    """俯视墙体顶面：深灰褐混凝土，分块与污渍。"""
    size = TILE * 4
    img = Image.new("RGB", (size, size), (74, 69, 63))
    draw = ImageDraw.Draw(img)
    for ty in range(4):
        for tx in range(4):
            x0, y0 = tx * TILE, ty * TILE
            base = (74 + rng.randint(-4, 4), 69 + rng.randint(-4, 4), 63 + rng.randint(-4, 4))
            draw.rectangle([x0, y0, x0 + TILE - 1, y0 + TILE - 1], fill=base)
            draw.line([x0, y0, x0 + TILE - 1, y0], fill=(52, 48, 44))
            draw.line([x0, y0, x0, y0 + TILE - 1], fill=(52, 48, 44))
            draw.line([x0 + 1, y0 + 1, x0 + TILE - 1, y0 + 1], fill=(86, 80, 73))
            _noise(img, (x0 + 2, y0 + 2, x0 + TILE - 2, y0 + TILE - 2), 70,
                   [(base[0] + 10, base[1] + 9, base[2] + 8),
                    (base[0] - 12, base[1] - 11, base[2] - 10)])
    img.save(path)


def make_shelf(path: Path) -> None:
    """俯视货架：黑铁架体 + 橙褐木托边，分为上下两层。"""
    w, h = 128, 96
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    draw.rectangle([0, 0, w - 1, h - 1], fill=(30, 28, 27, 255))
    draw.rectangle([0, 0, w - 1, h - 1], outline=(18, 17, 16, 255))
    # 架板高光
    draw.line([2, 2, w - 3, 2], fill=(52, 49, 46, 255))
    # 两层分隔
    for split in (33, 66):
        draw.line([2, split, w - 3, split], fill=(16, 15, 14, 255))
        draw.line([2, split + 1, w - 3, split + 1], fill=(46, 43, 40, 255))
    # 两侧立柱
    for x in (4, w - 7):
        draw.rectangle([x, 3, x + 2, h - 4], fill=(38, 35, 33, 255))
    # 橙褐托盘边（参考图货架底缘）
    draw.rectangle([0, h - 12, w - 1, h - 5], fill=(126, 74, 40, 255))
    draw.line([0, h - 12, w - 1, h - 12], fill=(164, 102, 58, 255))
    draw.line([0, h - 5, w - 1, h - 5], fill=(78, 44, 24, 255))
    # 架上零星物资
    item_colors = [(78, 96, 110), (120, 96, 60), (96, 92, 84), (150, 138, 110)]
    for _ in range(7):
        ix = rng.randrange(8, w - 14)
        iy = rng.randrange(5, h - 18)
        iw = rng.randrange(5, 12)
        ih = rng.randrange(4, 9)
        draw.rectangle([ix, iy, ix + iw, iy + ih], fill=rng.choice(item_colors) + (255,))
    img.save(path)


def make_shelf_variant(path: Path) -> None:
    """货架变体：物资更满、托盘偏暗，避免整排货架完全重复。"""
    w, h = 128, 96
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    draw.rectangle([0, 0, w - 1, h - 1], fill=(26, 25, 24, 255))
    draw.rectangle([0, 0, w - 1, h - 1], outline=(16, 15, 14, 255))
    draw.line([2, 2, w - 3, 2], fill=(48, 45, 43, 255))
    for split in (30, 62):
        draw.line([2, split, w - 3, split], fill=(14, 13, 12, 255))
        draw.line([2, split + 1, w - 3, split + 1], fill=(42, 40, 38, 255))
    for x in (3, w - 6):
        draw.rectangle([x, 3, x + 2, h - 4], fill=(34, 32, 30, 255))
    draw.rectangle([0, h - 14, w - 1, h - 6], fill=(104, 60, 32, 255))
    draw.line([0, h - 14, w - 1, h - 14], fill=(138, 84, 46, 255))
    draw.line([0, h - 6, w - 1, h - 6], fill=(64, 36, 20, 255))
    item_colors = [(62, 74, 86), (88, 72, 46), (74, 70, 64), (112, 104, 82), (50, 54, 52)]
    for _ in range(11):
        ix = rng.randrange(10, w - 16)
        iy = rng.randrange(5, h - 20)
        iw = rng.randrange(6, 16)
        ih = rng.randrange(5, 11)
        draw.rectangle([ix, iy, ix + iw, iy + ih], fill=rng.choice(item_colors) + (255,))
        draw.line([ix, iy, ix + iw, iy], fill=(min(255, rng.choice(item_colors)[0] + 22),) * 3 + (255,))
    img.save(path)


def make_crate(path: Path) -> None:
    w, h = 48, 40
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    draw.rectangle([0, 0, w - 1, h - 1], fill=(92, 71, 48, 255))
    draw.rectangle([0, 0, w - 1, h - 1], outline=(48, 36, 24, 255))
    draw.line([0, 8, w - 1, 8], fill=(112, 88, 60, 255))
    draw.line([0, h - 9, w - 1, h - 9], fill=(64, 48, 32, 255))
    for x in (6, w // 2, w - 7):
        draw.line([x, 1, x, h - 2], fill=(70, 53, 35, 255))
    img.save(path)


def make_barrel(path: Path) -> None:
    w, h = 40, 40
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    draw.ellipse([0, 0, w - 1, h - 1], fill=(66, 74, 72, 255), outline=(34, 38, 37, 255))
    draw.ellipse([4, 4, w - 5, h - 5], outline=(86, 96, 92, 255))
    draw.ellipse([12, 12, w - 13, h - 13], fill=(58, 66, 64, 255))
    img.save(path)


def make_contact_shadow(path: Path) -> None:
    """角色脚下的像素椭圆接触阴影，替代模糊径向图，避免人物看起来悬空。"""
    w, h = 64, 24
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    cx, cy = w // 2, h // 2
    for y in range(h):
        for x in range(w):
            dx = (x - cx) / (w * 0.5 - 1)
            dy = (y - cy) / (h * 0.5 - 1)
            d = dx * dx + dy * dy
            if d > 1.0:
                continue
            alpha = 150 if d < 0.55 else (96 if d < 0.8 else 46)
            draw.point((x, y), fill=(8, 8, 9, alpha))
    img.save(path)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    make_floor(OUT / "pixel_floor_256.png")
    make_wall(OUT / "pixel_wall_256.png")
    make_shelf(OUT / "pixel_shelf_128.png")
    make_shelf_variant(OUT / "pixel_shelf_128_b.png")
    make_crate(OUT / "pixel_crate_48.png")
    make_barrel(OUT / "pixel_barrel_40.png")
    make_contact_shadow(OUT / "pixel_shadow_64.png")
    print("done")


if __name__ == "__main__":
    main()
