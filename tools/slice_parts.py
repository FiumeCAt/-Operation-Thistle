#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把 image2.5 生成的 4x2 部件图切成独立零件，供模块化骨架使用。

部件图里相邻零件的内容容易越过格子边界，所以这里做了两步清理：
  1. 每个格子先向内收一点边，切掉邻格溢出；
  2. 只保留最大的连通块（以及面积 >= 其 15% 的伴随块），去掉零散残片。

用法：python tools/slice_parts.py <部件图.png> <输出子目录名>
输出：assets/art/characters/doll_b/parts/<子目录>/*.png
"""

import sys
from collections import deque
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))

from sprite_utils import clean_auto

ROOT = Path(__file__).resolve().parents[1]
OUT_ROOT = ROOT / "assets/art/characters/doll_b/parts"
NAMES = ["head_front", "head_back", "head_left", "head_right", "torso", "arm", "leg", "case"]
COLS = 4
ROWS = 2
INSET = 8
KEEP_RATIO = 0.15


def blobs(image: Image.Image) -> list:
    """返回所有连通块的像素坐标集合（4 邻域）。"""
    mask = image.getchannel("A").point(lambda a: 255 if a > 8 else 0)
    w, h = mask.size
    px = mask.load()
    seen = bytearray(w * h)
    found = []
    for y in range(h):
        for x in range(w):
            index = y * w + x
            if seen[index] or px[x, y] == 0:
                continue
            queue = deque([(x, y)])
            seen[index] = 1
            pixels = []
            while queue:
                cx, cy = queue.popleft()
                pixels.append((cx, cy))
                for nx, ny in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
                    if 0 <= nx < w and 0 <= ny < h:
                        ni = ny * w + nx
                        if not seen[ni] and px[nx, ny] != 0:
                            seen[ni] = 1
                            queue.append((nx, ny))
            found.append(pixels)
    return found


def keep_main_blobs(cell: Image.Image) -> Image.Image:
    pieces = blobs(cell)
    if not pieces:
        return cell
    pieces.sort(key=len, reverse=True)
    biggest = len(pieces[0])
    keep = [p for p in pieces if len(p) >= biggest * KEEP_RATIO]
    mask = Image.new("L", cell.size, 0)
    mpx = mask.load()
    for piece in keep:
        for x, y in piece:
            mpx[x, y] = 255
    cleaned = cell.copy()
    cleaned.putalpha(Image.composite(cell.getchannel("A"), Image.new("L", cell.size, 0), mask))
    return cleaned


def main() -> None:
    if len(sys.argv) < 3:
        raise SystemExit("用法：slice_parts.py <部件图.png> <输出子目录名>")
    sheet_path = Path(sys.argv[1])
    target = OUT_ROOT / sys.argv[2]
    target.mkdir(parents=True, exist_ok=True)

    sheet = clean_auto(Image.open(sheet_path))
    cell_w, cell_h = sheet.width // COLS, sheet.height // ROWS
    for index, name in enumerate(NAMES):
        row, col = divmod(index, COLS)
        left = col * cell_w + INSET
        top = row * cell_h + INSET
        right = (col + 1) * cell_w - INSET
        bottom = (row + 1) * cell_h - INSET
        cell = keep_main_blobs(sheet.crop((left, top, right, bottom)))
        bbox = cell.getbbox()
        if bbox is None:
            raise SystemExit(f"{name} 对应的格子是空的，检查部件图布局")
        part = cell.crop(bbox)
        part.save(target / f"{name}.png")
        print(f"{name:12s} {part.size[0]}x{part.size[1]}  宽高比 {part.width / part.height:.2f}")


if __name__ == "__main__":
    main()
