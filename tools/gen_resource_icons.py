"""生成 32×32 像素风资源 / 信用点图标（手绘兜底版本）。

注意：当前美术资源已由 tools/gen_resource_icons_seedream.py（Seedream 5.5，128×128）
生成并覆盖；本脚本仅作为离线兜底，运行会覆盖同名图标。

用法：python tools/gen_resource_icons.py
输出到 assets/art/ui/icons/res_*.png，游戏内用 PixelUI.icon() 以最近邻绘制。
"""

from pathlib import Path

from PIL import Image, ImageDraw

SIZE = 32
OUT = Path(__file__).resolve().parents[1] / "assets" / "art" / "ui" / "icons"

OUTLINE = (10, 12, 16, 255)


def new_canvas() -> tuple[Image.Image, ImageDraw.ImageDraw]:
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)


def save(img: Image.Image, name: str) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    img.save(OUT / name)


def rect(d: ImageDraw.ImageDraw, box, color) -> None:
    d.rectangle(box, fill=color)


def credit() -> None:
    img, d = new_canvas()
    dark = (120, 62, 12, 255)
    base = (240, 158, 52, 255)
    light = (255, 214, 128, 255)
    # 六边形硬币
    d.polygon([(16, 2), (28, 8), (28, 24), (16, 30), (4, 24), (4, 8)], fill=OUTLINE)
    d.polygon([(16, 4), (26, 9), (26, 23), (16, 28), (6, 23), (6, 9)], fill=base)
    d.polygon([(16, 4), (26, 9), (16, 13), (6, 9)], fill=light)
    d.rectangle((10, 14, 21, 16), fill=dark)
    d.rectangle((10, 19, 21, 21), fill=dark)
    d.rectangle((14, 12, 17, 23), fill=dark)
    save(img, "res_credit.png")


def electronics() -> None:
    img, d = new_canvas()
    body = (30, 82, 96, 255)
    top = (86, 208, 224, 255)
    edge = (140, 240, 255, 255)
    pin = (196, 214, 220, 255)
    d.rectangle((7, 7, 24, 24), fill=OUTLINE)
    d.rectangle((8, 8, 23, 23), fill=body)
    d.rectangle((10, 10, 21, 21), fill=top)
    d.rectangle((12, 12, 19, 19), fill=body)
    d.rectangle((13, 13, 15, 15), fill=edge)
    for y in (11, 15, 19):
        d.rectangle((4, y, 7, y + 2), fill=pin)
        d.rectangle((24, y, 27, y + 2), fill=pin)
    save(img, "res_electronics.png")


def energy() -> None:
    img, d = new_canvas()
    body = (222, 168, 44, 255)
    light = (255, 226, 140, 255)
    d.rectangle((10, 4, 21, 27), fill=OUTLINE)
    d.rectangle((11, 5, 20, 26), fill=body)
    d.rectangle((12, 6, 15, 24), fill=light)
    d.rectangle((13, 2, 18, 4), fill=OUTLINE)
    d.rectangle((14, 3, 17, 4), fill=(210, 210, 214, 255))
    # 闪电
    d.polygon([(18, 9), (13, 17), (16, 17), (14, 23), (20, 14), (17, 14)], fill=OUTLINE)
    d.polygon([(17, 10), (14, 16), (17, 16), (15, 21), (19, 15), (16, 15)], fill=(255, 248, 200, 255))
    save(img, "res_energy.png")


def parts() -> None:
    img, d = new_canvas()
    body = (150, 162, 174, 255)
    light = (208, 216, 224, 255)
    dark = (96, 106, 118, 255)
    teeth = [
        (12, 1, 19, 9), (12, 23, 19, 31), (1, 12, 9, 19), (23, 12, 31, 19),
        (4, 4, 11, 11), (21, 4, 28, 11), (4, 21, 11, 28), (21, 21, 28, 28),
    ]
    d.ellipse((7, 7, 24, 24), fill=OUTLINE)
    d.ellipse((8, 8, 23, 23), fill=body)
    d.ellipse((10, 10, 21, 21), fill=light)
    d.ellipse((13, 13, 18, 18), fill=OUTLINE)
    d.rectangle((11, 11, 15, 13), fill=light)
    # 齿在圆环之后绘制，让齿根压住描边，齿轮轮廓连成一体
    for t in teeth:
        d.rectangle(t, fill=OUTLINE)
        d.rectangle((t[0] + 1, t[1] + 1, t[2] - 1, t[3] - 1), fill=body)
    # 齿根接缝用圆环本体盖回，避免出现黑色断缝
    d.ellipse((8, 8, 23, 23), fill=body)
    d.ellipse((10, 10, 21, 21), fill=light)
    d.ellipse((13, 13, 18, 18), fill=OUTLINE)
    save(img, "res_parts.png")


def weapon_parts() -> None:
    img, d = new_canvas()
    brass = (206, 120, 46, 255)
    brass_light = (244, 178, 96, 255)
    copper = (236, 108, 66, 255)
    # 弹壳
    d.rectangle((11, 13, 20, 29), fill=OUTLINE)
    d.rectangle((12, 14, 19, 28), fill=brass)
    d.rectangle((13, 15, 15, 27), fill=brass_light)
    d.rectangle((10, 27, 21, 30), fill=OUTLINE)
    d.rectangle((11, 28, 20, 29), fill=(150, 92, 40, 255))
    # 弹头
    d.polygon([(11, 13), (16, 2), (20, 13)], fill=OUTLINE)
    d.polygon([(12, 12), (16, 4), (19, 12)], fill=copper)
    d.rectangle((14, 6, 15, 11), fill=(255, 176, 138, 255))
    save(img, "res_weapon_parts.png")


def electronic_core() -> None:
    img, d = new_canvas()
    purple = (128, 92, 214, 255)
    glow = (196, 168, 255, 255)
    core = (246, 236, 255, 255)
    d.polygon([(16, 2), (28, 10), (28, 22), (16, 30), (4, 22), (4, 10)], fill=OUTLINE)
    d.polygon([(16, 4), (26, 11), (26, 21), (16, 28), (6, 21), (6, 11)], fill=purple)
    d.polygon([(16, 8), (22, 12), (22, 20), (16, 24), (10, 20), (10, 12)], fill=glow)
    d.polygon([(16, 12), (19, 14), (19, 18), (16, 20), (13, 18), (13, 14)], fill=core)
    d.rectangle((9, 8, 11, 10), fill=(255, 255, 255, 180))
    save(img, "res_electronic_core.png")


def high_energy_cell() -> None:
    img, d = new_canvas()
    body = (46, 168, 96, 255)
    light = (128, 240, 160, 255)
    d.rectangle((6, 8, 25, 27), fill=OUTLINE)
    d.rectangle((7, 9, 24, 26), fill=body)
    d.rectangle((9, 6, 12, 8), fill=OUTLINE)
    d.rectangle((19, 6, 22, 8), fill=OUTLINE)
    d.rectangle((9, 11, 12, 24), fill=light)
    d.rectangle((15, 11, 18, 24), fill=light)
    d.rectangle((21, 11, 22, 24), fill=(28, 110, 66, 255))
    d.rectangle((9, 14, 12, 18), fill=(226, 255, 236, 255))
    save(img, "res_high_energy_cell.png")


def military_alloy() -> None:
    img, d = new_canvas()
    body = (108, 124, 152, 255)
    light = (168, 184, 208, 255)
    dark = (70, 84, 108, 255)
    # 梯形合金锭：顶面亮、正面暗，带铆钉
    d.polygon([(9, 8), (23, 8), (26, 14), (6, 14)], fill=OUTLINE)
    d.polygon([(10, 9), (22, 9), (25, 13), (7, 13)], fill=light)
    d.polygon([(6, 14), (26, 14), (24, 26), (8, 26)], fill=OUTLINE)
    d.polygon([(7, 15), (25, 15), (23, 25), (9, 25)], fill=body)
    d.rectangle((11, 19, 12, 20), fill=dark)
    d.rectangle((15, 19, 16, 20), fill=dark)
    d.rectangle((19, 19, 20, 20), fill=dark)
    d.rectangle((12, 22, 19, 23), fill=dark)
    save(img, "res_military_alloy.png")


def main() -> None:
    credit()
    electronics()
    energy()
    parts()
    weapon_parts()
    electronic_core()
    high_energy_cell()
    military_alloy()
    print("icons written to", OUT)


if __name__ == "__main__":
    main()
