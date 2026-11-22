#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""容器贴图后处理：image2.5 原始图 → 64 逻辑像素 HD-pixel 成品。

输入：tools/art_sources/containers/<id>_<state>_raw.png
输出：assets/art/containers/<id>/<state>.png   （64 逻辑 × 8 倍 = 512×512）
      assets/art/containers/<id>/preview.png   （关闭/开启并排预览，棋盘底）

规范：64×64 逻辑画布，物体最大 60×56，水平居中、底部落在 y=62；
32 色量化 + 8 倍最近邻放大，1px 深色描边由生成阶段保证。

用法：
  python tools/prep_containers.py ammo_box
  python tools/prep_containers.py --all
"""

import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "tools" / "art_sources" / "containers"
OUT = ROOT / "assets" / "art" / "containers"

CANVAS = 64
MAX_W = 60
MAX_H = 56
MAX_H_OPEN = 60  # 开盖态允许更高，避免立起的盖子把整体缩小
BOTTOM = 62
UPSCALE = 8
PALETTE = 32
STATES = ("closed", "open")


def strip_bg(im: Image.Image) -> Image.Image:
    """源图没有透明通道时，按边框底色（浅色或深色）泛洪抠背景，保留物体内部细节。"""
    rgb = np.array(im.convert("RGB")).astype(np.int16)
    border = np.concatenate([rgb[0], rgb[-1], rgb[:, 0], rgb[:, -1]])
    bg = np.median(border, axis=0)
    if float(bg.mean()) >= 185:
        # 浅色底：近白且低饱和，兼容浅灰渐变。
        lo = rgb.min(axis=2)
        hi = rgb.max(axis=2)
        near_bg = (lo >= 185) & (hi - lo <= 16)
    else:
        # 深色底：与边框底色接近即可。
        near_bg = np.abs(rgb - bg).max(axis=2) <= 20
    mask = Image.fromarray(near_bg.astype(np.uint8) * 255, "L").copy()
    w, h = mask.size
    seeds = [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]
    seeds += [(x, 0) for x in range(0, w, 8)] + [(x, h - 1) for x in range(0, w, 8)]
    seeds += [(0, y) for y in range(0, h, 8)] + [(w - 1, y) for y in range(0, h, 8)]
    for seed in seeds:
        if mask.getpixel(seed) == 255:
            ImageDraw.floodfill(mask, seed, 128)
    arr = np.array(im.convert("RGBA"))
    arr[:, :, 3] = np.where(np.array(mask) == 128, 0, arr[:, :, 3])
    return Image.fromarray(arr, "RGBA")


def clean(path: Path) -> Image.Image:
    im = Image.open(path).convert("RGBA")
    arr = np.array(im)
    if int(arr[:, :, 3].min()) > 250:
        im = strip_bg(im)
        arr = np.array(im)
    arr[:, :, 3] = np.where(arr[:, :, 3] < 24, 0, arr[:, :, 3])
    im = Image.fromarray(arr, "RGBA")
    a = np.array(im)[:, :, 3]
    ys, xs = np.nonzero(a > 16)
    if xs.size == 0:
        raise ValueError(f"全透明：{path}")
    return im.crop((int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1))


def body_width(im: Image.Image) -> int:
    """取下半身（55% 以下）的宽度，近似箱体宽度；开盖的盖子不影响该值。"""
    a = np.array(im)[:, :, 3] > 16
    ys, xs = np.nonzero(a)
    if xs.size == 0:
        return im.width
    top, bottom = int(ys.min()), int(ys.max())
    band = a[top + int((bottom - top + 1) * 0.55):bottom + 1, :]
    bys, bxs = np.nonzero(band)
    return int(bxs.max() - bxs.min() + 1) if bxs.size else im.width


def body_height(im: Image.Image) -> int:
    """取左侧主体列的纵向高度，避免右侧敞开的柜门抬高整体高度。"""
    a = np.array(im)[:, :, 3] > 16
    band = a[:, :max(1, int(im.width * 0.55))]
    ys, xs = np.nonzero(band)
    return int(ys.max() - ys.min() + 1) if ys.size else im.height


def scale_to(im: Image.Image, scale: float) -> Image.Image:
    size = (max(1, int(round(im.width * scale))), max(1, int(round(im.height * scale))))
    small = im.resize(size, Image.BOX).quantize(colors=PALETTE, method=Image.FASTOCTREE).convert("RGBA")
    arr = np.array(small)
    arr[:, :, 3] = np.where(arr[:, :, 3] < 24, 0, arr[:, :, 3])
    return Image.fromarray(arr, "RGBA")


def compose(small: Image.Image) -> Image.Image:
    canvas_img = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    x = (CANVAS - small.width) // 2
    y = BOTTOM - small.height
    canvas_img.paste(small, (x, y), small)
    return canvas_img.resize((CANVAS * UPSCALE, CANVAS * UPSCALE), Image.NEAREST)


def pixelate(im: Image.Image) -> Image.Image:
    """单状态无配对时的兜底缩放。"""
    return scale_to(im, min(MAX_W / im.width, MAX_H / im.height))


def checker_preview(images: dict, out: Path) -> None:
    cell = CANVAS * UPSCALE
    board = Image.new("RGBA", (cell * len(images) + 16 * (len(images) + 1),
                                cell + 32), (26, 28, 30, 255))
    tile = 16
    for idx, (state, im) in enumerate(images.items()):
        x = 16 + idx * (cell + 16)
        bg = Image.new("RGBA", (cell, cell), (60, 62, 64, 255))
        for ty in range(0, cell, tile):
            for tx in range(0, cell, tile):
                if (tx // tile + ty // tile) % 2 == 0:
                    bg.paste((44, 46, 48, 255), (tx, ty, min(tx + tile, cell), min(ty + tile, cell)))
        bg.alpha_composite(im)
        board.paste(bg, (x, 16))
    board.convert("RGB").save(out)


def process(wid: str) -> bool:
    ims = {}
    for state in STATES:
        raw = SRC / f"{wid}_{state}_raw.png"
        if raw.exists():
            ims[state] = clean(raw)
    if "closed" not in ims:
        print(f"缺少关闭状态：{SRC / (wid + '_closed_raw.png')}")
        return False

    closed = ims["closed"]
    closed_scale = min(MAX_W / closed.width, MAX_H / closed.height)
    scales = {"closed": closed_scale}
    if "open" in ims:
        opened = ims["open"]
        wide = closed.width / max(closed.height, 1) >= 1.2
        if wide:
            # 宽箱体：按箱体宽度对齐，避免开盖图整体缩水。
            ratio = body_width(closed) / max(body_width(opened), 1)
        else:
            # 高柜体：按柜体高度对齐，右侧打开的门不计入高度。
            ratio = body_height(closed) / max(body_height(opened), 1)
        scales["open"] = min(closed_scale * ratio,
            MAX_W / opened.width, MAX_H_OPEN / opened.height)
        # 配对共用缩放：开盖态受画布限制时，关闭态一起降，保证两态体积一致。
        shared = min(scales["closed"], scales["open"])
        scales["closed"] = scales["open"] = shared

    out_dir = OUT / wid
    out_dir.mkdir(parents=True, exist_ok=True)
    done = {}
    for state, im in ims.items():
        img = compose(scale_to(im, scales[state]))
        img.save(out_dir / f"{state}.png")
        done[state] = img
        print(f"[{wid}/{state}] {img.width}x{img.height} scale={scales[state]:.3f}")
    checker_preview(done, out_dir / "preview.png")
    return True


def main() -> int:
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        return 2
    ids = sorted({p.name.rsplit("_closed_raw", 1)[0]
                  for p in SRC.glob("*_closed_raw.png")}) if args[0] == "--all" else args
    ok = True
    for wid in ids:
        ok = process(wid) and ok
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
