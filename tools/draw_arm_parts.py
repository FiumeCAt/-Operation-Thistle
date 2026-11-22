"""程序化重绘两段手臂和手，替换 AI 切图里的“香肠条”。

设计要点：
- 大臂/小臂是锥形袖子，颜色取自角色外套，上下有 1px 描边；
- 关节端不画竖封口，靠 1.5px 重叠自然接合，减少分段感；
- 小臂末端加袖口，手画成有拇指和指节的握拳，方向朝枪身。

输出到 assets/art/characters/doll_b/parts/arm2/。
运行：python tools/draw_arm_parts.py
"""
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/art/characters/doll_b/parts/arm2"

## 外套袖子的取样色（见 slice_arm_parts.py 的 atlas_palette）。
OUTLINE = (13, 19, 34, 255)
DEEP = (26, 28, 43, 255)
SHADOW = (42, 47, 71, 255)
BASE = (64, 71, 97, 255)
LIGHT = (76, 82, 101, 255)

## 手的灰白皮肤 ramp。
HAND_OUTLINE = (26, 28, 43, 255)
HAND_DARK = (76, 82, 101, 255)
HAND_MID = (120, 120, 114, 255)
HAND_LIGHT = (157, 156, 148, 255)


def tapered(width: int, height_start: int, height_end: int, height: int) -> Image.Image:
    """锥形袖段：上下描边跟着锥度走，左右两端保持开口。"""
    img = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    px = img.load()
    center = height // 2
    for x in range(width):
        t = x / float(max(width - 1, 1))
        h = int(round(height_start + (height_end - height_start) * t))
        y0 = center - (h - 1) // 2
        y1 = y0 + h - 1
        for y in range(y0, y1 + 1):
            if y == y0:
                px[x, y] = LIGHT
            elif y >= y1 - 1:
                px[x, y] = SHADOW
            else:
                px[x, y] = BASE
        if y0 - 1 >= 0:
            px[x, y0 - 1] = OUTLINE
        if y1 + 1 < height:
            px[x, y1 + 1] = OUTLINE
    return img


def upper_arm() -> Image.Image:
    """肩端粗、肘端收；比 IK 的 12px 多 1px，伸进肘关节遮住接缝。"""
    img = tapered(26, 13, 10, 15)
    px = img.load()
    # 肩端内侧压暗半格，让手臂从外套里“长出来”而不是贴在上面
    for y in range(5, 11):
        if px[0, y][3] > 0:
            px[0, y] = SHADOW
    return img


def forearm() -> Image.Image:
    """肘端与上臂同宽，腕端收窄；手前方留一圈袖口。"""
    img = tapered(27, 11, 8, 13)
    px = img.load()
    # 袖口放在手会盖住的位置之前，游戏里才看得见
    for x in range(15, 19):
        for y in range(13):
            if px[x, y][3] > 0:
                px[x, y] = DEEP if x < 18 else SHADOW
    return img


def hand() -> Image.Image:
    """握拳：左侧接袖口，右侧指节，下侧拇指。"""
    img = Image.new("RGBA", (14, 12), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    draw.rounded_rectangle((1, 2, 12, 10), radius=2, fill=HAND_MID, outline=HAND_OUTLINE)
    draw.rounded_rectangle((2, 8, 6, 11), radius=1, fill=HAND_MID, outline=HAND_OUTLINE)
    # 指节分隔
    for x in (9, 11):
        draw.line((x, 4, x, 8), fill=HAND_DARK)
    # 手背高光
    draw.line((3, 3, 6, 3), fill=HAND_LIGHT)
    draw.point((3, 4), fill=HAND_LIGHT)
    # 底部暗面
    draw.line((3, 9, 8, 9), fill=HAND_DARK)
    return img


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for name, image in (("upper_arm", upper_arm()), ("forearm", forearm()), ("hand", hand())):
        image.save(OUT / f"{name}.png")
        print(f"{name:10s} {image.width}x{image.height}")


if __name__ == "__main__":
    main()
