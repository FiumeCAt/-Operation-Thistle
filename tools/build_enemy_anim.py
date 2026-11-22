#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把 4 条 image2.5 动作条带拼成 16 帧 Godot 像素图集。

输入：tools/art_sources/enemies_anim/<id>/{alert,attack,move,death}.png
      （每条 4 帧，透明底，正面）
输出：
  assets/art/enemies/<id>_anim_sheet.png    4 行 × 4 列，单元格 640×384
  assets/art/enemies/<id>_anim_sheet.json   动作/帧索引
  assets/art/enemies/<id>_anim_preview.png  带标签检查图

处理流程：
  1. 按空白带切成 4 帧，并清掉 alpha < 24 的浅色晕边；
  2. 预乘 alpha 后 1/3 降采样 → 得到真正的像素级尺寸（避免透明边缘发黑）；
  3. 用全部 16 帧共享的 64 色调色板量化，保证帧间不闪色；
  4. 整数倍 NEAREST 放大并拼进 640×384 单元格，脚底对齐 y=372。

行序：alert / attack / move / death
"""

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "tools" / "art_sources" / "enemies_anim"
OUT = ROOT / "assets" / "art" / "enemies"

CELL_W, CELL_H = 640, 384
TARGET_H = 320
GROUND = 372
PIXEL_DIV = 3
PALETTE_COLORS = 64
ROWS = ["alert", "attack", "move", "death"]
FPS = {"alert": 8, "attack": 10, "move": 7, "death": 8}


def ensure_alpha(image: Image.Image) -> Image.Image:
    arr = np.array(image)
    if arr[:, :, 3].min() < 250:
        return image
    # 兜底：image2.5 偶尔输出不透明底（含伪棋盘格）。
    # 先抠掉浅色中性底（棋盘格两种灰都在 235+），不行再按角落主色抠。
    rgb = image.convert("RGB")
    px = np.array(rgb).astype(np.int16)
    mn = px.min(axis=2)
    mx = px.max(axis=2)
    light_bg = (mn >= 230) & ((mx - mn) <= 14)
    if light_bg.mean() > 0.2:
        alpha = np.where(light_bg, 0, 255).astype(np.uint8)
        out = rgb.convert("RGBA")
        out.putalpha(Image.fromarray(alpha, "L"))
        return out
    bg = rgb.getpixel((0, 0))
    out = Image.new("RGBA", rgb.size)
    op = out.load()
    for y in range(rgb.height):
        for x in range(rgb.width):
            r, g, b = rgb.getpixel((x, y))
            dist = abs(r - bg[0]) + abs(g - bg[1]) + abs(b - bg[2])
            alpha = 0 if dist < 40 else (128 if dist < 80 else 255)
            op[x, y] = (r, g, b, alpha)
    return out


def clean_alpha(image: Image.Image) -> Image.Image:
    arr = np.array(image)
    a = arr[:, :, 3]
    a[a < 24] = 0
    arr[:, :, 3] = a
    return Image.fromarray(arr, "RGBA")


def slice_frames(image: Image.Image, expected: int = 4) -> list:
    """等分切帧，并在分界点附近吸附到最宽空白列，避免把邻帧效果带进来。"""
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
                if x - run_start > best_len:
                    best_len = x - run_start
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
        frames.append(robust_trim(sub.crop(bbox)))
    return frames


def pixel_down(frame: Image.Image):
    """预乘 alpha 后 BOX 降采样，返回 (rgb uint8, alpha 0-1 float)。"""
    arr = np.array(frame).astype(np.float32)
    rgb = arr[:, :, :3]
    a = arr[:, :, 3] / 255.0
    pre = rgb * a[..., None]
    h, w = a.shape
    nh, nw = max(1, h // PIXEL_DIV), max(1, w // PIXEL_DIV)
    pre_img = Image.fromarray(np.clip(pre, 0, 255).astype(np.uint8), "RGB").resize((nw, nh), Image.BOX)
    a_img = Image.fromarray((a * 255.0).astype(np.uint8), "L").resize((nw, nh), Image.BOX)
    p = np.array(pre_img).astype(np.float32)
    aa = np.array(a_img).astype(np.float32) / 255.0
    rgb_out = np.divide(p, aa[..., None], out=np.zeros_like(p), where=aa[..., None] > 0.004)
    return np.clip(rgb_out, 0, 255).astype(np.uint8), aa


def shared_palette(small_frames: list) -> Image.Image:
    pixels = np.concatenate([rgb.reshape(-1, 3) for rgb, _ in small_frames], axis=0)
    strip = Image.fromarray(pixels.reshape(1, -1, 3), "RGB")
    return strip.quantize(colors=PALETTE_COLORS, method=Image.MEDIANCUT)


def quantize_frame(rgb: np.ndarray, alpha: np.ndarray, palette: Image.Image,
                   out_factor: int) -> Image.Image:
    q = Image.fromarray(rgb, "RGB").quantize(palette=palette, dither=Image.Dither.NONE).convert("RGB")
    q = q.resize((rgb.shape[1] * out_factor, rgb.shape[0] * out_factor), Image.NEAREST)
    a = np.clip(alpha * 1.8, 0.0, 1.0)
    a = np.where(a > 0.65, 255, np.where(a > 0.22, 140, 0)).astype(np.uint8)
    a_img = Image.fromarray(a, "L").resize(
        (rgb.shape[1] * out_factor, rgb.shape[0] * out_factor), Image.NEAREST)
    out = q.convert("RGBA")
    out.putalpha(a_img)
    return out.crop(out.getbbox())


def anchor_x(sprite: Image.Image) -> float:
    """取脚部实心区域的横向重心，避免枪口火光/冲锋拖影把整帧推偏。"""
    a = np.array(sprite)[:, :, 3]
    ys, xs = np.where(a > 90)
    if xs.size == 0:
        return sprite.width / 2.0
    y_max = int(ys.max())
    y_min = int(ys.min())
    cut = y_max - max(8, int((y_max - y_min) * 0.18))
    sel = ys >= cut
    return float(xs[sel].mean())


def solid_bottom(sprite: Image.Image) -> int:
    """实心内容的底边；半透明辉光不算脚底，避免爆炸帧浮空。"""
    a = np.array(sprite)[:, :, 3]
    ys, _ = np.where(a > 90)
    if ys.size == 0:
        return sprite.height
    return int(ys.max()) + 1


def robust_trim(frame: Image.Image) -> Image.Image:
    """去掉零散火星/碎片把包围盒撑大的问题：只保留像素足够密的行列。"""
    a = np.array(frame)[:, :, 3]
    mask = a > 24
    h, w = mask.shape
    row_need = max(3, int(w * 0.012))
    col_need = max(3, int(h * 0.012))
    rows = np.where(mask.sum(axis=1) >= row_need)[0]
    cols = np.where(mask.sum(axis=0) >= col_need)[0]
    if rows.size == 0 or cols.size == 0:
        return frame
    return frame.crop((int(cols.min()), int(rows.min()),
                       int(cols.max()) + 1, int(rows.max()) + 1))


def build(enemy_id: str) -> int:
    rows = {}
    for state in ROWS:
        path = SRC / enemy_id / (state + ".png")
        if not path.exists():
            raise FileNotFoundError(path)
        image = clean_alpha(ensure_alpha(Image.open(path).convert("RGBA")))
        rows[state] = slice_frames(image)
        print("[%s] %s frames: %s" % (
            enemy_id, state, [f.size for f in rows[state]]))

    small = {}
    for state, group in rows.items():
        small[state] = [pixel_down(f) for f in group]
    palette = shared_palette([pair for group in small.values() for pair in group])

    # 统一 2× 放大：所有敌人的像素块密度一致，体型差异由原始身高自然体现。
    body_h = sorted(rgb.shape[0] for state in ("move", "alert") for rgb, _ in small[state])
    med_h = float(body_h[(len(body_h) - 1) // 2])
    out_factor = 2
    print("[%s] pixel_h=%.0f out_factor=%d" % (enemy_id, med_h, out_factor))

    atlas = Image.new("RGBA", (CELL_W * 4, CELL_H * len(ROWS)), (0, 0, 0, 0))
    for ri, state in enumerate(ROWS):
        for ci, (rgb, alpha) in enumerate(small[state]):
            sprite = quantize_frame(rgb, alpha, palette, out_factor)
            # 大爆炸帧可能高过单元格：等比缩进单元格，避免被裁掉。
            max_h = GROUND - 8
            if sprite.height > max_h:
                ratio = max_h / float(sprite.height)
                sprite = sprite.resize(
                    (max(1, int(round(sprite.width * ratio))), max_h), Image.NEAREST)
            if sprite.width > CELL_W - 8:
                sprite = sprite.resize((CELL_W - 8, int(sprite.height * (CELL_W - 8) / sprite.width)),
                                       Image.NEAREST)
            cell = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
            px = int(round(CELL_W / 2.0 - anchor_x(sprite)))
            px = max(0, min(CELL_W - sprite.width, px))
            py = max(8, GROUND - solid_bottom(sprite))
            cell.alpha_composite(sprite, (px, py))
            atlas.alpha_composite(cell, (ci * CELL_W, ri * CELL_H))

    OUT.mkdir(parents=True, exist_ok=True)
    sheet = OUT / (enemy_id + "_anim_sheet.png")
    atlas.save(sheet)
    meta = {
        "id": enemy_id,
        "cell": [CELL_W, CELL_H],
        "rows": len(ROWS),
        "columns": 4,
        "ground": GROUND,
        "facing": "front (mirror on X for left/right)",
        "animations": {
            state: {"row": ri, "frames": 4, "fps": FPS[state]}
            for ri, state in enumerate(ROWS)
        },
    }
    (OUT / (enemy_id + "_anim_sheet.json")).write_text(
        json.dumps(meta, ensure_ascii=False, indent=2), encoding="utf-8")
    build_preview(enemy_id, atlas)
    print("[%s] -> %s" % (enemy_id, sheet))
    return 0


def build_preview(enemy_id: str, atlas: Image.Image) -> None:
    scale = 0.42
    cw, ch = int(CELL_W * scale), int(CELL_H * scale)
    label_w = 90
    header_h = 24
    preview = Image.new("RGB", (label_w + cw * 4, header_h + ch * len(ROWS)), (22, 20, 18))
    draw = ImageDraw.Draw(preview)
    for ci in range(4):
        draw.text((label_w + ci * cw + 8, 6), "FRAME %d" % (ci + 1), fill=(255, 196, 90))
    for ri, state in enumerate(ROWS):
        y = header_h + ri * ch
        draw.text((6, y + ch // 2 - 6), state.upper(), fill=(205, 205, 205))
        for ci in range(4):
            cell = atlas.crop((ci * CELL_W, ri * CELL_H,
                               (ci + 1) * CELL_W, (ri + 1) * CELL_H))
            cell = cell.resize((cw, ch), Image.LANCZOS)
            preview.paste(cell, (label_w + ci * cw, y), cell)
        draw.line([(0, y), (preview.width, y)], fill=(60, 55, 50))
    preview.save(OUT / (enemy_id + "_anim_preview.png"))


def main() -> int:
    ids = sys.argv[1:]
    if not ids:
        print("用法：python tools/build_enemy_anim.py <enemy_id> [...]")
        return 1
    fails = 0
    for enemy_id in ids:
        try:
            build(enemy_id)
        except Exception as exc:  # noqa: BLE001
            fails += 1
            print("[fail] %s: %s" % (enemy_id, exc))
    return 0 if fails == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
