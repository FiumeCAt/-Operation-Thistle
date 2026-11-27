#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""第二套正式角色皮肤包 doll_thistle（白发高马尾红白水手战术人偶）1:1 像素构建管线。

参考设定：D:/AI Game/temp_20261027_01/design_art/character.jpg
高清无臂分件母版（Seedream 5.5）：assets/art/characters/doll_thistle/source/thistle_seedream_parts.png

严格遵循 docs/character_skin_contract.md 全部 19+3 尺寸与枢轴契约：
  - 零改代码即完整继承 DollRigV2 步态、360° 持枪、弹簧物理飘动（高马尾+红白裙摆）、眨眼与团身翻滚；
  - 输出 assets/art/characters/doll_thistle/{parts,arm2,skin_manifest.json}。
"""

from __future__ import annotations

import math
import sys
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from skin_part_helpers import (  # noqa: E402
    add_neck_overlap,
    add_torso_collar_and_pelvis_caps,
    crop_tight,
    draw_coat_or_dress_flaps,
    draw_gripping_hand,
    draw_hair_back_segments,
    draw_horizontal_arm2_capsule,
    draw_pleated_skirt_hem,
    draw_side_shin_and_footwear,
    draw_vertical_limb_capsule,
    enhance_rgba,
    finalize_and_export_skin,
    fit_to_contract_canvas,
    new_img,
    put,
    put_rect,
    render_contact_sheet,
    soften_joint_cap_outline,
)

OUT_ROOT = ROOT / "assets/art/characters/doll_thistle"
SRC_PATH = OUT_ROOT / "source/thistle_seedream_parts.png"
PREVIEW_OUT = Path(
    r"C:\Users\81349\.gemini\antigravity\brain\c8612c36-8745-480a-9096-c8e0dcbd6621\scratch\doll_thistle_parts.png"
)

# ---- 白发高马尾红白战术人偶统一像素色系（控制高光反照率防 VisionFog2D 光锥过曝，增强褶皱与发丝可读性）----
HAIR_HI = (238, 240, 248, 255)
HAIR_BASE = (214, 218, 232, 255)
HAIR_SHADE = (172, 178, 200, 255)
HAIR_DEEP = (128, 134, 158, 255)

DRESS_HI = (238, 240, 248, 255)
DRESS_BASE = (214, 218, 230, 255)
DRESS_SHADE = (172, 178, 196, 255)

RED_HI = (224, 78, 86, 255)
RED_BASE = (190, 44, 56, 255)
RED_SHADE = (138, 26, 38, 255)

SKIN_HI = (248, 230, 222, 255)
SKIN_BASE = (236, 208, 198, 255)
SKIN_SHADE = (204, 168, 158, 255)
KNEE_BLUSH = (228, 188, 178, 255)
KNEE_CREASE = (194, 156, 148, 255)

BOOT_HI = (80, 84, 98, 255)
BOOT_BASE = (46, 49, 60, 255)
BOOT_SHADE = (28, 30, 38, 255)
BOOT_SOLE = (22, 24, 30, 255)
BOOT_CUFF = (64, 68, 82, 255)
TAC_METAL = (184, 192, 208, 255)
CHOKER_DARK = (32, 32, 40, 255)

GLOVE_HI = (236, 238, 246, 255)
GLOVE_BASE = (210, 214, 226, 255)
GLOVE_SHADE = (168, 174, 190, 255)
PALM_TAC = (58, 62, 74, 255)

BLUSH_COL = (232, 178, 174, 255)
LASH_DARK = (48, 34, 42, 255)
IRIS_PUPIL = (98, 62, 66, 255)
IRIS_AMBER = (170, 114, 108, 255)
EYE_WHITE = (248, 246, 250, 255)


def extract_largest_component(img: Image.Image, alpha_thresh: int = 25) -> Image.Image:
    """Isolate the primary connected sprite component (removes disconnected neighboring hair piece)."""
    arr = np.asarray(img.convert("RGBA"), dtype=np.uint8).copy()
    h, w, _ = arr.shape
    mask = arr[:, :, 3] > alpha_thresh
    # Label on 2x downsampled grid for speed, then map back cleanly
    sub = mask[::2, ::2]
    sh, sw = sub.shape
    labels = np.zeros((sh, sw), dtype=np.int32)
    cur = 0
    best_lbl = 0
    best_cnt = 0
    for y in range(sh):
        for x in range(sw):
            if sub[y, x] and labels[y, x] == 0:
                cur += 1
                q = deque([(y, x)])
                labels[y, x] = cur
                cnt = 0
                while q:
                    cy, cx = q.popleft()
                    cnt += 1
                    for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                        ny, nx = cy + dy, cx + dx
                        if 0 <= ny < sh and 0 <= nx < sw and sub[ny, nx] and labels[ny, nx] == 0:
                            labels[ny, nx] = cur
                            q.append((ny, nx))
                if cnt > best_cnt:
                    best_cnt = cnt
                    best_lbl = cur
    keep_sub = labels == best_lbl
    keep = np.repeat(np.repeat(keep_sub, 2, axis=0), 2, axis=1)[:h, :w]
    arr[~keep] = 0
    return Image.fromarray(arr, mode="RGBA")


def strip_front_torso_bg_hair(torso_front: Image.Image) -> Image.Image:
    """Remove the static ponytail lock peeking behind viewer-right shoulder of torso_front symmetrically."""
    arr = np.asarray(torso_front.convert("RGBA"), dtype=np.uint8).copy()
    h, w, _ = arr.shape
    # Find dress vertical centerline from crisp red collar & bottom hem pixels
    r, g, b, a = arr[:, :, 0], arr[:, :, 1], arr[:, :, 2], arr[:, :, 3]
    red = (a > 128) & (r > 155) & (g < 95) & (b < 95)
    rys, rxs = np.where(red)
    if len(rxs) < 20:
        return torso_front
    cx = float(np.median(rxs))
    # For upper 78% of dress, erase right-side overhang pixels beyond clean left-side silhouette mirror
    for y in range(0, int(h * 0.78)):
        row_a = arr[y, :, 3] > 60
        left_xs = np.where(row_a[: int(cx)])[0]
        if len(left_xs) == 0:
            continue
        left_edge = int(left_xs[0])
        sym_right = int(round(cx + (cx - left_edge))) + 10
        if sym_right < w:
            arr[y, sym_right:] = 0
    return Image.fromarray(arr, mode="RGBA")


def trim_head_lower_ponytail(head_img: Image.Image, mode: str) -> Image.Image:
    """Keep the iconic high ponytail crown & hair tie while trimming the cut-off vertical tail below the jaw
    so the spring-animated hair_back_root + hair_back_tip seamlessly handle the flowing ponytail."""
    arr = np.asarray(head_img.convert("RGBA"), dtype=np.uint8).copy()
    h, w, _ = arr.shape
    if mode == "front":
        for y in range(int(h * 0.54), h):
            t = (y - h * 0.54) / max(1.0, h * 0.46)
            cut_x = int(w * (0.76 - 0.08 * t))
            arr[y, cut_x:] = 0
    elif mode == "left":
        # Side profile faces left (-X): keep face + skull + rounded ponytail tie bulb, cleanly trim lower-right tail
        for y in range(int(h * 0.44), h):
            t = (y - h * 0.44) / max(1.0, h * 0.56)
            cut_x = int(w * (0.73 - 0.11 * min(1.0, t * 1.4)))
            arr[y, cut_x:] = 0
    return Image.fromarray(arr, mode="RGBA")


def center_head_by_choker_or_neck(
    head_raw: Image.Image,
    canvas_w: int,
    canvas_h: int,
    target_neck_x: float,
    pad_top: int = 1,
    pad_bottom: int = 2,
) -> Image.Image:
    """Fit head into exact contract canvas while centering neck/choker horizontally on target_neck_x."""
    tight = crop_tight(head_raw, pad=0)
    # Detect dark choker or neck center in bottom 16% of tight head crop
    arr = np.asarray(tight.convert("RGBA"), dtype=np.uint8)
    th, tw, _ = arr.shape
    bot = arr[int(th * 0.84) :, :, :]
    dark = (bot[:, :, 3] > 180) & (bot[:, :, 0] < 90) & (bot[:, :, 1] < 90) & (bot[:, :, 2] < 100)
    if dark.sum() > 20:
        _, dxs = np.where(dark)
        src_neck_x = float(np.median(dxs))
    else:
        occ = bot[:, :, 3] > 180
        _, oxs = np.where(occ)
        src_neck_x = float(np.median(oxs)) if len(oxs) > 0 else tw * 0.5

    # Compute uniform scale to fit nicely inside canvas leaving 1px outline margin
    avail_h = canvas_h - pad_top - pad_bottom
    avail_w = canvas_w - 2
    scale = min(avail_h / float(max(th, 1)), avail_w / float(max(tw, 1)))
    # Fit first using standard helper, then compute shift so src_neck_x lands on target_neck_x
    scaled_w = max(2, int(round(tw * scale)))
    default_ox = 1 + (avail_w - scaled_w) // 2
    desired_ox = int(round(target_neck_x - src_neck_x * scale))
    shift_x = max(1 - default_ox, min((canvas_w - 1 - scaled_w) - default_ox, desired_ox - default_ox))
    return fit_to_contract_canvas(
        tight, canvas_w, canvas_h,
        pad_left=1, pad_right=1, pad_top=pad_top, pad_bottom=pad_bottom,
        align_y="bottom", shift_x=shift_x, alpha_thresh=116,
    )


def polish_thistle_front_eyes(head_px: Image.Image) -> Image.Image:
    """Crisp reddish-amber anime eyes with subtle white catchlight on 38×36 front head."""
    arr = np.asarray(head_px.convert("RGBA"), dtype=np.uint8).copy()
    h, w, _ = arr.shape
    # Find black choker center x to keep eyes strictly symmetric around nose axis
    dark_neck = (arr[26:, :, 3] > 180) & (arr[26:, :, 0] < 85) & (arr[26:, :, 1] < 85)
    _, dxs = np.where(dark_neck)
    cx = int(round(float(np.median(dxs)))) if len(dxs) >= 3 else 18
    # Locate eye row (~y=19..21)
    eye_y = 20
    out = Image.fromarray(arr, mode="RGBA")
    for ex in (cx - 4, cx + 4):
        if 2 <= ex < w - 2:
            for dx in (-1, 0, 1):
                put(out, ex + dx, eye_y - 1, LASH_DARK)
            put(out, ex, eye_y, IRIS_PUPIL)
            put(out, ex, eye_y + 1, IRIS_AMBER)
            put(out, ex - 1, eye_y, EYE_WHITE)
    return out


def paint_thistle_front_blink(head_front_final: Image.Image) -> Image.Image:
    """Pixel-locked crisp closed-eye blink over finalized 38×36 head_front."""
    arr = np.asarray(head_front_final.convert("RGBA"), dtype=np.uint8).copy()
    h, w, _ = arr.shape
    dark_neck = (arr[26:, :, 3] > 180) & (arr[26:, :, 0] < 85) & (arr[26:, :, 1] < 85)
    _, dxs = np.where(dark_neck)
    cx = int(round(float(np.median(dxs)))) if len(dxs) >= 3 else 18
    eye_y = 20
    # Sample cheek skin color from y=22..26
    cheek = arr[22:27, max(1, cx - 5) : min(w - 1, cx + 6)]
    cpx = cheek[(cheek[:, :, 3] > 200) & (cheek[:, :, 0] > 210) & (cheek[:, :, 1] > 180)]
    skin_rgb = np.median(cpx[:, :3], axis=0).astype(np.uint8) if len(cpx) > 0 else np.array(SKIN_BASE[:3], dtype=np.uint8)

    for y in range(eye_y - 2, eye_y + 3):
        for ex in (cx - 4, cx + 4):
            for x in range(max(1, ex - 2), min(w - 1, ex + 3)):
                if arr[y, x, 3] > 200:
                    # Keep bright pure-white hair bangs if above eye line
                    r, g, b = int(arr[y, x, 0]), int(arr[y, x, 1]), int(arr[y, x, 2])
                    is_white_bang = (y <= eye_y - 2) and (b > 228 and g > 226)
                    if not is_white_bang:
                        arr[y, x, :3] = skin_rgb

    out = Image.fromarray(arr, mode="RGBA")
    for x0 in (cx - 6, cx + 2):
        put(out, x0, eye_y, LASH_DARK)
        put(out, x0 + 1, eye_y + 1, LASH_DARK)
        put(out, x0 + 2, eye_y + 1, LASH_DARK)
        put(out, x0 + 3, eye_y, LASH_DARK)
        bx = x0 if x0 < cx else x0 + 3
        if eye_y + 2 < h and out.getpixel((bx, eye_y + 2))[3] > 200:
            put(out, bx, eye_y + 2, BLUSH_COL)
    return out


def paint_thistle_side_blink(head_left_final: Image.Image) -> Image.Image:
    """Pixel-locked closed-eye side profile over finalized 36×36 head_left (facing -X)."""
    arr = np.asarray(head_left_final.convert("RGBA"), dtype=np.uint8).copy()
    h, w, _ = arr.shape
    # Locate the actual reddish-amber side eye directly inside the face band (y=17..23, x=4..14)
    face_band = arr[17:24, 4:14]
    # Dark/reddish iris or lash pixels have lower luminance than white hair & fair skin
    lum = face_band[:, :, :3].mean(axis=2)
    eye_cand = (face_band[:, :, 3] > 200) & (lum < 185)
    eys, exs = np.where(eye_cand)
    if len(eys) >= 1:
        eye_y = int(round(17 + float(np.median(eys))))
        eye_x = int(round(4 + float(np.median(exs))))
    else:
        eye_y, eye_x = 20, 9

    # Sample clean warm cheek skin directly below eye (y=eye_y+2..eye_y+6, x=eye_x-2..eye_x+4)
    cheek = arr[min(h - 1, eye_y + 2) : min(h, eye_y + 6), max(1, eye_x - 2) : min(w - 1, eye_x + 4)]
    cpx = cheek[(cheek[:, :, 3] > 200) & (cheek[:, :, 0] > 210) & (cheek[:, :, 1] > 180)]
    skin_rgb = np.median(cpx[:, :3], axis=0).astype(np.uint8) if len(cpx) > 0 else np.array(SKIN_BASE[:3], dtype=np.uint8)

    # Smoothly clear open eye pixels around (eye_x, eye_y) without touching bright white bangs
    for y in range(max(1, eye_y - 2), min(h - 1, eye_y + 2)):
        for x in range(max(1, eye_x - 2), min(w - 1, eye_x + 3)):
            if arr[y, x, 3] > 200:
                r, g, b = int(arr[y, x, 0]), int(arr[y, x, 1]), int(arr[y, x, 2])
                is_white_hair = (b > 224 and g > 224 and r > 224)
                if not is_white_hair:
                    arr[y, x, :3] = skin_rgb

    out = Image.fromarray(arr, mode="RGBA")
    lx = max(3, eye_x - 2)
    put(out, lx, eye_y, LASH_DARK)
    put(out, lx + 1, eye_y + 1, LASH_DARK)
    put(out, lx + 2, eye_y + 1, LASH_DARK)
    put(out, lx + 3, eye_y, LASH_DARK)
    if eye_y + 2 < h and out.getpixel((lx + 2, eye_y + 2))[3] > 200:
        put(out, lx + 2, eye_y + 2, BLUSH_COL)
    return out


def build_thigh_thistle() -> Image.Image:
    """10×33 fair porcelain anime thigh with sleek black tactical thigh holster strap (hip=(5,3.5), knee=(5,29.5))."""
    img = draw_vertical_limb_capsule(
        10, 33, top_r=3.2, bot_r=3.2,
        base_col=SKIN_BASE, hi_col=SKIN_HI, shade_col=SKIN_SHADE,
        half_w_top=3.2, half_w_bot=2.8, inset=1,
    )
    # Iconic matte-black tactical thigh strap near upper thigh (y=8..10) + silver buckle glint
    put_rect(img, 2, 8, 7, 10, BOOT_BASE)
    put_rect(img, 2, 8, 3, 10, BOOT_HI)
    put(img, 4, 9, TAC_METAL)
    # Second thin lower tactical garter band (y=13)
    put_rect(img, 2, 13, 7, 13, BOOT_SHADE)
    # Soft rosy knee-cap highlight
    put_rect(img, 4, 27, 5, 28, KNEE_BLUSH)
    return img


def build_arm_upper_thistle() -> Image.Image:
    """10×20 crisp white sailor upper sleeve with iconic crimson-red trim band near elbow."""
    img = draw_vertical_limb_capsule(
        10, 20, top_r=3.0, bot_r=3.0,
        base_col=DRESS_BASE, hi_col=DRESS_HI, shade_col=DRESS_SHADE,
        half_w_top=3.2, half_w_bot=3.1, inset=1,
    )
    # Crimson sailor short-sleeve cuff trim (y=12..14)
    put_rect(img, 2, 12, 7, 13, RED_BASE)
    put_rect(img, 2, 12, 3, 13, RED_HI)
    put_rect(img, 6, 12, 7, 13, RED_SHADE)
    return img


def build_arm_forearm_thistle() -> Image.Image:
    """10×20 white inner sleeve + crimson wrist trim + white/charcoal tactical glove."""
    img = draw_vertical_limb_capsule(
        10, 20, top_r=3.0, bot_r=2.4,
        base_col=DRESS_BASE, hi_col=DRESS_HI, shade_col=DRESS_SHADE,
        half_w_top=3.0, half_w_bot=2.9, inset=1,
    )
    for y in range(14, 19):
        for x in range(1, 9):
            img.putpixel((x, y), (0, 0, 0, 0))
    # Crimson wrist cuff (y=11..13)
    put_rect(img, 2, 11, 7, 13, RED_BASE)
    put_rect(img, 2, 11, 3, 13, RED_HI)
    put_rect(img, 6, 11, 7, 13, RED_SHADE)
    # Tactical white glove with dark charcoal wrist strap (y=14..18)
    put_rect(img, 3, 14, 6, 14, PALM_TAC)
    put_rect(img, 3, 15, 6, 17, GLOVE_BASE)
    put_rect(img, 3, 15, 4, 16, GLOVE_HI)
    put_rect(img, 6, 16, 6, 17, GLOVE_SHADE)
    put_rect(img, 4, 18, 5, 18, PALM_TAC)
    return img


def build_arm2_parts_thistle() -> dict[str, Image.Image]:
    """Build exact 26×14 / 27×13 / 12×10 horizontal (+X) white+crimson sailor sleeves + tactical gloves."""
    up = draw_horizontal_arm2_capsule(
        26, 14, left_r=4.8, right_r=4.6,
        base_col=DRESS_BASE, hi_col=DRESS_HI, shade_col=DRESS_SHADE,
        taper_right=0.06, inset=1,
    )
    # Crimson sailor upper-sleeve trim ring (x=16..18)
    for y in range(2, 12):
        for x in (16, 17, 18):
            if up.getpixel((x, y))[3] > 0:
                col = RED_HI if y <= 4 else (RED_SHADE if y >= 9 else RED_BASE)
                up.putpixel((x, y), col)

    fo = draw_horizontal_arm2_capsule(
        27, 13, left_r=4.6, right_r=4.4,
        base_col=DRESS_BASE, hi_col=DRESS_HI, shade_col=DRESS_SHADE,
        taper_right=0.10, inset=1,
    )
    # Crimson wrist cuff trim (x=18..21)
    for y in range(2, 11):
        for x in (18, 19, 20, 21):
            if fo.getpixel((x, y))[3] > 0:
                col = RED_HI if y <= 4 else (RED_SHADE if y >= 8 else RED_BASE)
                fo.putpixel((x, y), col)

    hand = draw_gripping_hand(
        12, 10,
        palm_base=GLOVE_BASE, palm_hi=GLOVE_HI, palm_shade=GLOVE_SHADE,
        accent_col=PALM_TAC,
    )
    return {"upper_arm": up, "forearm": fo, "hand": hand}


def build_tactical_back_pack() -> Image.Image:
    """18×64 sleek matte-black & crimson tactical drop-scabbard/comms pack positioned cleanly
    at mid-to-lower back (y=17..58) so her iconic white high ponytail remains unobstructed!"""
    w, h = 18, 64
    img = new_img(w, h)
    # Compact tactical hardcase/pack body (x=3..14, y=18..57) with beveled corners
    for y in range(18, 58):
        inset_x = 4 if y in (18, 57) else 3
        for x in range(inset_x, w - inset_x):
            if x <= inset_x + 1:
                col = BOOT_HI
            elif x >= w - inset_x - 2 or y >= 55:
                col = BOOT_SHADE
            else:
                col = BOOT_BASE
            img.putpixel((x, y), col)
    # Slim upper comms antenna / folding stock rail (x=11..13, y=10..18)
    put_rect(img, 11, 10, 12, 18, BOOT_SHADE)
    put(img, 11, 10, RED_HI)
    put(img, 11, 11, RED_BASE)
    # Crimson tactical harness straps & MOLLE bands
    for by in (25, 39, 50):
        put_rect(img, 3, by, 14, by + 1, BOOT_SHADE)
        put_rect(img, 5, by, 12, by, RED_BASE)
        put(img, 6, by, RED_HI)
        put_rect(img, 8, by, 9, by + 1, TAC_METAL)
    # Tactical pouch flap accent at center (y=29..36)
    put_rect(img, 5, 29, 12, 36, BOOT_CUFF)
    put_rect(img, 5, 35, 12, 36, BOOT_SHADE)
    put_rect(img, 8, 31, 9, 33, RED_BASE)
    return img


def main() -> int:
    # Slightly dial brightness to 0.93 & boost contrast so pure-white hair/dress retains rich fold detail under VisionFog2D light
    src = enhance_rgba(Image.open(SRC_PATH).convert("RGBA"), contrast=1.14, saturation=1.12, brightness=0.93)

    # ---- 1) Extract high-res parts from Seedream 5.5 sheet ----
    hf_raw = trim_head_lower_ponytail(crop_tight(src, (28, 20, 560, 548)), mode="front")
    hl_raw = trim_head_lower_ponytail(crop_tight(src, (1230, 20, 1804, 548)), mode="left")
    hbk_raw = crop_tight(src, (1910, 20, 2348, 548))

    tf_raw = strip_front_torso_bg_hair(crop_tight(src, (30, 700, 686, 1752)))
    tl_raw = crop_tight(extract_largest_component(src.crop((860, 702, 1608, 1752))), pad=0)
    tb_raw = crop_tight(src, (1638, 700, 2304, 1752))

    # Heads aligned strictly to neck pivots (18.5, 32) / (18, 32)
    head_front = center_head_by_choker_or_neck(hf_raw, 38, 36, target_neck_x=18.5, pad_top=1, pad_bottom=2)
    head_front = add_neck_overlap(head_front, SKIN_BASE[:3], CHOKER_DARK[:3], cx=18.5)
    head_front = polish_thistle_front_eyes(head_front)

    head_back = fit_to_contract_canvas(hbk_raw, 38, 36, pad_left=1, pad_right=1, pad_top=1, pad_bottom=2, align_y="bottom", alpha_thresh=116)
    head_back = add_neck_overlap(head_back, HAIR_SHADE[:3], HAIR_DEEP[:3], cx=18.5)

    head_left = center_head_by_choker_or_neck(hl_raw, 36, 36, target_neck_x=17.5, pad_top=1, pad_bottom=2)
    head_left = add_neck_overlap(head_left, SKIN_BASE[:3], CHOKER_DARK[:3], cx=17.5)

    # Armless crisp white & crimson sailor dress torsos (36×46, 34×46, 26×46)
    torso_front = fit_to_contract_canvas(tf_raw, 36, 46, pad_left=1, pad_right=1, pad_top=1, pad_bottom=1, align_y="center", alpha_thresh=116)
    torso_front = add_torso_collar_and_pelvis_caps(torso_front, RED_SHADE[:3], RED_BASE[:3], trim_shoulders=True, max_shoulder_half_w=12.4)

    torso_back = fit_to_contract_canvas(tb_raw, 34, 46, pad_left=1, pad_right=1, pad_top=1, pad_bottom=1, align_y="center", alpha_thresh=116)
    torso_back = add_torso_collar_and_pelvis_caps(torso_back, RED_SHADE[:3], RED_BASE[:3], trim_shoulders=True, max_shoulder_half_w=11.8)

    torso_left = fit_to_contract_canvas(tl_raw, 26, 46, pad_left=1, pad_right=1, pad_top=1, pad_bottom=1, align_y="center", alpha_thresh=116)
    torso_left = add_torso_collar_and_pelvis_caps(torso_left, RED_SHADE[:3], RED_BASE[:3], trim_shoulders=False)

    # ---- 2) Native 1:1 pixel-crafted silky ponytail, crimson-trimmed dress flaps, bare legs + combat boots ----
    thigh = build_thigh_thistle()
    shin_boot = draw_side_shin_and_footwear(
        shin_base=SKIN_BASE, shin_hi=SKIN_HI, shin_shade=SKIN_SHADE,
        boot_base=BOOT_BASE, boot_hi=BOOT_HI, boot_shade=BOOT_SHADE,
        sole_col=BOOT_SOLE, midsole_col=BOOT_SHADE, lace_col=TAC_METAL,
        boot_top_y=19, knee_hi=KNEE_BLUSH, knee_crease=KNEE_CREASE,
        boot_cuff_col=BOOT_CUFF, sole_thick=2,
    )

    arm_upper = build_arm_upper_thistle()
    arm_forearm = build_arm_forearm_thistle()
    arm2_parts = build_arm2_parts_thistle()
    gun_case = build_tactical_back_pack()

    hair_back_root, hair_back_tip, hair_side = draw_hair_back_segments(
        base_col=HAIR_BASE, hi_col=HAIR_HI, shade_col=HAIR_SHADE, deep_col=HAIR_DEEP,
        style="ponytail",
    )
    coat_flap_root, coat_flap_tip = draw_coat_or_dress_flaps(
        base_col=DRESS_BASE, hi_col=DRESS_HI, shade_col=DRESS_SHADE,
        trim_col=RED_BASE, trim_hi=RED_HI, style="sailor_dress",
    )
    skirt_hem = draw_pleated_skirt_hem(
        base_col=DRESS_BASE, hi_col=DRESS_HI, shade_col=DRESS_SHADE,
        trim_col=RED_BASE, plaid_col=None,
    )

    raw_parts: dict[str, Image.Image] = {
        "head_front": head_front,
        "head_front_blink": head_front.copy(),
        "head_back": head_back,
        "head_left": head_left,
        "head_left_blink": head_left.copy(),
        "torso_front": torso_front,
        "torso_back": torso_back,
        "torso_left": torso_left,
        "hair_back_root": hair_back_root,
        "hair_back_tip": hair_back_tip,
        "hair_side": hair_side,
        "coat_flap_root": coat_flap_root,
        "coat_flap_tip": coat_flap_tip,
        "skirt_hem": skirt_hem,
        "thigh": thigh,
        "shin_boot": shin_boot,
        "gun_case": gun_case,
        "arm_upper": arm_upper,
        "arm_forearm": arm_forearm,
    }

    palette_anchors = [
        head_front, head_left, head_back,
        torso_front, torso_left, torso_back,
        thigh, shin_boot, gun_case,
        arm_forearm, coat_flap_tip, skirt_hem,
    ]

    joint_hooks = {
        "thigh": lambda im: soften_joint_cap_outline(im, top_rows=4, bottom_rows=4),
        "shin_boot": lambda im: soften_joint_cap_outline(im, top_rows=4),
        "arm_upper": lambda im: soften_joint_cap_outline(im, top_rows=4, bottom_rows=4),
        "arm_forearm": lambda im: soften_joint_cap_outline(im, top_rows=4),
        "coat_flap_root": lambda im: soften_joint_cap_outline(im, top_rows=3),
        "coat_flap_tip": lambda im: soften_joint_cap_outline(im, top_rows=2),
        "hair_back_tip": lambda im: soften_joint_cap_outline(im, top_rows=3),
        "arm2_upper_arm": lambda im: soften_joint_cap_outline(im, left_cols=4, right_cols=4),
        "arm2_forearm": lambda im: soften_joint_cap_outline(im, left_cols=4),
    }
    saved_parts, saved_arm2 = finalize_and_export_skin(
        skin_id="doll_thistle",
        display_name="白发高马尾战术人偶 (Thistle · 1:1)",
        out_root=OUT_ROOT,
        raw_parts=raw_parts,
        raw_arm2=arm2_parts,
        palette_anchors=palette_anchors,
        max_colors=48,
        outline_strength=0.14,
        post_quantize_hooks=joint_hooks,
    )

    # Pixel-locked clean blink layers derived directly from finalized head_front / head_left
    blink_front = paint_thistle_front_blink(saved_parts["head_front"])
    blink_front.save(OUT_ROOT / "parts/head_front_blink.png")
    saved_parts["head_front_blink"] = blink_front

    blink_left = paint_thistle_side_blink(saved_parts["head_left"])
    blink_left.save(OUT_ROOT / "parts/head_left_blink.png")
    saved_parts["head_left_blink"] = blink_left

    render_contact_sheet(
        saved_parts, saved_arm2, PREVIEW_OUT,
        title="doll_thistle (White-Hair High-Ponytail Tactical Sailor · 1:1 Contract · 19+3 Parts)",
    )
    print(f"[build_doll_thistle_parts] Exported 19 parts + 3 arm2 + skin_manifest.json to {OUT_ROOT}")
    print(f"[build_doll_thistle_parts] Contact sheet: {PREVIEW_OUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
