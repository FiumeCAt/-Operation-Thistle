"""把 8 向立绘图集烘成"浮雕受光"版本，用固定屏幕光伪造体积。

镜头锁定、太阳固定，所以屏幕空间光向是不变的，可以直接把明暗烘进贴图：
亮度当高度 -> 求梯度得伪法线 -> 方向光漫反射 + 高光 + 轮廓补光 + 底部 AO + 折痕内描线。
"""
import os
import numpy as np
from PIL import Image

CELL_W, CELL_H = 128, 192
COLS, ROWS = 8, 23

# 屏幕空间光向：从左上偏前打过来，与场景里的主光一致。
LIGHT = np.array([-0.50, -0.60, 0.62], dtype=np.float32)
LIGHT /= np.linalg.norm(LIGHT)
HALF = LIGHT + np.array([0.0, 0.0, 1.0], dtype=np.float32)
HALF /= np.linalg.norm(HALF)

HEIGHT_GAIN = 3.0      # 亮度当高度的夸张程度，越大越"浮雕"
HEIGHT_BLUR = 2.4      # 先重模糊，避免布褶/发丝纹理被当成法线噪声
GRADE_BANDS = 3        # 明暗色阶数量：3 档在缩小后仍能读出受光面与背光面
SHADE_BASE = 0.74
SHADE_RANGE = 0.42
BAND_BLEND = 0.62
## 冷暖分离的强度：太强会把柔光厚涂撕成脏斑，这里只做轻微色温偏移。
TINT_STRENGTH = 0.35
COOL_TINT = np.array([0.86, 0.93, 1.14], dtype=np.float32)
WARM_TINT = np.array([1.08, 1.03, 0.93], dtype=np.float32)
RIM_STRENGTH = 0.22
RIM_COLOR = np.array([0.80, 0.88, 1.0], dtype=np.float32)
SPEC_STRENGTH = 0.15
AO_STRENGTH = 0.42


def gaussian_kernel(sigma: float) -> np.ndarray:
    radius = max(1, int(sigma * 3))
    x = np.arange(-radius, radius + 1, dtype=np.float32)
    k = np.exp(-(x * x) / (2.0 * sigma * sigma))
    return k / k.sum()


def blur(img: np.ndarray, sigma: float) -> np.ndarray:
    k = gaussian_kernel(sigma)
    r = len(k) // 2
    pad = np.pad(img, ((0, 0), (r, r)), mode="edge")
    out = np.zeros_like(img)
    for i, w in enumerate(k):
        out += pad[:, i:i + img.shape[1]] * w
    pad = np.pad(out, ((r, r), (0, 0)), mode="edge")
    out = np.zeros_like(img)
    for i, w in enumerate(k):
        out += pad[i:i + img.shape[0], :] * w
    return out


def erode(mask: np.ndarray, radius: int) -> np.ndarray:
    out = mask.copy()
    h, w = mask.shape
    for dy in range(-radius, radius + 1):
        for dx in range(-radius, radius + 1):
            shifted = np.zeros_like(mask)
            ys = slice(max(0, dy), h + min(0, dy))
            xs = slice(max(0, dx), w + min(0, dx))
            yd = slice(max(0, -dy), h + min(0, -dy))
            xd = slice(max(0, -dx), w + min(0, -dx))
            shifted[ys, xs] = mask[yd, xd]
            out = np.minimum(out, shifted)
    return out


def process_cell(rgb: np.ndarray, alpha: np.ndarray) -> np.ndarray:
    h, w = alpha.shape
    lum = rgb[..., 0] * 0.299 + rgb[..., 1] * 0.587 + rgb[..., 2] * 0.114
    height = blur(lum * alpha, HEIGHT_BLUR)

    gy, gx = np.gradient(height)
    nx = -gx * HEIGHT_GAIN
    ny = -gy * HEIGHT_GAIN
    nz = np.ones_like(nx)
    norm = np.sqrt(nx * nx + ny * ny + nz * nz)
    nx, ny, nz = nx / norm, ny / norm, nz / norm

    diff = np.clip(nx * LIGHT[0] + ny * LIGHT[1] + nz * LIGHT[2], 0.0, 1.0)
    shade = SHADE_BASE + SHADE_RANGE * diff
    # 硬色阶：把连续明暗压成几档，和场景的平涂语言对齐。
    banded = np.floor(shade * GRADE_BANDS) / GRADE_BANDS
    shade = banded * BAND_BLEND + shade * (1.0 - BAND_BLEND)
    shade = np.where(alpha > 0.01, shade, 1.0)

    spec = np.clip(nx * HALF[0] + ny * HALF[1] + nz * HALF[2], 0.0, 1.0) ** 24
    spec = spec * SPEC_STRENGTH * np.clip((lum - 0.45) / 0.4, 0.0, 1.0) * alpha

    # 轮廓补光：朝向光的轮廓边缘提亮，让剪影不至于死板。
    edge = np.clip(alpha - erode(alpha > 0.5, 1).astype(np.float32), 0.0, 1.0)
    facing = np.clip(-nx * 0.75 - ny * 0.75, 0.0, 1.0)
    rim = edge * facing * RIM_STRENGTH * alpha

    # 底部 AO + 内缘压暗，强化接地。
    vertical = np.linspace(0.0, 1.0, h, dtype=np.float32)[:, None]
    ao = 1.0 - AO_STRENGTH * 0.34 * np.clip((vertical - 0.66) / 0.34, 0.0, 1.0)
    inner = np.clip(erode(alpha > 0.5, 3).astype(np.float32) - erode(alpha > 0.5, 7).astype(np.float32), 0.0, 1.0)
    ao = ao * (1.0 - 0.16 * inner)

    out = rgb * (shade * ao)[..., None]
    # 冷暖分离：背光面压向蓝紫，受光面推回暖色，轻度即可。
    warm = np.clip((shade - 1.0) / 0.28, 0.0, 1.0)[..., None]
    cool = np.clip((0.94 - shade) / 0.26, 0.0, 1.0)[..., None]
    out = out * (1.0 + (cool * (COOL_TINT - 1.0) + warm * (WARM_TINT - 1.0)) * TINT_STRENGTH)
    out = out + (rim[..., None] * RIM_COLOR + spec[..., None])
    out = np.clip(out, 0.0, 1.0)
    out = np.concatenate([out, alpha[..., None]], axis=2)
    return out


def main() -> None:
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    src = os.path.join(root, "assets", "art", "characters", "doll_a", "doll_a_8dir.png")
    dst = os.path.join(root, "assets", "art", "characters", "doll_a", "doll_a_8dir_cel.png")

    atlas = np.asarray(Image.open(src).convert("RGBA"), dtype=np.float32) / 255.0
    out = atlas.copy()
    for row in range(ROWS):
        for col in range(COLS):
            y0, x0 = row * CELL_H, col * CELL_W
            cell = atlas[y0:y0 + CELL_H, x0:x0 + CELL_W]
            out[y0:y0 + CELL_H, x0:x0 + CELL_W] = process_cell(cell[..., :3], cell[..., 3])

    img = Image.fromarray((out * 255.0 + 0.5).astype(np.uint8), mode="RGBA")
    img.save(dst)
    print("saved", dst, img.size)


if __name__ == "__main__":
    main()
