#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""从 image2.5 生成的四向行走图，导出 1024 / 512 / 256 / 128 四档角色图集（LOD）。

图像内容全部来自 image2.5，这里只做抠白底、切帧、等比缩放与排版，不重绘、不镜像。
输出：assets/art/characters/doll_b/lod/doll_lod_{N}.png
      4 行方向 × 4 帧，单帧 = 1.25N，身体高 N px，脚底基线在帧高 95%。
"""

from collections import deque
from pathlib import Path

from PIL import Image

from sprite_utils import clean_auto, cut_transparent, resize_premultiplied

ROOT = Path(__file__).resolve().parents[1]
SHEET = ROOT / "assets/art/characters/doll_b/walk_sheet_magenta.png"
BACK = ROOT / "assets/art/characters/doll_b/walk_back_magenta.png"
RIGHT = ROOT / "assets/art/characters/doll_b/walk_right_magenta.png"
OUT_DIR = ROOT / "assets/art/characters/doll_b/lod"

SIZES = [1024, 512, 256, 128]
COLS = 4
ROWS = 4
FEET_RATIO = 0.95


def row_bands(img: Image.Image) -> list:
    w, h = img.size
    px = img.load()
    occupied = [any(px[x, y][3] > 8 for x in range(w)) for y in range(h)]
    bands = []
    start = None
    for y in range(h):
        if occupied[y] and start is None:
            start = y
        elif not occupied[y] and start is not None:
            if y - start > 40:
                bands.append((start, y))
            start = None
    if start is not None:
        bands.append((start, h))
    return bands


def frames_of_band(band: Image.Image) -> list:
    w, h = band.size
    px = band.load()
    occupied = [any(px[x, y][3] > 8 for y in range(h)) for x in range(w)]
    boxes = []
    start = None
    for x in range(w):
        if occupied[x] and start is None:
            start = x
        elif not occupied[x] and start is not None:
            if x - start > 10:
                boxes.append((start, x))
            start = None
    if start is not None:
        boxes.append((start, w))
    if len(boxes) != COLS:
        raise SystemExit(f"期望 4 帧，实际 {len(boxes)} 帧：{boxes}")
    out = []
    for x0, x1 in boxes:
        cell = band.crop((x0, 0, x1, band.height))
        out.append(cell.crop(cell.getbbox()))
    return out


def load_rows() -> list:
    sheet = clean_auto(Image.open(SHEET))
    rows = [frames_of_band(sheet.crop((0, y0, sheet.width, y1))) for y0, y1 in row_bands(sheet)]
    for index, path in ((1, BACK), (3, RIGHT)):
        if not path.exists():
            continue
        strip = clean_auto(Image.open(path))
        bands = row_bands(strip)
        if bands:
            rows[index] = frames_of_band(strip.crop((0, bands[0][0], strip.width, bands[0][1])))
    return rows[:ROWS]


def export(rows: list, body_h: int) -> None:
    frame = int(round(body_h * 1.25))
    feet = int(round(frame * FEET_RATIO))
    sheet_out = Image.new("RGBA", (frame * COLS, frame * ROWS), (0, 0, 0, 0))
    for row_index, frames in enumerate(rows):
        scale = body_h / float(max(f.height for f in frames))
        for col_index, cell in enumerate(frames):
            size = (max(1, round(cell.width * scale)), max(1, round(cell.height * scale)))
            body = cut_transparent(resize_premultiplied(cell, size))
            canvas = Image.new("RGBA", (frame, frame), (0, 0, 0, 0))
            canvas.paste(body, ((frame - body.width) // 2, feet - body.height), body)
            sheet_out.paste(canvas, (col_index * frame, row_index * frame), canvas)
    path = OUT_DIR / f"doll_lod_{body_h}.png"
    path.parent.mkdir(parents=True, exist_ok=True)
    sheet_out.save(path)
    print(f"{path.relative_to(ROOT)}  {sheet_out.size[0]}x{sheet_out.size[1]}  frame={frame}")


def main() -> None:
    rows = load_rows()
    for size in SIZES:
        export(rows, size)


if __name__ == "__main__":
    main()
