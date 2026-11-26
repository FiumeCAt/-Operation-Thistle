#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Phase 7B Modular Doll Rig v2 分件裁剪、关节圆润包边、48 色锁定色板量化与 128px 像素化管线。

输入（Seedream 5.5 生成的高清母版）：
  - assets/art/characters/doll_v2/source/catgirl_seedream_parts_v2.png（透明底，主体头/无臂躯干/后发/衣袖）
  - assets/art/characters/doll_v2/source/catgirl_seedream_parts.png（白底抠透明，竖直风衣下摆/深灰长袜双腿+球鞋/战术枪盒）

输出（严格 128px×1 单一规格 + 全局 48 色锁定色板 + 1px 选择性暗轮廓）：
  - assets/art/characters/doll_v2/parts/*.png  (19 个模块化骨骼分件，供 DollRigV2.gd 使用)
  - assets/art/characters/doll_v2/arm2/*.png   (3 个横置武器持枪手臂分件，供 WeaponRig2D.gd 使用)
"""

from __future__ import annotations

import sys
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from pixel_char_pipeline import (  # noqa: E402
    add_selective_outline,
    apply_palette,
    build_locked_palette,
    harden_alpha,
    premul_box_resize,
    remove_isolated_pixels,
)
from sprite_utils import clean_auto  # noqa: E402

SRC_DIR = ROOT / "assets/art/characters/doll_v2/source"
OUT_PARTS = ROOT / "assets/art/characters/doll_v2/parts"
OUT_ARM2 = ROOT / "assets/art/characters/doll_v2/arm2"
PREVIEW_OUT = Path(r"C:\Users\81349\.gemini\antigravity\brain\39efb0de-c6a8-4d42-9309-96c4eeb3f0b1\scratch\doll_v2_parts_preview.png")


def crop_tight(img: Image.Image, box: tuple[int, int, int, int], pad: int = 4) -> Image.Image:
    sub = img.crop(box)
    bb = sub.getbbox()
    if bb is None:
        return sub
    x0 = max(0, bb[0] - pad)
    y0 = max(0, bb[1] - pad)
    x1 = min(sub.width, bb[2] + pad)
    y1 = min(sub.height, bb[3] + pad)
    return sub.crop((x0, y0, x1, y1))


def scale_to_height(img: Image.Image, target_h: int) -> Image.Image:
    ratio = target_h / float(max(img.height, 1))
    tw = max(4, int(round(img.width * ratio)))
    return premul_box_resize(img, (tw, target_h))


def round_joint_caps(img: Image.Image, top_cap: bool = False, bottom_cap: bool = False) -> Image.Image:
    """Add soft 2px rounded ellipse overlap at limb joint cuts so large rotations never show gaps."""
    arr = np.asarray(img.convert("RGBA"), dtype=np.uint8).copy()
    h, w, _ = arr.shape
    mask = arr[:, :, 3] > 128

    def fill_cap(row_y: int, direction: int) -> None:
        xs = np.where(mask[row_y])[0]
        if len(xs) < 2:
            return
        x0, x1 = int(xs[0]), int(xs[-1])
        cx = 0.5 * (x0 + x1)
        rx = max(1.5, 0.5 * (x1 - x0))
        sample_rgb = np.median(arr[row_y, xs, :3], axis=0).astype(np.uint8)
        for dy in (1, 2):
            ny = row_y + dy * direction
            if ny < 0 or ny >= h:
                continue
            half_w = rx * np.sqrt(max(0.0, 1.0 - (dy / 2.6) ** 2))
            for x in range(max(0, int(round(cx - half_w))), min(w, int(round(cx + half_w)) + 1)):
                if arr[ny, x, 3] < 128:
                    arr[ny, x, :3] = sample_rgb
                    arr[ny, x, 3] = 255

    if top_cap:
        occ = np.where(mask.any(axis=1))[0]
        if len(occ) > 0:
            fill_cap(int(occ[0]), -1)
    if bottom_cap:
        occ = np.where(mask.any(axis=1))[0]
        if len(occ) > 0:
            fill_cap(int(occ[-1]), 1)
    return Image.fromarray(arr, mode="RGBA")


def make_symmetric_blink_head(head_open: Image.Image, head_wink: Image.Image) -> Image.Image:
    """Create pixel-locked both-eyes-closed head by copying the closed eye from head_wink onto both eyes of head_open."""
    # Resize wink to match open exactly
    w_im = head_wink.resize(head_open.size, Image.Resampling.LANCZOS)
    o_arr = np.asarray(head_open.convert("RGBA"), dtype=np.uint8).copy()
    w_arr = np.asarray(w_im.convert("RGBA"), dtype=np.uint8)
    h, w, _ = o_arr.shape
    # In head_wink, viewer's right eye (x: 52%..68%, y: 63%..79%) is cleanly closed!
    y0, y1 = int(h * 0.61), int(h * 0.80)
    rx0, rx1 = int(w * 0.52), int(w * 0.70)
    # Copy right closed eye to right side of open head
    o_arr[y0:y1, rx0:rx1] = w_arr[y0:y1, rx0:rx1]
    # Mirror right closed eye horizontally onto left eye region (x: 30%..48%)
    lx1 = w - rx0
    lx0 = w - rx1
    o_arr[y0:y1, lx0:lx1] = w_arr[y0:y1, rx0:rx1][:, ::-1, :]
    return Image.fromarray(o_arr, mode="RGBA")


def make_side_blink_head(head_left_px: Image.Image) -> Image.Image:
    """Paint a clean pixel closed eyelid over the side-view eye (zero stray eye-highlight dots)."""
    arr = np.asarray(head_left_px.convert("RGBA"), dtype=np.uint8).copy()
    h, w, _ = arr.shape
    # Sample smooth warm cheek skin color just below the eye
    cheek = arr[int(h * 0.72) : int(h * 0.84), int(w * 0.14) : int(w * 0.34)]
    skin_px = cheek[(cheek[:, :, 3] > 200) & (cheek[:, :, 0] > 195) & (cheek[:, :, 1] > 170)]
    skin_rgb = np.median(skin_px[:, :3], axis=0).astype(np.uint8) if len(skin_px) > 0 else np.array([240, 222, 214], dtype=np.uint8)
    # Cleanly replace the side-profile eye region (only pixels that aren't dark hair outline)
    y0, y1 = int(h * 0.56), int(h * 0.74)
    x0, x1 = int(w * 0.14), int(w * 0.31)
    for y in range(y0, y1):
        for x in range(x0, x1):
            if arr[y, x, 3] > 200:
                r, g, b = int(arr[y, x, 0]), int(arr[y, x, 1]), int(arr[y, x, 2])
                # Skip hair bangs (dark cool grey-blue with r < 110 and b > r)
                is_hair = r < 115 and b >= r and g < 115
                if not is_hair:
                    arr[y, x, :3] = skin_rgb
    # Draw crisp 1px dark closed eyelid curve
    lash_y = int(h * 0.67)
    for dx, x in enumerate(range(int(w * 0.17), int(w * 0.28))):
        ly = lash_y + (1 if dx in (1, 2) else 0)
        if 0 <= ly < h and arr[ly, x, 3] > 200:
            arr[ly, x, :3] = [42, 38, 52]
    return Image.fromarray(arr, mode="RGBA")


def add_joint_shading(img: Image.Image, row_frac: float, highlight_delta: int = 18, shadow_delta: int = -18) -> Image.Image:
    """Add crisp subtle pixel-art joint highlight + crease (knee cap / elbow fold) for clear articulation readability."""
    arr = np.asarray(img.convert("RGBA"), dtype=np.int16).copy()
    h, w, _ = arr.shape
    mask = arr[:, :, 3] > 200
    occ_rows = np.where(mask.any(axis=1))[0]
    if len(occ_rows) < 6:
        return img
    y_joint = int(occ_rows[0] + (occ_rows[-1] - occ_rows[0]) * row_frac)
    for dy, delta in ((-1, highlight_delta), (0, highlight_delta // 2), (1, shadow_delta)):
        y = y_joint + dy
        if 0 <= y < h:
            xs = np.where(mask[y])[0]
            if len(xs) >= 3:
                inner = xs[1:-1]
                arr[y, inner, :3] = np.clip(arr[y, inner, :3] + delta, 0, 255)
    return Image.fromarray(arr.astype(np.uint8), mode="RGBA")


def main() -> int:
    p_v2 = SRC_DIR / "catgirl_seedream_parts_v2.png"
    p_v1 = SRC_DIR / "catgirl_seedream_parts.png"
    im_v2 = Image.open(p_v2).convert("RGBA")
    im_v1 = clean_auto(Image.open(p_v1).convert("RGBA"))

    # ---- 1) Crop raw high-res parts from Seedream 5.5 sheets ----
    head_front_raw = crop_tight(im_v2, (100, 36, 496, 404))
    head_wink_raw = crop_tight(im_v2, (576, 36, 968, 404))
    head_blink_raw = make_symmetric_blink_head(head_front_raw, head_wink_raw)
    head_left_raw = crop_tight(im_v2, (1076, 36, 1440, 404))
    head_back_raw = crop_tight(im_v2, (1528, 36, 1904, 396))

    # Hair flowing clump -> rotate vertical-hanging & split into 2 spring segments + side lock
    hair_raw = crop_tight(im_v2, (2008, 84, 2408, 440))
    hair_hang = hair_raw.rotate(-68, resample=Image.Resampling.BICUBIC, expand=True)
    hb = hair_hang.getbbox()
    if hb:
        hair_hang = hair_hang.crop(hb)
    hh = hair_hang.height
    hair_root_raw = hair_hang.crop((0, 0, hair_hang.width, int(hh * 0.62)))
    hair_tip_raw = hair_hang.crop((0, int(hh * 0.44), hair_hang.width, hh))
    hair_side_raw = hair_hang.crop((int(hair_hang.width * 0.18), int(hh * 0.28), int(hair_hang.width * 0.62), hh))

    # Armless 3-view torsos from v2
    torso_front_raw = crop_tight(im_v2, (56, 524, 540, 1148))
    torso_left_raw = crop_tight(im_v2, (600, 520, 980, 1148))
    torso_back_raw = crop_tight(im_v2, (1028, 524, 1496, 1156))
    # Skirt hem strip extracted cleanly from bottom of front torso
    skirt_hem_raw = crop_tight(
        torso_front_raw,
        (int(torso_front_raw.width * 0.08), int(torso_front_raw.height * 0.74),
         int(torso_front_raw.width * 0.92), torso_front_raw.height),
    )

    # Flowing vertical coat flap from v1 [6] -> split into 2 spring segments
    flap_raw = crop_tight(im_v1, (716, 848, 1072, 1408))
    fh = flap_raw.height
    coat_root_raw = flap_raw.crop((0, 0, flap_raw.width, int(fh * 0.64)))
    coat_tip_raw = flap_raw.crop((0, int(fh * 0.48), flap_raw.width, fh))

    # Full dark-tights leg + grey sneaker from v1 [10] -> split at knee (47%) with overlap
    leg_raw = crop_tight(im_v1, (1840, 824, 2036, 1516))
    lh = leg_raw.height
    thigh_raw = leg_raw.crop((0, 0, leg_raw.width, int(lh * 0.50)))
    shin_raw = leg_raw.crop((0, int(lh * 0.43), leg_raw.width, lh))

    # Tactical gun case from v1 [11]
    guncase_raw = crop_tight(im_v1, (2104, 792, 2408, 1472))

    # Oversized navy sleeves + hand from v2 [9], [15], [11]
    arm_up_raw = crop_tight(im_v2, (1972, 544, 2160, 900))
    arm_fore_raw = crop_tight(im_v2, (1996, 1052, 2172, 1544))
    hand_raw = crop_tight(im_v2, (2012, 904, 2156, 1036))

    # ---- 2) Downsample every part to exact 128px-body pixel target dimensions ----
    def scale_wh(im: Image.Image, tw: int, th: int) -> Image.Image:
        return premul_box_resize(im, (max(4, tw), max(4, th)))

    down_parts: dict[str, Image.Image] = {
        "head_front": scale_to_height(head_front_raw, 36),
        "head_front_blink": scale_to_height(head_blink_raw, 36),
        "head_left": scale_to_height(head_left_raw, 36),
        "head_back": scale_to_height(head_back_raw, 36),
        "hair_back_root": scale_to_height(hair_root_raw, 21),
        "hair_back_tip": scale_to_height(hair_tip_raw, 14),
        "hair_side": scale_to_height(hair_side_raw, 13),
        "torso_front": scale_to_height(torso_front_raw, 46),
        "torso_left": scale_to_height(torso_left_raw, 46),
        "torso_back": scale_to_height(torso_back_raw, 46),
        "skirt_hem": scale_to_height(skirt_hem_raw, 14),
        "coat_flap_root": scale_wh(coat_root_raw, 13, 20),
        "coat_flap_tip": scale_wh(coat_tip_raw, 12, 12),
        # Sleek anime tights & sneaker proportions matching 128px catgirl 3-view
        "thigh": scale_wh(thigh_raw, 10, 31),
        "shin_boot": scale_wh(shin_raw, 13, 33),
        "gun_case": scale_wh(guncase_raw, 17, 64),
        "arm_upper": scale_wh(arm_up_raw, 10, 19),
        "arm_forearm": scale_wh(arm_fore_raw, 10, 20),
    }

    # Horizontal weapon-rig arm2 parts matching WeaponRig2D sizes (~26x14, 27x13, 12x10)
    w_up_rot = arm_up_raw.rotate(90, resample=Image.Resampling.BICUBIC, expand=True)
    fore_only = arm_fore_raw.crop((0, 0, arm_fore_raw.width, int(arm_fore_raw.height * 0.72)))
    w_fo_rot = fore_only.rotate(90, resample=Image.Resampling.BICUBIC, expand=True)
    # Compact gripping hand cropped around palm core so it wraps rifle/pistol grips neatly
    hand_core = hand_raw.crop((int(hand_raw.width * 0.14), int(hand_raw.height * 0.14),
                               int(hand_raw.width * 0.86), int(hand_raw.height * 0.82)))
    w_hand_rot = hand_core.rotate(90, resample=Image.Resampling.BICUBIC, expand=True)
    down_arm2: dict[str, Image.Image] = {
        "upper_arm": premul_box_resize(w_up_rot, (26, 14)),
        "forearm": premul_box_resize(w_fo_rot, (27, 13)),
        "hand": premul_box_resize(w_hand_rot, (12, 10)),
    }

    # ---- 3) Harden alpha & clean stray 1px dust ----
    for d in (down_parts, down_arm2):
        for k, im in list(d.items()):
            d[k] = remove_isolated_pixels(harden_alpha(im, threshold=126))

    # Add rounded joint overlap caps at limb cuts
    for k, tc, bc in [
        ("thigh", True, True),
        ("shin_boot", True, False),
        ("arm_upper", True, True),
        ("arm_forearm", True, False),
        ("coat_flap_root", True, False),
        ("coat_flap_tip", True, False),
    ]:
        down_parts[k] = round_joint_caps(down_parts[k], top_cap=tc, bottom_cap=bc)

    # Add subtle pixel-art knee-cap & elbow-fold joint readability shading
    down_parts["shin_boot"] = add_joint_shading(down_parts["shin_boot"], 0.12, 20, -16)
    down_parts["arm_forearm"] = add_joint_shading(down_parts["arm_forearm"], 0.14, 18, -16)

    # Create crisp pixel side-view blink head from cleaned head_left
    down_parts["head_left_blink"] = make_side_blink_head(down_parts["head_left"])

    # ---- 4) Extract ONE single global 48-color locked palette anchored to catgirl_seedream_parts_v2 ----
    palette_anchors = [
        down_parts["head_front"],
        down_parts["head_left"],
        down_parts["head_back"],
        down_parts["torso_front"],
        down_parts["torso_left"],
        down_parts["torso_back"],
        down_parts["thigh"],
        down_parts["shin_boot"],
        down_parts["gun_case"],
        down_parts["arm_forearm"],
    ]
    palette = build_locked_palette(palette_anchors, max_colors=48)

    # ---- 5) Apply locked palette + 1px selective dark outline & save ----
    OUT_PARTS.mkdir(parents=True, exist_ok=True)
    OUT_ARM2.mkdir(parents=True, exist_ok=True)

    saved_parts: dict[str, Image.Image] = {}
    for k, im in down_parts.items():
        q = apply_palette(im, palette)
        # Skip heavy outer outline on blink overlay & tiny hair tips? Keep clean subtle sel-out everywhere!
        out_im = add_selective_outline(q, strength=0.38)
        out_im.save(OUT_PARTS / f"{k}.png")
        saved_parts[k] = out_im

    for k, im in down_arm2.items():
        q = apply_palette(im, palette)
        out_im = add_selective_outline(q, strength=0.38)
        out_im.save(OUT_ARM2 / f"{k}.png")
        saved_parts["arm2_" + k] = out_im

    # ---- 6) Render 3x zoomed visual inspection contact sheet ----
    cols = 6
    keys = list(saved_parts.keys())
    rows = (len(keys) + cols - 1) // cols
    cell_w, cell_h = 220, 240
    sheet = Image.new("RGBA", (cols * cell_w, rows * cell_h), (42, 46, 54, 255))
    draw = ImageDraw.Draw(sheet)
    for idx, k in enumerate(keys):
        im = saved_parts[k]
        r, c = divmod(idx, cols)
        ox, oy = c * cell_w, r * cell_h
        # Checkerboard backing inside cell
        draw.rectangle([ox + 6, oy + 22, ox + cell_w - 6, oy + cell_h - 6], fill=(64, 68, 78, 255))
        scale = 3 if max(im.width, im.height) <= 56 else 2
        zoomed = im.resize((im.width * scale, im.height * scale), Image.Resampling.NEAREST)
        px = ox + (cell_w - zoomed.width) // 2
        py = oy + 22 + (cell_h - 28 - zoomed.height) // 2
        sheet.paste(zoomed, (px, py), zoomed)
        draw.text((ox + 8, oy + 4), f"{k} ({im.width}x{im.height})", fill=(255, 225, 130, 255))
    PREVIEW_OUT.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(PREVIEW_OUT)
    print(f"[build_doll_v2_parts] Saved {len(down_parts)} rig parts + {len(down_arm2)} arm2 parts (48-color locked palette)")
    print(f"[build_doll_v2_parts] Preview sheet: {PREVIEW_OUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
