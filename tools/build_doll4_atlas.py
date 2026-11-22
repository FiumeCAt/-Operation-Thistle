#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把 image2.5 生成的四向行走图切成 4 向精灵图集（不做镜像、不重绘）。

输入：
  assets/art/characters/doll_b/walk_sheet_raw.png  —— 4 行 4 列（正面 / 背面 / 左向 / 右向）
  assets/art/characters/doll_b/walk_right_raw.png  —— 1 行 4 帧（朝右行走，作备用来源）
输出：
  assets/art/characters/doll_b/doll_b_4dir.png
  4 行方向 × 4 帧，单帧 160×160，身体高 128 px，脚底基线 y=152
"""

from pathlib import Path

from PIL import Image

from sprite_utils import clean_auto, cut_transparent, resize_premultiplied

ROOT = Path(__file__).resolve().parents[1]
SHEET = ROOT / "assets/art/characters/doll_b/walk_sheet_magenta.png"
BACK = ROOT / "assets/art/characters/doll_b/walk_back_magenta.png"
RIGHT = ROOT / "assets/art/characters/doll_b/walk_right_magenta.png"
DST = ROOT / "assets/art/characters/doll_b/doll_b_4dir.png"

FRAME_W, FRAME_H = 160, 160
FEET_Y = 152
BODY_H = 128
COLS = 4
ROWS = 4


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


def col_boxes(band: Image.Image) -> list:
    w, h = band.size
    px = band.load()
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
    return groups


def frames_of_band(band: Image.Image) -> list:
    boxes = col_boxes(band)
    if len(boxes) != COLS:
        raise SystemExit(f"期望 4 帧，实际 {len(boxes)} 帧：{boxes}")
    out = []
    for x0, x1 in boxes:
        cell = band.crop((x0, 0, x1, band.height))
        out.append(cell.crop(cell.getbbox()))
    return out


def main() -> None:
    rows = []
    sheet = clean_auto(Image.open(SHEET))
    for y0, y1 in row_bands(sheet):
        rows.append(frames_of_band(sheet.crop((0, y0, sheet.width, y1))))
    if len(rows) < ROWS:
        raise SystemExit(f"行走图只有 {len(rows)} 行")

    # 背面 / 朝右两行：优先使用单独生成的方向条，避免镜像与弱动作帧。
    for index, path in ((1, BACK), (3, RIGHT)):
        if not path.exists():
            continue
        strip = clean_auto(Image.open(path))
        bands = row_bands(strip)
        if not bands:
            continue
        try:
            rows[index] = frames_of_band(strip.crop((0, bands[0][0], strip.width, bands[0][1])))
        except SystemExit:
            pass

    sheet_out = Image.new("RGBA", (FRAME_W * COLS, FRAME_H * ROWS), (0, 0, 0, 0))
    for row_index, frames in enumerate(rows[:ROWS]):
        tallest = max(f.height for f in frames)
        scale = BODY_H / float(tallest)
        for col_index, cell in enumerate(frames):
            size = (max(1, round(cell.width * scale)), max(1, round(cell.height * scale)))
            body = cut_transparent(resize_premultiplied(cell, size))
            frame = Image.new("RGBA", (FRAME_W, FRAME_H), (0, 0, 0, 0))
            frame.paste(body, ((FRAME_W - body.width) // 2, FEET_Y - body.height), body)
            sheet_out.paste(frame, (col_index * FRAME_W, row_index * FRAME_H), frame)

    DST.parent.mkdir(parents=True, exist_ok=True)
    sheet_out.save(DST)
    print(f"已保存：{DST.relative_to(ROOT)}  {sheet_out.size[0]}x{sheet_out.size[1]}")


if __name__ == "__main__":
    main()
