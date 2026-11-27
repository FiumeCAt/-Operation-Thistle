#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""1:1 像素换皮契约通用构建工具（服务于 doll_v2、doll_thistle 及后续正式角色皮肤包）。

严格遵循 docs/character_skin_contract.md 与 assets/art/characters/mannequin/skin_manifest.json：
  - 19 个身体分件 PNG 尺寸严格 == 契约 (W, H)，保证 DollRigV2 运行时 scale == (1.0, 1.0)；
  - 3 个横置持枪双臂分件严格 26×14 / 27×13 / 12×10，匹配 WeaponRig2D 0.5× 缩放与 2-Bone IK；
  - 所有关节切口保留 2–4px 圆角重叠包边，且外轮廓统一使用 1px 选择性暗描边（sel-out）不越界截断。
"""

from __future__ import annotations

import json
import math
from pathlib import Path
from typing import Callable

import numpy as np
from PIL import Image, ImageDraw, ImageEnhance

from pixel_char_pipeline import (
    add_selective_outline,
    apply_palette,
    build_locked_palette,
    harden_alpha,
    premul_box_resize,
    remove_isolated_pixels,
)

RGBA = tuple[int, int, int, int]

# ---- 严格锁定契约表（与 mannequin/skin_manifest.json 100% 同尺寸、同偏移、同枢轴）----
PARTS_CONTRACT: dict[str, dict] = {
    "head_front": {"width": 38, "height": 36, "target_h": 36, "offset": [0, -14], "pivots_px": {"neck": [18.5, 32]}, "z_index": {"0": 5}, "flip_rule": "none", "role": "正面头部（视线朝向镜头）"},
    "head_front_blink": {"width": 38, "height": 36, "target_h": 36, "offset": [0, -14], "pivots_px": {"neck": [18.5, 32]}, "z_index": {"0": 6}, "flip_rule": "none", "role": "正面独立眨眼覆盖层"},
    "head_back": {"width": 38, "height": 36, "target_h": 36, "offset": [0, -14], "pivots_px": {"neck": [18.5, 32]}, "z_index": {"1": 5}, "flip_rule": "none", "role": "背面头部"},
    "head_left": {"width": 36, "height": 36, "target_h": 36, "offset": [0, -14], "pivots_px": {"neck": [18, 32]}, "z_index": {"2": 5, "3": 5}, "flip_rule": "flip_h_when_dir_3", "role": "侧视头部（原图朝左 -X）"},
    "head_left_blink": {"width": 36, "height": 36, "target_h": 36, "offset": [0, -14], "pivots_px": {"neck": [18, 32]}, "z_index": {"2": 6, "3": 6}, "flip_rule": "flip_h_when_dir_3", "role": "侧视独立眨眼覆盖层（原图朝左）"},
    "torso_front": {"width": 36, "height": 46, "target_h": 46, "offset": [0, -20], "pivots_px": {"pelvis": [18, 43], "neck": [18, 4], "shoulder_l": [28, 10], "shoulder_r": [8, 10]}, "z_index": {"0": 1}, "flip_rule": "none", "role": "正面无臂躯干"},
    "torso_back": {"width": 34, "height": 46, "target_h": 46, "offset": [0, -20], "pivots_px": {"pelvis": [17, 43], "neck": [17, 4], "shoulder_l": [7, 10], "shoulder_r": [27, 10]}, "z_index": {"1": 1}, "flip_rule": "none", "role": "背面无臂躯干"},
    "torso_left": {"width": 26, "height": 46, "target_h": 46, "offset": [0, -20], "pivots_px": {"pelvis": [13, 43], "neck": [13, 4], "shoulder": [13, 10]}, "z_index": {"2": 1, "3": 1}, "flip_rule": "flip_h_when_dir_3", "role": "侧视无臂躯干（原图朝左 -X）"},
    "hair_back_root": {"width": 26, "height": 18, "target_h": 18, "offset": [0, 5], "pivots_px": {"root": [13, 4]}, "z_index": {"0": -1, "1": 4, "2": -1, "3": -1}, "flip_rule": "flip_h_when_dir_3", "role": "次级物理后发上段"},
    "hair_back_tip": {"width": 20, "height": 12, "target_h": 12, "offset": [0, 4], "pivots_px": {"joint": [10, 2]}, "z_index": {"0": -1, "1": 4, "2": -1, "3": -1}, "flip_rule": "flip_h_when_dir_3", "role": "次级物理后发发梢"},
    "hair_side": {"width": 6, "height": 12, "target_h": 12, "offset": [0, 5], "pivots_px": {"root": [3, 1]}, "z_index": {"0": 4}, "flip_rule": "mirror_right_side", "role": "正面两侧鬓发微动片"},
    "coat_flap_root": {"width": 14, "height": 21, "target_h": 21, "offset": [0, 9], "pivots_px": {"root": [7, 1.5]}, "z_index": {"0": 0, "1": 0, "2": 0, "3": 0}, "flip_rule": "mirror_right_flap", "role": "次级物理衣摆上段"},
    "coat_flap_tip": {"width": 12, "height": 13, "target_h": 13, "offset": [0, 5], "pivots_px": {"joint": [6, 1.5]}, "z_index": {"0": 0, "1": 0, "2": 0, "3": 0}, "flip_rule": "mirror_right_flap", "role": "次级物理衣摆下段"},
    "skirt_hem": {"width": 34, "height": 13, "target_h": 13, "offset": [0, 3], "pivots_px": {"waist": [17, 3.5]}, "z_index": {"0": -1, "1": -1}, "flip_rule": "hidden_on_side", "role": "正/背面裙摆下沿微摆片"},
    "thigh": {"width": 10, "height": 33, "target_h": 33, "offset": [0, 13], "pivots_px": {"hip": [5, 3.5], "knee": [5, 29.5]}, "z_index": {"near": -2, "far": -4, "front_back": -3}, "flip_rule": "flip_h_when_lower_dir_3", "role": "大腿段（含上下 3.5px 圆角重叠包边）"},
    "shin_boot": {"width": 14, "height": 34, "target_h": 34, "offset": [0, 14], "pivots_px": {"knee": [7, 3], "ankle": [7, 25], "sole_y": 33}, "z_index": {"near": -2, "far": -4, "front_back": -3}, "flip_rule": "flip_h_when_lower_dir_3", "role": "小腿+鞋靴段（原图鞋尖朝左 -X）"},
    "gun_case": {"width": 18, "height": 64, "target_h": 64, "offset": [0, -6], "pivots_px": {"mount": [9, 38]}, "z_index": {"0": -6, "1": 7, "2": -2, "3": -2}, "flip_rule": "flip_h_when_dir_3", "role": "背后战术装备/枪盒挂件"},
    "arm_upper": {"width": 10, "height": 20, "target_h": 20, "offset": [0, 7], "pivots_px": {"shoulder": [5, 3], "elbow": [5, 17]}, "z_index": {"0": 4, "1": -2, "near": 4, "far": -3}, "flip_rule": "flip_h_when_dir_3", "role": "收枪状态上臂段（含肩/肘 3px 包边）"},
    "arm_forearm": {"width": 10, "height": 20, "target_h": 20, "offset": [0, 7], "pivots_px": {"elbow": [5, 3], "wrist": [5, 15]}, "z_index": {"0": 4, "1": -2, "near": 4, "far": -3}, "flip_rule": "flip_h_when_dir_3", "role": "收枪状态前臂与手部"},
}

OPTIONAL_PARTS: set[str] = {"gun_case"}

ARM2_CONTRACT: dict[str, dict] = {
    "upper_arm": {"width": 26, "height": 14, "arm_scale": 0.5, "world_size": [13.0, 7.0], "offset": [13.0, 0.0], "pivots_px": {"shoulder": [3, 7], "elbow": [22, 7]}, "role": "持枪水平上臂（左肩→右肘，0.5× 缩放）"},
    "forearm": {"width": 27, "height": 13, "arm_scale": 0.5, "world_size": [13.5, 6.5], "offset": [13.5, 0.0], "pivots_px": {"elbow": [3, 6.5], "wrist": [23, 6.5]}, "role": "持枪水平前臂（左肘→右腕，0.5× 缩放）"},
    "hand": {"width": 12, "height": 10, "arm_scale": 0.5, "world_size": [6.0, 5.0], "offset": [0.0, 0.0], "pivots_px": {"grip": [6, 5]}, "role": "持枪握持手掌（居中对齐握把，0.5× 缩放）"},
}


def new_img(w: int, h: int) -> Image.Image:
    return Image.new("RGBA", (w, h), (0, 0, 0, 0))


def put(img: Image.Image, x: int, y: int, col: RGBA) -> None:
    if 0 <= x < img.width and 0 <= y < img.height:
        img.putpixel((x, y), col)


def put_rect(img: Image.Image, x0: int, y0: int, x1: int, y1: int, col: RGBA) -> None:
    for y in range(max(0, y0), min(img.height, y1 + 1)):
        for x in range(max(0, x0), min(img.width, x1 + 1)):
            img.putpixel((x, y), col)


def crop_tight(img: Image.Image, box: tuple[int, int, int, int] | None = None, pad: int = 2) -> Image.Image:
    sub = img.crop(box) if box is not None else img
    bb = sub.getbbox()
    if bb is None:
        return sub
    x0 = max(0, bb[0] - pad)
    y0 = max(0, bb[1] - pad)
    x1 = min(sub.width, bb[2] + pad)
    y1 = min(sub.height, bb[3] + pad)
    return sub.crop((x0, y0, x1, y1))


def enhance_rgba(img: Image.Image, contrast: float = 1.0, saturation: float = 1.0, brightness: float = 1.0) -> Image.Image:
    """Enhance RGB channels while preserving exact alpha."""
    rgba = img.convert("RGBA")
    r, g, b, a = rgba.split()
    rgb = Image.merge("RGB", (r, g, b))
    if contrast != 1.0:
        rgb = ImageEnhance.Contrast(rgb).enhance(contrast)
    if saturation != 1.0:
        rgb = ImageEnhance.Color(rgb).enhance(saturation)
    if brightness != 1.0:
        rgb = ImageEnhance.Brightness(rgb).enhance(brightness)
    nr, ng, nb = rgb.split()
    return Image.merge("RGBA", (nr, ng, nb, a))


def fit_to_contract_canvas(
    src: Image.Image,
    canvas_w: int,
    canvas_h: int,
    pad_left: int = 1,
    pad_right: int = 1,
    pad_top: int = 1,
    pad_bottom: int = 1,
    align_x: str = "center",
    align_y: str = "bottom",
    shift_x: int = 0,
    shift_y: int = 0,
    alpha_thresh: int = 122,
) -> Image.Image:
    """Scale high-res sprite cleanly into exact contract (canvas_w, canvas_h) leaving room for 1px sel-out."""
    tight = crop_tight(src, pad=0)
    avail_w = max(2, canvas_w - pad_left - pad_right)
    avail_h = max(2, canvas_h - pad_top - pad_bottom)
    scale = min(avail_w / float(max(tight.width, 1)), avail_h / float(max(tight.height, 1)))
    tw = max(2, int(round(tight.width * scale)))
    th = max(2, int(round(tight.height * scale)))
    down = premul_box_resize(tight, (tw, th))
    down = remove_isolated_pixels(harden_alpha(down, threshold=alpha_thresh))
    canvas = new_img(canvas_w, canvas_h)
    if align_x == "left":
        ox = pad_left
    elif align_x == "right":
        ox = canvas_w - pad_right - tw
    else:
        ox = pad_left + (avail_w - tw) // 2
    if align_y == "top":
        oy = pad_top
    elif align_y == "center":
        oy = pad_top + (avail_h - th) // 2
    else:
        oy = canvas_h - pad_bottom - th
    canvas.paste(down, (ox + shift_x, oy + shift_y), down)
    return canvas


def add_neck_overlap(img: Image.Image, neck_rgb: tuple[int, int, int], shade_rgb: tuple[int, int, int], cx: float | None = None) -> Image.Image:
    """Ensure a subtle tucked neck-stump cap centered at (cx, 31.5) beneath the chin so head rotation never shows gaps."""
    out = img.copy()
    w, h = out.size
    if cx is None:
        cx = (w - 1) * 0.5
    px = out.load()
    for y in range(max(0, h - 6), h - 2):
        dy = (y - 31.0) / 2.6
        if abs(dy) > 1.0:
            continue
        rx = 2.6 * math.sqrt(max(0.0, 1.0 - dy * dy))
        for x in range(1, w - 1):
            if abs(x - cx) <= rx + 0.15 and px[x, y][3] == 0:
                col = shade_rgb if (y >= h - 4 or abs(x - cx) > rx * 0.50) else neck_rgb
                px[x, y] = (col[0], col[1], col[2], 255)
    return out


def add_torso_collar_and_pelvis_caps(
    img: Image.Image,
    collar_rgb: tuple[int, int, int],
    pelvis_rgb: tuple[int, int, int],
    trim_shoulders: bool = False,
    max_shoulder_half_w: float = 13.5,
) -> Image.Image:
    """Cleanly refine torso shoulder contours (removing stray sleeve stubs) and keep collar/pelvis intact."""
    out = img.copy()
    w, h = out.size
    cx = (w - 1) * 0.5
    px = out.load()
    if trim_shoulders:
        # Smoothly taper upper shoulder region (y=5..20) to avoid floating stubby sleeve nubs
        for y in range(4, 22):
            t = (y - 4) / 18.0
            allowed = max_shoulder_half_w * (0.72 + 0.28 * math.sin(min(1.0, t * 1.45) * math.pi * 0.5))
            for x in range(w):
                if abs(x - cx) > allowed:
                    px[x, y] = (0, 0, 0, 0)
    # Ensure solid collar base at y=2..5 (neck pivot at y=4) without leaving hollow top gap
    for y in range(2, 6):
        for x in range(int(round(cx - 3)), int(round(cx + 3)) + 1):
            if 1 <= x < w - 1 and px[x, y][3] == 0 and y >= 3:
                # Only fill if flanked or supported below
                if px[x, min(h - 1, y + 1)][3] > 0:
                    px[x, y] = (collar_rgb[0], collar_rgb[1], collar_rgb[2], 255)
    return out


def draw_vertical_limb_capsule(
    w: int,
    h: int,
    top_r: float,
    bot_r: float,
    base_col: RGBA,
    hi_col: RGBA,
    shade_col: RGBA,
    half_w_top: float | None = None,
    half_w_bot: float | None = None,
    inset: int = 1,
) -> Image.Image:
    """Draw a sleek vertical articulated limb (leaving 1px margin for clean sel-out outline)."""
    img = new_img(w, h)
    cx = (w - 1) * 0.5
    max_rx = max(1.2, (w - 1 - 2 * inset) * 0.5)
    rx_top = half_w_top if half_w_top is not None else max_rx
    rx_bot = half_w_bot if half_w_bot is not None else max_rx
    y_start = inset
    y_end = h - 1 - inset
    span = max(1.0, float(y_end - y_start))
    for y in range(y_start, y_end + 1):
        t = (y - y_start) / span
        rx_mid = rx_top + (rx_bot - rx_top) * t
        if y - y_start < top_r:
            dy = (top_r - (y - y_start)) / max(top_r, 1.0)
            rx = rx_mid * math.sqrt(max(0.0, 1.0 - dy * dy))
        elif y_end - y < bot_r:
            dy = (bot_r - (y_end - y)) / max(bot_r, 1.0)
            rx = rx_mid * math.sqrt(max(0.0, 1.0 - dy * dy))
        else:
            rx = rx_mid
        for x in range(inset, w - inset):
            if abs(x - cx) <= rx + 0.18:
                if x - cx < -rx * 0.22:
                    col = hi_col
                elif x - cx > rx * 0.28:
                    col = shade_col
                else:
                    col = base_col
                img.putpixel((x, y), col)
    return img


def draw_horizontal_arm2_capsule(
    w: int,
    h: int,
    left_r: float,
    right_r: float,
    base_col: RGBA,
    hi_col: RGBA,
    shade_col: RGBA,
    taper_right: float = 0.08,
    inset: int = 1,
) -> Image.Image:
    """Draw horizontal (+X) weapon-holding arm segment with rounded shoulder/elbow/wrist overlap."""
    img = new_img(w, h)
    cy = (h - 1) * 0.5
    max_ry = max(1.5, (h - 1 - 2 * inset) * 0.5)
    x_start = inset
    x_end = w - 1 - inset
    for x in range(x_start, x_end + 1):
        if x - x_start < left_r:
            dx = (left_r - (x - x_start)) / max(left_r, 1.0)
            ry = max_ry * math.sqrt(max(0.0, 1.0 - dx * dx))
        elif x_end - x < right_r:
            dx = (right_r - (x_end - x)) / max(right_r, 1.0)
            ry = max_ry * (1.0 - taper_right) * math.sqrt(max(0.0, 1.0 - dx * dx))
        else:
            t = (x - x_start - left_r) / max(1.0, (x_end - right_r) - (x_start + left_r))
            ry = max_ry * (1.0 - taper_right * t)
        if ry < 1.15:
            continue
        for y in range(inset, h - inset):
            if abs(y - cy) <= ry + 0.15:
                if y < cy - ry * 0.22:
                    col = hi_col
                elif y > cy + ry * 0.28:
                    col = shade_col
                else:
                    col = base_col
                img.putpixel((x, y), col)
    return img


def draw_gripping_hand(
    w: int,
    h: int,
    palm_base: RGBA,
    palm_hi: RGBA,
    palm_shade: RGBA,
    accent_col: RGBA | None = None,
) -> Image.Image:
    """Compact rounded gripping hand/glove (12×10) centered at (6, 5) that wraps cleanly around grips."""
    img = new_img(w, h)
    cx, cy = (w - 1) * 0.5, (h - 1) * 0.5
    for y in range(1, h - 1):
        for x in range(1, w - 1):
            # Rounded fist/grip silhouette slightly curled on right/bottom
            dx = (x - cx) / 4.2
            dy = (y - cy) / 3.3
            if dx * dx + dy * dy <= 1.0:
                if y < cy - 1.0:
                    col = palm_hi
                elif y > cy + 1.0 or x > cx + 1.8:
                    col = palm_shade
                else:
                    col = palm_base
                img.putpixel((x, y), col)
    # Subtle knuckle / finger separation crease + optional fingerless tactical strap
    if accent_col is not None:
        put_rect(img, 3, 3, 5, 6, accent_col)
    put(img, 7, 4, palm_shade)
    put(img, 8, 5, palm_shade)
    put(img, 7, 6, palm_shade)
    return img


def draw_side_shin_and_footwear(
    shin_base: RGBA,
    shin_hi: RGBA,
    shin_shade: RGBA,
    boot_base: RGBA,
    boot_hi: RGBA,
    boot_shade: RGBA,
    sole_col: RGBA,
    midsole_col: RGBA,
    lace_col: RGBA,
    boot_top_y: int = 24,
    knee_hi: RGBA | None = None,
    knee_crease: RGBA | None = None,
    boot_cuff_col: RGBA | None = None,
    sole_thick: int = 2,
) -> Image.Image:
    """Build exact 14×34 side-profile shin + footwear (knee=(7,3), ankle=(7,25), sole flush y=33, toe pointing -X)."""
    w, h = 14, 34
    img = new_img(w, h)
    cx = 7.5
    # 1) Shin column (y=1..boot_top_y+2, leaving y=0 for 1px sel-out cap)
    for y in range(1, min(31, boot_top_y + 3)):
        if y - 1 < 3.0:
            dy = (3.0 - (y - 1)) / 3.0
            rx = 3.0 * math.sqrt(max(0.0, 1.0 - dy * dy))
        else:
            t = (y - 4.0) / max(1.0, float(boot_top_y - 4))
            rx = 3.0 - 0.55 * min(1.0, max(0.0, t))
        for x in range(1, w - 1):
            if abs(x - cx) <= rx + 0.15:
                if x < cx - 0.8:
                    col = shin_hi
                elif x > cx + 1.1:
                    col = shin_shade
                else:
                    col = shin_base
                img.putpixel((x, y), col)

    # Subtle knee-cap articulation highlight + crease (y=3..6)
    if knee_hi is not None:
        put_rect(img, 5, 3, 7, 4, knee_hi)
    if knee_crease is not None:
        put_rect(img, 6, 5, 9, 5, knee_crease)

    # 2) Boot shaft / cuff (if tall combat boot, boot_top_y < 24)
    if boot_top_y < 25:
        for y in range(boot_top_y, 26):
            hw = 3.2 if y == boot_top_y else 3.0
            for x in range(1, w - 1):
                if abs(x - cx) <= hw + 0.15:
                    if y == boot_top_y and boot_cuff_col is not None:
                        col = boot_cuff_col
                    elif x < cx - 0.8:
                        col = boot_hi
                    elif x > cx + 1.2:
                        col = boot_shade
                    else:
                        col = boot_base
                    img.putpixel((x, y), col)
        # Lace eyelets down front edge of boot shaft
        for ly in range(boot_top_y + 2, 26, 2):
            put(img, 5, ly, lace_col)

    # 3) Foot & toe box pointing clearly LEFT (-X: toe at x=2, heel at x=11, leaving x=1/12 for 1px sel-out!)
    sole_y0 = 33 - sole_thick
    for y in range(25, 33):
        if y == 25:
            x0, x1 = 5, 10
        elif y == 26:
            x0, x1 = 4, 11
        elif y == 27:
            x0, x1 = 3, 11
        elif y == 28:
            x0, x1 = 2, 11
        else:
            x0, x1 = 2, 11
        for x in range(x0, x1 + 1):
            if y >= sole_y0:
                col = sole_col
            elif y == sole_y0 - 1:
                col = midsole_col
            elif x <= 4 and y <= 29:
                col = boot_hi
            elif x >= 9:
                col = boot_shade
            else:
                col = boot_base
            img.putpixel((x, y), col)

    # Crisp sneaker/boot lace & strap detail on vamp (x=4..6, y=26..28)
    put(img, 5, 26, lace_col)
    put(img, 4, 27, lace_col)
    put(img, 6, 27, lace_col)
    if boot_top_y >= 24:
        # Diagonal sneaker side-stripe (matches grey tactical sneaker in reference!)
        put(img, 7, 29, midsole_col)
        put(img, 8, 28, midsole_col)
        put(img, 9, 27, boot_hi)
    return img


def draw_hair_back_segments(
    base_col: RGBA,
    hi_col: RGBA,
    shade_col: RGBA,
    deep_col: RGBA,
    style: str = "bob",
) -> tuple[Image.Image, Image.Image, Image.Image]:
    """Generate native 1:1 hair_back_root (26×18), hair_back_tip (20×12), hair_side (6×12)."""
    # 1) hair_back_root (26×18, root pivot=(13, 4))
    root = new_img(26, 18)
    cx = 12.5
    if style == "ponytail":
        # Silky high-ponytail flowing volume (sleek gathered root widening into layered glossy strands)
        for y in range(1, 17):
            t = (y - 1) / 15.0
            hw = 4.2 + 4.8 * math.sin(min(1.0, t * 1.15) * math.pi * 0.76)
            shift = 1.0 * t
            for x in range(1, 25):
                dx = x - (cx + shift)
                if abs(dx) <= hw:
                    strand = math.sin(dx * 1.15 + t * 1.3)
                    sheen_y = 5.0 + 1.1 * math.sin(dx * 0.7)
                    if abs(y - sheen_y) <= 0.9 and abs(dx) < hw * 0.62 and strand > -0.15:
                        col = hi_col
                    elif abs(dx) > hw * 0.70 or strand < -0.58:
                        col = shade_col
                    elif y > 13 and ((x + y) % 4 == 0):
                        col = deep_col
                    else:
                        col = base_col
                    root.putpixel((x, y), col)
        for gap_x in (6, 11, 16, 20):
            put(root, gap_x, 16, (0, 0, 0, 0))
            put(root, gap_x, 15, deep_col)
    else:
        # Lush shoulder-length bob back hair (soft rounded dome tapering into natural multi-strand wispy tips)
        for y in range(1, 16):
            t = (y - 1) / 14.0
            if y <= 5:
                hw = 5.6 + 4.6 * math.sin(((y - 1) / 4.0) * math.pi * 0.5)
            else:
                hw = 10.2 - 2.0 * ((y - 5) / 10.0) ** 1.2
            for x in range(1, 25):
                dx = x - cx
                if abs(dx) <= hw:
                    strand = math.sin(dx * 1.05 + y * 0.12)
                    sheen_y = 5.5 + 1.0 * math.cos(dx * 0.65)
                    if abs(y - sheen_y) <= 0.75 and abs(dx) < hw * 0.62 and strand > -0.1:
                        col = hi_col
                    elif abs(dx) > hw * 0.72 or strand < -0.55:
                        col = shade_col
                    elif y >= 13 and ((x % 4) == 0):
                        col = deep_col
                    else:
                        col = base_col
                    root.putpixel((x, y), col)
        for gx in (5, 9, 13, 17, 20):
            put(root, gx, 15, (0, 0, 0, 0))
            if gx in (9, 17):
                put(root, gx, 14, (0, 0, 0, 0))

    # 2) hair_back_tip (20×12, joint pivot=(10, 2))
    tip = new_img(20, 12)
    tcx = 9.5
    if style == "ponytail":
        # Long flowing ponytail tail tips (distinct sculpted twin/triple silky points)
        for y in range(1, 11):
            t = (y - 1) / 9.0
            hw = 7.4 * (1.0 - 0.68 * (t ** 1.15))
            shift = 1.6 * t
            for x in range(1, 19):
                dx = x - (tcx + shift)
                if abs(dx) <= hw:
                    if y <= 3 and abs(dx) < hw * 0.6:
                        col = hi_col
                    elif abs(dx) > hw * 0.62 or y >= 9:
                        col = shade_col
                    else:
                        col = base_col
                    tip.putpixel((x, y), col)
        # Sculpted trailing wisp notch
        put(tip, 8, 9, (0, 0, 0, 0))
        put(tip, 8, 10, (0, 0, 0, 0))
        put(tip, 14, 10, (0, 0, 0, 0))
    else:
        # Subtle soft bob under-tips (compact wispy fringe so bob doesn't look overly long)
        for y in range(1, 10):
            t = (y - 1) / 8.0
            hw = 7.6 * (1.0 - 0.58 * (t ** 1.25))
            for x in range(1, 19):
                dx = x - tcx
                if abs(dx) <= hw:
                    if y <= 2 and abs(dx) < hw * 0.6:
                        col = hi_col
                    elif abs(dx) > hw * 0.65 or y >= 8:
                        col = shade_col
                    else:
                        col = base_col
                    tip.putpixel((x, y), col)
        for gx in (5, 9, 13):
            put(tip, gx, 8, (0, 0, 0, 0))
            put(tip, gx, 9, (0, 0, 0, 0))

    # 3) hair_side (6×12, root pivot=(3, 1))
    side = new_img(6, 12)
    for y in range(1, 11):
        t = (y - 1) / 9.0
        # Curved framing strand tapering to a delicate tip
        center = 2.6 - 0.6 * math.sin(t * math.pi * 0.7)
        hw = 1.55 * (1.0 - 0.65 * (t ** 1.3))
        for x in range(1, 5):
            if abs(x - center) <= hw:
                if y in (2, 3):
                    col = hi_col
                elif y >= 8 or x > center + 0.4:
                    col = shade_col
                else:
                    col = base_col
                side.putpixel((x, y), col)

    return root, tip, side


def soften_joint_cap_outline(
    img: Image.Image,
    top_rows: int = 0,
    bottom_rows: int = 0,
    left_cols: int = 0,
    right_cols: int = 0,
    cap_rgb: tuple[int, int, int] | None = None,
) -> Image.Image:
    """Replace harsh exterior dark outline pixels along internal overlapping joint caps (knee/elbow/hip/shoulder)
    with soft self-colored fill so overlapping limbs blend smoothly without a dark horizontal seam ring!"""
    arr = np.asarray(img.convert("RGBA"), dtype=np.uint8).copy()
    h, w, _ = arr.shape
    opaque = arr[:, :, 3] > 200

    def is_interior_cap_border(y: int, x: int) -> bool:
        # Only soften top/bottom cap borders on the inner span (keep left/right outer limb silhouettes crisp!)
        if top_rows > 0 and y < top_rows:
            # Check if this pixel is on the top arc (transparent above) AND has opaque left+right neighbors
            above_empty = (y == 0) or (not opaque[y - 1, x])
            left_ok = (x > 0) and opaque[y, x - 1]
            right_ok = (x + 1 < w) and opaque[y, x + 1]
            if above_empty and left_ok and right_ok:
                return True
        if bottom_rows > 0 and y >= h - bottom_rows:
            below_empty = (y == h - 1) or (not opaque[y + 1, x])
            left_ok = (x > 0) and opaque[y, x - 1]
            right_ok = (x + 1 < w) and opaque[y, x + 1]
            if below_empty and left_ok and right_ok:
                return True
        if left_cols > 0 and x < left_cols:
            left_empty = (x == 0) or (not opaque[y, x - 1])
            up_ok = (y > 0) and opaque[y - 1, x]
            dn_ok = (y + 1 < h) and opaque[y + 1, x]
            if left_empty and up_ok and dn_ok:
                return True
        if right_cols > 0 and x >= w - right_cols:
            right_empty = (x == w - 1) or (not opaque[y, x + 1])
            up_ok = (y > 0) and opaque[y - 1, x]
            dn_ok = (y + 1 < h) and opaque[y + 1, x]
            if right_empty and up_ok and dn_ok:
                return True
        return False

    for y in range(h):
        for x in range(w):
            if not opaque[y, x]:
                continue
            if is_interior_cap_border(y, x):
                if cap_rgb is not None:
                    arr[y, x, :3] = cap_rgb
                else:
                    # Sample interior neighbor pixel right inside the limb
                    ny = min(h - 1, y + 1) if (top_rows > 0 and y < top_rows) else (
                        max(0, y - 1) if (bottom_rows > 0 and y >= h - bottom_rows) else y
                    )
                    nx = min(w - 1, x + 1) if (left_cols > 0 and x < left_cols) else (
                        max(0, x - 1) if (right_cols > 0 and x >= w - right_cols) else x
                    )
                    if opaque[ny, nx]:
                        arr[y, x, :3] = arr[ny, nx, :3]
    return Image.fromarray(arr, mode="RGBA")


def draw_coat_or_dress_flaps(
    base_col: RGBA,
    hi_col: RGBA,
    shade_col: RGBA,
    trim_col: RGBA | None = None,
    trim_hi: RGBA | None = None,
    style: str = "trenchcoat",
) -> tuple[Image.Image, Image.Image]:
    """Generate native 1:1 coat_flap_root (14×21) and coat_flap_tip (12×13)."""
    root = new_img(14, 21)
    tip = new_img(12, 13)
    cx_r = 6.5
    cx_t = 5.5

    if style == "sailor_dress":
        # Align crimson hem strictly flush with torso skirt hem (y=13..15 in 14×21 root = Torso y=+0.5..+2.5),
        # eliminating any protruding double red hem while keeping crisp spring flare during motion!
        for y in range(2, 16):
            t = (y - 2) / 13.0
            hw = 2.4 + 2.6 * t
            shift = -0.5 * t
            for x in range(1, 13):
                dx = x - (cx_r + shift)
                if abs(dx) <= hw:
                    if trim_col is not None and y >= 14:
                        col = trim_hi if (dx < -hw * 0.2 and trim_hi is not None and y == 14) else trim_col
                    elif dx < -hw * 0.25:
                        col = hi_col
                    elif dx > hw * 0.35:
                        col = shade_col
                    else:
                        col = base_col
                    root.putpixel((x, y), col)
        # Compact fluttering dress-hem tip (y=1..4 inside 12×13 canvas) tucked flush behind root hem
        for y in range(1, 5):
            hw = 3.8 + 0.4 * ((y - 1) / 3.0)
            for x in range(1, 11):
                dx = x - cx_t
                if abs(dx) <= hw:
                    if trim_col is not None and y >= 3:
                        col = trim_hi if (dx < -hw * 0.2 and trim_hi is not None and y == 3) else trim_col
                    elif dx < -hw * 0.25:
                        col = hi_col
                    elif dx > hw * 0.35:
                        col = shade_col
                    else:
                        col = base_col
                    tip.putpixel((x, y), col)
    else:
        # Graceful dark-navy trenchcoat tail panel (tapered organic coat hem, sleek seamless flow)
        for y in range(1, 20):
            t = (y - 1) / 18.0
            hw = 2.6 + 2.7 * (t ** 0.85)
            shift = -0.5 * t
            for x in range(1, 13):
                dx = x - (cx_r + shift)
                if abs(dx) <= hw:
                    if dx < -hw * 0.32:
                        col = hi_col
                    elif dx > hw * 0.28 or (abs(dx - 0.5) < 0.6 and y > 6):
                        col = shade_col
                    else:
                        col = base_col
                    root.putpixel((x, y), col)
        # Sleek tapered coat tail tip (y=1..8 inside 12×13 canvas)
        for y in range(1, 9):
            t = (y - 1) / 7.0
            left_e = 1.6 + 1.0 * t
            right_e = 10.0 - 2.6 * (t ** 1.2)
            for x in range(1, 11):
                if left_e <= x <= right_e:
                    if trim_col is not None and y == 7:
                        col = trim_col
                    elif x < left_e + 1.8:
                        col = hi_col
                    elif x > right_e - 1.8:
                        col = shade_col
                    else:
                        col = base_col
                    tip.putpixel((x, y), col)

    return root, tip


def draw_pleated_skirt_hem(
    base_col: RGBA,
    hi_col: RGBA,
    shade_col: RGBA,
    trim_col: RGBA,
    plaid_col: RGBA | None = None,
) -> Image.Image:
    """Build exact 34×13 pleated skirt hem (waist pivot=(17, 3.5)) with gentle curved silhouette."""
    img = new_img(34, 13)
    cx = 16.5
    for y in range(1, 12):
        t = (y - 1) / 10.0
        hw = 12.4 + 2.4 * t
        for x in range(1, 33):
            dx = x - cx
            # Slight downward curve at center (+1px) for organic drape
            curve_y = y - (0 if abs(dx) < 9.5 else 1)
            if abs(dx) <= hw and curve_y >= 1 and y <= (11 if abs(dx) < 10.5 else 10):
                trim_row = 10 if abs(dx) < 10.5 else 9
                if y >= trim_row:
                    col = trim_col if (plaid_col is None or y == trim_row or (x % 3 != 0)) else hi_col
                else:
                    pleat = int(round(dx + 18)) % 5
                    if pleat == 0:
                        col = shade_col
                    elif pleat == 2 and y < trim_row - 1:
                        col = hi_col
                    elif plaid_col is not None and y in (4, 7) and (pleat != 0):
                        col = plaid_col
                    else:
                        col = base_col
                img.putpixel((x, y), col)
    return img


def finalize_and_export_skin(
    skin_id: str,
    display_name: str,
    out_root: Path,
    raw_parts: dict[str, Image.Image],
    raw_arm2: dict[str, Image.Image],
    palette_anchors: list[Image.Image],
    max_colors: int = 48,
    outline_strength: float = 0.34,
    post_quantize_hooks: dict[str, Callable[[Image.Image], Image.Image]] | None = None,
    extra_components_default: dict[str, bool] | None = None,
) -> tuple[dict[str, Image.Image], dict[str, Image.Image]]:
    """Quantize to 1 locked palette, apply 1px sel-out within strict 1:1 sizes, verify sizes, and write manifest."""
    palette = build_locked_palette(palette_anchors, max_colors=max_colors)
    out_parts = out_root / "parts"
    out_arm2 = out_root / "arm2"
    out_parts.mkdir(parents=True, exist_ok=True)
    out_arm2.mkdir(parents=True, exist_ok=True)

    saved_parts: dict[str, Image.Image] = {}
    parts_manifest: dict[str, dict] = {}
    hooks = post_quantize_hooks or {}

    for key, spec in PARTS_CONTRACT.items():
        if key not in raw_parts:
            if key in OPTIONAL_PARTS:
                # 清理历史遗留的可选分件 PNG 与 .import，防止无背包角色残留旧文件
                for stale in (out_parts / f"{key}.png", out_parts / f"{key}.png.import"):
                    if stale.exists():
                        stale.unlink()
                continue
            raise KeyError(f"[{skin_id}] missing required core part: {key}")
        im = raw_parts[key]
        assert im.size == (spec["width"], spec["height"]), (
            f"[{skin_id}] part {key} size {im.size} != contract {(spec['width'], spec['height'])}"
        )
        q = apply_palette(im, palette)
        out_im = add_selective_outline(q, strength=outline_strength)
        if key in hooks:
            out_im = hooks[key](out_im)
        assert out_im.size == (spec["width"], spec["height"]), (
            f"[{skin_id}] finalized part {key} size {out_im.size} != contract"
        )
        out_im.save(out_parts / f"{key}.png")
        saved_parts[key] = out_im
        parts_manifest[key] = {"file": f"parts/{key}.png", **spec}

    saved_arm2: dict[str, Image.Image] = {}
    arm2_manifest: dict[str, dict] = {}
    for key, spec in ARM2_CONTRACT.items():
        im = raw_arm2[key]
        assert im.size == (spec["width"], spec["height"]), (
            f"[{skin_id}] arm2 {key} size {im.size} != contract {(spec['width'], spec['height'])}"
        )
        q = apply_palette(im, palette)
        out_im = add_selective_outline(q, strength=outline_strength)
        if ("arm2_" + key) in hooks:
            out_im = hooks["arm2_" + key](out_im)
        out_im.save(out_arm2 / f"{key}.png")
        saved_arm2[key] = out_im
        arm2_manifest[key] = {"file": f"arm2/{key}.png", **spec}

    extra_defaults = {
        "back_gear": "gun_case" in saved_parts,
        "armor": True,
        "backpack": True,
        "coat_flaps": True,
        "hair_secondary": True,
    }
    if extra_components_default:
        for k, v in extra_components_default.items():
            extra_defaults[str(k)] = bool(v)

    manifest = {
        "schema_version": 1,
        "skin_id": skin_id,
        "display_name": display_name,
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
            "limb_side_coloring": False,
        },
        "extra_components_default": extra_defaults,
        "parts_count": len(parts_manifest),
        "arm2_count": len(arm2_manifest),
        "parts": parts_manifest,
        "arm2": arm2_manifest,
    }
    (out_root / "skin_manifest.json").write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False),
        encoding="utf-8",
    )
    return saved_parts, saved_arm2


def render_contact_sheet(
    saved_parts: dict[str, Image.Image],
    saved_arm2: dict[str, Image.Image],
    out_path: Path,
    title: str = "",
) -> None:
    """Render 3x zoomed inspection contact sheet of all 19+3 finalized parts."""
    items = [(k, v) for k, v in saved_parts.items()] + [(f"arm2/{k}", v) for k, v in saved_arm2.items()]
    cols = 6
    rows = (len(items) + cols - 1) // cols
    cw, ch = 164, 180
    top_bar = 28 if title else 0
    sheet = Image.new("RGBA", (cols * cw, rows * ch + top_bar), (38, 42, 50, 255))
    draw = ImageDraw.Draw(sheet)
    if title:
        draw.text((10, 6), title, fill=(130, 235, 255, 255))
    for idx, (lbl, im) in enumerate(items):
        r, c = divmod(idx, cols)
        ox, oy = c * cw, top_bar + r * ch
        draw.rectangle([ox + 4, oy + 18, ox + cw - 4, oy + ch - 4], fill=(64, 68, 78, 255))
        sc = 3 if max(im.width, im.height) <= 48 else 2
        z = im.resize((im.width * sc, im.height * sc), Image.Resampling.NEAREST)
        sheet.paste(z, (ox + (cw - z.width) // 2, oy + 18 + (ch - 22 - z.height) // 2), z)
        draw.text((ox + 6, oy + 3), f"{lbl} ({im.width}x{im.height})", fill=(255, 225, 130, 255))
    out_path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out_path)
