"""生成 2.5D 线稿风墙面/地面贴图（可平铺，无写实照片纹理）。"""
from PIL import Image, ImageDraw, ImageFilter
import random

random.seed(21)


def noise(img, amount=4):
    px = img.load()
    w, h = img.size
    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y][:3]
            n = random.randint(-amount, amount)
            px[x, y] = (max(0, min(255, r + n)), max(0, min(255, g + n)), max(0, min(255, b + n))
                        , 255) if img.mode == "RGBA" else (max(0, min(255, r + n)), max(0, min(255, g + n)), max(0, min(255, b + n)))


def make_wall(path):
    w, h = 1024, 512
    img = Image.new("RGB", (w, h), (63, 71, 80))
    d = ImageDraw.Draw(img)
    # 上下两段明度分区
    d.rectangle([0, 340, w, h], fill=(52, 59, 67))
    d.line([(0, 340), (w, 340)], fill=(28, 33, 39), width=3)
    d.line([(0, 343), (w, 343)], fill=(96, 106, 116), width=1)
    # 竖向面板接缝
    for x in (0, 256, 512, 768):
        d.line([(x, 0), (x, h)], fill=(24, 29, 34), width=3)
        d.line([(x + 3, 0), (x + 3, h)], fill=(104, 114, 124), width=1)
    # 顶部压条
    d.rectangle([0, 0, w, 26], fill=(80, 89, 98))
    d.line([(0, 26), (w, 26)], fill=(30, 35, 41), width=2)
    # 竖向加强筋
    for x in (128, 384, 640, 896):
        d.rectangle([x - 5, 30, x + 5, 338], fill=(72, 81, 90))
        d.line([(x - 6, 30), (x - 6, 338)], fill=(106, 116, 126), width=1)
        d.line([(x + 6, 30), (x + 6, 338)], fill=(36, 42, 48), width=1)
    # 铆钉
    for x in range(32, w, 64):
        for y in (48, 190, 300, 420, 480):
            d.ellipse([x - 3, y - 3, x + 3, y + 3], fill=(70, 79, 88))
            d.ellipse([x - 2, y - 2, x + 2, y + 2], fill=(118, 129, 140))
    # 轻微锈迹与污渍（低对比）
    for _ in range(18):
        x = random.randint(0, w - 4)
        y = random.randint(40, h - 20)
        ln = random.randint(8, 40)
        d.line([(x, y), (x, min(h, y + ln))], fill=(96, 80, 62), width=1)
    for _ in range(10):
        x = random.randint(0, w - 40)
        y = random.randint(60, h - 40)
        d.ellipse([x, y, x + random.randint(10, 34), y + random.randint(6, 18)], fill=(48, 54, 60))
    noise(img, 3)
    img.save(path)
    print("saved", path, img.size)


def make_floor(path):
    w, h = 1024, 1024
    img = Image.new("RGB", (w, h), (66, 73, 81))
    d = ImageDraw.Draw(img)
    # 2x2 混凝土板，逐块轻微色差
    tones = [(70, 77, 85), (63, 70, 78), (67, 74, 82), (60, 67, 75)]
    for i in range(2):
        for j in range(2):
            d.rectangle([i * 512, j * 512, (i + 1) * 512, (j + 1) * 512], fill=tones[i * 2 + j])
    # 板缝
    for x in (0, 512):
        d.line([(x, 0), (x, h)], fill=(28, 33, 38), width=4)
        d.line([(x + 4, 0), (x + 4, h)], fill=(96, 104, 112), width=1)
    for y in (0, 512):
        d.line([(0, y), (w, y)], fill=(28, 33, 38), width=4)
        d.line([(0, y + 4), (w, y + 4)], fill=(96, 104, 112), width=1)
    # 细裂纹
    for _ in range(7):
        x = random.randint(20, w - 20)
        y = random.randint(20, h - 20)
        pts = [(x, y)]
        for _step in range(random.randint(3, 7)):
            x += random.randint(-24, 24)
            y += random.randint(-24, 24)
            pts.append((x, y))
        d.line(pts, fill=(44, 50, 56), width=1)
    # 油污
    for _ in range(5):
        x = random.randint(30, w - 90)
        y = random.randint(30, h - 70)
        rx = random.randint(20, 50)
        ry = random.randint(10, 26)
        d.ellipse([x, y, x + rx, y + ry], fill=(50, 56, 62))
    noise(img, 4)
    img = img.filter(ImageFilter.SMOOTH)
    img.save(path)
    print("saved", path, img.size)


if __name__ == "__main__":
    make_wall(r"assets/art/env/lineart_wall_2_5.png")
    make_floor(r"assets/art/env/lineart_floor_2_5.png")
