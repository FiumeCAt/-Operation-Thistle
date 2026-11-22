#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""从图集里自动检测每个方向/姿态的手部像素坐标，打印可直接粘贴的 GDScript 表。

思路：皮肤色分割 + 连通域；在手部搜索带内取「离身体中轴最近的皮肤块」重心。
比人眼比对 probe 截图快得多，而且可重复。
"""

import sys
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ATLAS = ROOT / "assets" / "art" / "characters" / "doll_a" / "doll_a_8dir.png"
CELL_W, CELL_H = 128, 192
COLS = 8

# 姿态组 -> 图集行号
GROUP_ROW = {"LOW": 0, "AIM": 12, "RELOAD": 15}
# 每组的手部搜索带（单元格 y）
GROUP_BAND = {"LOW": (52, 128), "AIM": (40, 96), "RELOAD": (48, 112)}


def skin_mask(rgb: np.ndarray) -> np.ndarray:
    r = rgb[:, :, 0].astype(np.int16)
    g = rgb[:, :, 1].astype(np.int16)
    b = rgb[:, :, 2].astype(np.int16)
    return (r > 185) & (g > 145) & (b > 120) & (r > g + 14) & (g > b + 8) & (r < 253)


def components(mask: np.ndarray) -> list[tuple[int, int, int, int, int, float, float]]:
    """返回 [(area, x0,y0,x1,y1, cx, cy), ...]"""
    h, w = mask.shape
    seen = np.zeros_like(mask, dtype=bool)
    out = []
    for y in range(h):
        for x in range(w):
            if not mask[y, x] or seen[y, x]:
                continue
            q = deque([(y, x)])
            seen[y, x] = True
            pts = []
            while q:
                cy, cx = q.popleft()
                pts.append((cy, cx))
                for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    ny, nx = cy + dy, cx + dx
                    if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True
                        q.append((ny, nx))
            ys = [p[0] for p in pts]
            xs = [p[1] for p in pts]
            out.append((
                len(pts), min(xs), min(ys), max(xs), max(ys),
                float(np.mean(xs)), float(np.mean(ys)),
            ))
    return out


def detect_cell(arr: np.ndarray, group: str) -> tuple[int, int] | None:
    y0, y1 = GROUP_BAND[group]
    band_rgb = arr[y0:y1, :, :3]
    mask = skin_mask(band_rgb)
    # 主体水平中轴：用整格不透明像素的重心
    alpha = arr[:, :, 3] > 16
    ys, xs = np.nonzero(alpha)
    body_cx = float(np.mean(xs)) if xs.size else CELL_W / 2.0

    comps = [c for c in components(mask) if c[0] >= 12]
    if not comps:
        return None
    # 候选：面积足够、且不贴着左右边缘（避免手臂被切）
    comps.sort(key=lambda c: abs(c[5] - body_cx))
    c = comps[0]
    return int(round(c[5])), int(round(c[6] + y0))


def main() -> int:
    if not ATLAS.exists():
        print("找不到图集：", ATLAS)
        return 1
    atlas = np.array(Image.open(ATLAS).convert("RGBA"))
    result: dict[str, list] = {}
    for group, row in GROUP_ROW.items():
        row_vals = []
        for d in range(COLS):
            cell = atlas[row * CELL_H:(row + 1) * CELL_H, d * CELL_W:(d + 1) * CELL_W]
            got = detect_cell(cell, group)
            row_vals.append(got if got else (-1, -1))
        result[group] = row_vals
        print(f"{group}: {row_vals}")

    print("\n---- GDScript ----")
    for group in ("LOW", "AIM", "RELOAD"):
        vals = result[group]
        parts = ", ".join(f"Vector2({v[0]}, {v[1]})" for v in vals)
        print(f'\t"{group}": [\n\t\t{parts},\n\t],')
    return 0


if __name__ == "__main__":
    sys.exit(main())
