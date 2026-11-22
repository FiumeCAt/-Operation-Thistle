"""把 image2.5 生成的「持枪瞄准」四向单帧追加到 256 图集（第 12~15 行）。

单帧生成（每向单独出图）能最大程度保留原角色的比例：
头像大小、腿长、身形都和站立图一致，不会变成 Q 版。

为了和现有 12 行素材风格一致：
  - 色调向现有站立帧的平均色对齐；
  - 颜色统一映射到「现有图集」生成的调色板；
  - 每个方向只算一次缩放，缩放后脚底对齐到同一基线。
输出：assets/art/characters/doll_b/lod/doll_lod_256.png（16 行）
运行：python tools/add_aim_block.py
"""

import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))

import build_doll_lods as base
from sprite_utils import clean_auto, cut_transparent

ROOT = Path(__file__).resolve().parents[1]
CHAR = ROOT / "assets/art/characters/doll_b"
RAW = [
    CHAR / "aim_front_raw.png",   # 0 下（正面）
    CHAR / "aim_back_raw.png",    # 1 上（背面）
    CHAR / "aim_left_raw.png",    # 2 左
    CHAR / "aim_right_raw.png",   # 3 右
]
LOD = CHAR / "lod/doll_lod_256.png"
BASE12 = CHAR / "lod/doll_lod_256_base.png"

BODY_PX = 256
COLS = 4
PALETTE_COLORS = 40
FEET_RATIO = 0.95


def mean_color(frame: Image.Image) -> list:
    alpha = frame.getchannel("A")
    mask = alpha.point(lambda a: 255 if a > 200 else 0)
    total = [0.0, 0.0, 0.0]
    count = 0
    rgb = frame.convert("RGB").load()
    mpx = mask.load()
    for y in range(frame.height):
        for x in range(frame.width):
            if mpx[x, y]:
                r, g, b = rgb[x, y]
                total[0] += r
                total[1] += g
                total[2] += b
                count += 1
    return [v / count for v in total] if count else [0.0, 0.0, 0.0]


def normalize_tone(rows, target):
    out = []
    for row in rows:
        new_row = []
        for frame in row:
            cur = mean_color(frame)
            gains = []
            for i in range(3):
                if cur[i] < 1.0:
                    gains.append(1.0)
                else:
                    gains.append(min(1.3, max(0.75, target[i] / cur[i])))
            r, g, b, a = frame.split()
            r = r.point(lambda v: min(255, round(v * gains[0])))
            g = g.point(lambda v: min(255, round(v * gains[1])))
            b = b.point(lambda v: min(255, round(v * gains[2])))
            new_row.append(Image.merge("RGBA", (r, g, b, a)))
        out.append(new_row)
    return out


def palette_from_sheet(sheet: Image.Image, frame: int, rows: int) -> Image.Image:
    montage = Image.new("RGB", (32 * COLS * rows, 32), (255, 0, 255))
    index = 0
    for row in range(rows):
        for col in range(COLS):
            cell = sheet.crop((col * frame, row * frame, (col + 1) * frame, (row + 1) * frame))
            montage.paste(cell.resize((32, 32), Image.NEAREST).convert("RGB"), (index * 32, 0))
            index += 1
    return montage.quantize(colors=PALETTE_COLORS, method=Image.MEDIANCUT)


def unify_palette(rows, palette):
    out = []
    for row in rows:
        new_row = []
        for frame in row:
            alpha = frame.getchannel("A")
            q = frame.convert("RGB").quantize(palette=palette, dither=Image.Dither.NONE).convert("RGB")
            q.putalpha(alpha)
            new_row.append(q)
        out.append(new_row)
    return out


def main():
    for path in RAW:
        if not path.exists():
            raise SystemExit("缺少素材：" + path.name)
    if not BASE12.exists():
        Image.open(LOD).save(BASE12)
        print("备份原始 12 行图集 ->", BASE12.name)
    base_sheet = Image.open(BASE12).convert("RGBA")
    frame = int(round(BODY_PX * 1.25))
    rows12 = base_sheet.height // frame
    if rows12 != 12:
        raise SystemExit(f"基础图集应为 12 行，实际 {rows12}")

    aim_rows = []
    for path in RAW:
        img = clean_auto(Image.open(path))
        box = img.getbbox()
        if box is None:
            raise SystemExit("素材没有内容：" + path.name)
        aim_rows.append([img.crop(box)] * COLS)

    # 以现有站立正面帧为色调基准
    idle_front = base_sheet.crop((0, 0, frame, frame))
    target = mean_color(idle_front)
    aim_rows = normalize_tone(aim_rows, target)
    aim_rows = unify_palette(aim_rows, palette_from_sheet(base_sheet, frame, rows12))

    feet = int(round(frame * FEET_RATIO))
    out = Image.new("RGBA", (frame * COLS, frame * (rows12 + 4)), (0, 0, 0, 0))
    out.alpha_composite(base_sheet, (0, 0))
    for row_index, frames in enumerate(aim_rows):
        cell = frames[0]
        scale = BODY_PX / float(cell.height)
        size = (max(1, round(cell.width * scale)), max(1, round(cell.height * scale)))
        body = cut_transparent(cell.resize(size, Image.NEAREST))
        for col_index in range(COLS):
            canvas = Image.new("RGBA", (frame, frame), (0, 0, 0, 0))
            canvas.paste(body, ((frame - body.width) // 2, feet - body.height), body)
            out.paste(canvas, (col_index * frame, (rows12 + row_index) * frame), canvas)
    out.save(LOD)
    print(f"写入 {LOD.relative_to(ROOT)}  {out.size[0]}x{out.size[1]}  行数={rows12 + 4}")


if __name__ == "__main__":
    main()
