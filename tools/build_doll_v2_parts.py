#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Phase 7B+ 正式主角 doll_v2（灰蓝猫耳少女）1:1 像素换皮契约精修管线。

严格遵循 docs/character_skin_contract.md 与 assets/art/characters/mannequin/skin_manifest.json：
  - 全部 19 个身体分件严格满足 (W, H) == 契约精确尺寸（height == target_h，运行时 1:1 零畸变缩放）；
  - 全部 3 个横置持枪双臂分件严格 26×14 / 27×13 / 12×10；
  - 大型核心分件（正/背/侧头、无臂正/背/侧躯干、战术枪盒）源自 Seedream 5.5 高清母版并做明暗/对比度提纯与肩袖口清修；
  - 精密关节肢体、侧面朝左（-X）战术球鞋、清晰手绘闭眼眨眼层、圆润握枪手掌、多层顺滑后发/衣摆/格裙均按 1:1 原生像素构建；
  - 统一提取全局 48 色锁定色板 + 1px 选择性暗轮廓（sel-out）+ 输出 assets/art/characters/doll_v2/skin_manifest.json。
"""

from __future__ import annotations

import sys
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
    put,
    put_rect,
    render_contact_sheet,
    soften_joint_cap_outline,
)
from sprite_utils import clean_auto  # noqa: E402

OUT_ROOT = ROOT / "assets/art/characters/doll_v2"
SRC_DIR = OUT_ROOT / "source"
PREVIEW_OUT = Path(
    r"C:\Users\81349\.gemini\antigravity\brain\c8612c36-8745-480a-9096-c8e0dcbd6621\scratch\doll_v2_refined_parts.png"
)

# ---- 灰蓝猫耳少女统一像素色系（与 Seedream 母版 100% 同源，并略提明暗对比以适配深灰战术水泥地）----
HAIR_HI = (134, 140, 166, 255)
HAIR_BASE = (92, 96, 118, 255)
HAIR_SHADE = (64, 67, 86, 255)
HAIR_DEEP = (46, 48, 64, 255)

COAT_HI = (78, 90, 122, 255)
COAT_BASE = (52, 61, 86, 255)
COAT_SHADE = (34, 40, 58, 255)
COAT_CUFF_HI = (94, 108, 142, 255)
COAT_BUTTON = (156, 164, 186, 255)

SKIRT_HI = (130, 136, 156, 255)
SKIRT_BASE = (98, 104, 124, 255)
SKIRT_SHADE = (68, 73, 90, 255)
SKIRT_PLAID = (78, 84, 104, 255)
LACE_WHITE = (224, 228, 238, 255)

TIGHTS_HI = (102, 104, 126, 255)
TIGHTS_BASE = (74, 76, 96, 255)
TIGHTS_SHADE = (50, 52, 68, 255)
KNEE_HI = (118, 120, 142, 255)
KNEE_CREASE = (44, 46, 62, 255)

SHOE_HI = (154, 162, 184, 255)
SHOE_BASE = (112, 120, 142, 255)
SHOE_SHADE = (74, 80, 98, 255)
SHOE_MIDSOLE = (224, 228, 238, 255)
SHOE_SOLE = (54, 58, 72, 255)
SHOE_LACE = (232, 236, 244, 255)

SKIN_HI = (250, 232, 224, 255)
SKIN_BASE = (236, 212, 204, 255)
SKIN_SHADE = (206, 174, 168, 255)
BLUSH_COL = (232, 184, 182, 255)
LASH_DARK = (38, 34, 52, 255)
IRIS_COL = (112, 106, 152, 255)
EYE_WHITE = (246, 244, 250, 255)


def polish_front_head_eyes(head_px: Image.Image) -> Image.Image:
    """Clarify front-view anime eyes on 38×36 head so pupils & catchlights read crisply at 128px×1."""
    arr = np.asarray(head_px.convert("RGBA"), dtype=np.uint8).copy()
    h, w, _ = arr.shape
    # Restrict face skin search strictly below cat-ear zone (y >= 16) so pale inner ear fluff never shifts eye_y!
    face_roi = arr[16:32, 9:29]
    skin_mask = (face_roi[:, :, 3] > 200) & (face_roi[:, :, 0] > 195) & (face_roi[:, :, 1] > 170) & (face_roi[:, :, 2] > 160)
    ys, _xs = np.where(skin_mask)
    if len(ys) < 12:
        return head_px
    y_min, y_max = 16 + int(ys.min()), 16 + int(ys.max())
    eye_y = int(round(y_min + (y_max - y_min) * 0.38))
    out = Image.fromarray(arr, mode="RGBA")
    for cx in (14, 23):
        if 0 <= eye_y - 1 < h:
            for dx in (-1, 0, 1):
                if out.getpixel((cx + dx, eye_y - 1))[3] > 200:
                    put(out, cx + dx, eye_y - 1, LASH_DARK)
        if 0 <= eye_y < h and 0 <= eye_y + 1 < h:
            put(out, cx, eye_y, IRIS_COL)
            put(out, cx, eye_y + 1, IRIS_COL)
            put(out, cx - 1, eye_y, EYE_WHITE)
    return out


def paint_front_blink_clean(head_front_final: Image.Image) -> Image.Image:
    """Create crisp, zero-artifact closed-eye front head directly over finalized 38×36 head_front."""
    arr = np.asarray(head_front_final.convert("RGBA"), dtype=np.uint8).copy()
    h, w, _ = arr.shape
    face_roi = arr[16:32, 9:29]
    skin_mask = (face_roi[:, :, 3] > 200) & (face_roi[:, :, 0] > 195) & (face_roi[:, :, 1] > 170) & (face_roi[:, :, 2] > 160)
    ys, _xs = np.where(skin_mask)
    if len(ys) < 12:
        return head_front_final
    y_min, y_max = 16 + int(ys.min()), 16 + int(ys.max())
    eye_y = int(round(y_min + (y_max - y_min) * 0.38))
    cheek = arr[max(0, eye_y + 2) : min(h, y_max), 12:26]
    cheek_px = cheek[(cheek[:, :, 3] > 200) & (cheek[:, :, 0] > 195) & (cheek[:, :, 1] > 170)]
    skin_rgb = np.median(cheek_px[:, :3], axis=0).astype(np.uint8) if len(cheek_px) > 0 else np.array(SKIN_BASE[:3], dtype=np.uint8)

    for y in range(max(16, eye_y - 2), min(h, eye_y + 3)):
        for x in list(range(12, 17)) + list(range(21, 26)):
            if arr[y, x, 3] > 200:
                r, g, b = int(arr[y, x, 0]), int(arr[y, x, 1]), int(arr[y, x, 2])
                is_bang = (r < 125 and b >= r and g < 125) and (y <= eye_y - 1 or x in (17, 18, 19, 20))
                if not is_bang:
                    arr[y, x, :3] = skin_rgb

    out = Image.fromarray(arr, mode="RGBA")
    for x0 in (12, 22):
        put(out, x0, eye_y, LASH_DARK)
        put(out, x0 + 1, eye_y + 1, LASH_DARK)
        put(out, x0 + 2, eye_y + 1, LASH_DARK)
        put(out, x0 + 3, eye_y, LASH_DARK)
        bx = x0 if x0 < 18 else x0 + 3
        if eye_y + 2 < h and out.getpixel((bx, eye_y + 2))[3] > 200:
            put(out, bx, eye_y + 2, BLUSH_COL)
    return out


def paint_side_blink_clean(head_left_final: Image.Image) -> Image.Image:
    """Create crisp closed-eye side profile directly over finalized 36×36 head_left (facing -X)."""
    arr = np.asarray(head_left_final.convert("RGBA"), dtype=np.uint8).copy()
    h, w, _ = arr.shape
    # Restrict search strictly to face zone (y=16..31, x=4..18) below cat ears!
    face_roi = arr[16:32, 4:18]
    skin_mask = (face_roi[:, :, 3] > 200) & (face_roi[:, :, 0] > 195) & (face_roi[:, :, 1] > 170) & (face_roi[:, :, 2] > 160)
    ys, xs = np.where(skin_mask)
    if len(ys) < 8:
        return head_left_final
    y_min, y_max = 16 + int(ys.min()), 16 + int(ys.max())
    x_min = 4 + int(xs.min())
    eye_y = int(round(y_min + (y_max - y_min) * 0.28))
    skin_rgb = np.median(face_roi[skin_mask][:, :3], axis=0).astype(np.uint8)

    for y in range(max(16, eye_y - 2), min(h, eye_y + 3)):
        for x in range(max(1, x_min), min(w - 1, x_min + 6)):
            if arr[y, x, 3] > 200:
                r, g, b = int(arr[y, x, 0]), int(arr[y, x, 1]), int(arr[y, x, 2])
                is_hair = r < 125 and b >= r and g < 125 and (x >= x_min + 4 or y < eye_y - 1)
                if not is_hair:
                    arr[y, x, :3] = skin_rgb

    out = Image.fromarray(arr, mode="RGBA")
    lx = max(2, x_min + 1)
    put(out, lx, eye_y, LASH_DARK)
    put(out, lx + 1, eye_y + 1, LASH_DARK)
    put(out, lx + 2, eye_y + 1, LASH_DARK)
    put(out, lx + 3, eye_y, LASH_DARK)
    if eye_y + 2 < h and out.getpixel((lx + 2, eye_y + 2))[3] > 200:
        put(out, lx + 2, eye_y + 2, BLUSH_COL)
    return out


def build_arm_upper_v2() -> Image.Image:
    """10×20 oversized dark-navy coat upper sleeve (shoulder=(5,3), elbow=(5,17))."""
    img = draw_vertical_limb_capsule(
        10, 20, top_r=3.0, bot_r=3.0,
        base_col=COAT_BASE, hi_col=COAT_HI, shade_col=COAT_SHADE,
        half_w_top=3.2, half_w_bot=3.4, inset=1,
    )
    # Subtle shoulder seam highlight
    put_rect(img, 3, 4, 6, 4, COAT_HI)
    return img


def build_arm_forearm_v2() -> Image.Image:
    """10×20 navy coat forearm with folded buttoned cuff + cute fair hand (elbow=(5,3), wrist=(5,15))."""
    img = draw_vertical_limb_capsule(
        10, 20, top_r=3.0, bot_r=2.5,
        base_col=COAT_BASE, hi_col=COAT_HI, shade_col=COAT_SHADE,
        half_w_top=3.3, half_w_bot=3.6, inset=1,
    )
    # Clear bottom 5 rows and replace with crisp folded cuff (y=11..14) + rounded fair hand (y=15..18)
    for y in range(14, 19):
        for x in range(1, 9):
            img.putpixel((x, y), (0, 0, 0, 0))
    # Folded oversized cuff band (y=11..14)
    put_rect(img, 2, 11, 7, 11, COAT_SHADE)
    put_rect(img, 2, 12, 7, 13, COAT_BASE)
    put_rect(img, 2, 12, 3, 13, COAT_CUFF_HI)
    put(img, 6, 13, COAT_BUTTON)
    put_rect(img, 2, 14, 7, 14, COAT_SHADE)
    # Cute rounded fair hand (y=15..18)
    put_rect(img, 3, 15, 6, 17, SKIN_BASE)
    put_rect(img, 3, 15, 4, 16, SKIN_HI)
    put_rect(img, 6, 16, 6, 17, SKIN_SHADE)
    put_rect(img, 4, 18, 5, 18, SKIN_SHADE)
    return img


def build_arm2_parts_v2() -> dict[str, Image.Image]:
    """Build exact 26×14 / 27×13 / 12×10 horizontal (+X) weapon-holding sleeves + rounded gripping hand."""
    up = draw_horizontal_arm2_capsule(
        26, 14, left_r=5.2, right_r=5.0,
        base_col=COAT_BASE, hi_col=COAT_HI, shade_col=COAT_SHADE,
        taper_right=0.06, inset=1,
    )
    # Subtle fabric fold along upper sleeve
    put_rect(up, 8, 7, 17, 7, COAT_SHADE)

    fo = draw_horizontal_arm2_capsule(
        27, 13, left_r=4.8, right_r=4.4,
        base_col=COAT_BASE, hi_col=COAT_HI, shade_col=COAT_SHADE,
        taper_right=0.10, inset=1,
    )
    # Crisp folded buttoned cuff near wrist (x=18..23)
    put_rect(fo, 18, 2, 18, 10, COAT_SHADE)
    put_rect(fo, 19, 2, 22, 4, COAT_CUFF_HI)
    put_rect(fo, 19, 5, 22, 8, COAT_BASE)
    put_rect(fo, 19, 9, 22, 10, COAT_SHADE)
    put(fo, 21, 8, COAT_BUTTON)

    hand = draw_gripping_hand(
        12, 10,
        palm_base=SKIN_BASE, palm_hi=SKIN_HI, palm_shade=SKIN_SHADE,
    )
    return {"upper_arm": up, "forearm": fo, "hand": hand}


def main() -> int:
    p_v2 = SRC_DIR / "catgirl_seedream_parts_v2.png"
    p_v1 = SRC_DIR / "catgirl_seedream_parts.png"
    im_v2 = enhance_rgba(Image.open(p_v2).convert("RGBA"), contrast=1.18, saturation=1.20, brightness=1.15)
    im_v1 = enhance_rgba(clean_auto(Image.open(p_v1).convert("RGBA")), contrast=1.15, saturation=1.16, brightness=1.12)

    # ---- 1) Crop high-res Seedream parts & fit cleanly into exact 1:1 contract canvases ----
    head_front_raw = crop_tight(im_v2, (100, 36, 496, 404))
    head_left_raw = crop_tight(im_v2, (1076, 36, 1440, 404))
    head_back_raw = crop_tight(im_v2, (1528, 36, 1904, 396))

    torso_front_raw = crop_tight(im_v2, (56, 524, 540, 1148))
    torso_left_raw = crop_tight(im_v2, (600, 520, 980, 1148))
    torso_back_raw = crop_tight(im_v2, (1028, 524, 1496, 1156))
    guncase_raw = crop_tight(im_v1, (2104, 792, 2408, 1472))

    # Heads (38×36 front/back, 36×36 left) with 1px sel-out margin & tucked neck overlap cap at y=31
    head_front = fit_to_contract_canvas(head_front_raw, 38, 36, pad_left=1, pad_right=1, pad_top=1, pad_bottom=2, align_y="bottom")
    head_front = add_neck_overlap(head_front, SKIN_BASE[:3], SKIN_SHADE[:3], cx=18.5)
    head_front = polish_front_head_eyes(head_front)

    head_back = fit_to_contract_canvas(head_back_raw, 38, 36, pad_left=1, pad_right=1, pad_top=1, pad_bottom=2, align_y="bottom")
    head_back = add_neck_overlap(head_back, HAIR_SHADE[:3], HAIR_DEEP[:3], cx=18.5)

    head_left = fit_to_contract_canvas(head_left_raw, 36, 36, pad_left=1, pad_right=1, pad_top=1, pad_bottom=2, align_y="bottom")
    head_left = add_neck_overlap(head_left, SKIN_BASE[:3], SKIN_SHADE[:3], cx=17.5)

    # Armless torsos (36×46 front, 34×46 back, 26×46 left), cleanly rounded shoulders at (±10, 10)
    torso_front = fit_to_contract_canvas(torso_front_raw, 36, 46, pad_left=1, pad_right=1, pad_top=1, pad_bottom=1, align_y="center")
    torso_front = add_torso_collar_and_pelvis_caps(torso_front, COAT_SHADE[:3], SKIRT_SHADE[:3], trim_shoulders=True, max_shoulder_half_w=12.6)

    torso_back = fit_to_contract_canvas(torso_back_raw, 34, 46, pad_left=1, pad_right=1, pad_top=1, pad_bottom=1, align_y="center")
    torso_back = add_torso_collar_and_pelvis_caps(torso_back, COAT_SHADE[:3], SKIRT_SHADE[:3], trim_shoulders=True, max_shoulder_half_w=11.8)

    torso_left = fit_to_contract_canvas(torso_left_raw, 26, 46, pad_left=1, pad_right=1, pad_top=1, pad_bottom=1, align_y="center")
    torso_left = add_torso_collar_and_pelvis_caps(torso_left, COAT_SHADE[:3], SKIRT_SHADE[:3], trim_shoulders=False)

    # Tactical gun case (18×64)
    gun_case = fit_to_contract_canvas(guncase_raw, 18, 64, pad_left=1, pad_right=1, pad_top=1, pad_bottom=1, align_y="center")

    # ---- 2) Native 1:1 pixel-crafted articulated limbs, side-profile sneakers, layered bob hair & trench flaps ----
    thigh = draw_vertical_limb_capsule(
        10, 33, top_r=3.2, bot_r=3.2,
        base_col=TIGHTS_BASE, hi_col=TIGHTS_HI, shade_col=TIGHTS_SHADE,
        half_w_top=3.1, half_w_bot=2.8, inset=1,
    )
    # Subtle sheen strip along front edge of tights + knee-top highlight
    put_rect(thigh, 3, 6, 3, 25, TIGHTS_HI)
    put_rect(thigh, 4, 27, 5, 28, KNEE_HI)

    shin_boot = draw_side_shin_and_footwear(
        shin_base=TIGHTS_BASE, shin_hi=TIGHTS_HI, shin_shade=TIGHTS_SHADE,
        boot_base=SHOE_BASE, boot_hi=SHOE_HI, boot_shade=SHOE_SHADE,
        sole_col=SHOE_SOLE, midsole_col=SHOE_MIDSOLE, lace_col=SHOE_LACE,
        boot_top_y=25, knee_hi=KNEE_HI, knee_crease=KNEE_CREASE, sole_thick=1,
    )

    arm_upper = build_arm_upper_v2()
    arm_forearm = build_arm_forearm_v2()
    arm2_parts = build_arm2_parts_v2()

    hair_back_root, hair_back_tip, hair_side = draw_hair_back_segments(
        base_col=HAIR_BASE, hi_col=HAIR_HI, shade_col=HAIR_SHADE, deep_col=HAIR_DEEP,
        style="bob",
    )
    coat_flap_root, coat_flap_tip = draw_coat_or_dress_flaps(
        base_col=COAT_BASE, hi_col=COAT_HI, shade_col=COAT_SHADE,
        trim_col=COAT_CUFF_HI, style="trenchcoat",
    )
    skirt_hem = draw_pleated_skirt_hem(
        base_col=SKIRT_BASE, hi_col=SKIRT_HI, shade_col=SKIRT_SHADE,
        trim_col=LACE_WHITE, plaid_col=SKIRT_PLAID,
    )

    raw_parts: dict[str, Image.Image] = {
        "head_front": head_front,
        "head_front_blink": head_front.copy(),  # replaced post-quantize by clean hand-painted blink!
        "head_back": head_back,
        "head_left": head_left,
        "head_left_blink": head_left.copy(),    # replaced post-quantize by clean hand-painted blink!
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
        arm_forearm, coat_flap_root, skirt_hem,
    ]

    # Finalize with 48-color locked palette + 1px sel-out + seamless soft-shaded joint caps (zero black ring seams!)
    joint_hooks = {
        "thigh": lambda im: soften_joint_cap_outline(im, top_rows=4, bottom_rows=4),
        "shin_boot": lambda im: soften_joint_cap_outline(im, top_rows=4),
        "arm_upper": lambda im: soften_joint_cap_outline(im, top_rows=4, bottom_rows=4),
        "arm_forearm": lambda im: soften_joint_cap_outline(im, top_rows=4),
        "coat_flap_tip": lambda im: soften_joint_cap_outline(im, top_rows=3),
        "hair_back_tip": lambda im: soften_joint_cap_outline(im, top_rows=3),
        "arm2_upper_arm": lambda im: soften_joint_cap_outline(im, left_cols=4, right_cols=4),
        "arm2_forearm": lambda im: soften_joint_cap_outline(im, left_cols=4),
    }
    saved_parts, saved_arm2 = finalize_and_export_skin(
        skin_id="doll_v2",
        display_name="灰蓝猫耳少女 (Doll v2 · 精修 1:1)",
        out_root=OUT_ROOT,
        raw_parts=raw_parts,
        raw_arm2=arm2_parts,
        palette_anchors=palette_anchors,
        max_colors=48,
        outline_strength=0.32,
        post_quantize_hooks=joint_hooks,
    )

    # Pixel-locked clean blink layers derived directly from finalized head_front / head_left (zero outline shift!)
    blink_front = paint_front_blink_clean(saved_parts["head_front"])
    blink_front.save(OUT_ROOT / "parts/head_front_blink.png")
    saved_parts["head_front_blink"] = blink_front

    blink_left = paint_side_blink_clean(saved_parts["head_left"])
    blink_left.save(OUT_ROOT / "parts/head_left_blink.png")
    saved_parts["head_left_blink"] = blink_left

    render_contact_sheet(
        saved_parts, saved_arm2, PREVIEW_OUT,
        title="doll_v2 (Refined 1:1 Contract · 19+3 Parts · 48-Color Locked Palette)",
    )
    print(f"[build_doll_v2_parts] Exported 19 parts + 3 arm2 + skin_manifest.json to {OUT_ROOT}")
    print(f"[build_doll_v2_parts] Contact sheet: {PREVIEW_OUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
