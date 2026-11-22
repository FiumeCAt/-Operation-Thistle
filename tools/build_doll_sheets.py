#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把 image2.5 生成的站立 / 行走 / 跑步素材拼成统一风格的 12 行图集（只出 1024 档）。

行布局（每行 4 帧）：
  0-3   站立 idle_0..3（下 / 上 / 左 / 右，单帧重复 4 列）
  4-7   行走 walk_0..3
  8-11  跑步 run_0..3

为保证三套动作风格与尺寸统一，这里做两件事：
  1. 用站立图作为调色板来源，把所有帧重新映射到同一套颜色，避免跑步偏蓝等色差；
  2. 每套动作用「正面那一行」的身高算统一缩放，四个方向共用同一比例，
     不会出现侧向视图被缩得更小的情况。

输出：assets/art/characters/doll_b/lod/doll_lod_1024.png
"""

import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))

import build_doll_lods as base
from sprite_utils import clean_auto, cut_transparent, resize_premultiplied

ROOT = Path(__file__).resolve().parents[1]
CHAR = ROOT / "assets/art/characters/doll_b"
IDLE = CHAR / "flat_idle.png"
if not IDLE.exists():
    IDLE = CHAR / "idle_unified.png"
if not IDLE.exists():
    IDLE = CHAR / "idle_sheet_magenta.png"
# 平涂硬边版优先；没有则退回早期版本，仍然保持同一套色与比例。
WALK = CHAR / "flat_walk.png"
if not WALK.exists():
    WALK = CHAR / "walk_unified.png"
if not WALK.exists():
    WALK = CHAR / "walk_sheet_magenta.png"
RUN = CHAR / "flat_run.png"
if not RUN.exists():
    RUN = CHAR / "run_unified.png"
if not RUN.exists():
    RUN = CHAR / "run_sheet_magenta.png"
OUT_DIR = CHAR / "lod"

COLS = 4
## 1024 为母版尺寸；游戏内在用的 256 由同一母版按同一比例导出（避免 300MB 显存）。
BODY_SIZES = [1024, 256]
PALETTE_COLORS = 40


def strip_frames(path: Path) -> list:
    strip = clean_auto(Image.open(path))
    bands = base.row_bands(strip)
    if not bands:
        raise SystemExit(f"素材没有内容：{path.name}")
    return base.frames_of_band(strip.crop((0, bands[0][0], strip.width, bands[0][1])))


def sheet_rows(path: Path) -> list:
    sheet = clean_auto(Image.open(path))
    rows = [base.frames_of_band(sheet.crop((0, y0, sheet.width, y1))) for y0, y1 in base.row_bands(sheet)]
    if len(rows) != 4:
        raise SystemExit(f"{path.name} 应有 4 行，实际 {len(rows)} 行")
    return rows


def idle_rows(path: Path) -> list:
    sheet = clean_auto(Image.open(path))
    bands = base.row_bands(sheet)
    views = base.frames_of_band(sheet.crop((0, bands[0][0], sheet.width, bands[0][1])))
    return [[view] * COLS for view in views]


def mean_color(frame: Image.Image) -> list:
    """角色不透明像素的平均 RGB。"""
    alpha = frame.getchannel("A")
    mask = alpha.point(lambda a: 255 if a > 200 else 0)
    total = [0.0, 0.0, 0.0]
    count = 0
    pixels = frame.convert("RGB").load()
    mask_pixels = mask.load()
    for y in range(frame.height):
        for x in range(frame.width):
            if mask_pixels[x, y]:
                r, g, b = pixels[x, y]
                total[0] += r
                total[1] += g
                total[2] += b
                count += 1
    if not count:
        return [0.0, 0.0, 0.0]
    return [value / count for value in total]


def normalize_tone(rows: list, target: list) -> list:
    """把每一帧的整体色调拉回同一条基准线，消除不同批次越来越偏蓝的问题。"""
    out = []
    for row in rows:
        new_row = []
        for frame in row:
            current = mean_color(frame)
            gains = []
            for index in range(3):
                if current[index] < 1.0:
                    gains.append(1.0)
                else:
                    gains.append(min(1.3, max(0.75, target[index] / current[index])))
            r, g, b, a = frame.split()
            r = r.point(lambda v: min(255, round(v * gains[0])))
            g = g.point(lambda v: min(255, round(v * gains[1])))
            b = b.point(lambda v: min(255, round(v * gains[2])))
            new_row.append(Image.merge("RGBA", (r, g, b, a)))
        out.append(new_row)
    return out


def build_palette(rows: list) -> Image.Image:
    """用所有帧拼一张缩略图来生成共用调色板，避免偏向某一批素材。"""
    frames = [frame for row in rows for frame in row]
    width = sum(32 for _ in frames)
    montage = Image.new("RGB", (width, 32), (255, 0, 255))
    offset = 0
    for frame in frames:
        thumb = frame.resize((32, 32), Image.NEAREST)
        montage.paste(thumb.convert("RGB"), (offset, 0))
        offset += 32
    return montage.quantize(colors=PALETTE_COLORS, method=Image.MEDIANCUT)


def unify_palette(rows: list, palette: Image.Image) -> list:
    out = []
    for row in rows:
        new_row = []
        for frame in row:
            alpha = frame.getchannel("A")
            quantized = frame.convert("RGB").quantize(palette=palette, dither=Image.Dither.NONE).convert("RGB")
            quantized.putalpha(alpha)
            new_row.append(quantized)
        out.append(new_row)
    return out


def collect_rows() -> list:
    idle = idle_rows(IDLE)
    walk = sheet_rows(WALK)
    run = sheet_rows(RUN) if RUN.exists() else walk

    rows = idle + walk + run
    # 三批素材整体平均色分别是 B=93 / 107 / 121，越生成越蓝；
    # 这里统一把色调拉回站立图的基准，再映射到一张由全部帧生成的共用调色板。
    target = mean_color(rows[0][0])
    # 站立图本身仍偏蓝，再把蓝色通道压 10%，让角色靠近原设定的蓝灰而不是纯蓝。
    target[2] *= 0.9
    rows = normalize_tone(rows, target)
    rows = unify_palette(rows, build_palette(rows))
    if len(rows) != 12:
        raise SystemExit(f"图集行数应为 12，实际 {len(rows)}")
    return rows


def median_height(frames: list) -> float:
    heights = sorted(f.height for f in frames)
    return float(heights[len(heights) // 2])


def export(rows: list, body_px: int) -> None:
    frame = int(round(body_px * 1.25))
    feet = int(round(frame * base.FEET_RATIO))
    # 每套动作（4 行一组）用正面行算统一缩放，四个方向共用同一比例。
    scales = []
    for block in range(len(rows) // 4):
        scales.append(body_px / median_height(rows[block * 4]))

    sheet_out = Image.new("RGBA", (frame * COLS, frame * len(rows)), (0, 0, 0, 0))
    for row_index, frames in enumerate(rows):
        scale = scales[row_index // 4]
        for col_index, cell in enumerate(frames):
            size = (max(1, round(cell.width * scale)), max(1, round(cell.height * scale)))
            # 像素画用最近邻，保证每个源像素是一块实色，不会被双线性/Lanczos 糊成渐变。
            body = cut_transparent(cell.resize(size, Image.NEAREST))
            canvas = Image.new("RGBA", (frame, frame), (0, 0, 0, 0))
            canvas.paste(body, ((frame - body.width) // 2, feet - body.height), body)
            sheet_out.paste(canvas, (col_index * frame, row_index * frame), canvas)

    path = OUT_DIR / f"doll_lod_{body_px}.png"
    path.parent.mkdir(parents=True, exist_ok=True)
    sheet_out.save(path)
    print(f"{path.relative_to(ROOT)}  {sheet_out.size[0]}x{sheet_out.size[1]}  frame={frame}")
    for index, scale in enumerate(scales):
        print(f"  block {index}: scale={scale:.4f}")


def main() -> None:
    rows = collect_rows()
    for body_px in BODY_SIZES:
        export(rows, body_px)


if __name__ == "__main__":
    main()
