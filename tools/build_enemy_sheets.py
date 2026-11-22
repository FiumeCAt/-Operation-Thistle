#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把 gen_enemy_sheets.py 生成的品红条带切成游戏可用四向图集。

输入：tools/art_sources/enemies_sprites/<id>/{down,left,up}_{walk,attack,alert}_raw.png
输出：
  assets/art/enemies/<id>_sheet.png    12 行 × 4 列图集（行=状态×方向，列=帧）
  assets/art/enemies/<id>_sheet.json   动画元数据
  assets/art/enemies/<id>_preview.png  带标签的检查图
  assets/art/enemies/<id>_walk.gif     四向行走循环预览

行序（每状态 4 行，方向序 down / left / right / up）：
  walk   0-3  （4 帧）
  attack 4-7  （3 帧）
  alert  8-11 （1 帧）
方向 right 由 left 镜像得到。所有帧共享同一缩放，脚底对齐 GROUND 基线。
"""

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "tools" / "art_sources" / "enemies_sprites"
OUT = ROOT / "assets" / "art" / "enemies"

CELL_W, CELL_H = 512, 384
FIT_W, FIT_H = 480, 340
TARGET_H = 320
GROUND = 372

STATES = ["walk", "attack", "alert"]
STATE_FRAMES = {"walk": 4, "attack": 3, "alert": 1}
DIRS = ["down", "left", "right", "up"]
SOURCE_VIEWS = ["down", "left", "up"]


def key_magenta(path: Path) -> Image.Image:
    src = Image.open(path).convert("RGB")
    px = src.load()
    out = Image.new("RGBA", src.size)
    op = out.load()
    for y in range(src.height):
        for x in range(src.width):
            r, g, b = px[x, y]
            score = min(r, b) - g
            if score >= 60:
                alpha = 0
            elif score <= 15:
                alpha = 255
            else:
                alpha = int(255 * (60 - score) / 45)
            if alpha and score > 12:
                r = min(r, g + 24)
                b = min(b, g + 24)
            op[x, y] = (r, g, b, alpha)
    return out


def slice_frames(image: Image.Image, expected: int) -> list:
    """按内容包围盒等分切帧，并在等分点附近吸附到最宽的空白列。

    等分比「按空白列分段」稳：机器人抬起的爪子/火花可能和身体断开，
    会被误判成额外帧；但模型排版不绝对均匀，纯等分又会把邻帧的火花带进来，
    所以在理论分界点 ±18% 槽宽内找最宽空白带作为实际分界。
    """
    alpha = np.array(image.getchannel("A"))
    ys, xs = np.where(alpha > 16)
    if xs.size == 0:
        raise ValueError("条带为空")
    x0, x1 = int(xs.min()), int(xs.max()) + 1
    filled = (alpha > 16).any(axis=0)
    slot = (x1 - x0) / float(expected)
    bounds = [x0]
    for i in range(1, expected):
        target = x0 + int(round(slot * i))
        radius = max(8, int(slot * 0.18))
        lo = max(bounds[-1] + 4, target - radius)
        hi = min(x1 - 4, target + radius)
        best_len = 0
        best_center = target
        run_start = None
        for x in range(lo, hi + 1):
            if not filled[x]:
                if run_start is None:
                    run_start = x
            elif run_start is not None:
                length = x - run_start
                if length > best_len:
                    best_len = length
                    best_center = (run_start + x) // 2
                run_start = None
        if run_start is not None and (hi + 1 - run_start) > best_len:
            best_center = (run_start + hi + 1) // 2
        bounds.append(max(bounds[-1] + 1, best_center))
    bounds.append(x1)

    frames = []
    for a, b in zip(bounds, bounds[1:]):
        sub = image.crop((a, 0, b, image.height))
        bbox = sub.getbbox()
        if bbox is None or bbox[2] - bbox[0] < 8 or bbox[3] - bbox[1] < 8:
            raise ValueError("切帧异常：空槽位")
        frames.append(sub.crop(bbox))
    return frames


def load_view(enemy_id: str, view: str, state: str) -> list:
    path = SRC / enemy_id / ("%s_%s_raw.png" % (view, state))
    if not path.exists():
        raise FileNotFoundError(path)
    image = key_magenta(path)
    if state == "alert":
        bbox = image.getbbox()
        if bbox is None:
            raise ValueError("空图：" + path.name)
        return [image.crop(bbox)]
    return slice_frames(image, STATE_FRAMES[state])


def flip(frame: Image.Image) -> Image.Image:
    return frame.transpose(Image.Transpose.FLIP_LEFT_RIGHT)


def build(enemy_id: str) -> int:
    frames = {}
    for view in SOURCE_VIEWS:
        for state in STATES:
            frames[(view, state)] = load_view(enemy_id, view, state)
    for state in STATES:
        frames[("right", state)] = [flip(f) for f in frames[("left", state)]]

    # 同一组（视角+状态）内统一缩放：以该组中位高度对齐 TARGET_H，
    # 避免单帧大图（如 1254 的 alert 立绘）把整张图集压小，也避免枪口火光把机身缩小。
    for key, group in frames.items():
        heights = sorted(f.height for f in group)
        base = float(heights[(len(heights) - 1) // 2])
        factor = TARGET_H / base
        frames[key] = [
            f.resize((max(1, int(round(f.width * factor))),
                      max(1, int(round(f.height * factor)))), Image.LANCZOS)
            for f in group
        ]

    all_frames = [f for group in frames.values() for f in group]
    max_h = max(f.height for f in all_frames)
    max_w = max(f.width for f in all_frames)
    scale = min(1.0, FIT_H / max_h, FIT_W / max_w)
    print("[%s] frames=%d max=%dx%d scale=%.3f" % (
        enemy_id, len(all_frames), max_w, max_h, scale))

    placed = {}
    for key, group in frames.items():
        cells = []
        for frame in group:
            w = max(1, int(round(frame.width * scale)))
            h = max(1, int(round(frame.height * scale)))
            resized = frame.resize((w, h), Image.LANCZOS)
            cell = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
            cell.alpha_composite(resized, ((CELL_W - w) // 2, GROUND - h))
            cells.append(cell)
        placed[key] = cells

    cols = STATE_FRAMES["walk"]
    rows = len(STATES) * len(DIRS)
    atlas = Image.new("RGBA", (CELL_W * cols, CELL_H * rows), (0, 0, 0, 0))
    meta_rows = {}
    for si, state in enumerate(STATES):
        for di, dir_name in enumerate(DIRS):
            row = si * len(DIRS) + di
            meta_rows["%s_%s" % (state, dir_name)] = row
            for fi, cell in enumerate(placed[(dir_name, state)]):
                atlas.alpha_composite(cell, (fi * CELL_W, row * CELL_H))
    OUT.mkdir(parents=True, exist_ok=True)
    sheet_path = OUT / (enemy_id + "_sheet.png")
    atlas.save(sheet_path)

    meta = {
        "id": enemy_id,
        "cell": [CELL_W, CELL_H],
        "columns": cols,
        "rows": rows,
        "ground": GROUND,
        "animations": {
            state: {
                "row_start": si * len(DIRS),
                "frames": STATE_FRAMES[state],
                "fps": {"walk": 8, "attack": 10, "alert": 1}[state],
                "dirs": {d: si * len(DIRS) + di for di, d in enumerate(DIRS)},
            }
            for si, state in enumerate(STATES)
        },
    }
    (OUT / (enemy_id + "_sheet.json")).write_text(
        json.dumps(meta, ensure_ascii=False, indent=2), encoding="utf-8")

    build_preview(enemy_id, atlas)
    build_gif(enemy_id, placed)
    print("[%s] -> %s" % (enemy_id, sheet_path))
    return 0


def build_preview(enemy_id: str, atlas: Image.Image) -> None:
    scale = 0.4
    cw, ch = int(CELL_W * scale), int(CELL_H * scale)
    label_w = 110
    header_h = 24
    preview = Image.new("RGB", (label_w + cw * 4, header_h + ch * 12), (22, 20, 18))
    draw = ImageDraw.Draw(preview)
    for fi in range(4):
        draw.text((label_w + fi * cw + 8, 6), "FRAME %d" % (fi + 1), fill=(255, 196, 90))
    for si, state in enumerate(STATES):
        for di, dir_name in enumerate(DIRS):
            row = si * 4 + di
            y = header_h + row * ch
            draw.text((6, y + ch // 2 - 6), "%s %s" % (state.upper(), dir_name.upper()),
                      fill=(200, 200, 200))
            for fi in range(4):
                cell = atlas.crop((fi * CELL_W, row * CELL_H,
                                   (fi + 1) * CELL_W, (row + 1) * CELL_H))
                cell = cell.resize((cw, ch), Image.LANCZOS)
                preview.paste(cell, (label_w + fi * cw, y), cell)
            draw.line([(0, y), (preview.width, y)], fill=(60, 55, 50))
    preview.save(OUT / (enemy_id + "_preview.png"))


def build_gif(enemy_id: str, placed: dict) -> None:
    w, h = CELL_W // 2, CELL_H // 2
    gif_frames = []
    for frame_index in range(4):
        canvas = Image.new("RGB", (CELL_W, CELL_H), (22, 20, 18))
        for i, dir_name in enumerate(["down", "left", "right", "up"]):
            sprite = placed[(dir_name, "walk")][frame_index].resize((w, h), Image.LANCZOS)
            canvas.paste(sprite, ((i % 2) * w, (i // 2) * h), sprite)
        gif_frames.append(canvas)
    gif_frames[0].save(OUT / (enemy_id + "_walk.gif"), save_all=True,
                       append_images=gif_frames[1:], duration=120, loop=0)


def main() -> int:
    ids = sys.argv[1:]
    if not ids:
        ids = sorted(p.name for p in SRC.iterdir() if p.is_dir() and p.name != "refs")
    for enemy_id in ids:
        try:
            build(enemy_id)
        except FileNotFoundError as exc:
            print("[skip] %s 缺少素材：%s" % (enemy_id, exc))
        except Exception as exc:  # noqa: BLE001
            print("[fail] %s: %s" % (enemy_id, exc))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
