#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""敌人素材后处理：按 alpha 裁切、统一缩放到固定单元格、脚底对齐基线。

输出：assets/art/enemies/<id>.png   256x384，内容高 360，脚底 y=372
"""

import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "tools" / "art_sources" / "enemies"
OUT = ROOT / "assets" / "art" / "enemies"

CELL_W, CELL_H = 256, 384
BODY_H = 360
GROUND = 372


def alpha_crop(im: Image.Image, pad: float = 0.02) -> Image.Image:
    a = np.array(im)[:, :, 3]
    ys, xs = np.nonzero(a > 16)
    if xs.size == 0:
        raise ValueError("全透明")
    l, r = int(xs.min()), int(xs.max()) + 1
    t, b = int(ys.min()), int(ys.max()) + 1
    pad_px = int(round(max(r - l, b - t) * pad))
    return im.crop((max(0, l - pad_px), max(0, t - pad_px), min(im.width, r + pad_px), min(im.height, b + pad_px)))


def main() -> int:
    if not SRC.exists():
        print("没有敌人源目录")
        return 1
    raws = sorted(SRC.glob("*_raw.png"))
    if not raws:
        print("没有 *_raw.png")
        return 1
    OUT.mkdir(parents=True, exist_ok=True)
    for raw in raws:
        eid = raw.stem.replace("_raw", "")
        im = alpha_crop(Image.open(raw).convert("RGBA"))
        scale = BODY_H / float(im.height)
        new_w = max(1, int(round(im.width * scale)))
        im = im.resize((new_w, BODY_H), Image.LANCZOS)
        if new_w > CELL_W - 8:
            print(f"[warn] {eid} 宽度 {new_w} 超过单元格，等比缩小")
            scale2 = (CELL_W - 8) / float(new_w)
            im = im.resize((CELL_W - 8, max(1, int(round(im.height * scale2)))), Image.LANCZOS)
        cell = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
        x = (CELL_W - im.width) // 2
        y = GROUND - im.height
        cell.alpha_composite(im, (x, y))
        cell.save(OUT / f"{eid}.png")
        print(f"[{eid}] {im.width}x{im.height} -> cell {CELL_W}x{CELL_H} at ({x},{y})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
