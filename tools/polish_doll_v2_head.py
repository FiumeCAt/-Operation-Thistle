"""Pixel-art precision retouch for doll_v2 (灰蓝猫耳少女) head parts (v2).

Preserves the exact canvas size, anchor, lush bob-hair shading, and 128px×1 palette
harmony while giving her a clean anime face silhouette, feathery bangs, crisp bright
cool-blue eyes with specular catchlights, natural curved blink lashes, and a refined
left-facing profile.
"""
from __future__ import annotations

import shutil
from pathlib import Path
from PIL import Image
import numpy as np

PARTS_DIR = Path(r"D:\AI Game\HellWalker\HellWalker_DollProtocol\assets\art\characters\doll_v2\parts")
BACKUP_DIR = Path(r"C:\Users\81349\.gemini\antigravity\brain\c8612c36-8745-480a-9096-c8e0dcbd6621\scratch\doll_v2_head_backup")
COMPARE_OUT = Path(r"D:\AI Game\HellWalker\captures\screenshots\catgirl_head_before_after.png")

# Locked grey-blue tactical catgirl palette
OUTLINE  = (32, 33, 48, 255)      # #202130 crisp outer outline
HAIR_DK  = (56, 57, 79, 255)      # #38394f deep hair shadow / lock border
HAIR_MD  = (82, 82, 106, 255)     # #52526a primary hair base
HAIR_MD2 = (96, 97, 124, 255)     # #60617c secondary soft strand tone
HAIR_LT  = (120, 122, 152, 255)   # #787a98 strand highlight
HAIR_HI  = (162, 165, 196, 255)   # #a2a5c4 glossy crown highlight
EAR_IN1  = (160, 146, 174, 255)   # #a092ae inner ear lavender-grey
EAR_IN2  = (210, 194, 214, 255)   # #d2c2d6 inner ear bright fluff

SKIN_HI  = (253, 244, 242, 255)   # #fdf4f2 cheek / nose bridge highlight
SKIN_MD  = (247, 232, 228, 255)   # #f7e8e4 clean anime porcelain base
SKIN_SH  = (226, 202, 200, 255)   # #e2caca soft shadow under bangs & chin
SKIN_LN  = (162, 134, 144, 255)   # #a28690 soft warm jaw / profile contour
CHIN_LN  = (118, 98, 114, 255)    # #766272 clean delicate chin outline
BLUSH    = (244, 186, 192, 255)   # #f4bac0 subtle rosy cheek blush
MOUTH    = (196, 138, 146, 255)   # #c48a92 gentle cool calm mouth

LASH     = (26, 27, 42, 255)      # #1a1b2a crisp dark upper eyelash
LASH_SFT = (68, 70, 96, 255)      # #444660 soft eyelash corner / crease
SCLERA   = (255, 255, 255, 255)   # #ffffff crisp eye white & catchlight
EYE_TOP  = (42, 58, 98, 255)      # #2a3a62 deep slate-indigo upper iris / pupil
EYE_MID  = (82, 126, 198, 255)    # #527ec6 cool sapphire-blue iris
EYE_BOT  = (156, 210, 250, 255)   # #9cd2fa bright sky-cyan iris inner light


def put(arr: np.ndarray, x: int, y: int, col: tuple[int, int, int, int]) -> None:
    if 0 <= y < arr.shape[0] and 0 <= x < arr.shape[1]:
        arr[y, x] = col


def hline(arr: np.ndarray, x0: int, x1: int, y: int, col: tuple[int, int, int, int]) -> None:
    for x in range(x0, x1 + 1):
        put(arr, x, y, col)


def refine_hair_preserve_strands(arr: np.ndarray, protect_mask: np.ndarray) -> None:
    """Crisp up muddy anti-aliasing in hair while keeping lush strand variation."""
    h, w, _ = arr.shape
    for y in range(h):
        for x in range(w):
            if protect_mask[y, x]:
                continue
            if arr[y, x, 3] < 128:
                arr[y, x] = (0, 0, 0, 0)
                continue
            r, g, b = int(arr[y, x, 0]), int(arr[y, x, 1]), int(arr[y, x, 2])
            lum = 0.299 * r + 0.587 * g + 0.114 * b
            if y <= 9 and lum > 112 and (r - b) > -18:
                arr[y, x] = EAR_IN2 if lum > 158 else EAR_IN1
            elif lum < 52:
                arr[y, x] = OUTLINE
            elif lum < 75:
                arr[y, x] = HAIR_DK
            elif lum < 96:
                arr[y, x] = HAIR_MD
            elif lum < 122:
                arr[y, x] = HAIR_MD2
            elif lum < 160:
                arr[y, x] = HAIR_LT
            else:
                arr[y, x] = HAIR_HI


def clean_outer_border(arr: np.ndarray) -> None:
    h, w, _ = arr.shape
    opaque = arr[:, :, 3] >= 128
    arr[~opaque] = (0, 0, 0, 0)
    arr[opaque, 3] = 255
    for y in range(h):
        for x in range(w):
            if not opaque[y, x]:
                continue
            edge = False
            for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                nx, ny = x + dx, y + dy
                if nx < 0 or nx >= w or ny < 0 or ny >= h or not opaque[ny, nx]:
                    edge = True
                    break
            if edge:
                r, g, b = int(arr[y, x, 0]), int(arr[y, x, 1]), int(arr[y, x, 2])
                lum = 0.299 * r + 0.587 * g + 0.114 * b
                if lum > 170:
                    arr[y, x] = SKIN_LN
                elif lum > 70:
                    arr[y, x] = OUTLINE


def build_front(orig: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Build crisp front face (38x36) with feathered bangs, bright cool-blue anime eyes & clean blink."""
    arr = orig.copy()
    h, w, _ = arr.shape
    protect = np.zeros((h, w), dtype=bool)
    protect[18:35, 10:28] = True
    refine_hair_preserve_strands(arr, protect)

    # Soft twin hair sheen highlights across crown
    for x in (13, 14, 15, 22, 23, 24):
        if arr[12, x, 3] >= 128:
            put(arr, x, 12, HAIR_LT)
    for x in (14, 15, 22, 23):
        if arr[13, x, 3] >= 128:
            put(arr, x, 13, HAIR_HI if x in (14, 23) else HAIR_LT)

    # 1. Clean tapered anime face oval (symmetrical around x=18.5)
    face_spans = {
        19: (14, 23),
        20: (13, 24),
        21: (12, 25),
        22: (11, 26),
        23: (11, 26),
        24: (11, 26),
        25: (12, 25),
        26: (12, 25),
        27: (13, 24),
        28: (14, 23),
        29: (15, 22),
        30: (17, 20),
    }
    # Fill surrounding bangs/side-locks smoothly first
    for y in range(18, 32):
        for x in range(10, 28):
            if arr[y, x, 3] >= 128:
                put(arr, x, y, HAIR_MD)

    for y, (x0, x1) in face_spans.items():
        for x in range(x0, x1 + 1):
            if y <= 20:
                col = SKIN_SH
            elif y >= 29 or x in (x0, x1) and y <= 25:
                col = SKIN_SH
            elif 25 <= y <= 27 and 15 <= x <= 22:
                col = SKIN_HI
            else:
                col = SKIN_MD
            put(arr, x, y, col)
        # Soft dark hair shadow hugging outside cheeks & side-locks
        put(arr, x0 - 1, y, HAIR_DK if y <= 28 else OUTLINE)
        put(arr, x1 + 1, y, HAIR_DK if y <= 28 else OUTLINE)

    # Delicate tapered anime chin & cheek contour (no harsh blocky square!)
    put(arr, 13, 28, SKIN_LN)
    put(arr, 24, 28, SKIN_LN)
    put(arr, 14, 29, SKIN_LN)
    put(arr, 23, 29, SKIN_LN)
    put(arr, 15, 30, CHIN_LN)
    put(arr, 16, 30, CHIN_LN)
    put(arr, 21, 30, CHIN_LN)
    put(arr, 22, 30, CHIN_LN)
    hline(arr, 17, 20, 31, CHIN_LN)

    # Clean neck matching torso collar
    hline(arr, 16, 21, 32, SKIN_SH)
    hline(arr, 17, 20, 32, SKIN_MD)
    hline(arr, 17, 20, 33, SKIN_SH)
    put(arr, 16, 33, OUTLINE)
    put(arr, 21, 33, OUTLINE)
    hline(arr, 17, 20, 34, OUTLINE)

    # 2. Feathered, natural anime bangs (varied strand lengths + slim center parting!)
    # Top fringe band
    for x in range(11, 27):
        put(arr, x, 18, HAIR_MD2 if x in (14, 15, 22, 23) else HAIR_MD)
    # Feathered jagged bangs tips at y=19..21 (leaves tiny bright forehead gap & frames eyes!)
    for x in (11, 12, 13, 14, 15, 16, 17, 20, 21, 22, 23, 24, 25, 26):
        put(arr, x, 19, HAIR_DK if x in (11, 14, 17, 20, 23, 26) else HAIR_MD)
    for x in (11, 12, 16, 17, 20, 21, 25, 26):
        put(arr, x, 20, HAIR_DK if x in (12, 17, 20, 25) else HAIR_MD)
    # Delicate center-side lock tips touching bridge of nose
    put(arr, 17, 21, HAIR_DK)
    put(arr, 20, 21, HAIR_DK)
    # Forehead parting sliver at x=18..19
    put(arr, 18, 18, HAIR_DK)
    put(arr, 19, 18, HAIR_DK)
    put(arr, 18, 19, SKIN_SH)
    put(arr, 19, 19, SKIN_SH)
    put(arr, 18, 20, SKIN_MD)
    put(arr, 19, 20, SKIN_MD)
    # Subtle side-lock highlights on cheeks
    for y in (22, 23, 24, 25):
        put(arr, 9, y, HAIR_MD2)
        put(arr, 28, y, HAIR_MD2)

    # 3. Soft rosy cheeks + delicate calm expression mouth
    put(arr, 12, 26, BLUSH)
    put(arr, 13, 26, BLUSH)
    put(arr, 24, 26, BLUSH)
    put(arr, 25, 26, BLUSH)
    put(arr, 18, 28, MOUTH)
    put(arr, 19, 28, MOUTH)

    # Snapshot BEFORE drawing open eyes -> derive blink cleanly!
    blink = arr.copy()

    # 4. Crisp cool anime eyes on `arr` (left x=12..16, right x=21..25, y=21..24)
    # Upper dark lash arc (slightly tapered outer flick -> cool catgirl vibe!)
    put(arr, 12, 22, LASH)
    hline(arr, 13, 15, 21, LASH)
    put(arr, 16, 22, LASH_SFT)
    # Left sclera + vivid multi-tone slate-blue/cyan iris + sharp specular catchlight
    put(arr, 12, 23, SCLERA)
    put(arr, 16, 23, SCLERA)
    put(arr, 16, 24, SCLERA)
    put(arr, 13, 22, EYE_TOP)
    put(arr, 14, 22, EYE_TOP)
    put(arr, 15, 22, EYE_TOP)
    put(arr, 13, 23, SCLERA)      # bright upper-left highlight
    put(arr, 14, 23, EYE_TOP)     # deep pupil center
    put(arr, 15, 23, EYE_MID)     # sapphire iris
    put(arr, 13, 24, EYE_MID)     # iris lower-left
    put(arr, 14, 24, EYE_BOT)     # bright aqua-cyan lower bounce
    put(arr, 15, 24, EYE_BOT)

    # Right eye (symmetrical, matching upper-left highlight for lively gaze!)
    put(arr, 25, 22, LASH)
    hline(arr, 22, 24, 21, LASH)
    put(arr, 21, 22, LASH_SFT)
    put(arr, 25, 23, SCLERA)
    put(arr, 21, 23, SCLERA)
    put(arr, 21, 24, SCLERA)
    put(arr, 22, 22, EYE_TOP)
    put(arr, 23, 22, EYE_TOP)
    put(arr, 24, 22, EYE_TOP)
    put(arr, 22, 23, SCLERA)      # matching upper-left specular highlight
    put(arr, 23, 23, EYE_TOP)     # pupil center
    put(arr, 24, 23, EYE_MID)     # sapphire iris
    put(arr, 22, 24, EYE_MID)
    put(arr, 23, 24, EYE_BOT)     # lower bounce light
    put(arr, 24, 24, EYE_BOT)

    # 5. Clean gentle curved closed eyelashes on `blink` (fixed: written to `blink`, NOT `arr`!)
    put(blink, 12, 23, LASH)
    hline(blink, 13, 15, 24, LASH)
    put(blink, 16, 23, LASH_SFT)
    put(blink, 13, 23, SKIN_SH)
    put(blink, 14, 23, SKIN_SH)
    put(blink, 15, 23, SKIN_SH)

    put(blink, 21, 23, LASH_SFT)
    hline(blink, 22, 24, 24, LASH)
    put(blink, 25, 23, LASH)
    put(blink, 22, 23, SKIN_SH)
    put(blink, 23, 23, SKIN_SH)
    put(blink, 24, 23, SKIN_SH)

    clean_outer_border(arr)
    clean_outer_border(blink)
    return arr, blink


def build_left(orig: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Build crisp left-facing anime profile head (36x36) + matching curved blink frame."""
    arr = orig.copy()
    h, w, _ = arr.shape
    protect = np.zeros((h, w), dtype=bool)
    protect[19:35, 3:15] = True
    refine_hair_preserve_strands(arr, protect)

    # Glossy hair highlight band across crown
    for x in (12, 13, 14, 15, 16, 17, 18, 19):
        if arr[11, x, 3] >= 128 and x != 16:
            put(arr, x, 11, HAIR_LT)
    for x in (13, 14, 15, 18, 19):
        if arr[12, x, 3] >= 128:
            put(arr, x, 12, HAIR_HI if x in (14, 18) else HAIR_LT)

    # Clear blurry original face patch cleanly
    for y in range(21, 31):
        for x in range(3, 12):
            put(arr, x, y, (0, 0, 0, 0))

    # Organic diagonal bangs sweeping over forehead -> cheek side-lock
    for x in range(4, 13):
        put(arr, x, 19, HAIR_MD2 if x in (6, 7, 10) else HAIR_MD)
    for x in range(4, 12):
        put(arr, x, 20, HAIR_DK if x in (4, 8, 9) else HAIR_MD)
    put(arr, 3, 20, OUTLINE)
    put(arr, 4, 21, OUTLINE)
    put(arr, 5, 21, HAIR_MD)
    put(arr, 6, 21, HAIR_DK)
    for x in range(9, 13):
        put(arr, x, 21, HAIR_DK if x == 9 else HAIR_MD)

    # Delicate anime side profile (facing LEFT)
    profile_rows = {
        22: (5, 9),    # brow / temple
        23: (5, 10),   # upper eye
        24: (5, 10),   # lower eye / bridge
        25: (4, 10),   # cute small anime nose tip
        26: (5, 11),   # cheek
        27: (5, 11),   # mouth level
        28: (6, 11),   # chin curve
        29: (6, 10),   # lower chin
        30: (7, 10),   # jaw under-edge
    }
    for y, (x0, x1) in profile_rows.items():
        for x in range(x0, x1 + 1):
            if y == 22 or x == x1:
                col = SKIN_SH
            elif 25 <= y <= 27 and 5 <= x <= 8:
                col = SKIN_HI
            else:
                col = SKIN_MD
            put(arr, x, y, col)

    # Soft contoured profile edge
    put(arr, 4, 22, SKIN_LN)
    put(arr, 4, 23, SKIN_LN)
    put(arr, 4, 24, SKIN_LN)
    put(arr, 3, 25, SKIN_LN)   # nose tip
    put(arr, 4, 26, SKIN_LN)
    put(arr, 4, 27, SKIN_LN)
    put(arr, 5, 28, SKIN_LN)
    put(arr, 5, 29, CHIN_LN)
    put(arr, 6, 30, CHIN_LN)
    hline(arr, 7, 10, 31, CHIN_LN)

    # Diagonal cheek side-lock curving gracefully down toward bob tips
    put(arr, 10, 22, HAIR_DK)
    put(arr, 11, 22, HAIR_MD)
    put(arr, 11, 23, HAIR_DK)
    put(arr, 11, 24, HAIR_DK)
    put(arr, 11, 25, HAIR_DK)
    for y in range(26, 31):
        put(arr, 12, y, HAIR_DK if y <= 28 else HAIR_MD)
        put(arr, 11, y, HAIR_DK if y >= 29 else SKIN_SH)
    put(arr, 11, 29, HAIR_DK)
    put(arr, 11, 30, HAIR_DK)

    # Soft cheek blush + delicate tiny mouth
    put(arr, 9, 26, BLUSH)
    put(arr, 10, 26, BLUSH)
    put(arr, 6, 27, (214, 160, 168, 255))

    # Clean neck
    hline(arr, 15, 19, 32, SKIN_SH)
    hline(arr, 16, 18, 32, SKIN_MD)
    hline(arr, 15, 19, 33, SKIN_SH)
    put(arr, 14, 33, OUTLINE)
    put(arr, 20, 33, OUTLINE)
    hline(arr, 15, 19, 34, OUTLINE)

    # Snapshot BEFORE drawing open eye!
    blink = arr.copy()

    # Crisp left-facing anime side eye on `arr` (x=6..9, y=22..24)
    hline(arr, 6, 9, 22, LASH)
    put(arr, 9, 23, LASH_SFT)
    put(arr, 6, 23, SCLERA)       # bright front sclera + catchlight
    put(arr, 7, 23, EYE_TOP)      # pupil core
    put(arr, 8, 23, EYE_MID)      # sapphire iris
    put(arr, 6, 24, SCLERA)
    put(arr, 7, 24, EYE_MID)
    put(arr, 8, 24, EYE_BOT)      # aqua lower iris glow

    # Crisp closed eyelash on `blink` (fixed: written to `blink`!)
    put(blink, 6, 23, SKIN_SH)
    put(blink, 7, 23, SKIN_SH)
    put(blink, 8, 23, SKIN_SH)
    hline(blink, 6, 8, 24, LASH)
    put(blink, 9, 23, LASH_SFT)

    clean_outer_border(arr)
    clean_outer_border(blink)
    return arr, blink


def build_back(orig: np.ndarray) -> np.ndarray:
    arr = orig.copy()
    protect = np.zeros((arr.shape[0], arr.shape[1]), dtype=bool)
    refine_hair_preserve_strands(arr, protect)
    for x in (13, 14, 15, 16, 21, 22, 23, 24):
        if arr[12, x, 3] >= 128:
            put(arr, x, 12, HAIR_LT)
    for x in (14, 15, 22, 23):
        if arr[13, x, 3] >= 128:
            put(arr, x, 13, HAIR_HI if x in (14, 23) else HAIR_LT)
    clean_outer_border(arr)
    return arr


def main() -> None:
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    COMPARE_OUT.parent.mkdir(parents=True, exist_ok=True)

    files = ["head_front.png", "head_front_blink.png", "head_left.png", "head_left_blink.png", "head_back.png"]
    originals: dict[str, np.ndarray] = {}
    for fn in files:
        src = PARTS_DIR / fn
        bak = BACKUP_DIR / fn
        if not bak.exists():
            shutil.copy2(src, bak)
        originals[fn] = np.array(Image.open(bak).convert("RGBA"))

    new_front, new_front_blink = build_front(originals["head_front.png"])
    new_left, new_left_blink = build_left(originals["head_left.png"])
    new_back = build_back(originals["head_back.png"])

    outputs = {
        "head_front.png": new_front,
        "head_front_blink.png": new_front_blink,
        "head_left.png": new_left,
        "head_left_blink.png": new_left_blink,
        "head_back.png": new_back,
    }
    for fn, arr in outputs.items():
        Image.fromarray(arr, "RGBA").save(PARTS_DIR / fn)

    scale = 8
    pad = 20
    cell_w = 38 * scale
    cell_h = 36 * scale
    cols = 4
    rows = 2
    sheet = Image.new("RGBA", (cols * cell_w + (cols + 1) * pad, rows * cell_h + (rows + 1) * pad + 20), (34, 38, 48, 255))
    show_order = ["head_front.png", "head_front_blink.png", "head_left.png", "head_left_blink.png"]
    for idx, fn in enumerate(show_order):
        x = pad + idx * (cell_w + pad)
        im_b = Image.fromarray(originals[fn], "RGBA")
        im_b_z = im_b.resize((im_b.width * scale, im_b.height * scale), Image.Resampling.NEAREST)
        sheet.alpha_composite(im_b_z, (x, pad + 10))
        im_a = Image.fromarray(outputs[fn], "RGBA")
        im_a_z = im_a.resize((im_a.width * scale, im_a.height * scale), Image.Resampling.NEAREST)
        sheet.alpha_composite(im_a_z, (x, pad * 2 + cell_h + 10))

    sheet.save(COMPARE_OUT)
    print(f"Saved v2 polished heads & comparison sheet: {COMPARE_OUT}")


if __name__ == "__main__":
    main()
