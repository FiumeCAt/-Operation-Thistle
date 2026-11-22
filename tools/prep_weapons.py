#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""武器素材后处理：裁切 + 握把/枪口标定 + 输出 meta.json。

输入：tools/art_sources/weapons/<id>_raw.png
输出：assets/art/weapons/<id>/side.png
      assets/art/weapons/<id>/meta.json  {grip_px, muzzle_px, visual_length}
      tools/previews/weapon_<id>_calib.png   标定可视化（红=握把 青=枪口）

握把启发式：枪托在最左，握把/扳机在左侧 20%~26% 处、本体下沿略上。
枪口：最右 3 列不透明像素的垂直重心。

运行：py -3.11 tools/prep_weapons.py
"""

from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "tools" / "art_sources" / "weapons"
OUT = ROOT / "assets" / "art" / "weapons"
PREV = ROOT / "tools" / "previews"

# 真实枪长（米），用于换算世界尺寸
VISUAL_LENGTH = {
    "m870": 0.98,
    "m1014": 0.89,
    "saiga12k": 0.82,
    "g17": 0.20,
}

# 握把（扳机手）在裁剪后贴图中的相对位置。
# 长枪：枪托在最左，扳机大约在 36% 处、垂直居中偏下。
# 手枪：握把在最左下方。
GRIP_X_RATIO = {"long": 0.36, "pistol": 0.20}
GRIP_Y_RATIO = {"long": 0.62, "pistol": 0.86}


def load_rgba(path: Path) -> Image.Image:
    return Image.open(path).convert("RGBA")


def alpha_crop(im: Image.Image, pad_ratio: float = 0.015) -> Image.Image:
    """按 alpha 通道裁切（不能用 getbbox：透明区常残留非零 RGB，会裁成整张画布）。"""
    a = np.array(im)[:, :, 3]
    ys, xs = np.nonzero(a > 16)
    if xs.size == 0:
        raise ValueError("整张图全透明")
    l, r = int(xs.min()), int(xs.max()) + 1
    t, b = int(ys.min()), int(ys.max()) + 1
    pad = int(round(max(r - l, b - t) * pad_ratio))
    l = max(0, l - pad)
    t = max(0, t - pad)
    r = min(im.width, r + pad)
    b = min(im.height, b + pad)
    return im.crop((l, t, r, b))


def principal_angle(im: Image.Image) -> float:
    """求武器主方向角（度），水平时为 0。

    只用 bbox 上半部的像素做 PCA：手枪的握把朝下会把整体主方向拽成对角，
    而枪管/套筒永远在水平带上，所以取上半部更稳。
    """
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
    cov = np.cov(pts, rowvar=False)
    evals, evecs = np.linalg.eigh(cov)
    major = evecs[:, int(np.argmax(evals))]
    ang = float(np.degrees(np.arctan2(major[1], major[0])))
    while ang > 90.0:
        ang -= 180.0
    while ang < -90.0:
        ang += 180.0
    return ang


def level(im: Image.Image, min_deg: float = 1.5) -> Image.Image:
    """把武器摆正到水平（主方向角归零），再做一次 alpha 阈值清理。"""
    ang = principal_angle(im)
    if abs(ang) < min_deg:
        return im
    rot = im.rotate(-ang, resample=Image.BICUBIC, expand=True, fillcolor=(0, 0, 0, 0))
    arr = np.array(rot)
    arr[:, :, 3] = np.where(arr[:, :, 3] < 40, 0, arr[:, :, 3])
    return Image.fromarray(arr, "RGBA")


def calibrate(im: Image.Image, kind: str = "long") -> tuple[tuple[int, int], tuple[int, int]]:
    a = np.array(im)[:, :, 3]
    h, w = a.shape
    opaque = a > 16

    # 枪口：最右若干列不透明像素的重心
    cols = np.where(opaque.any(axis=0))[0]
    right = int(cols.max())
    band = opaque[:, max(0, right - 2): right + 1]
    ys = np.where(band.any(axis=1))[0]
    muzzle = (right, int(round(float(np.mean(ys)))) if ys.size else h // 2)

    # 握把：按类别取相对横坐标，纵向取该列不透明区间的相对高度
    gx = int(round(w * GRIP_X_RATIO.get(kind, 0.36)))
    lo = max(0, gx - max(2, int(w * 0.02)))
    hi = min(w, gx + max(2, int(w * 0.02)))
    window = opaque[:, lo:hi]
    ys2 = np.where(window.any(axis=1))[0]
    if ys2.size:
        top, bottom = int(ys2.min()), int(ys2.max())
        gy = int(round(top + (bottom - top) * GRIP_Y_RATIO.get(kind, 0.62)))
    else:
        gy = h // 2
    return (gx, gy), muzzle


def draw_calib(im: Image.Image, grip, muzzle, wid: str) -> None:
    PREV.mkdir(parents=True, exist_ok=True)
    view = im.copy()
    dr = ImageDraw.Draw(view)
    r = max(6, int(im.width * 0.012))
    for (x, y), color in ((grip, (255, 60, 60, 255)), (muzzle, (60, 220, 240, 255))):
        dr.ellipse([x - r, y - r, x + r, y + r], outline=color, width=max(2, r // 4))
        dr.line([x - r * 2, y, x + r * 2, y], fill=color, width=2)
        dr.line([x, y - r * 2, x, y + r * 2], fill=color, width=2)
    bg = Image.new("RGBA", view.size, (18, 22, 28, 255))
    bg.alpha_composite(view)
    bg.convert("RGB").save(PREV / f"weapon_{wid}_calib.png")


def main() -> int:
    if not SRC.exists():
        print("没有 weapons 源目录")
        return 1
    raws = sorted(SRC.glob("*_raw.png"))
    if not raws:
        print("没有 *_raw.png")
        return 1
    for raw in raws:
        wid = raw.stem.replace("_raw", "")
        im = alpha_crop(load_rgba(raw))
        ang = principal_angle(im)
        im = alpha_crop(level(im))
        grip, muzzle = calibrate(im, "pistol" if wid == "g17" else "long")
        ratio = im.width / max(im.height, 1)
        # 手枪本身接近 L 形，长宽比 ~1.4 属正常；长枪才要求 > 2.2
        min_ratio = 2.2 if wid != "g17" else 1.25
        if ratio < min_ratio:
            print(f"[warn] {wid} 长宽比只有 {ratio:.2f}，可能不是水平侧视，建议重生成")
        print(f"[{wid}] src_angle={ang:+.1f}deg")
        dst = OUT / wid
        dst.mkdir(parents=True, exist_ok=True)
        im.save(dst / "side.png")
        length = VISUAL_LENGTH.get(wid, 0.9)
        meta = (
            '{\n'
            f'  "id": "{wid}",\n'
            f'  "grip_px": [{grip[0]}, {grip[1]}],\n'
            f'  "muzzle_px": [{muzzle[0]}, {muzzle[1]}],\n'
            f'  "visual_length": {length}\n'
            '}\n'
        )
        (dst / "meta.json").write_text(meta, encoding="utf-8")
        draw_calib(im, grip, muzzle, wid)
        print(f"[{wid}] {im.width}x{im.height} grip={grip} muzzle={muzzle} len={length}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
