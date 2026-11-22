#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""武器侧视素材后处理（按《武器侧视素材规范》）。

输入：tools/art_sources/weapons/<id>_raw.png（Seedream 5.5，透明底、裸枪）
输出：assets/art/weapons/<id>/side.png   固定画布：枪管轴线在 35% 高度，左右留白 5%
      assets/art/weapons/<id>/icon.png   由 side.png 最近邻缩放派生
      assets/art/weapons/<id>/meta.json  grip_px / muzzle_px / visual_length / barrel_angle_deg
      tools/previews/weapon_<id>_calib.png

处理顺序：清边 → alpha 裁切 → 摆正 → 枪管轴精修（≤0.2°）→ 缩到逻辑像素网格 →
48 色量化 → 按固定轴线合成画布 → 4 倍最近邻放大。

用法：
  python tools/prep_new_weapons.py g18
  python tools/prep_new_weapons.py --all
"""

import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "tools" / "art_sources" / "weapons"
OUT = ROOT / "assets" / "art" / "weapons"
PREV = ROOT / "tools" / "previews"

ICON_SIZE = 128
# 逻辑画布宽度（规范：长枪 240~320、冲锋枪 200~260、手枪 140~180）
CANVAS_WIDTH = {
    "pistol": 180,
    "revolver": 180,
    "smg": 260,
    "rifle": 320,
    "dmr": 320,
    "sniper": 320,
}
MARGIN_RATIO = 0.05      # 左右留白 5%（规范 4%~6%）
AXIS_RATIO = 0.35        # 枪管轴线固定画布高度 35%
PALETTE_COLORS = 48      # 规范 32~64 色
UPSCALE = 4

# id: (类别, 真实枪长 m, 握把横向比例, 握把纵向比例)
SPECS = {
    "g18": ("pistol", 0.20, 0.20, 0.86),
    "m1911": ("pistol", 0.22, 0.18, 0.86),
    "fn57": ("pistol", 0.21, 0.19, 0.86),
    "python": ("revolver", 0.30, 0.17, 0.84),
    "mp7": ("smg", 0.60, 0.44, 0.70),
    "tmp": ("smg", 0.45, 0.47, 0.72),
    "p90": ("smg", 0.50, 0.70, 0.72),
    "ump45": ("smg", 0.69, 0.40, 0.72),
    "fal": ("rifle", 1.10, 0.31, 0.72),
    "akm": ("rifle", 0.88, 0.31, 0.72),
    "l85a2": ("rifle", 0.785, 0.45, 0.70),
    "sr25": ("dmr", 1.11, 0.30, 0.72),
    "vss": ("dmr", 0.894, 0.42, 0.72),
    "awm": ("sniper", 1.23, 0.30, 0.72),
}


def load_rgba(path: Path) -> Image.Image:
    im = Image.open(path).convert("RGBA")
    arr = np.array(im)
    arr[:, :, 3] = np.where(arr[:, :, 3] < 24, 0, arr[:, :, 3])
    return Image.fromarray(arr, "RGBA")


def alpha_crop(im: Image.Image) -> Image.Image:
    a = np.array(im)[:, :, 3]
    ys, xs = np.nonzero(a > 16)
    if xs.size == 0:
        raise ValueError("整张图全透明")
    return im.crop((int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1))


def principal_angle(im: Image.Image) -> float:
    a = np.array(im)[:, :, 3]
    ys, xs = np.nonzero(a > 16)
    if xs.size < 100:
        return 0.0
    y0, y1 = ys.min(), ys.max()
    cut = y0 + (y1 - y0) * 0.5
    keep = ys <= cut
    xs = xs[keep]
    ys = ys[keep]
    if xs.size < 100:
        return 0.0
    pts = np.stack([xs - xs.mean(), ys - ys.mean()], axis=1).astype(np.float64)
    evals, evecs = np.linalg.eigh(np.cov(pts, rowvar=False))
    major = evecs[:, int(np.argmax(evals))]
    ang = float(np.degrees(np.arctan2(major[1], major[0])))
    while ang > 90.0:
        ang -= 180.0
    while ang < -90.0:
        ang += 180.0
    return ang


def rotate_clean(im: Image.Image, degrees: float) -> Image.Image:
    rot = im.rotate(degrees, resample=Image.BICUBIC, expand=True, fillcolor=(0, 0, 0, 0))
    arr = np.array(rot)
    arr[:, :, 3] = np.where(arr[:, :, 3] < 40, 0, arr[:, :, 3])
    return Image.fromarray(arr, "RGBA")


def level(im: Image.Image) -> Image.Image:
    # 用右侧枪管段顶边做基准；PCA 会被握把/枪托带偏，不能用来判断平直。
    for _ in range(4):
        ang = barrel_angle(im)
        if abs(ang) < 0.2:
            break
        im = alpha_crop(rotate_clean(im, ang))
    return im


def barrel_angle(im: Image.Image) -> float:
    """取右侧枪管段的上沿做最小二乘拟合，返回带符号角度（度）。"""
    a = np.array(im)[:, :, 3] > 16
    h, w = a.shape
    xs, ys = [], []
    for x in range(int(w * 0.55), int(w * 0.95)):
        col = np.where(a[:, x])[0]
        if col.size:
            xs.append(x)
            ys.append(int(col.min()))
    if len(xs) < 20:
        return 0.0
    x_arr = np.array(xs, dtype=np.float64)
    y_arr = np.array(ys, dtype=np.float64)
    slope = np.polyfit(x_arr, y_arr, 1)[0]
    return float(math.degrees(math.atan(slope)))


def refine_axis(im: Image.Image) -> tuple[Image.Image, float]:
    """把枪管轴压到规范误差内，返回（图, 旋转后残余角度）。"""
    for _ in range(3):
        ang = barrel_angle(im)
        if abs(ang) <= 0.2:
            break
        im = alpha_crop(rotate_clean(im, ang))
    return im, barrel_angle(im)


def ensure_facing_right(im: Image.Image) -> Image.Image:
    a = np.array(im)[:, :, 3] > 16
    cols = np.where(a.any(axis=0))[0]
    if cols.size == 0:
        return im
    l, r = int(cols.min()), int(cols.max())
    band = max(1, int((r - l) * 0.10))

    def ext(x0: int, x1: int) -> int:
        ys = np.where(a[:, x0:x1].any(axis=1))[0]
        return int(ys.max() - ys.min()) if ys.size else 0

    left = ext(l, min(r, l + band))
    right = ext(max(l, r - band), r + 1)
    return im.transpose(Image.FLIP_LEFT_RIGHT) if left < right * 0.8 else im


def quantize(im: Image.Image) -> Image.Image:
    q = im.quantize(colors=PALETTE_COLORS, method=Image.FASTOCTREE).convert("RGBA")
    arr = np.array(q)
    arr[:, :, 3] = np.where(arr[:, :, 3] < 24, 0, arr[:, :, 3])
    return Image.fromarray(arr, "RGBA")


def compose(im: Image.Image, kind: str) -> tuple[Image.Image, dict]:
    """把枪缩到逻辑网格并放进固定轴线画布；返回画布与枪身 bbox。"""
    width = CANVAS_WIDTH[kind]
    margin = max(1, int(round(width * MARGIN_RATIO)))
    gun_w = width - margin * 2
    scale = gun_w / im.width
    gun_h = max(1, int(round(im.height * scale)))
    gun = quantize(im.resize((gun_w, gun_h), Image.BOX))

    a = np.array(gun)[:, :, 3] > 16
    cols = np.where(a.any(axis=0))[0]
    right = int(cols.max())
    band = a[:, max(0, right - 1):right + 1]
    ys = np.where(band.any(axis=1))[0]
    axis_in_gun = int(round(float(np.mean(ys)))) if ys.size else gun_h // 2

    top = axis_in_gun
    bottom = gun_h - axis_in_gun
    height = int(math.ceil(max(top / (AXIS_RATIO - 0.04), bottom / (1.0 - AXIS_RATIO - 0.04), 40)))
    for _ in range(4):
        axis_y = int(round(height * AXIS_RATIO))
        grow = 0.0
        if axis_y - top < 2:
            grow = max(grow, (top + 2) / AXIS_RATIO - height)
        if height - axis_y - bottom < 2:
            grow = max(grow, (bottom + 2) / (1.0 - AXIS_RATIO) - height)
        if grow <= 0.0:
            break
        height = int(math.ceil(height + grow))
    axis_y = int(round(height * AXIS_RATIO))

    canvas = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    y0 = axis_y - axis_in_gun
    canvas.paste(gun, (margin, y0), gun)
    return canvas, {"x": margin, "y": y0, "w": gun_w, "h": gun_h,
                    "axis_y": axis_y, "height": height}


def anchors(canvas: Image.Image, box: dict, grip_x: float, grip_y: float):
    a = np.array(canvas)[:, :, 3]
    opaque = a > 16
    h, w = a.shape

    cols = np.where(opaque.any(axis=0))[0]
    right = int(cols.max())
    band = opaque[:, max(0, right - 1):right + 1]
    ys = np.where(band.any(axis=1))[0]
    muzzle = (right, int(round(float(np.mean(ys)))) if ys.size else h // 2)

    gx = int(round(box["x"] + box["w"] * grip_x))
    lo = max(0, gx - 1)
    window = opaque[:, lo:gx + 1]
    ys2 = np.where(window.any(axis=1))[0]
    if ys2.size:
        top, bottom = int(ys2.min()), int(ys2.max())
        gy = int(round(top + (bottom - top) * grip_y))
    else:
        gy = box["y"] + box["h"] // 2
    return (gx, gy), muzzle


def make_icon(side: Image.Image, out: Path) -> None:
    img = side.copy()
    scale = min((ICON_SIZE - 8) / img.width, (ICON_SIZE - 8) / img.height)
    size = (max(1, int(round(img.width * scale))), max(1, int(round(img.height * scale))))
    img = img.resize(size, Image.NEAREST)
    icon = Image.new("RGBA", (ICON_SIZE, ICON_SIZE), (0, 0, 0, 0))
    icon.paste(img, ((ICON_SIZE - img.width) // 2, (ICON_SIZE - img.height) // 2), img)
    out.parent.mkdir(parents=True, exist_ok=True)
    icon.save(out)


def draw_calib(im: Image.Image, grip, muzzle, wid: str, axis_y: int) -> None:
    PREV.mkdir(parents=True, exist_ok=True)
    view = im.copy()
    dr = ImageDraw.Draw(view)
    half = int(view.width * 0.012)
    for (x, y), color in ((grip, (255, 60, 60, 255)), (muzzle, (60, 220, 240, 255))):
        dr.ellipse([x - half, y - half, x + half, y + half], outline=color, width=max(2, half // 3))
        dr.line([x - half * 2, y, x + half * 2, y], fill=color, width=2)
        dr.line([x, y - half * 2, x, y + half * 2], fill=color, width=2)
    dr.line([0, axis_y, view.width, axis_y], fill=(80, 200, 255, 120), width=1)
    bg = Image.new("RGBA", view.size, (30, 26, 24, 255))
    bg.alpha_composite(view)
    bg.convert("RGB").save(PREV / f"weapon_{wid}_calib.png")


def process(wid: str) -> bool:
    if wid not in SPECS:
        print(f"未知武器 id：{wid}")
        return False
    kind, length, grip_x, grip_y = SPECS[wid]
    raw = SRC / f"{wid}_raw.png"
    if not raw.exists():
        print(f"缺少原图：{raw}")
        return False

    im = alpha_crop(load_rgba(raw))
    im = ensure_facing_right(alpha_crop(level(im)))
    im, residual = refine_axis(im)
    im = alpha_crop(im)
    if residual > 0.2:
        print(f"[warn] {wid} 枪管轴残余 {residual:.2f}° 超过 0.2°")

    logical, box = compose(im, kind)
    grip, muzzle = anchors(logical, box, grip_x, grip_y)

    side = logical.resize(
        (logical.width * UPSCALE, logical.height * UPSCALE), Image.NEAREST)
    dst = OUT / wid
    dst.mkdir(parents=True, exist_ok=True)
    side.save(dst / "side.png")
    make_icon(side, dst / "icon.png")
    meta = (
        '{\n'
        f'  "id": "{wid}",\n'
        f'  "grip_px": [{grip[0] * UPSCALE}, {grip[1] * UPSCALE}],\n'
        f'  "muzzle_px": [{muzzle[0] * UPSCALE}, {muzzle[1] * UPSCALE}],\n'
        f'  "visual_length": {length},\n'
        f'  "barrel_angle_deg": {round(residual, 2)}\n'
        '}\n'
    )
    (dst / "meta.json").write_text(meta, encoding="utf-8")
    draw_calib(side, (grip[0] * UPSCALE, grip[1] * UPSCALE),
        (muzzle[0] * UPSCALE, muzzle[1] * UPSCALE), wid, muzzle[1] * UPSCALE)
    axis_pct = 100.0 * muzzle[1] / max(logical.height, 1)
    print(f"[{wid}] {kind} canvas={logical.width}x{logical.height} "
          f"axis={axis_pct:.1f}% residual={residual:+.2f}° "
          f"grip={grip} muzzle={muzzle} len={length}")
    return True


def main() -> int:
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        return 2
    targets = list(SPECS.keys()) if args[0] == "--all" else args
    ok = True
    for wid in targets:
        ok = process(wid) and ok
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
