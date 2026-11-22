"""生成 2D 武器表现用到的小素材。

- hand_grip.png：从角色手臂零件里裁出的握枪手（和角色同一套像素风）
- flash_strip.png：3 帧枪口焰（小→中→大），朝 +X 方向
- mag_pistol.png / mag_shell.png：换弹动画里的弹匣与霰弹壳

运行：python tools/make_weapon_fx.py
"""
from PIL import Image, ImageDraw
import os

ARM = "assets/art/characters/doll_b/parts/normal/arm.png"
OUT_DIR = "assets/art/weapons/fx"
HAND_OUT = os.path.join(OUT_DIR, "hand_grip.png")
FLASH_OUT = os.path.join(OUT_DIR, "flash_strip.png")
MAG_PISTOL_OUT = os.path.join(OUT_DIR, "mag_pistol.png")
MAG_SHELL_OUT = os.path.join(OUT_DIR, "mag_shell.png")

FLASH_SIZE = 48
FLASH_FRAMES = 3


def make_hand():
    im = Image.open(ARM).convert("RGBA")
    w, h = im.size
    px = im.load()
    xs, ys = [], []
    # 手是手臂最下端的肤色块：中高亮度、低饱和
    for y in range(int(h * 0.70), h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a < 200:
                continue
            lum = (r + g + b) / 3.0
            if lum > 120 and abs(r - g) < 18 and abs(g - b) < 22:
                xs.append(x)
                ys.append(y)
    if not xs:
        raise SystemExit("没找到手部像素")
    box = (max(0, min(xs) - 3), max(0, min(ys) - 3), min(w, max(xs) + 4), min(h, max(ys) + 4))
    hand = im.crop(box)
    os.makedirs(OUT_DIR, exist_ok=True)
    hand.save(HAND_OUT)
    print("hand:", hand.size, HAND_OUT)


def make_flash():
    frames = []
    for i in range(FLASH_FRAMES):
        f = Image.new("RGBA", (FLASH_SIZE, FLASH_SIZE), (0, 0, 0, 0))
        d = ImageDraw.Draw(f)
        cx, cy = 7.0, FLASH_SIZE * 0.5
        r = 5 + i * 4
        # 前向锥形火焰 + 中心亮核
        d.polygon([(cx - 2, cy - r * 0.62), (cx + r * 2.3, cy), (cx - 2, cy + r * 0.62)],
                  fill=(255, 168, 56, 235))
        d.polygon([(cx - 1, cy - r * 0.30), (cx + r * 1.55, cy), (cx - 1, cy + r * 0.30)],
                  fill=(255, 238, 186, 255))
        d.ellipse([cx - r * 0.72, cy - r * 0.72, cx + r * 0.72, cy + r * 0.72],
                  fill=(255, 248, 214, 255))
        frames.append(f)
    strip = Image.new("RGBA", (FLASH_SIZE * FLASH_FRAMES, FLASH_SIZE), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        strip.paste(f, (i * FLASH_SIZE, 0))
    os.makedirs(OUT_DIR, exist_ok=True)
    strip.save(FLASH_OUT)
    print("flash:", strip.size, FLASH_OUT)


def make_magazines():
    """换弹动画用的小贴图：深灰弹匣与红色霰弹壳，色调对齐枪身贴图。"""
    mag = Image.new("RGBA", (10, 26), (0, 0, 0, 0))
    d = ImageDraw.Draw(mag)
    d.rectangle([1, 3, 8, 22], fill=(40, 42, 46, 255))
    d.rectangle([1, 3, 8, 5], fill=(178, 138, 64, 255))
    d.line([2, 7, 2, 21], fill=(64, 68, 74, 255))
    d.line([7, 7, 7, 21], fill=(24, 25, 28, 255))
    d.rectangle([0, 21, 9, 24], fill=(26, 27, 30, 255))
    os.makedirs(OUT_DIR, exist_ok=True)
    mag.save(MAG_PISTOL_OUT)
    print("magazine:", mag.size, MAG_PISTOL_OUT)

    shell = Image.new("RGBA", (7, 18), (0, 0, 0, 0))
    d = ImageDraw.Draw(shell)
    d.rectangle([1, 0, 5, 13], fill=(150, 44, 38, 255))
    d.line([2, 1, 2, 12], fill=(198, 76, 64, 255))
    d.rectangle([0, 13, 6, 16], fill=(180, 142, 66, 255))
    d.line([0, 16, 6, 16], fill=(120, 92, 44, 255))
    shell.save(MAG_SHELL_OUT)
    print("shell:", shell.size, MAG_SHELL_OUT)


if __name__ == "__main__":
    make_hand()
    make_flash()
    make_magazines()
