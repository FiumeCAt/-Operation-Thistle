#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Operation Thistle（蓟花行动）— M0 占位美术生成器

生成内容：
  tools/previews/doll_a_8dir_placeholder.png     8 向 x 23 行 占位动画图集
  assets/art/fx/*.png                            阴影 / 准星 / 枪口火光
  assets/art/env/*.png                           地面 / 墙面 / 警示条 / 终端屏 / 靶板

所有图形均为程序化矢量绘制（4x 超采样后缩小），无第三方素材。
占位图只写到 tools/previews，不会覆盖正式图集。
正式图集由 tools/build_doll_atlas.py 从 AI 源图生成。
"""

import math
import random
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

# ---------------------------------------------------------------- 基础参数
SS = 4                      # 超采样倍率
CW, CH = 128, 192           # 单格尺寸（最终）
COLS = 8
GROUND = 184.0

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / "assets" / "art"

ANIMS = [
    # name, frames, fps, loop
    ("idle",   4, 6.0,  True),
    ("walk",   8, 10.0, True),
    ("aim",    1, 1.0,  True),
    ("fire",   2, 18.0, False),
    ("reload", 3, 8.0,  False),
    ("hurt",   1, 1.0,  False),
    ("death",  4, 8.0,  False),
]
TOTAL_ROWS = sum(a[1] for a in ANIMS)
ROW_INDEX = {}
_r = 0
for _name, _n, _fps, _loop in ANIMS:
    ROW_INDEX[_name] = _r
    _r += _n

# ---------------------------------------------------------------- 色板
SKIN       = (243, 211, 194, 255)
SKIN_SHADE = (212, 168, 154, 255)
HAIR       = (31, 36, 47, 255)
HAIR_HI    = (72, 84, 103, 255)
HAIR_TIP   = (242, 160, 61, 255)
JACKET     = (61, 71, 86, 255)
JACKET_DK  = (39, 45, 55, 255)
JACKET_HI  = (92, 105, 123, 255)
SHIRT      = (220, 229, 236, 255)
SKIRT      = (31, 36, 46, 255)
STOCKING   = (23, 27, 35, 255)
BOOT       = (15, 18, 24, 255)
GUN        = (78, 88, 101, 255)
GUN_DK     = (45, 51, 60, 255)
GUN_HI     = (112, 125, 140, 255)
AMBER      = (242, 160, 61, 255)
AMBER_DIM  = (168, 103, 34, 255)
CYAN       = (79, 209, 224, 255)
CYAN_DIM   = (40, 116, 128, 255)
OUTLINE    = (7, 9, 11, 255)
WHITE      = (255, 255, 255, 255)


# ---------------------------------------------------------------- 绘图封装
class Canvas:
    def __init__(self, w=CW, h=CH):
        self.w, self.h = w, h
        self.img = Image.new("RGBA", (w * SS, h * SS), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.img)

    def _xy(self, x, y):
        return (x * SS, y * SS)

    def ellipse(self, cx, cy, rx, ry, fill):
        self.d.ellipse(
            [((cx - rx) * SS, (cy - ry) * SS), ((cx + rx) * SS, (cy + ry) * SS)],
            fill=fill,
        )

    def rr(self, x0, y0, x1, y1, r, fill):
        self.d.rounded_rectangle(
            [x0 * SS, y0 * SS, x1 * SS, y1 * SS], radius=r * SS, fill=fill
        )

    def poly(self, pts, fill):
        self.d.polygon([(x * SS, y * SS) for x, y in pts], fill=fill)

    def line(self, pts, fill, width):
        self.d.line(
            [(x * SS, y * SS) for x, y in pts],
            fill=fill,
            width=max(1, int(width * SS)),
            joint="curve",
        )

    def rect(self, x0, y0, x1, y1, fill):
        self.d.rectangle([x0 * SS, y0 * SS, x1 * SS, y1 * SS], fill=fill)


def rot(p, a):
    x, y = p
    c, s = math.cos(a), math.sin(a)
    return (x * c - y * s, x * s + y * c)


def gun_point(local, cx, cy, angle, flip):
    x, y = local
    x *= flip
    rx, ry = rot((x, y), angle * flip)
    return (cx + rx, cy + ry)


# ---------------------------------------------------------------- 枪械绘制
def draw_rifle(cv: Canvas, cx, cy, angle, flip):
    def P(local):
        return gun_point(local, cx, cy, angle, flip)

    # 枪托
    cv.poly([P((-34, -5)), P((-16, -4)), P((-16, 4)), P((-32, 6))], GUN_DK)
    # 机匣
    cv.poly([P((-17, -5)), P((14, -5)), P((14, 5)), P((-17, 5))], GUN)
    # 上导轨
    cv.poly([P((-15, -7)), P((14, -7)), P((14, -4.5)), P((-15, -4.5))], GUN_DK)
    # 护木
    cv.poly([P((14, -5)), P((37, -4.5)), P((37, 4.5)), P((14, 5))], GUN)
    cv.poly([P((16, -2)), P((34, -1.8)), P((34, 1.8)), P((16, 2))], AMBER_DIM)
    # 枪管
    cv.poly([P((37, -2.6)), P((52, -2.2)), P((52, 2.2)), P((37, 2.6))], GUN_DK)
    # 枪口
    cv.poly([P((52, -3.4)), P((57, -3.0)), P((57, 3.0)), P((52, 3.4))], (18, 21, 25, 255))
    # 弹匣
    cv.poly([P((0, 5)), P((10, 5)), P((13, 19)), P((2, 19))], GUN_DK)
    cv.poly([P((2, 7)), P((9, 7)), P((10, 14)), P((3, 14))], GUN_HI)
    # 握把
    cv.poly([P((-11, 5)), P((-4, 5)), P((-7, 16)), P((-14, 16))], (24, 28, 34, 255))
    # 光学瞄具 + 青色点亮
    cv.poly([P((2, -12)), P((12, -12)), P((12, -7)), P((2, -7))], GUN_DK)
    cx_o, cy_o = P((7, -9.6))
    cv.ellipse(cx_o, cy_o, 1.5, 1.5, CYAN)
    # 前握把
    cv.poly([P((26, 5)), P((32, 5)), P((31, 14)), P((25, 14))], (24, 28, 34, 255))


def hand_positions(cx, cy, angle, flip):
    return gun_point((9, 5), cx, cy, angle, flip), gun_point((28, 4), cx, cy, angle, flip)


# ---------------------------------------------------------------- 角色绘制
def draw_doll(d, anim, frame, count):
    """d: 0..7, 0=面向镜头(前), 2=右, 4=背, 6=左"""
    theta = d * math.pi / 4.0
    c = math.cos(theta)          # 前向分量
    s = math.sin(theta)          # 右向分量
    wf = 0.78 + 0.22 * abs(c)    # 正面/背面更宽
    flip = 1.0 if s >= -0.15 else -1.0

    phase = 0.0 if count <= 1 else (frame / count) * math.tau
    is_walk = anim == "walk"
    is_aim = anim in ("aim", "fire")
    is_reload = anim == "reload"
    is_hurt = anim == "hurt"
    is_death = anim == "death"

    bob = 0.0
    crouch = 0.0
    if anim == "idle":
        bob = 1.0 * math.sin(phase)
    elif is_walk:
        bob = 1.7 * math.sin(phase * 2.0)
    elif is_aim:
        crouch = 2.0
    elif is_reload:
        crouch = 3.0
    elif is_hurt:
        bob = 2.0

    recoil = 0.0
    if anim == "fire":
        recoil = (4.5 if frame == 0 else 2.5)

    shift_x = -s * recoil
    shift_y = -c * recoil + bob

    hx = 64 + 3.0 * s
    head_y = 47 + shift_y * 0.6
    hip_y = 111 + shift_y + crouch
    sh_y = head_y + 24

    cv = Canvas()

    # ---------------- 尾巴（在身体后面）
    tail_sway = 2.5 * math.sin(phase + 0.6) + 2.0 * s
    for side in (-1, 1):
        base_x = hx + side * 13.0
        tip_x = hx + side * (20.0 + 2.5 * abs(s)) + tail_sway
        tip_y = head_y + 52
        cv.poly(
            [
                (base_x - 3.6, head_y + 8),
                (base_x + 3.6, head_y + 8),
                (tip_x + 2.6, tip_y - 8),
                (tip_x, tip_y),
                (tip_x - 2.4, tip_y - 9),
            ],
            HAIR,
        )
        cv.poly(
            [
                (tip_x - 2.2, tip_y - 9),
                (tip_x + 2.2, tip_y - 9),
                (tip_x, tip_y),
            ],
            HAIR_TIP,
        )

    # ---------------- 腿
    stance = 7.0 * wf
    swing = (6.0 * math.sin(phase)) * abs(s) if is_walk else 0.0
    if is_reload:
        swing = 0.0
    lfx = 64 - stance - swing
    rfx = 64 + stance + swing
    lfy = GROUND
    rfy = GROUND

    for fx, fy, knee_off in ((lfx, lfy, -1.0), (rfx, rfy, 1.0)):
        hip = (64 + knee_off * 6.0 * wf, hip_y - 2)
        knee = (fx + knee_off * 1.0, hip_y + 20)
        cv.line([hip, knee, (fx, fy - 5)], STOCKING, 10.0)
        # 靴子
        cv.ellipse(fx + knee_off * 0.5, fy - 4, 7.6, 5.2, BOOT)
        cv.ellipse(fx + knee_off * 0.5, fy - 6.5, 5.8, 3.2, (20, 24, 29, 255))
        # 膝盖护具
        if abs(c) > 0.25:
            kx, ky = knee
            cv.ellipse(kx, ky, 4.8, 4.0, JACKET_DK)
            cv.ellipse(kx, ky - 0.6, 3.2, 1.0, AMBER_DIM)

    # ---------------- 裙 / 腰
    sway = 2.0 * math.sin(phase) if is_walk else 0.0
    cv.poly(
        [
            (64 - 17 * wf, hip_y - 9),
            (64 + 17 * wf, hip_y - 9),
            (64 + 23 * wf + sway, hip_y + 14),
            (64 - 23 * wf + sway, hip_y + 14),
        ],
        SKIRT,
    )
    cv.poly(
        [
            (64 - 17 * wf, hip_y - 9),
            (64 + 17 * wf, hip_y - 9),
            (64 + 19 * wf, hip_y - 2),
            (64 - 19 * wf, hip_y - 2),
        ],
        (34, 39, 47, 255),
    )

    # ---------------- 躯干
    tw = 17.5 * wf
    cv.rr(64 - tw, sh_y - 8, 64 + tw, hip_y - 4, 7.0, JACKET)
    # 内衬
    cv.poly(
        [
            (64 - 5.5 * wf, sh_y - 8),
            (64 + 5.5 * wf, sh_y - 8),
            (64 + 4.0 * wf, hip_y - 8),
            (64 - 4.0 * wf, hip_y - 8),
        ],
        SHIRT,
    )
    # 战术背带
    cv.line([(64 - 11 * wf, sh_y - 4), (64 - 8 * wf, hip_y - 10)], JACKET_DK, 3.4)
    cv.line([(64 + 11 * wf, sh_y - 4), (64 + 8 * wf, hip_y - 10)], JACKET_DK, 3.4)
    cv.rect(64 - 9 * wf, hip_y - 15, 64 + 9 * wf, hip_y - 9, JACKET_DK)
    # 胸前琥珀小徽章
    if c > -0.25:
        cv.poly(
            [
                (64 + 6 * wf, sh_y - 1),
                (64 + 9.5 * wf, sh_y + 1.4),
                (64 + 6 * wf, sh_y + 3.8),
                (64 + 2.5 * wf, sh_y + 1.4),
            ],
            AMBER,
        )
    # 腰带 + 弹匣包
    cv.rect(64 - 18 * wf, hip_y - 7, 64 + 18 * wf, hip_y - 1, (16, 19, 24, 255))
    cv.rect(64 - 2.0, hip_y - 7, 64 + 2.0, hip_y - 1.5, AMBER_DIM)
    for px in (-12, -5, 5, 12):
        cv.rect(64 + px * wf - 2.2, hip_y - 6, 64 + px * wf + 2.2, hip_y + 1.5, (30, 35, 42, 255))

    # 大腿枪套
    if c > -0.4:
        cv.rr(64 - 20 * wf, hip_y + 8, 64 - 12 * wf, hip_y + 26, 2.0, (26, 30, 36, 255))
        cv.rect(64 - 19 * wf, hip_y + 10, 64 - 13 * wf, hip_y + 13, GUN_DK)

    # ---------------- 头
    # 颈部
    cv.line([(hx, head_y + 13), (hx, sh_y - 2)], SKIN_SHADE, 6.0)

    # 后发团
    cv.ellipse(hx, head_y + 1, 19.5, 20.5, HAIR)
    if c < 0.3:  # 背面/侧面，后发覆盖
        cv.poly(
            [
                (hx - 17, head_y - 4),
                (hx + 17, head_y - 4),
                (hx + 14, head_y + 24),
                (hx - 14, head_y + 24),
            ],
            HAIR,
        )

    # 脸
    face_shift = 3.0 * s
    if c > -0.35:
        cv.ellipse(hx + face_shift, head_y + 4, 12.6, 14.0, SKIN)
        # 下巴极窄阴影（避免像胡子）
        cv.ellipse(hx + face_shift, head_y + 15.6, 5.4, 1.2, SKIN_SHADE)

    # 刘海
    fringe = [
        (hx - 15.5, head_y - 10),
        (hx + 15.5, head_y - 10),
        (hx + 14.0, head_y + 1),
        (hx + 9.0, head_y - 4),
        (hx + 5.0, head_y + 4),
        (hx + 1.0, head_y - 5),
        (hx - 4.0, head_y + 3),
        (hx - 8.0, head_y - 4),
        (hx - 13.0, head_y + 1),
    ]
    cv.poly(fringe, HAIR)
    cv.poly(
        [
            (hx - 8.0, head_y - 9.5),
            (hx + 3.0, head_y - 9.5),
            (hx - 1.0, head_y - 3.0),
        ],
        HAIR_HI,
    )

    # 眼睛
    if c > 0.2:
        for side in (-1, 1):
            ex = hx + face_shift + side * 5.6
            ey = head_y + 5.4
            cv.poly([(ex - 2.6, ey - 1.4), (ex + 2.4, ey - 1.4), (ex + 1.6, ey + 1.8), (ex - 1.8, ey + 1.8)], WHITE)
            cv.ellipse(ex, ey + 0.2, 1.55, 2.1, AMBER)
            cv.ellipse(ex, ey + 0.4, 0.8, 1.2, (30, 20, 12, 255))
            cv.ellipse(ex - 0.8, ey - 0.8, 0.55, 0.6, WHITE)
            cv.line([(ex - 2.7, ey - 1.8), (ex + 2.5, ey - 1.8)], (12, 14, 18, 255), 1.3)
    elif abs(c) < 0.35:
        ex = hx + 6.0 * (1.0 if s >= 0 else -1.0)
        ey = head_y + 5.4
        cv.poly([(ex - 2.4, ey - 1.4), (ex + 2.4, ey - 1.4), (ex + 1.6, ey + 1.8), (ex - 1.8, ey + 1.8)], WHITE)
        cv.ellipse(ex, ey + 0.2, 1.5, 2.0, AMBER)
        cv.ellipse(ex, ey + 0.4, 0.78, 1.15, (30, 20, 12, 255))
        cv.line([(ex - 2.5, ey - 1.8), (ex + 2.3, ey - 1.8)], (12, 14, 18, 255), 1.2)

    if c > 0.35:
        cv.line([(hx + face_shift + 0.6, head_y + 11.0), (hx + face_shift + 2.6, head_y + 11.2)], SKIN_SHADE, 1.0)

    # 耳侧机械件 / 耳机
    if c > -0.5:
        side_x = hx + (12.5 if s >= 0 else -12.5)
        cv.rr(side_x - 2.4, head_y - 2.0, side_x + 2.4, head_y + 5.0, 1.0, (20, 23, 28, 255))
        cv.ellipse(side_x, head_y + 1.2, 1.0, 1.0, AMBER)
        # 太阳穴接口
        cv.rect(side_x - 1.2, head_y - 6.0, side_x + 2.6, head_y - 4.2, CYAN_DIM)

    # ---------------- 手臂 + 枪
    gun_cx = 64 + 4.0 * s + shift_x * 0.5
    gun_cy = hip_y - 20 + 1.5 * abs(c) + shift_y * 0.3
    gun_angle = math.radians(22)
    if is_aim:
        gun_angle = math.radians(0)
    elif anim == "fire":
        gun_angle = math.radians(-5 if frame == 0 else -2)
    elif is_reload:
        gun_angle = math.radians(52)
    elif is_hurt:
        gun_angle = math.radians(30)

    # 枪背带
    cv.line([(hx - 13 * wf, sh_y - 2), (gun_cx - 18, gun_cy - 2), (gun_cx - 26, gun_cy - 1)], JACKET_DK, 1.6)

    draw_rifle(cv, gun_cx, gun_cy, gun_angle, flip)
    hand_a, hand_b = hand_positions(gun_cx, gun_cy, gun_angle, flip)

    shoulder_l = (hx - 15.5 * wf, sh_y - 2)
    shoulder_r = (hx + 15.5 * wf, sh_y - 2)

    if is_aim or anim == "fire":
        # 双手前伸托枪
        cv.line([shoulder_r, (hand_a[0] + 2, hand_a[1] - 3), hand_a], JACKET, 7.2)
        cv.line([shoulder_l, (hand_b[0] - 2, hand_b[1] - 5), hand_b], JACKET, 7.2)
    elif is_reload:
        cv.line([shoulder_r, (hand_a[0] + 1, hand_a[1] - 5), (hand_a[0] + 1, hand_a[1] + 2)], JACKET, 7.2)
        cv.line([shoulder_l, (64 - 3, hip_y + 2), (64 + 1, hip_y + 6)], JACKET, 7.2)
    else:
        # 低戒备持枪：双手都在枪上
        cv.line([shoulder_l, (shoulder_l[0] + 2, sh_y + 10), hand_b], JACKET, 7.2)
        cv.line([shoulder_r, (shoulder_r[0] - 2, sh_y + 10), hand_a], JACKET, 7.2)

    # 手
    cv.ellipse(hand_a[0], hand_a[1], 3.0, 3.2, SKIN)
    cv.ellipse(hand_b[0], hand_b[1], 2.9, 3.1, SKIN)

    # 肩甲
    for side in (-1, 1):
        sx = hx + side * 16.0 * wf
        cv.ellipse(sx, sh_y - 1.5, 6.4, 4.6, JACKET_DK)
        cv.ellipse(sx, sh_y - 2.2, 5.2, 2.4, JACKET_HI)
        if side < 0 and c > -0.3:
            cv.ellipse(sx, sh_y - 2.2, 2.4, 1.0, AMBER_DIM)

    # ---------------- 受击 / 死亡 变形
    if is_hurt:
        cv.img = cv.img.rotate(3.5, resample=Image.BICUBIC, center=(64 * SS, GROUND * SS))
    if is_death:
        angles = [10.0, 30.0, 55.0, 74.0]
        drop = [2.0, 6.0, 10.0, 13.0]
        a = angles[min(frame, len(angles) - 1)]
        cv.img = cv.img.rotate(
            a, resample=Image.BICUBIC, center=(64 * SS, GROUND * SS)
        )
        cv.img = cv.img.transform(
            cv.img.size,
            Image.Transform.AFFINE,
            (1, 0, 0, 0, 1, drop[min(frame, len(drop) - 1)] * SS),
            resample=Image.BICUBIC,
        )

    return finish(cv.img)


def finish(img: Image.Image) -> Image.Image:
    """侧光渐变 + 右缘琥珀轮廓光 + 描边 + 缩小"""
    arr = np.array(img).astype(np.float32)
    alpha = arr[..., 3:4] / 255.0
    w = arr.shape[1]
    grad = np.linspace(0.88, 1.05, w)[None, :, None]
    arr[..., :3] = np.clip(arr[..., :3] * (1.0 + (grad - 1.0) * alpha), 0, 255)

    # 右缘轮廓光
    a2 = arr[..., 3]
    rim = np.clip(a2 - np.roll(a2, -3, axis=1), 0, 255)[..., None] / 255.0
    arr[..., :3] += rim * np.array([90, 62, 22], np.float32) * 0.55
    arr[..., :3] = np.clip(arr[..., :3], 0, 255)

    img = Image.fromarray(arr.astype(np.uint8), "RGBA")

    a = img.split()[3]
    blur = a.filter(ImageFilter.GaussianBlur(4.0))
    dilated = blur.point(lambda v: 255 if v > 12 else 0)
    ol = Image.new("RGBA", img.size, OUTLINE)
    ol.putalpha(dilated)
    ol.alpha_composite(img)

    return ol.resize((CW, CH), Image.LANCZOS)


# ---------------------------------------------------------------- 图集
def build_sheet():
    sheet = Image.new("RGBA", (CW * COLS, CH * TOTAL_ROWS), (0, 0, 0, 0))
    for name, count, fps, loop in ANIMS:
        start = ROW_INDEX[name]
        for f in range(count):
            for d in range(COLS):
                cell = draw_doll(d, name, f, count)
                sheet.alpha_composite(cell, (d * CW, (start + f) * CH))
    out = ROOT / "tools" / "previews" / "doll_a_8dir_placeholder.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out)
    print(f"[sheet] {out}  {sheet.width}x{sheet.height}  rows={TOTAL_ROWS}")
    return sheet


def build_previews(sheet: Image.Image):
    # 8 向预览（aim 姿态，2x）
    aim_row = ROW_INDEX["aim"]
    scale = 2
    pad = 8
    labels = ["FRONT 0", "FR 1", "RIGHT 2", "BR 3", "BACK 4", "BL 5", "LEFT 6", "FL 7"]
    pw, ph = CW * scale, CH * scale + 22
    out = Image.new("RGBA", (pw * 8 + pad * 9, ph + pad * 2), (18, 21, 26, 255))
    dr = ImageDraw.Draw(out)
    try:
        font = ImageFont.truetype("C:/Windows/Fonts/consola.ttf", 14)
    except Exception:
        font = ImageFont.load_default()
    for d in range(8):
        cell = sheet.crop((d * CW, aim_row * CH, (d + 1) * CW, (aim_row + 1) * CH))
        cell = cell.resize((CW * scale, CH * scale), Image.LANCZOS)
        x = pad + d * (pw + pad)
        out.alpha_composite(cell, (x, pad + 22))
        dr.text((x + 6, pad + 4), labels[d], fill=(242, 160, 61, 255), font=font)
    p1 = ROOT / "tools" / "previews" / "doll_a_preview_8dir.png"
    p1.parent.mkdir(parents=True, exist_ok=True)
    out.save(p1)
    print(f"[preview] {p1}")

    # 动画预览（正面，1.5x）
    scale = 1
    rows = len(ANIMS)
    maxf = max(a[1] for a in ANIMS)
    pw, ph = CW, CH + 18
    out = Image.new("RGBA", (pw * maxf + pad * (maxf + 1), ph * rows + pad * (rows + 1)), (18, 21, 26, 255))
    dr = ImageDraw.Draw(out)
    for ri, (name, count, fps, loop) in enumerate(ANIMS):
        start = ROW_INDEX[name]
        for f in range(count):
            cell = sheet.crop((0, (start + f) * CH, CW, (start + f + 1) * CH))
            x = pad + f * (pw + pad)
            y = pad + ri * (ph + pad)
            out.alpha_composite(cell, (x, y + 18))
        dr.text((pad, pad + ri * (ph + pad) + 2), name.upper(), fill=(79, 209, 224, 255), font=font)
    p2 = ROOT / "tools" / "previews" / "doll_a_preview_anims.png"
    out.save(p2)
    print(f"[preview] {p2}")


# ---------------------------------------------------------------- FX
def build_fx():
    fx = ART / "fx"
    fx.mkdir(parents=True, exist_ok=True)

    # 贴地软阴影
    n = 128
    yy, xx = np.mgrid[0:n, 0:n]
    dx = (xx - n / 2) / (n / 2)
    dy = (yy - n / 2) / (n / 2)
    r = np.sqrt(dx * dx + dy * dy)
    a = np.clip(1.0 - r, 0, 1) ** 1.12
    a *= 0.95
    img = np.zeros((n, n, 4), np.uint8)
    img[..., 3] = (a * 255).astype(np.uint8)
    Image.fromarray(img, "RGBA").save(fx / "shadow_radial.png")

    # 准星
    n = 128
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    dr = ImageDraw.Draw(img)
    dr.ellipse([10, 10, n - 10, n - 10], outline=(242, 160, 61, 210), width=3)
    for ang in (0, 90, 180, 270):
        a = math.radians(ang)
        x1 = n / 2 + math.cos(a) * 34
        y1 = n / 2 + math.sin(a) * 34
        x2 = n / 2 + math.cos(a) * 52
        y2 = n / 2 + math.sin(a) * 52
        dr.line([x1, y1, x2, y2], fill=(242, 160, 61, 230), width=3)
    dr.ellipse([n / 2 - 3, n / 2 - 3, n / 2 + 3, n / 2 + 3], fill=(255, 236, 200, 255))
    img.save(fx / "reticle_ring.png")

    # 枪口火光
    n = 128
    yy, xx = np.mgrid[0:n, 0:n]
    dx = (xx - n / 2) / (n / 2)
    dy = (yy - n / 2) / (n / 2)
    r = np.sqrt(dx * dx + dy * dy)
    th = np.arctan2(dy, dx)
    spikes = 0.55 + 0.45 * np.abs(np.cos(th * 3.0))
    core = np.clip(1.0 - r * 1.5, 0, 1) ** 1.4
    glow = np.clip(1.0 - r, 0, 1) ** 2.2 * spikes
    val = np.clip(core * 1.3 + glow * 0.8, 0, 1)
    rgba = np.zeros((n, n, 4), np.uint8)
    rgba[..., 0] = 255
    rgba[..., 1] = (150 + 105 * core).astype(np.uint8)
    rgba[..., 2] = (60 + 160 * core).astype(np.uint8)
    rgba[..., 3] = (val * 255).astype(np.uint8)
    Image.fromarray(rgba, "RGBA").save(fx / "muzzle_flash.png")


# ---------------------------------------------------------------- 环境
def periodic_noise(size, octaves, seed):
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:size, 0:size]
    out = np.zeros((size, size), np.float32)
    for o in range(octaves):
        f = 2 ** o
        for _ in range(3):
            fx, fy = rng.integers(1, f + 2, 2)
            ph = rng.random() * math.tau
            amp = 1.0 / (f ** 0.85)
            out += amp * np.sin(math.tau * (fx * xx / size + fy * yy / size) + ph)
    out -= out.min()
    out /= max(out.max(), 1e-6)
    return out


def build_env():
    env = ART / "env"
    env.mkdir(parents=True, exist_ok=True)
    size = 512
    rng = np.random.default_rng(20261025)
    yy, xx = np.mgrid[0:size, 0:size]

    # 混凝土地面
    base = periodic_noise(size, 4, 7) * 22 + 46
    grain = rng.normal(0, 2.6, (size, size))
    v = base + grain
    # 网格缝
    grid = ((xx % 128 < 2) | (yy % 128 < 2)).astype(np.float32)
    v -= grid * 8
    hi = ((xx % 128 >= 2) & (xx % 128 < 4) | (yy % 128 >= 2) & (yy % 128 < 4)).astype(np.float32)
    v += hi * 3
    # 污渍
    for _ in range(18):
        cx, cy = rng.integers(0, size, 2)
        rad = rng.integers(14, 60)
        m = ((xx - cx) ** 2 + (yy - cy) ** 2) < rad * rad
        v[m] -= rng.uniform(2, 7)
    rgb = np.stack([v * 0.92, v * 0.97, v * 1.06], axis=-1)
    rgb = np.clip(rgb, 0, 255).astype(np.uint8)
    Image.fromarray(rgb, "RGB").save(env / "concrete_floor.png")

    # 混凝土墙
    base = periodic_noise(size, 4, 11) * 20 + 40
    grain = rng.normal(0, 2.2, (size, size))
    v = base + grain
    seam = ((xx % 256 < 3) | (yy % 256 < 3)).astype(np.float32)
    v -= seam * 10
    # 锈迹竖纹
    for _ in range(26):
        sx = rng.integers(0, size)
        w = rng.integers(2, 7)
        ln = rng.integers(40, 240)
        y0 = rng.integers(0, size - ln)
        m = (np.abs(xx - sx) < w) & (yy > y0) & (yy < y0 + ln)
        v[m] -= rng.uniform(4, 12)
    rgb = np.stack([v * 1.0, v * 0.98, v * 0.94], axis=-1)
    rgb = np.clip(rgb, 0, 255).astype(np.uint8)
    Image.fromarray(rgb, "RGB").save(env / "concrete_wall.png")

    # 警示斜纹
    n = 256
    yy, xx = np.mgrid[0:n, 0:n]
    band = (((xx + yy) // 26) % 2).astype(np.float32)
    rgb = np.zeros((n, n, 3), np.uint8)
    amber = np.array([228, 148, 52])
    dark = np.array([26, 29, 34])
    rgb[..., :] = (band[..., None] * amber + (1 - band[..., None]) * dark).astype(np.uint8)
    wear = (periodic_noise(n, 3, 21) * 26 - 13)[..., None]
    rgb = np.clip(rgb.astype(np.float32) + wear, 0, 255).astype(np.uint8)
    Image.fromarray(rgb, "RGB").save(env / "hazard_stripe.png")

    # 终端屏（青）
    w, h = 256, 128
    img = Image.new("RGBA", (w, h), (6, 18, 22, 255))
    dr = ImageDraw.Draw(img)
    for x in range(0, w, 32):
        dr.line([x, 0, x, h], fill=(20, 70, 80, 255), width=1)
    for y in range(0, h, 16):
        dr.line([0, y, w, y], fill=(20, 70, 80, 255), width=1)
    for _ in range(18):
        x = rng.integers(6, w - 60)
        y = rng.integers(6, h - 8)
        bw = rng.integers(10, 56)
        dr.rectangle([x, y, x + bw, y + 3], fill=(79, 209, 224, 200))
    for i in range(0, h, 3):
        dr.line([0, i, w, i], fill=(0, 0, 0, 26), width=1)
    img.save(env / "terminal_screen.png")

    # 训练靶板
    tw, th = 256, 384
    img = Image.new("RGBA", (tw, th), (0, 0, 0, 0))
    dr = ImageDraw.Draw(img)
    dr.rounded_rectangle([10, 10, tw - 10, th - 10], radius=14, fill=(21, 25, 31, 255), outline=(242, 160, 61, 255), width=4)
    cx, cy = tw // 2, int(th * 0.43)
    for r, c in [
        (94, (48, 54, 64)),
        (76, (226, 233, 240)),
        (58, (198, 70, 54)),
        (40, (238, 158, 58)),
        (22, (26, 30, 36)),
        (9, (242, 160, 61)),
    ]:
        dr.ellipse([cx - r, cy - r, cx + r, cy + r], fill=c)
    dr.line([cx - 102, cy, cx + 102, cy], fill=(242, 160, 61, 170), width=2)
    dr.line([cx, cy - 102, cx, cy + 102], fill=(242, 160, 61, 170), width=2)
    for i in range(8):
        dr.rectangle([42 + i * 22, th - 72, 50 + i * 22, th - 34], fill=(220, 228, 236, 255) if i % 2 == 0 else (40, 46, 54, 255))
    try:
        f = ImageFont.truetype("C:/Windows/Fonts/consola.ttf", 26)
    except Exception:
        f = ImageFont.load_default()
    dr.text((62, 22), "T-01 // TRAINING", fill=(242, 160, 61, 255), font=f)
    dr.text((58, th - 28), "RANGE 25M", fill=(120, 200, 215, 255), font=f)
    img.save(env / "target_board.png")


# ---------------------------------------------------------------- 主流程
def main():
    ART.mkdir(parents=True, exist_ok=True)
    sheet = build_sheet()
    build_previews(sheet)
    build_fx()
    build_env()
    print("[done] placeholder art generated")


if __name__ == "__main__":
    main()
