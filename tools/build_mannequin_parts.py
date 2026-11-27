#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""程序化生成「功能分色 2D 标准体模（mannequin）」全套 19+3 精准 1:1 像素分件与 skin_manifest.json。

严格遵循 DollRigV2.gd（128px×1、160×160 SubViewport、GROUND_ORIGIN=(80,148)）
与 WeaponRig2D.gd（arm2 横置 0.5× 持枪双臂）的精确像素尺寸框，保证运行时零非整数缩放畸变：
  - assets/art/characters/mannequin/parts/*.png        (19 个身体骨骼分件，高度严格 == target_h)
  - assets/art/characters/mannequin/arm2/*.png         (3 个持枪双臂分件，26×14 / 27×13 / 12×10)
  - assets/art/characters/mannequin/skin_manifest.json (1:1 换皮契约清单)

高对比工程分色规范：
  - 躯干（正/背/侧）：中性灰白底 + 醒目胸口中线 / 正面青绿箭头 / 背面暗灰脊柱 X 标 / 侧面朝向标；
  - 头部（正/背/侧 + 眨眼）：灰白头模 + 深色眼线/面罩标示视线 + 高对比亮黄/洋红眨眼测试条；
  - 关节圆角包边与轴心点：髋/膝/踝/肩/肘/颈全部含 2–4px 圆角重叠包边，并精准点出纯红/纯黄关节圆心；
  - 四肢左右分色：磁盘 PNG 采用纯中性灰度基底 + 高饱和纯红/纯黄关节圆心，
    运行时由 DollRigV2 与 WeaponRig2D 保留高饱和圆心不变、仅将中性灰度像素精准着色为
    「左肢冷蓝 / 右肢暖橙」（同时兼容远近景明暗分离与 19+3 文件契约零冗余）；
  - 次级物理与背挂占位：后发/侧发/风衣下摆/格裙下摆采用半透明青色占位片，枪盒采用深灰框架盒。
"""

from __future__ import annotations

import json
import math
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
OUT_ROOT = ROOT / "assets/art/characters/mannequin"
OUT_PARTS = OUT_ROOT / "parts"
OUT_ARM2 = OUT_ROOT / "arm2"
OUT_MANIFEST = OUT_ROOT / "skin_manifest.json"
PREVIEW_OUT = Path(
    r"C:\Users\81349\.gemini\antigravity\brain\39efb0de-c6a8-4d42-9309-96c4eeb3f0b1\scratch\mannequin_parts_preview.png"
)

# ---- 工程分色调色板（严禁纯白剪影；所有肢体基色严格 R==G==B 以便运行时左冷蓝/右暖橙保点着色）----
OUTLINE = (28, 32, 40, 255)
OUTLINE_NEUTRAL = (36, 36, 36, 255)

# 中性灰白（头/躯干）
BODY_HI = (238, 242, 248, 255)
BODY_BASE = (206, 212, 222, 255)
BODY_MID = (164, 172, 186, 255)
BODY_DARK = (122, 130, 146, 255)
BODY_BACK_BASE = (158, 166, 180, 255)
BODY_BACK_SHADE = (124, 132, 148, 255)

# 纯灰度肢体基色（R==G==B，供运行时无损着色为左冷蓝 / 右暖橙）
LIMB_HI = (238, 238, 238, 255)
LIMB_BASE = (204, 204, 204, 255)
LIMB_MID = (160, 160, 160, 255)
LIMB_DARK = (116, 116, 116, 255)
BOOT_TOE = (144, 144, 144, 255)
BOOT_SOLE = (82, 82, 82, 255)

# 高饱和功能标记色（运行期着色会跳过高饱和像素，确保红/黄关节点永不偏色）
PIVOT_RED = (255, 42, 42, 255)       # 主枢轴：髋 / 肩 / 颈 / 踝 / 腕
PIVOT_YELLOW = (255, 228, 32, 255)   # 铰链枢轴：膝 / 肘
CENTER_GOLD = (255, 204, 56, 255)    # 胸口中线核心
CENTER_DARK = (46, 54, 68, 255)      # 中线暗边
FRONT_MINT = (40, 236, 168, 255)     # 正面/前向箭头标
BACK_CORAL = (232, 88, 96, 255)      # 背面脊柱/X 标
VISOR_DARK = (28, 38, 56, 255)       # 头模眼线/面罩底
VISOR_EYE = (72, 242, 255, 255)      # 视线焦点
BLINK_YELLOW = (255, 230, 40, 255)   # 眨眼测试条主色
BLINK_MAGENTA = (242, 58, 178, 255)  # 眨眼测试条边框

# 半透明青色软结构占位片
CYAN_FILL = (56, 224, 244, 152)
CYAN_HI = (126, 244, 255, 178)
CYAN_RIB = (24, 148, 174, 198)
CYAN_EDGE = (16, 100, 122, 232)
CYAN_PIVOT = (255, 228, 32, 235)

# 深灰战术枪盒占位框
CASE_OUTLINE = (22, 26, 34, 255)
CASE_FRAME = (106, 116, 134, 248)
CASE_FILL = (58, 64, 76, 246)
CASE_BRACE = (82, 92, 108, 248)
CASE_ACCENT = (240, 178, 56, 255)


def new_img(w: int, h: int) -> Image.Image:
    return Image.new("RGBA", (w, h), (0, 0, 0, 0))


def put(img: Image.Image, x: int, y: int, color: tuple[int, int, int, int]) -> None:
    if 0 <= x < img.width and 0 <= y < img.height:
        img.putpixel((x, y), color)


def put_rect(
    img: Image.Image,
    x0: int,
    y0: int,
    x1: int,
    y1: int,
    color: tuple[int, int, int, int],
) -> None:
    for y in range(max(0, y0), min(img.height, y1 + 1)):
        for x in range(max(0, x0), min(img.width, x1 + 1)):
            img.putpixel((x, y), color)


def put_pivot_2x2(
    img: Image.Image,
    cx: int,
    cy: int,
    color: tuple[int, int, int, int],
    ring: tuple[int, int, int, int] | None = None,
) -> None:
    """在 (cx, cy)..(cx+1, cy+1) 点出 2×2 精准关节圆心，可选 1px 暗框提对比。"""
    if ring is not None:
        for dy in (-1, 0, 1, 2):
            for dx in (-1, 0, 1, 2):
                if dx in (0, 1) and dy in (0, 1):
                    continue
                px, py = cx + dx, cy + dy
                if 0 <= px < img.width and 0 <= py < img.height and img.getpixel((px, py))[3] > 0:
                    img.putpixel((px, py), ring)
    put_rect(img, cx, cy, cx + 1, cy + 1, color)


def add_1px_outline(img: Image.Image, edge_color: tuple[int, int, int, int]) -> Image.Image:
    """对所有不透明像素的内边界着 1px 暗描边（严格保持画布精确 1:1 尺寸不外扩）。"""
    w, h = img.size
    out = img.copy()
    px = img.load()
    opx = out.load()
    for y in range(h):
        for x in range(w):
            if px[x, y][3] == 0:
                continue
            is_border = False
            for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                nx, ny = x + dx, y + dy
                if nx < 0 or ny < 0 or nx >= w or ny >= h or px[nx, ny][3] == 0:
                    is_border = True
                    break
            if is_border:
                opx[x, y] = edge_color
    return out


def draw_rounded_capsule_v(
    w: int,
    h: int,
    top_r: float,
    bot_r: float,
    base_col: tuple[int, int, int, int],
    hi_col: tuple[int, int, int, int],
    shade_col: tuple[int, int, int, int],
    front_left_hi: bool = True,
) -> Image.Image:
    """绘制竖直圆角胶囊肢体（上下均带圆角重叠包边，严格贴合 w×h 精确边框）。"""
    img = new_img(w, h)
    cx = (w - 1) * 0.5
    max_rx = max(1.0, (w - 1) * 0.5)
    for y in range(h):
        if y < top_r:
            dy = (top_r - y) / max(top_r, 1.0)
            rx = max_rx * math.sqrt(max(0.0, 1.0 - dy * dy))
        elif y > (h - 1) - bot_r:
            dy = (y - ((h - 1) - bot_r)) / max(bot_r, 1.0)
            rx = max_rx * math.sqrt(max(0.0, 1.0 - dy * dy))
        else:
            rx = max_rx
        for x in range(w):
            if abs(x - cx) <= rx + 0.15:
                if front_left_hi:
                    if x - cx < -rx * 0.25:
                        col = hi_col
                    elif x - cx > rx * 0.28:
                        col = shade_col
                    else:
                        col = base_col
                else:
                    col = base_col
                img.putpixel((x, y), col)
    return img


# ---- 1) 头部（38×36 正/背，36×36 侧；offset=(0,-14)，颈枢轴 y=32）----

def build_head_front(blink: bool = False) -> Image.Image:
    w, h = 38, 36
    img = new_img(w, h)
    cx = (w - 1) * 0.5  # 18.5
    # 主颅腔（椭圆，y=1..29）+ 下颌/颈圆角重叠包边（y=26..35，盖住领口防摆头露缝）
    for y in range(h):
        for x in range(w):
            dx = (x - cx) / 13.8
            dy = (y - 14.5) / 13.8
            in_cranium = (dx * dx + dy * dy) <= 1.0
            # 下巴收敛（y=22..30）
            chin_w = max(0.0, 11.5 - (y - 21) * 0.85) if 21 <= y <= 30 else 0.0
            in_chin = (21 <= y <= 30) and abs(x - cx) <= chin_w
            # 颈部圆角包边（y=28..35，中心 x=18.5，半径 5.5×4.2）
            ndx = (x - cx) / 5.4
            ndy = (y - 31.2) / 4.2
            in_neck = (ndx * ndx + ndy * ndy) <= 1.0
            # 侧耳/战术耳机定位块（y=14..21）
            in_ear = (14 <= y <= 21) and (abs(x - cx) <= 16.5) and (abs(x - cx) >= 12.2)
            if in_cranium or in_chin or in_neck or in_ear:
                if in_ear:
                    col = BODY_MID
                elif in_neck and not in_chin:
                    col = BODY_MID
                elif y < 10 and abs(x - cx) < 9.5:
                    col = BODY_HI
                elif x > cx + 7.0 or y > 24:
                    col = BODY_MID
                else:
                    col = BODY_BASE
                img.putpixel((x, y), col)

    img = add_1px_outline(img, OUTLINE)
    # 额头垂直中线（y=3..13）
    put_rect(img, 18, 3, 19, 13, CENTER_DARK)
    put_rect(img, 18, 5, 19, 11, CENTER_GOLD)
    # 深色眼线/面罩带（y=15..20）
    put_rect(img, 8, 15, 29, 20, VISOR_DARK)
    if blink:
        # 高对比亮黄/洋红眨眼测试条
        put_rect(img, 8, 15, 29, 20, BLINK_MAGENTA)
        put_rect(img, 9, 16, 28, 19, BLINK_YELLOW)
        put_rect(img, 11, 17, 26, 18, OUTLINE)
    else:
        # 清晰双目视线标 + 鼻梁标
        put_rect(img, 11, 16, 14, 19, VISOR_EYE)
        put_rect(img, 23, 16, 26, 19, VISOR_EYE)
        put_rect(img, 18, 16, 19, 19, BODY_MID)
    # 鼻/口与正中下颌标
    put_rect(img, 18, 22, 19, 24, CENTER_DARK)
    put_rect(img, 16, 26, 21, 26, BODY_DARK)
    # 颈枢轴红点（local (0,0) -> py=32）
    put_pivot_2x2(img, 18, 31, PIVOT_RED, OUTLINE)
    return img


def build_head_back() -> Image.Image:
    w, h = 38, 36
    img = new_img(w, h)
    cx = (w - 1) * 0.5
    for y in range(h):
        for x in range(w):
            dx = (x - cx) / 13.8
            dy = (y - 14.5) / 13.8
            in_cranium = (dx * dx + dy * dy) <= 1.0
            ndx = (x - cx) / 5.4
            ndy = (y - 31.2) / 4.2
            in_neck = (ndx * ndx + ndy * ndy) <= 1.0
            in_ear = (14 <= y <= 21) and (abs(x - cx) <= 16.5) and (abs(x - cx) >= 12.2)
            if in_cranium or in_neck or in_ear:
                if y < 9 and abs(x - cx) < 9.0:
                    col = BODY_BASE
                elif in_ear or y > 23:
                    col = BODY_DARK
                else:
                    col = BODY_BACK_BASE
                img.putpixel((x, y), col)

    img = add_1px_outline(img, OUTLINE)
    # 背面头带与后脑十字标（无面罩，正背一眼区分）
    put_rect(img, 7, 16, 30, 19, BODY_DARK)
    put_rect(img, 18, 5, 19, 27, CENTER_DARK)
    put_rect(img, 14, 17, 23, 18, BACK_CORAL)
    put_rect(img, 18, 13, 19, 22, BACK_CORAL)
    put_pivot_2x2(img, 18, 31, PIVOT_RED, OUTLINE)
    return img


def build_head_left(blink: bool = False) -> Image.Image:
    """侧视头模（面向左 -X；朝右时由 DollRigV2 水平翻转）。"""
    w, h = 36, 36
    img = new_img(w, h)
    cx = 18.0
    for y in range(h):
        for x in range(w):
            # 侧视颅腔（略偏右后脑，左前额+鼻梁突出）
            dx = (x - (cx + 1.0)) / 12.8
            dy = (y - 14.5) / 13.4
            in_cranium = (dx * dx + dy * dy) <= 1.0
            # 左前方额眉与鼻梁轮廓（x=4..12, y=13..25）
            in_face = (13 <= y <= 26) and (5 <= x <= 14) and ((x >= 5 if 17 <= y <= 21 else x >= 6))
            # 鼻尖突出（x=4, y=19..20）
            in_nose = (19 <= y <= 21) and (4 <= x <= 6)
            # 颈部圆角包边（y=27..35，中心 x=18）
            ndx = (x - cx) / 5.4
            ndy = (y - 31.2) / 4.2
            in_neck = (ndx * ndx + ndy * ndy) <= 1.0
            if in_cranium or in_face or in_nose or in_neck:
                if x < 13 and y < 23:
                    col = BODY_HI
                elif x > 24 or y > 25:
                    col = BODY_MID
                else:
                    col = BODY_BASE
                img.putpixel((x, y), col)

    img = add_1px_outline(img, OUTLINE)
    # 侧面耳部定位圆（x=19..23, y=15..21）
    put_rect(img, 19, 15, 23, 21, BODY_MID)
    put_rect(img, 20, 16, 22, 20, CENTER_DARK)
    # 侧面面罩/视线标（紧贴左前方，视线方向绝对清晰）
    put_rect(img, 6, 15, 16, 20, VISOR_DARK)
    if blink:
        put_rect(img, 6, 15, 16, 20, BLINK_MAGENTA)
        put_rect(img, 7, 16, 15, 19, BLINK_YELLOW)
        put_rect(img, 8, 17, 14, 18, OUTLINE)
    else:
        put_rect(img, 7, 16, 11, 19, VISOR_EYE)
        # 前向视线小箭头标（绿）指向左侧
        put(img, 13, 17, FRONT_MINT)
        put(img, 14, 16, FRONT_MINT)
        put(img, 14, 17, FRONT_MINT)
        put(img, 14, 18, FRONT_MINT)
    # 额顶前向标
    put_rect(img, 10, 6, 16, 7, CENTER_GOLD)
    # 颈枢轴红点（local (0,0) -> px=18, py=32）
    put_pivot_2x2(img, 17, 31, PIVOT_RED, OUTLINE)
    return img


# ---- 2) 躯干（正 36×46 / 背 34×46 / 侧 26×46；offset=(0,-20)，颈 y=4、肩 y=10、髋 y=43）----

def _draw_torso_silhouette(w: int, h: int, half_shoulder: float, half_waist: float, half_hip: float,
                           base_col: tuple[int, int, int, int], hi_col: tuple[int, int, int, int],
                           shade_col: tuple[int, int, int, int], side_left: bool = False) -> Image.Image:
    img = new_img(w, h)
    cx = (w - 1) * 0.5
    for y in range(h):
        # 顶部颈领圆角包边（y=0..6）
        if y <= 6:
            dy = (6 - y) / 6.0
            hw = 5.4 * math.sqrt(max(0.0, 1.0 - dy * dy * 0.72))
        elif y <= 14:
            # 肩部宽展（y=7..14）
            t = (y - 7) / 7.0
            hw = 6.2 + (half_shoulder - 6.2) * math.sin(t * math.pi * 0.5)
        elif y <= 28:
            # 胸腔到腰部收束
            t = (y - 14) / 14.0
            hw = half_shoulder + (half_waist - half_shoulder) * t
        elif y <= 38:
            # 腰部到骨盆外展
            t = (y - 28) / 10.0
            hw = half_waist + (half_hip - half_waist) * t
        else:
            # 底部骨盆圆角重叠包边（y=39..45）
            dy = (y - 38) / 7.2
            hw = half_hip * math.sqrt(max(0.0, 1.0 - dy * dy))

        left_edge = cx - hw
        right_edge = cx + hw
        if side_left:
            # 侧面胸前略微前挺（-X 方向），背部略直
            chest_bulge = 2.0 * math.sin(max(0.0, min(1.0, (y - 8) / 16.0)) * math.pi) if 8 <= y <= 24 else 0.0
            left_edge -= chest_bulge
            right_edge -= chest_bulge * 0.35

        for x in range(w):
            if left_edge - 0.15 <= x <= right_edge + 0.15:
                if side_left:
                    if x < cx - 2.0:
                        col = hi_col
                    elif x > cx + 3.0:
                        col = shade_col
                    else:
                        col = base_col
                else:
                    if y < 22 and abs(x - cx) < hw * 0.55:
                        col = hi_col
                    elif x > cx + hw * 0.55 or y > 35:
                        col = shade_col
                    else:
                        col = base_col
                img.putpixel((x, y), col)
    return add_1px_outline(img, OUTLINE)


def build_torso_front() -> Image.Image:
    img = _draw_torso_silhouette(36, 46, 14.5, 10.5, 13.2, BODY_BASE, BODY_HI, BODY_MID, False)
    # 醒目胸口中线（x=17..18, y=7..40）
    put_rect(img, 16, 7, 19, 39, CENTER_DARK)
    put_rect(img, 17, 7, 18, 39, CENTER_GOLD)
    # 胸口正面青绿 V 箭头标（一眼识别正面）
    for row, half_w in ((12, 6), (13, 5), (14, 4), (15, 3), (16, 2), (17, 1)):
        put_rect(img, 17 - half_w, row, 18 + half_w, row, FRONT_MINT)
    # 保留箭头内的中心金线，更有战术甲感
    put_rect(img, 17, 12, 18, 17, CENTER_GOLD)
    # 腰带分割线（y=27..29）
    put_rect(img, 8, 27, 27, 29, CENTER_DARK)
    put_rect(img, 15, 27, 20, 29, FRONT_MINT)
    # 肩窝定位环（落于肩腔内部）
    put_pivot_2x2(img, 8, 11, PIVOT_RED, OUTLINE)
    put_pivot_2x2(img, 26, 11, PIVOT_RED, OUTLINE)
    # 颈枢轴红点（y=3..4）+ 骨盆中轴红点（y=41..42）
    put_pivot_2x2(img, 17, 3, PIVOT_RED, OUTLINE)
    put_pivot_2x2(img, 17, 41, PIVOT_RED, OUTLINE)
    return img


def build_torso_back() -> Image.Image:
    img = _draw_torso_silhouette(34, 46, 13.8, 10.0, 12.6, BODY_BACK_BASE, BODY_BASE, BODY_BACK_SHADE, False)
    # 背面脊柱线 + 珊瑚红 X 标记（正背极高区分度）
    put_rect(img, 15, 7, 18, 39, CENTER_DARK)
    for i in range(9):
        put_rect(img, 11 + i, 12 + i, 12 + i, 12 + i, BACK_CORAL)
        put_rect(img, 21 - i, 12 + i, 22 - i, 12 + i, BACK_CORAL)
    # 背面腰带
    put_rect(img, 7, 27, 26, 29, CENTER_DARK)
    put_rect(img, 15, 27, 18, 29, BACK_CORAL)
    # 颈 / 肩 / 骨盆红点
    put_pivot_2x2(img, 16, 3, PIVOT_RED, OUTLINE)
    put_pivot_2x2(img, 7, 11, PIVOT_RED, OUTLINE)
    put_pivot_2x2(img, 25, 11, PIVOT_RED, OUTLINE)
    put_pivot_2x2(img, 16, 41, PIVOT_RED, OUTLINE)
    return img


def build_torso_left() -> Image.Image:
    """侧视躯干（面向左 -X；朝右时水平翻转）。"""
    img = _draw_torso_silhouette(26, 46, 9.2, 7.2, 8.8, BODY_BASE, BODY_HI, BODY_MID, True)
    # 胸前垂直前缘亮线 + 朝左青绿方向箭头（x=4..10, y=13..19）
    put_rect(img, 5, 11, 6, 25, CENTER_GOLD)
    for dx in range(5):
        y0 = 16 - dx
        y1 = 17 + dx
        put_rect(img, 6 + dx, y0, 6 + dx, y1, FRONT_MINT)
    # 后背暗条（区分胸前/后背）
    put_rect(img, 18, 11, 20, 34, BODY_DARK)
    # 腰带线
    put_rect(img, 6, 27, 20, 29, CENTER_DARK)
    put_rect(img, 6, 27, 10, 29, FRONT_MINT)
    # 颈 / 侧肩 / 侧髋枢轴红点
    put_pivot_2x2(img, 12, 3, PIVOT_RED, OUTLINE)
    put_pivot_2x2(img, 12, 9, PIVOT_RED, OUTLINE)
    put_pivot_2x2(img, 12, 41, PIVOT_RED, OUTLINE)
    return img


# ---- 3) 二段式屈膝双腿（纯灰度基色 + 精准纯红/纯黄关节圆心，运行时着左蓝/右橙）----

def build_thigh() -> Image.Image:
    """大腿 10×33（target_h=33, offset=(0,13)）：髋枢轴 y=3..4 (红)，膝枢轴 y=29..30 (黄)。"""
    img = draw_rounded_capsule_v(10, 33, 3.8, 3.8, LIMB_BASE, LIMB_HI, LIMB_MID, front_left_hi=True)
    img = add_1px_outline(img, OUTLINE_NEUTRAL)
    # 沿中轴画 1px 淡灰骨线，增强腿部旋转角度可读性
    put_rect(img, 4, 7, 5, 26, LIMB_MID)
    # 前缘 1px 高光条（朝向 -X，方便辨认前侧）
    put_rect(img, 2, 7, 2, 26, LIMB_HI)
    # 髋关节红点（py=3.5 -> 3..4）与膝关节黄点（py=29.5 -> 29..30）
    put_pivot_2x2(img, 4, 3, PIVOT_RED, OUTLINE_NEUTRAL)
    put_pivot_2x2(img, 4, 29, PIVOT_YELLOW, OUTLINE_NEUTRAL)
    return img


def build_shin_boot() -> Image.Image:
    """小腿+鞋靴 14×34（target_h=34, offset=(0,14)）：面向左 -X；膝 y=2..3 (黄)，踝 y=24..25 (红)。"""
    w, h = 14, 34
    img = new_img(w, h)
    # 1) 小腿管身（中心 x=7.5，宽 8px -> x=3..11，顶端 y=0..4 做 3.5px 膝圆角重叠包边）
    cx = 7.5
    for y in range(28):
        if y < 3.6:
            dy = (3.6 - y) / 3.6
            rx = 3.8 * math.sqrt(max(0.0, 1.0 - dy * dy))
        else:
            # 略微向脚踝收窄（3.8 -> 3.0）
            t = (y - 3.6) / 24.4
            rx = 3.8 - 0.8 * t
        for x in range(w):
            if abs(x - cx) <= rx + 0.15:
                if x < cx - 1.0:
                    col = LIMB_HI
                elif x > cx + 1.4:
                    col = LIMB_MID
                else:
                    col = LIMB_BASE
                img.putpixel((x, y), col)

    # 2) 靴体与朝左鞋头（y=25..33，鞋头伸向 x=1，鞋跟在 x=11..12）
    for y in range(25, 34):
        if y == 25:
            x0, x1 = 4, 11
        elif y == 26:
            x0, x1 = 3, 12
        elif y == 27:
            x0, x1 = 2, 12
        elif y <= 31:
            x0, x1 = 1, 12
        else:
            # 鞋底（y=32..33，平踩地面）
            x0, x1 = 1, 12
        for x in range(x0, x1 + 1):
            if y >= 31:
                col = BOOT_SOLE
            elif x <= 4:
                col = LIMB_HI
            elif x >= 10:
                col = LIMB_DARK
            else:
                col = BOOT_TOE
            img.putpixel((x, y), col)

    img = add_1px_outline(img, OUTLINE_NEUTRAL)
    # 小腿胫骨中线（区分前后）
    put_rect(img, 7, 6, 7, 22, LIMB_MID)
    put_rect(img, 5, 6, 5, 22, LIMB_HI)
    # 膝关节黄点（py=3 -> 2..3）与踝关节红点（py=25 -> 24..25）
    put_pivot_2x2(img, 6, 2, PIVOT_YELLOW, OUTLINE_NEUTRAL)
    put_pivot_2x2(img, 6, 24, PIVOT_RED, OUTLINE_NEUTRAL)
    return img


# ---- 4) 收枪二段手臂（10×20 上臂 / 10×20 前臂，纯灰度 + 红/黄圆心，运行时着左蓝/右橙）----

def build_arm_upper() -> Image.Image:
    """收枪上臂 10×20（target_h=20, offset=(0,7)）：肩 y=2..3 (红)，肘 y=16..17 (黄)。"""
    img = draw_rounded_capsule_v(10, 20, 3.6, 3.6, LIMB_BASE, LIMB_HI, LIMB_MID, front_left_hi=True)
    img = add_1px_outline(img, OUTLINE_NEUTRAL)
    put_rect(img, 4, 6, 5, 14, LIMB_MID)
    put_pivot_2x2(img, 4, 2, PIVOT_RED, OUTLINE_NEUTRAL)
    put_pivot_2x2(img, 4, 16, PIVOT_YELLOW, OUTLINE_NEUTRAL)
    return img


def build_arm_forearm() -> Image.Image:
    """收枪前臂+手 10×20（target_h=20, offset=(0,7)）：肘 y=2..3 (黄)，腕 y=14..15 (红)。"""
    img = draw_rounded_capsule_v(10, 20, 3.6, 3.8, LIMB_BASE, LIMB_HI, LIMB_MID, front_left_hi=True)
    # 手掌/手套末段略加深（y=15..18）
    put_rect(img, 2, 15, 7, 18, LIMB_DARK)
    img = add_1px_outline(img, OUTLINE_NEUTRAL)
    put_rect(img, 4, 6, 5, 13, LIMB_MID)
    put_pivot_2x2(img, 4, 2, PIVOT_YELLOW, OUTLINE_NEUTRAL)
    put_pivot_2x2(img, 4, 14, PIVOT_RED, OUTLINE_NEUTRAL)
    return img


# ---- 5) 半透明青色次级物理占位片（后发根/梢、侧发、衣摆根/梢、格裙下摆）----

def build_soft_strip(w: int, h: int, taper_bottom: float = 0.25, rib_step: int = 4) -> Image.Image:
    """绘制半透明青色占位片：顶端圆角包边 + 纵/斜向流线刻度 + 枢轴黄点，便于验收弹簧飘动与遮挡。"""
    img = new_img(w, h)
    cx = (w - 1) * 0.5
    max_rx = max(1.0, (w - 1) * 0.5)
    top_r = min(3.0, max_rx)
    for y in range(h):
        if y < top_r:
            dy = (top_r - y) / max(top_r, 1.0)
            rx = max_rx * math.sqrt(max(0.0, 1.0 - dy * dy * 0.65))
        else:
            t = (y - top_r) / max(1.0, (h - 1) - top_r)
            rx = max_rx * (1.0 - taper_bottom * t)
        for x in range(w):
            if abs(x - cx) <= rx + 0.1:
                col = CYAN_HI if y < max(3, h // 3) else CYAN_FILL
                img.putpixel((x, y), col)
    img = add_1px_outline(img, CYAN_EDGE)
    # 内部横向波纹/纵向中筋，飘动弯折一目了然
    mid_x = w // 2
    for y in range(2, h - 2):
        if img.getpixel((mid_x, y))[3] > 0:
            img.putpixel((mid_x, y), CYAN_RIB)
        if rib_step > 0 and (y % rib_step == 0):
            for x in range(2, w - 2):
                if img.getpixel((x, y))[3] > 0:
                    img.putpixel((x, y), CYAN_RIB)
    # 顶部弹簧挂点黄标
    px = max(1, min(w - 3, mid_x - 1))
    put_pivot_2x2(img, px, 1, CYAN_PIVOT)
    return img


# ---- 6) 背挂战术枪盒占位框（18×64；offset=(0,-6)）----

def build_gun_case() -> Image.Image:
    w, h = 18, 64
    img = new_img(w, h)
    # 圆角矩形硬箱
    for y in range(h):
        inset = 2 if (y in (0, h - 1)) else (1 if (y in (1, h - 2)) else 0)
        for x in range(inset, w - inset):
            img.putpixel((x, y), CASE_FILL)
    img = add_1px_outline(img, CASE_OUTLINE)
    # 内边框高光
    put_rect(img, 2, 2, w - 3, 2, CASE_FRAME)
    put_rect(img, 2, h - 3, w - 3, h - 3, CASE_FRAME)
    put_rect(img, 2, 2, 2, h - 3, CASE_FRAME)
    put_rect(img, w - 3, 2, w - 3, h - 3, CASE_FRAME)
    # 战术斜向绑带 + 加强筋（前后遮挡极清晰）
    for band_y in (10, 26, 40, 54):
        put_rect(img, 2, band_y, w - 3, band_y + 1, CASE_BRACE)
    for i in range(12):
        put(img, 3 + i, 14 + i, CASE_ACCENT)
        put(img, 14 - i, 14 + i, CASE_ACCENT)
        put(img, 3 + i, 42 + i, CASE_ACCENT)
        put(img, 14 - i, 42 + i, CASE_ACCENT)
    # 顶部高亮锁扣
    put_rect(img, 5, 4, 12, 6, CASE_ACCENT)
    return img


# ---- 7) WeaponRig2D 横置 arm2 分件（26×14 / 27×13 / 12×10，纯灰度 + 纯红/纯黄枢轴点）----

def draw_rounded_capsule_h(
    w: int,
    h: int,
    left_r: float,
    right_r: float,
    taper_right: float = 0.0,
) -> Image.Image:
    img = new_img(w, h)
    cy = (h - 1) * 0.5
    max_ry = max(1.0, (h - 1) * 0.5)
    for x in range(w):
        if x < left_r:
            dx = (left_r - x) / max(left_r, 1.0)
            ry = max_ry * math.sqrt(max(0.0, 1.0 - dx * dx))
        elif x > (w - 1) - right_r:
            dx = (x - ((w - 1) - right_r)) / max(right_r, 1.0)
            ry = max_ry * (1.0 - taper_right) * math.sqrt(max(0.0, 1.0 - dx * dx))
        else:
            t = (x - left_r) / max(1.0, (w - 1 - right_r) - left_r)
            ry = max_ry * (1.0 - taper_right * t)
        for y in range(h):
            if abs(y - cy) <= ry + 0.15:
                if y < cy - ry * 0.25:
                    col = LIMB_HI
                elif y > cy + ry * 0.28:
                    col = LIMB_MID
                else:
                    col = LIMB_BASE
                img.putpixel((x, y), col)
    return add_1px_outline(img, OUTLINE_NEUTRAL)


def build_arm2_upper() -> Image.Image:
    """持枪上臂 26×14（0.5× 渲染为 13×7）：左端肩枢轴 x=3..5 (红)，右端肘枢轴 x=20..22 (黄)。"""
    img = draw_rounded_capsule_h(26, 14, 6.2, 6.2, taper_right=0.04)
    put_rect(img, 8, 6, 18, 7, LIMB_MID)
    put_pivot_2x2(img, 4, 6, PIVOT_RED, OUTLINE_NEUTRAL)
    put_pivot_2x2(img, 20, 6, PIVOT_YELLOW, OUTLINE_NEUTRAL)
    return img


def build_arm2_forearm() -> Image.Image:
    """持枪前臂 27×13（0.5× 渲染为 13.5×6.5）：左端肘重叠 x=3..5 (黄)，右端腕枢轴 x=21..23 (红)。"""
    img = draw_rounded_capsule_h(27, 13, 5.8, 5.2, taper_right=0.14)
    put_rect(img, 8, 6, 19, 6, LIMB_MID)
    put_pivot_2x2(img, 4, 5, PIVOT_YELLOW, OUTLINE_NEUTRAL)
    put_pivot_2x2(img, 21, 5, PIVOT_RED, OUTLINE_NEUTRAL)
    return img


def build_arm2_hand() -> Image.Image:
    """持枪手掌 12×10（0.5× 渲染为 6×5）：圆角手套 + 中心红点。"""
    img = draw_rounded_capsule_h(12, 10, 4.5, 4.5, taper_right=0.04)
    put_pivot_2x2(img, 5, 4, PIVOT_RED, OUTLINE_NEUTRAL)
    return img


def tint_preview_limb(img: Image.Image, tint_rgb: tuple[float, float, float]) -> Image.Image:
    """预览用着色：严格复刻运行时着色规则（保留高饱和红/黄圆心，仅将中性灰度着为左蓝/右橙）。"""
    out = img.copy()
    px = out.load()
    for y in range(out.height):
        for x in range(out.width):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            if max(r, g, b) - min(r, g, b) > 36:
                continue
            lum = r / 255.0
            # 暗描边保持深邃有色轮廓
            nr = int(max(0, min(255, round(lum * tint_rgb[0] * 255.0))))
            ng = int(max(0, min(255, round(lum * tint_rgb[1] * 255.0))))
            nb = int(max(0, min(255, round(lum * tint_rgb[2] * 255.0))))
            px[x, y] = (nr, ng, nb, a)
    return out


def build_manifest(parts_meta: dict[str, dict], arm2_meta: dict[str, dict]) -> dict:
    return {
        "schema_version": 1,
        "skin_id": "mannequin",
        "display_name": "功能分色 2D 标准体模 (Mannequin)",
        "pixel_spec": {
            "world_height_px": 128,
            "canvas_size": [160, 160],
            "ground_origin": [80, 148],
            "scale_mode": "1:1_integer",
            "texture_filter": "NEAREST",
        },
        "skeleton_constants": {
            "PELVIS_HEIGHT": 58,
            "THIGH_LEN": 28,
            "SHIN_LEN": 30,
            "TORSO_HEIGHT": 40,
            "NECK_OFFSET_Y": -39,
            "SHOULDER_OFFSET_Y": -33,
            "UPPER_ARM_LEN": 16,
            "FOREARM_LEN": 16,
            "ARM2_SCALE": 0.5,
        },
        "color_coding": {
            "limb_side_coloring": True,
            "left_limb_tint": [0.38, 0.80, 1.0],
            "right_limb_tint": [1.0, 0.62, 0.24],
            "pivot_proximal_hex": "#ff2a2a",
            "pivot_hinge_hex": "#ffe420",
            "secondary_motion_rgba": [56, 224, 244, 152],
            "torso_front_marker_hex": "#28eca8",
            "torso_back_marker_hex": "#e85860",
        },
        "extra_components_default": {
            "back_gear": True,
            "armor": True,
            "backpack": True,
            "coat_flaps": True,
            "hair_secondary": True,
        },
        "parts_count": len(parts_meta),
        "arm2_count": len(arm2_meta),
        "parts": parts_meta,
        "arm2": arm2_meta,
    }


def main() -> int:
    OUT_PARTS.mkdir(parents=True, exist_ok=True)
    OUT_ARM2.mkdir(parents=True, exist_ok=True)

    # 严格 1:1 对应 DollRigV2.gd 的 19 个身体分件（height == target_h）
    parts_imgs: dict[str, Image.Image] = {
        "head_front": build_head_front(blink=False),
        "head_front_blink": build_head_front(blink=True),
        "head_back": build_head_back(),
        "head_left": build_head_left(blink=False),
        "head_left_blink": build_head_left(blink=True),
        "torso_front": build_torso_front(),
        "torso_back": build_torso_back(),
        "torso_left": build_torso_left(),
        "hair_back_root": build_soft_strip(26, 18, taper_bottom=0.14, rib_step=4),
        "hair_back_tip": build_soft_strip(20, 12, taper_bottom=0.38, rib_step=4),
        "hair_side": build_soft_strip(6, 12, taper_bottom=0.35, rib_step=4),
        "coat_flap_root": build_soft_strip(14, 21, taper_bottom=0.10, rib_step=5),
        "coat_flap_tip": build_soft_strip(12, 13, taper_bottom=0.28, rib_step=4),
        "skirt_hem": build_soft_strip(34, 13, taper_bottom=-0.06, rib_step=4),
        "thigh": build_thigh(),
        "shin_boot": build_shin_boot(),
        "gun_case": build_gun_case(),
        "arm_upper": build_arm_upper(),
        "arm_forearm": build_arm_forearm(),
    }

    # 严格对应 WeaponRig2D.gd 的 3 个横置持枪手臂分件
    arm2_imgs: dict[str, Image.Image] = {
        "upper_arm": build_arm2_upper(),
        "forearm": build_arm2_forearm(),
        "hand": build_arm2_hand(),
    }

    parts_spec_meta: dict[str, dict] = {
        "head_front": {"target_h": 36, "offset": [0, -14], "pivots_px": {"neck": [18.5, 32]}, "z_index": {"0": 5}, "flip_rule": "none", "role": "正面头部（视线朝向镜头）"},
        "head_front_blink": {"target_h": 36, "offset": [0, -14], "pivots_px": {"neck": [18.5, 32]}, "z_index": {"0": 6}, "flip_rule": "none", "role": "正面独立眨眼覆盖层"},
        "head_back": {"target_h": 36, "offset": [0, -14], "pivots_px": {"neck": [18.5, 32]}, "z_index": {"1": 5}, "flip_rule": "none", "role": "背面头部"},
        "head_left": {"target_h": 36, "offset": [0, -14], "pivots_px": {"neck": [18, 32]}, "z_index": {"2": 5, "3": 5}, "flip_rule": "flip_h_when_dir_3", "role": "侧视头部（原图朝左 -X）"},
        "head_left_blink": {"target_h": 36, "offset": [0, -14], "pivots_px": {"neck": [18, 32]}, "z_index": {"2": 6, "3": 6}, "flip_rule": "flip_h_when_dir_3", "role": "侧视独立眨眼覆盖层（原图朝左）"},
        "torso_front": {"target_h": 46, "offset": [0, -20], "pivots_px": {"pelvis": [18, 43], "neck": [18, 4], "shoulder_l": [28, 10], "shoulder_r": [8, 10]}, "z_index": {"0": 1}, "flip_rule": "none", "role": "正面无臂躯干"},
        "torso_back": {"target_h": 46, "offset": [0, -20], "pivots_px": {"pelvis": [17, 43], "neck": [17, 4], "shoulder_l": [7, 10], "shoulder_r": [27, 10]}, "z_index": {"1": 1}, "flip_rule": "none", "role": "背面无臂躯干"},
        "torso_left": {"target_h": 46, "offset": [0, -20], "pivots_px": {"pelvis": [13, 43], "neck": [13, 4], "shoulder": [13, 10]}, "z_index": {"2": 1, "3": 1}, "flip_rule": "flip_h_when_dir_3", "role": "侧视无臂躯干（原图朝左 -X）"},
        "hair_back_root": {"target_h": 18, "offset": [0, 5], "pivots_px": {"root": [13, 4]}, "z_index": {"0": -1, "1": 4, "2": -1, "3": -1}, "flip_rule": "flip_h_when_dir_3", "role": "次级物理后发上段"},
        "hair_back_tip": {"target_h": 12, "offset": [0, 4], "pivots_px": {"joint": [10, 2]}, "z_index": {"0": -1, "1": 4, "2": -1, "3": -1}, "flip_rule": "flip_h_when_dir_3", "role": "次级物理后发发梢"},
        "hair_side": {"target_h": 12, "offset": [0, 5], "pivots_px": {"root": [3, 1]}, "z_index": {"0": 4}, "flip_rule": "mirror_right_side", "role": "正面两侧鬓发微动片"},
        "coat_flap_root": {"target_h": 21, "offset": [0, 9], "pivots_px": {"root": [7, 1.5]}, "z_index": {"0": 0, "1": 0, "2": 0, "3": 0}, "flip_rule": "mirror_right_flap", "role": "次级物理衣摆上段"},
        "coat_flap_tip": {"target_h": 13, "offset": [0, 5], "pivots_px": {"joint": [6, 1.5]}, "z_index": {"0": 0, "1": 0, "2": 0, "3": 0}, "flip_rule": "mirror_right_flap", "role": "次级物理衣摆下段"},
        "skirt_hem": {"target_h": 13, "offset": [0, 3], "pivots_px": {"waist": [17, 3.5]}, "z_index": {"0": -1, "1": -1}, "flip_rule": "hidden_on_side", "role": "正/背面裙摆下沿微摆片"},
        "thigh": {"target_h": 33, "offset": [0, 13], "pivots_px": {"hip": [5, 3.5], "knee": [5, 29.5]}, "z_index": {"near": -2, "far": -4, "front_back": -3}, "flip_rule": "flip_h_when_lower_dir_3", "role": "大腿段（含上下 3.5px 圆角重叠包边）"},
        "shin_boot": {"target_h": 34, "offset": [0, 14], "pivots_px": {"knee": [7, 3], "ankle": [7, 25], "sole_y": 33}, "z_index": {"near": -2, "far": -4, "front_back": -3}, "flip_rule": "flip_h_when_lower_dir_3", "role": "小腿+鞋靴段（原图鞋尖朝左 -X）"},
        "gun_case": {"target_h": 64, "offset": [0, -6], "pivots_px": {"mount": [9, 38]}, "z_index": {"0": -6, "1": 7, "2": -2, "3": -2}, "flip_rule": "flip_h_when_dir_3", "role": "背后战术装备/枪盒挂件"},
        "arm_upper": {"target_h": 20, "offset": [0, 7], "pivots_px": {"shoulder": [5, 3], "elbow": [5, 17]}, "z_index": {"0": 4, "1": -2, "near": 4, "far": -3}, "flip_rule": "flip_h_when_dir_3", "role": "收枪状态上臂段（含肩/肘 3px 包边）"},
        "arm_forearm": {"target_h": 20, "offset": [0, 7], "pivots_px": {"elbow": [5, 3], "wrist": [5, 15]}, "z_index": {"0": 4, "1": -2, "near": 4, "far": -3}, "flip_rule": "flip_h_when_dir_3", "role": "收枪状态前臂与手部"},
    }

    arm2_spec_meta: dict[str, dict] = {
        "upper_arm": {"arm_scale": 0.5, "world_size": [13.0, 7.0], "offset": [13.0, 0.0], "pivots_px": {"shoulder": [3, 7], "elbow": [22, 7]}, "role": "持枪水平上臂（左肩→右肘，0.5× 缩放）"},
        "forearm": {"arm_scale": 0.5, "world_size": [13.5, 6.5], "offset": [13.5, 0.0], "pivots_px": {"elbow": [3, 6.5], "wrist": [23, 6.5]}, "role": "持枪水平前臂（左肘→右腕，0.5× 缩放）"},
        "hand": {"arm_scale": 0.5, "world_size": [6.0, 5.0], "offset": [0.0, 0.0], "pivots_px": {"grip": [6, 5]}, "role": "持枪握持手掌（居中对齐握把，0.5× 缩放）"},
    }

    # 严格校验高度 == target_h 并写盘
    parts_manifest: dict[str, dict] = {}
    for key, im in parts_imgs.items():
        meta = parts_spec_meta[key]
        assert im.height == meta["target_h"], f"{key} height {im.height} != target_h {meta['target_h']}"
        out_path = OUT_PARTS / f"{key}.png"
        im.save(out_path)
        parts_manifest[key] = {
            "file": f"parts/{key}.png",
            "width": im.width,
            "height": im.height,
            **meta,
        }

    arm2_manifest: dict[str, dict] = {}
    for key, im in arm2_imgs.items():
        out_path = OUT_ARM2 / f"{key}.png"
        im.save(out_path)
        arm2_manifest[key] = {
            "file": f"arm2/{key}.png",
            "width": im.width,
            "height": im.height,
            **arm2_spec_meta[key],
        }

    manifest = build_manifest(parts_manifest, arm2_manifest)
    OUT_MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    # ---- 生成 3× 放大可视化目视检查图（含 L 冷蓝 / R 暖橙着色对照）----
    preview_items: list[tuple[str, Image.Image]] = []
    for k, im in parts_imgs.items():
        preview_items.append((f"{k} ({im.width}x{im.height})", im))
    for k, im in arm2_imgs.items():
        preview_items.append((f"arm2/{k} ({im.width}x{im.height})", im))
    # 额外展示运行时 L 冷蓝 / R 暖橙保点着色预览
    preview_items.append(("L-blue thigh+shin", tint_preview_limb(parts_imgs["thigh"], (0.38, 0.80, 1.0))))
    preview_items.append(("R-orange thigh+shin", tint_preview_limb(parts_imgs["thigh"], (1.0, 0.62, 0.24))))
    preview_items.append(("L-blue shin_boot", tint_preview_limb(parts_imgs["shin_boot"], (0.38, 0.80, 1.0))))
    preview_items.append(("R-orange shin_boot", tint_preview_limb(parts_imgs["shin_boot"], (1.0, 0.62, 0.24))))
    preview_items.append(("L-blue arm2/upper", tint_preview_limb(arm2_imgs["upper_arm"], (0.38, 0.80, 1.0))))
    preview_items.append(("R-orange arm2/upper", tint_preview_limb(arm2_imgs["upper_arm"], (1.0, 0.62, 0.24))))

    cols = 7
    rows = (len(preview_items) + cols - 1) // cols
    cell_w, cell_h = 196, 214
    sheet = Image.new("RGBA", (cols * cell_w, rows * cell_h), (26, 30, 38, 255))
    draw = ImageDraw.Draw(sheet)
    for idx, (label, im) in enumerate(preview_items):
        r, c = divmod(idx, cols)
        ox, oy = c * cell_w, r * cell_h
        draw.rectangle([ox + 5, oy + 20, ox + cell_w - 5, oy + cell_h - 5], fill=(50, 56, 68, 255))
        scale = 4 if max(im.width, im.height) <= 36 else (3 if max(im.width, im.height) <= 52 else 2)
        zoomed = im.resize((im.width * scale, im.height * scale), Image.Resampling.NEAREST)
        px = ox + (cell_w - zoomed.width) // 2
        py = oy + 20 + (cell_h - 26 - zoomed.height) // 2
        sheet.paste(zoomed, (px, py), zoomed)
        draw.text((ox + 8, oy + 4), label, fill=(255, 224, 130, 255))

    PREVIEW_OUT.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(PREVIEW_OUT)
    print(f"[build_mannequin_parts] Saved {len(parts_imgs)} parts + {len(arm2_imgs)} arm2 + {OUT_MANIFEST.name}")
    print(f"[build_mannequin_parts] Preview sheet: {PREVIEW_OUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
