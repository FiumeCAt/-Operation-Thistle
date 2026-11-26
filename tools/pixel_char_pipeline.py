#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Phase 7A/7B Seedream 5.5 高清母版 → 规范像素角色管线（网格下采样 + 锁定色板量化 + 轮廓清理）。

设计约束（严禁文生图直接吐 64 帧序列图导致闪烁与比例漂移）：
  1. 由 Seedream 5.5 基于参考图生成高清母版（1024–2048px 四视图或单动作关键帧）；
  2. 通过本脚本对整套帧统一提取“全局锁定色板”，确保帧与帧之间色彩零漂移；
  3. 仅支持锁死的单一目标像素规格输出：
       - `64`  （单帧 80×80，世界内 ×2 整数放大 → 128px 身高，纯正复古像素颗粒感）
       - `128` （单帧 160×160，世界内 1:1 渲染 → 128px 身高，高精战术像素、与现有 128px 敌人/武器同密）
  4. 强制硬透明阈值（alpha >= 136 → 255，其余 → 0），杜绝半透明脏边；
  5. 可选 1px 选择性暗色轮廓（sel-out），在深灰战术水泥地面与视野迷雾下保持清晰剪影。

示例：
  # 从现有 256/1024 图集生成 64px×2 与 128px×1 同屏对比验证图集
  python tools/pixel_char_pipeline.py --sheet assets/art/characters/doll_b/lod/doll_lod_256.png \\
      --cols 4 --rows 16 --targets 64 128 --out-dir assets/art/characters/doll_b/lod

  # Phase 7B：把单张 Seedream 5.5 高清角色帧（透明底或白/品红底）规范化为单帧像素图
  python tools/pixel_char_pipeline.py --single path/to/seedream_front.png \\
      --body-px 128 --colors 48 --outline --out out/preview_128.png
"""

from __future__ import annotations

import argparse
from pathlib import Path
from typing import Iterable

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
FEET_RATIO = 0.95


def premul_box_resize(img: Image.Image, target_size: tuple[int, int]) -> Image.Image:
    """Premultiplied-alpha BOX/LANCZOS downsample to prevent dark/white fringe halos."""
    rgba = np.asarray(img.convert("RGBA"), dtype=np.float32)
    a = rgba[:, :, 3:4] / 255.0
    rgb_pm = rgba[:, :, :3] * a
    pm_img = Image.fromarray(
        np.concatenate([np.clip(rgb_pm, 0, 255), rgba[:, :, 3:4]], axis=2).astype(np.uint8),
        mode="RGBA",
    )
    resized = pm_img.resize(target_size, Image.Resampling.BOX if target_size[0] <= img.width // 2 else Image.Resampling.LANCZOS)
    arr = np.asarray(resized, dtype=np.float32)
    ra = arr[:, :, 3:4] / 255.0
    safe_a = np.where(ra > 1e-4, ra, 1.0)
    rgb = np.where(ra > 1e-4, arr[:, :, :3] / safe_a, 0.0)
    out = np.concatenate([np.clip(rgb, 0, 255), arr[:, :, 3:4]], axis=2).astype(np.uint8)
    return Image.fromarray(out, mode="RGBA")


def harden_alpha(img: Image.Image, threshold: int = 132) -> Image.Image:
    """Snap alpha to strict 0 or 255 so pixel art never has blurry semi-transparent edges."""
    arr = np.asarray(img.convert("RGBA"), dtype=np.uint8).copy()
    mask = arr[:, :, 3] >= threshold
    arr[~mask] = 0
    arr[mask, 3] = 255
    return Image.fromarray(arr, mode="RGBA")


def remove_isolated_pixels(img: Image.Image) -> Image.Image:
    """Remove 1px stray alpha dust with zero 4-connected neighbors."""
    arr = np.asarray(img.convert("RGBA"), dtype=np.uint8).copy()
    opaque = arr[:, :, 3] > 0
    h, w = opaque.shape
    neighbors = np.zeros((h, w), dtype=np.int32)
    neighbors[1:, :] += opaque[:-1, :]
    neighbors[:-1, :] += opaque[1:, :]
    neighbors[:, 1:] += opaque[:, :-1]
    neighbors[:, :-1] += opaque[:, 1:]
    dust = opaque & (neighbors == 0)
    arr[dust] = 0
    return Image.fromarray(arr, mode="RGBA")


def build_locked_palette(images: Iterable[Image.Image], max_colors: int) -> np.ndarray:
    """Extract a single shared RGB palette across all frames to prevent inter-frame color flicker."""
    samples = []
    for im in images:
        arr = np.asarray(im.convert("RGBA"), dtype=np.uint8)
        rgb = arr[arr[:, :, 3] >= 128][:, :3]
        if len(rgb) > 0:
            samples.append(rgb)
    if not samples:
        return np.array([[24, 26, 36]], dtype=np.uint8)
    all_rgb = np.concatenate(samples, axis=0)
    # Build a compact strip image for Pillow's median-cut quantizer
    step = max(1, len(all_rgb) // 65536)
    sub = all_rgb[::step]
    side = int(np.ceil(np.sqrt(len(sub))))
    padded = np.zeros((side * side, 3), dtype=np.uint8)
    padded[: len(sub)] = sub
    strip = Image.fromarray(padded.reshape(side, side, 3), mode="RGB")
    q = strip.quantize(colors=max_colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    pal_raw = q.getpalette()[: max_colors * 3]
    pal = np.array(pal_raw, dtype=np.uint8).reshape(-1, 3)
    return pal


def apply_palette(img: Image.Image, palette: np.ndarray) -> Image.Image:
    """Map every opaque pixel to its nearest color in the locked palette (perceptual RGB weights)."""
    arr = np.asarray(img.convert("RGBA"), dtype=np.uint8).copy()
    mask = arr[:, :, 3] > 0
    if not np.any(mask):
        return img
    pixels = arr[mask][:, :3].astype(np.float32)
    pal = palette.astype(np.float32)
    # Perceptual luminance-weighted Euclidean distance (Redmean approximation)
    weights = np.array([2.0, 4.0, 3.0], dtype=np.float32)
    # Process in chunks to keep RAM tiny
    nearest = np.empty(len(pixels), dtype=np.int32)
    chunk = 8192
    for i in range(0, len(pixels), chunk):
        p = pixels[i : i + chunk, None, :]  # (C, 1, 3)
        diff = (p - pal[None, :, :]) ** 2 * weights[None, None, :]
        nearest[i : i + chunk] = np.argmin(diff.sum(axis=2), axis=1)
    arr[mask, :3] = palette[nearest]
    return Image.fromarray(arr, mode="RGBA")


def add_selective_outline(img: Image.Image, strength: float = 0.36) -> Image.Image:
    """Add a clean 1px dark selective-color outline on exterior contour pixels (sel-out)."""
    arr = np.asarray(img.convert("RGBA"), dtype=np.uint8).copy()
    opaque = arr[:, :, 3] > 0
    h, w = opaque.shape
    # Detect inner-boundary pixels or outer 1px shell?
    # Outer 1px shell keeps thin limbs (like ankles/gun straps) from thinning at 64px!
    padded = np.pad(opaque, 1, mode="constant", constant_values=False)
    adj_n = padded[:-2, 1:-1]
    adj_s = padded[2:, 1:-1]
    adj_w = padded[1:-1, :-2]
    adj_e = padded[1:-1, 2:]
    border = (~opaque) & (adj_n | adj_s | adj_w | adj_e)
    if not np.any(border):
        return img

    # Compute average neighbor RGB for selective-dark outline (richer than flat pure black)
    rgb_pad = np.pad(arr[:, :, :3].astype(np.float32), ((1, 1), (1, 1), (0, 0)), mode="constant")
    acc = np.zeros((h, w, 3), dtype=np.float32)
    cnt = np.zeros((h, w, 1), dtype=np.float32)
    for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
        m = padded[1 + dy : 1 + dy + h, 1 + dx : 1 + dx + w]
        acc += rgb_pad[1 + dy : 1 + dy + h, 1 + dx : 1 + dx + w] * m[:, :, None]
        cnt += m[:, :, None].astype(np.float32)
    avg = acc / np.maximum(cnt, 1.0)
    # Darken toward deep cool tactical ink (16, 18, 28)
    ink = np.array([16.0, 18.0, 28.0], dtype=np.float32)
    outline_rgb = np.clip(avg * strength + ink * (1.0 - strength), 0, 255).astype(np.uint8)
    arr[border, :3] = outline_rgb[border]
    arr[border, 3] = 255
    return Image.fromarray(arr, mode="RGBA")


def process_atlas(sheet_path: Path, cols: int, rows: int, body_px: int,
                  max_colors: int, outline: bool, out_path: Path) -> None:
    src = Image.open(sheet_path).convert("RGBA")
    src_fw = src.width // cols
    src_fh = src.height // rows
    dst_frame = int(round(body_px * 1.25))

    # Pass 1: Downsample & clean every cell first so palette matches exact final pixel density
    cells: list[list[Image.Image]] = []
    flat_cells: list[Image.Image] = []
    for r in range(rows):
        row_cells = []
        for c in range(cols):
            cell = src.crop((c * src_fw, r * src_fh, (c + 1) * src_fw, (r + 1) * src_fh))
            down = premul_box_resize(cell, (dst_frame, dst_frame))
            down = harden_alpha(down, threshold=126 if body_px <= 64 else 134)
            down = remove_isolated_pixels(down)
            row_cells.append(down)
            flat_cells.append(down)
        cells.append(row_cells)

    # Pass 2: Extract a single locked palette for the entire character sheet
    palette = build_locked_palette(flat_cells, max_colors=max_colors)

    # Pass 3: Quantize + optional selective outline + pack
    out = Image.new("RGBA", (dst_frame * cols, dst_frame * rows), (0, 0, 0, 0))
    for r in range(rows):
        for c in range(cols):
            im = apply_palette(cells[r][c], palette)
            if outline:
                im = add_selective_outline(im, strength=0.32 if body_px <= 64 else 0.38)
            out.paste(im, (c * dst_frame, r * dst_frame), im)

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out.save(out_path)
    print(f"[pixel_char_pipeline] wrote {out_path} ({out.width}x{out.height}, body={body_px}px, frame={dst_frame}px, colors={len(palette)}, outline={outline})")


def process_single(img_path: Path, body_px: int, max_colors: int, outline: bool, out_path: Path) -> None:
    src = Image.open(img_path).convert("RGBA")
    bbox = src.getbbox()
    if bbox:
        src = src.crop(bbox)
    frame = int(round(body_px * 1.25))
    feet = int(round(frame * FEET_RATIO))
    scale = body_px / float(max(src.height, 1))
    new_size = (max(1, round(src.width * scale)), max(1, round(src.height * scale)))
    body = premul_box_resize(src, new_size)
    body = harden_alpha(body, threshold=128)
    body = remove_isolated_pixels(body)
    palette = build_locked_palette([body], max_colors=max_colors)
    body = apply_palette(body, palette)
    if outline:
        body = add_selective_outline(body, strength=0.35)
    canvas = Image.new("RGBA", (frame, frame), (0, 0, 0, 0))
    canvas.paste(body, ((frame - body.width) // 2, feet - body.height), body)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(out_path)
    print(f"[pixel_char_pipeline] wrote single {out_path} ({canvas.width}x{canvas.height}, body={body_px}px)")


def main() -> int:
    parser = argparse.ArgumentParser(description="Seedream 5.5 -> Pixel Character Pipeline")
    parser.add_argument("--sheet", type=Path, help="Input high-res sprite atlas PNG")
    parser.add_argument("--single", type=Path, help="Input single character PNG")
    parser.add_argument("--cols", type=int, default=4)
    parser.add_argument("--rows", type=int, default=16)
    parser.add_argument("--targets", type=int, nargs="+", default=[64, 128])
    parser.add_argument("--body-px", type=int, default=128)
    parser.add_argument("--colors", type=int, default=0, help="0 = auto (32 for 64px, 48 for 128px)")
    parser.add_argument("--outline", action="store_true", help="Add 1px selective dark outline")
    parser.add_argument("--out-dir", type=Path, default=ROOT / "assets/art/characters/doll_b/lod")
    parser.add_argument("--out", type=Path, help="Output path for --single mode")
    args = parser.parse_args()

    if args.sheet:
        for bp in args.targets:
            colors = args.colors if args.colors > 0 else (32 if bp <= 64 else 48)
            out_path = args.out_dir / f"doll_lod_{bp}.png"
            process_atlas(args.sheet, args.cols, args.rows, bp, colors, args.outline, out_path)
        return 0
    if args.single:
        colors = args.colors if args.colors > 0 else (32 if args.body_px <= 64 else 48)
        out_path = args.out or (ROOT / f"out/char_single_{args.body_px}.png")
        process_single(args.single, args.body_px, colors, args.outline, out_path)
        return 0
    parser.error("Provide either --sheet or --single")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
