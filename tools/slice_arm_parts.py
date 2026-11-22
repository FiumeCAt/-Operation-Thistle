"""把 image2.5 生成的 4 段手臂图切成 大臂 / 小臂 / 手，并缩放到游戏尺寸。

注意：当前 arm2/ 下的分件由 tools/draw_arm_parts.py 程序化生成；
本脚本用于换新母版时重新切图，直接运行会覆盖现有分件。

源图是 4 个独立零件的横排：完整参考臂、大臂、小臂（带袖口）、拳头。
切完后按「袖子厚度」统一缩放，保证三段的粗细和现有角色一致；
输出到 assets/art/characters/doll_b/parts/arm2/，地面尺寸见打印。

运行：python tools/slice_arm_parts.py
"""
from collections import Counter, deque
from pathlib import Path
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from sprite_utils import clean_auto, resize_premultiplied

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "assets/art/characters/doll_b/arms_raw_1.png"
OUT = ROOT / "assets/art/characters/doll_b/parts/arm2"
## 颜色参照：从角色图集「瞄准右」帧的袖子区域取调色板，
## 生成的手臂必须映射回这套色，才不会比外套亮一截、像外挂零件。
ATLAS = ROOT / "assets/art/characters/doll_b/lod/doll_lod_256_body.png"
ATLAS_FRAME = 320
ATLAS_ROW = 15           # aim 右
ATLAS_SLEEVE = (132, 100, 196, 124)
NAMES = ["full_arm", "upper_arm", "forearm", "hand"]
# 源图按 2 倍绘制（与角色图集一致），TARGET_LEN 是源像素长度
TARGET_LEN = {"full_arm": 50, "upper_arm": 24, "forearm": 24, "hand": 14}
PALETTE_COLORS = 10
## 最多取多少个袖子颜色作为映射目标；太少会丢掉暗部描边，手臂看着发平。
SLEEVE_PALETTE_MAX = 16
## 手 = 娃娃的灰白皮肤，按明度映射到这几档，避免暖色皮肤像另一只手。
HAND_RAMP = [(157, 156, 148), (120, 120, 114), (76, 82, 101), (26, 28, 43)]


def blobs(image: Image.Image):
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


def pixelize(part: Image.Image) -> Image.Image:
    """缩到小尺寸后重采样会发虚，这里压回有限色板并把 alpha 拍成硬边。"""
    alpha = np.array(part.getchannel("A"))
    rgb = part.convert("RGB").quantize(
        colors=PALETTE_COLORS, method=Image.MEDIANCUT, dither=Image.NONE
    ).convert("RGB")
    arr = np.array(rgb)
    solid = alpha >= 96
    arr[~solid] = 0
    out = np.dstack([arr, np.where(solid, 255, 0).astype(np.uint8)])
    return Image.fromarray(out, "RGBA")


def atlas_palette() -> list:
    """从图集瞄准帧的袖子区域取色：只保留冷色（排除皮肤/内衬）并去掉过亮的反光。"""
    atlas = Image.open(ATLAS).convert("RGBA")
    x0, y0, x1, y1 = ATLAS_SLEEVE
    top = ATLAS_ROW * ATLAS_FRAME
    sleeve = atlas.crop((x0, top + y0, x1, top + y1))
    counts = Counter(p[:3] for p in sleeve.get_flattened_data() if p[3] > 200)
    palette = []
    for color, count in counts.most_common():
        if count < 8:
            break
        r, g, b = color
        if b < r:
            continue
        if (r * 299 + g * 587 + b * 114) // 1000 > 140:
            continue
        palette.append(color)
        if len(palette) >= SLEEVE_PALETTE_MAX:
            break
    print(f"袖子色板 {len(palette)} 色: {palette}")
    return palette


def recolor(part: Image.Image, palette: list) -> Image.Image:
    """把每个像素吸附到目标色板里的最近色，保留 alpha。"""
    arr = np.array(part)
    rgb = arr[:, :, :3].astype(np.int16)
    pal = np.array(palette, dtype=np.int16)
    dist = ((rgb[:, :, None, :] - pal[None, None, :, :]) ** 2).sum(axis=3)
    out = arr.copy()
    out[:, :, :3] = pal[dist.argmin(axis=2)]
    return Image.fromarray(out, "RGBA")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    sheet = clean_auto(Image.open(SRC))
    pieces = [p for p in blobs(sheet) if len(p) > 400]
    if len(pieces) < 4:
        raise SystemExit(f"只找到 {len(pieces)} 个零件，检查源图")
    pieces.sort(key=len, reverse=True)
    pieces = pieces[:4]
    boxes = []
    for piece in pieces:
        xs = [p[0] for p in piece]
        ys = [p[1] for p in piece]
        boxes.append((min(xs), min(ys), max(xs) + 1, max(ys) + 1))
    boxes.sort(key=lambda b: b[0])
    sleeve_palette = atlas_palette()

    for name, box in zip(NAMES, boxes):
        part = sheet.crop(box)
        scale = TARGET_LEN[name] / max(part.width, 1)
        size = (max(int(round(part.width * scale)), 1), max(int(round(part.height * scale)), 1))
        part = pixelize(resize_premultiplied(part, size))
        part = recolor(part, HAND_RAMP if name == "hand" else sleeve_palette)
        part.save(OUT / f"{name}.png")
        print(f"{name:10s} {size[0]}x{size[1]}  thickness={size[1]}")


if __name__ == "__main__":
    main()
