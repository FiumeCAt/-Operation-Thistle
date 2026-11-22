#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把「持枪行走 / 奔跑」四向帧追加到 256 图集（第 16~23 行）。

行块布局（每块 4 行：下 / 上 / 左 / 右）：
  0-3   idle        4-7   walk       8-11  run       12-15 aim
  16-19 armed_walk  20-23 armed_run

输入：assets/art/characters/doll_b/armed/{action}_{dir}_{i}_raw.png
输出：assets/art/characters/doll_b/lod/doll_lod_256.png（24 行）

对齐方式：所有生成帧与参考图同构图，因此用「参考站立帧高度」算出的固定缩放，
不再逐帧按包围盒归一（否则弯腿帧会被放大），水平用固定偏移（避免走路时躯干左右抖），
垂直按包围盒底对齐到脚底基线。
运行：python tools/add_armed_block.py
"""

import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))

from add_aim_block import mean_color, normalize_tone, palette_from_sheet, unify_palette
from sprite_utils import clean_auto, cut_transparent, resize_premultiplied

ROOT = Path(__file__).resolve().parents[1]
CHAR = ROOT / "assets/art/characters/doll_b"
ARMED = CHAR / "armed"
LOD = CHAR / "lod/doll_lod_256.png"
BASE16 = CHAR / "lod/doll_lod_256_aim16.png"

BODY_PX = 256
COLS = 4
FEET_RATIO = 0.95
OLD_ROWS = 16
DIRS = ("front", "back", "left", "right")
ACTIONS = ("walk", "run")


def main():
    for action in ACTIONS:
        for d in DIRS:
            for i in range(COLS):
                path = ARMED / f"{action}_{d}_{i}_raw.png"
                if not path.exists():
                    raise SystemExit("缺少素材：" + str(path.relative_to(ROOT)))

    frame = int(round(BODY_PX * 1.25))
    if BASE16.exists():
        base_sheet = Image.open(BASE16).convert("RGBA")
    else:
        base_sheet = Image.open(LOD).convert("RGBA")
        rows_now = base_sheet.height // frame
        if rows_now != OLD_ROWS:
            raise SystemExit(f"当前图集应为 {OLD_ROWS} 行（aim 块），实际 {rows_now}，无法备份")
        base_sheet.save(BASE16)
        print("备份 16 行图集 ->", BASE16.name)

    # 参考站立帧：决定固定缩放与水平偏移
    ref = clean_auto(Image.open(CHAR / "aim_front_raw.png"))
    ref_box = ref.getbbox()
    if ref_box is None:
        raise SystemExit("参考帧没有内容")
    scale = BODY_PX / float(ref_box[3] - ref_box[1])
    ref_cx = (ref_box[0] + ref_box[2]) / 2.0

    # 32 帧统一做色调/调色板归一
    rows = []
    boxes = []
    for action in ACTIONS:
        for d in DIRS:
            for i in range(COLS):
                img = clean_auto(Image.open(ARMED / f"{action}_{d}_{i}_raw.png"))
                box = img.getbbox()
                if box is None:
                    raise SystemExit(f"素材没有内容：{action}_{d}_{i}")
                rows.append([img])
                boxes.append(box)

    target = mean_color(base_sheet.crop((0, 0, frame, frame)))
    rows = normalize_tone(rows, target)
    rows = unify_palette(rows, palette_from_sheet(base_sheet, frame, OLD_ROWS))

    out = Image.new("RGBA", (frame * COLS, frame * (OLD_ROWS + 8)), (0, 0, 0, 0))
    out.alpha_composite(base_sheet, (0, 0))

    feet = int(round(frame * FEET_RATIO))
    for index, (frames, box) in enumerate(zip(rows, boxes)):
        cell = frames[0]
        size = (max(1, round(cell.width * scale)), max(1, round(cell.height * scale)))
        body = cut_transparent(resize_premultiplied(cell, size))
        # 垂直：按包围盒底对齐基线；水平：沿用参考帧的中心偏移（避免步态左右抖动）
        box_bottom = box[3] * scale
        x = int(round(frame * 0.5 - ref_cx * scale))
        y = int(round(feet - box_bottom))
        canvas = Image.new("RGBA", (frame, frame), (0, 0, 0, 0))
        canvas.paste(body, (x, y), body)
        action_index = index // (COLS * 4)
        dir_index = (index // COLS) % 4
        row = OLD_ROWS + action_index * 4 + dir_index
        col = index % COLS
        out.paste(canvas, (col * frame, row * frame), canvas)

    out.save(LOD)
    print(f"写入 {LOD.relative_to(ROOT)}  {out.size[0]}x{out.size[1]}  行数={OLD_ROWS + 8}")


if __name__ == "__main__":
    main()
