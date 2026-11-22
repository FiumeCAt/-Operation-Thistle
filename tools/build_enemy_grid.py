#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把 Seedream 5.5 生成的 4×4 像素图集切成游戏用 16 帧图集。

输入：tools/art_sources/enemies_sprites/<id>/sheet_raw.png
      （4 行 × 4 列，行=朝向，列=发现/行走A/行走B/攻击，透明底）
输出：
  assets/art/enemies/<id>_sheet.png    4 行 × 4 列，单元格 640×384
  assets/art/enemies/<id>_sheet.json   方向/动作索引
  assets/art/enemies/<id>_preview.png  带标签检查图

行序：down / left / right / up
列序：0 发现 alert · 1 行走 A · 2 行走 B · 3 攻击 attack
像素画缩放用 NEAREST，保持硬边像素；脚底对齐 GROUND。
"""

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "tools" / "art_sources" / "enemies_sprites"
OUT = ROOT / "assets" / "art" / "enemies"

CELL_W, CELL_H = 640, 384
FIT_W, FIT_H = 600, 340
TARGET_H = 320
GROUND = 372
DIRS = ["down", "left", "right", "up"]
COLS = ["alert", "walk_a", "walk_b", "attack"]


def ensure_alpha(image: Image.Image) -> Image.Image:
    """Seedream 通常直接给透明底；若整幅不透明则按品红/白底抠像兜底。"""
    arr = np.array(image)
    if arr[:, :, 3].min() < 250:
        return image
    rgb = image.convert("RGB")
    px = rgb.load()
    out = Image.new("RGBA", rgb.size)
    op = out.load()
    for y in range(rgb.height):
        for x in range(rgb.width):
            r, g, b = px[x, y]
            score = min(r, b) - g
            if score >= 60:
                alpha = 0
            elif score <= 15:
                alpha = 255
            else:
                alpha = int(255 * (60 - score) / 45)
            op[x, y] = (r, g, b, alpha)
    return out


def slice_grid(image: Image.Image) -> list:
    """4×4 等分，每格裁到内容包围盒；返回 16 个 RGBA 帧（行优先）。"""
    w, h = image.size
    frames = []
    for row in range(4):
        for col in range(4):
            cell = image.crop((
                col * w // 4, row * h // 4,
                (col + 1) * w // 4, (row + 1) * h // 4,
            ))
            bbox = cell.getbbox()
            if bbox is None:
                raise ValueError("第 %d 行第 %d 列为空" % (row + 1, col + 1))
            frames.append(cell.crop(bbox))
    return frames


def build(enemy_id: str) -> int:
    raw = SRC / enemy_id / "sheet_raw.png"
    if not raw.exists():
        raise FileNotFoundError(raw)
    image = ensure_alpha(Image.open(raw).convert("RGBA"))
    frames = slice_grid(image)

    # 用行走两列（16 帧中的索引 1、2）的中位高度定统一比例，发现/攻击动作随之对齐。
    walk_heights = sorted(
        frames[row * 4 + col].height for row in range(4) for col in (1, 2)
    )
    base = float(walk_heights[(len(walk_heights) - 1) // 2])
    scale = min(TARGET_H / base, FIT_W / max(f.width for f in frames))
    print("[%s] walk_h=%.0f scale=%.3f" % (enemy_id, base, scale))

    atlas = Image.new("RGBA", (CELL_W * 4, CELL_H * 4), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        row, col = divmod(index, 4)
        w = max(1, int(round(frame.width * scale)))
        h = max(1, int(round(frame.height * scale)))
        sprite = frame.resize((w, h), Image.NEAREST)
        cell = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
        cell.alpha_composite(sprite, ((CELL_W - w) // 2, GROUND - h))
        atlas.alpha_composite(cell, (col * CELL_W, row * CELL_H))

    OUT.mkdir(parents=True, exist_ok=True)
    atlas.save(OUT / (enemy_id + "_sheet.png"))
    meta = {
        "id": enemy_id,
        "cell": [CELL_W, CELL_H],
        "rows": 4,
        "columns": 4,
        "ground": GROUND,
        "dirs": {name: i for i, name in enumerate(DIRS)},
        "columns_map": {name: i for i, name in enumerate(COLS)},
        "animations": {
            "alert": {"column": 0, "frames": 1, "fps": 1},
            "walk": {"columns": [1, 2], "frames": 2, "fps": 6},
            "attack": {"column": 3, "frames": 1, "fps": 1},
        },
    }
    (OUT / (enemy_id + "_sheet.json")).write_text(
        json.dumps(meta, ensure_ascii=False, indent=2), encoding="utf-8")
    build_preview(enemy_id, atlas)
    print("[%s] -> %s" % (enemy_id, OUT / (enemy_id + "_sheet.png")))
    return 0


def build_preview(enemy_id: str, atlas: Image.Image) -> None:
    scale = 0.44
    cw, ch = int(CELL_W * scale), int(CELL_H * scale)
    label_w = 96
    header_h = 26
    preview = Image.new("RGB", (label_w + cw * 4, header_h + ch * 4), (22, 20, 18))
    draw = ImageDraw.Draw(preview)
    for ci, name in enumerate(COLS):
        draw.text((label_w + ci * cw + 8, 7), name.upper(), fill=(255, 196, 90))
    for ri, name in enumerate(DIRS):
        y = header_h + ri * ch
        draw.text((6, y + ch // 2 - 6), name.upper(), fill=(205, 205, 205))
        for ci in range(4):
            cell = atlas.crop((ci * CELL_W, ri * CELL_H,
                               (ci + 1) * CELL_W, (ri + 1) * CELL_H))
            cell = cell.resize((cw, ch), Image.LANCZOS)
            preview.paste(cell, (label_w + ci * cw, y), cell)
        draw.line([(0, y), (preview.width, y)], fill=(60, 55, 50))
    preview.save(OUT / (enemy_id + "_preview.png"))


def main() -> int:
    ids = sys.argv[1:]
    if not ids:
        print("用法：python tools/build_enemy_grid.py <enemy_id> [...]")
        return 1
    for enemy_id in ids:
        try:
            build(enemy_id)
        except Exception as exc:  # noqa: BLE001
            print("[fail] %s: %s" % (enemy_id, exc))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
