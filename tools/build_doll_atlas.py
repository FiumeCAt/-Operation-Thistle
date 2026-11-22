"""把重绘的 8 方向立绘拼回游戏图集。

输入：每个方向一张透明底立绘（1024x1536 之类的大图），可选每个方向一条行走帧条。
输出：与原图集同布局的 1024x4416 图集，未重绘的动画行沿用底图。

对齐规则与游戏里 BillboardVisual 的假设一致：
  角色高 180px（15/16 格高），脚底基线在 y=186，水平居中于 x=64。
"""
import argparse
import os

from PIL import Image, ImageDraw

CELL_W, CELL_H = 128, 192
COLS = 8
BODY_PX = 180
BASELINE_Y = 186
ROWS = 23
IDLE_START, IDLE_COUNT = 0, 4
WALK_START, WALK_COUNT = 4, 8
MAGIC = (255, 0, 255)


def ensure_alpha(img: Image.Image) -> Image.Image:
    """生图偶尔不给透明底（还会画一层棋盘格）：从四角把浅色区域泛洪抠掉。

    只处理与画布边缘连通的浅色像素，所以白衬衫这类被轮廓包住的白色不会被误删。
    """
    img = img.convert("RGBA")
    if img.split()[3].getextrema()[0] == 0:
        return img
    rgb = img.convert("RGB")
    w, h = rgb.size
    px = rgb.load()
    light = [[min(px[x, y]) >= 210 for x in range(w)] for y in range(h)]
    seen = [[False] * w for _ in range(h)]
    stack = []
    for x in range(w):
        stack.append((x, 0))
        stack.append((x, h - 1))
    for y in range(h):
        stack.append((0, y))
        stack.append((w - 1, y))
    while stack:
        x, y = stack.pop()
        if x < 0 or y < 0 or x >= w or y >= h or seen[y][x] or not light[y][x]:
            continue
        seen[y][x] = True
        stack.append((x + 1, y))
        stack.append((x - 1, y))
        stack.append((x, y + 1))
        stack.append((x, y - 1))
    out = img.copy()
    dst = out.load()
    for y in range(h):
        for x in range(w):
            if seen[y][x]:
                dst[x, y] = (0, 0, 0, 0)
    return out


def fit_figure(img: Image.Image, height: int = BODY_PX, max_width: int = 120) -> Image.Image:
    """裁掉透明边，等比缩放到指定高度；过宽时以宽度为准。"""
    img = ensure_alpha(img)
    bbox = img.split()[3].point(lambda a: 255 if a > 8 else 0).getbbox()
    if bbox:
        img = img.crop(bbox)
    w, h = img.size
    scale = height / float(h)
    if w * scale > max_width:
        scale = max_width / float(w)
    return img.resize((max(1, round(w * scale)), max(1, round(h * scale))), Image.LANCZOS)


def place(cell: Image.Image, figure: Image.Image, dy: int = 0) -> None:
    x = (CELL_W - figure.width) // 2
    y = BASELINE_Y - figure.height + dy
    cell.alpha_composite(figure, (max(0, x), max(0, y)))


def build_idle(figure: Image.Image) -> list[Image.Image]:
    """静立 4 帧：只做 1–2px 的呼吸起伏，避免站桩完全静止。"""
    frames = []
    for dy in (0, -1, -2, -1):
        cell = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
        place(cell, figure, dy)
        frames.append(cell)
    return frames


def split_walk_strip(path: str, count: int = 4) -> list[Image.Image]:
    strip = ensure_alpha(Image.open(path))
    w, h = strip.size
    frames = []
    for i in range(count):
        part = strip.crop((round(w * i / count), 0, round(w * (i + 1) / count), h))
        frames.append(fit_figure(part, BODY_PX + 6, 124))
    return frames


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--idle", nargs=8, required=True, help="8 个方向的重绘立绘，顺序 FRONT/FRONT-R/RIGHT/BACK-R/BACK/BACK-L/LEFT/FRONT-L")
    ap.add_argument("--walk", nargs=8, default=None, help="可选：8 个方向的行走帧条（每条 4 帧）")
    ap.add_argument("--base", required=True, help="作为底图的旧图集，未重绘的动画行从它复制")
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    atlas = Image.open(args.base).convert("RGBA")
    if atlas.size != (CELL_W * COLS, CELL_H * ROWS):
        raise SystemExit(f"底图尺寸不对：{atlas.size}")

    for col, path in enumerate(args.idle):
        figure = fit_figure(Image.open(path))
        for i, frame in enumerate(build_idle(figure)):
            atlas.paste(frame, (col * CELL_W, (IDLE_START + i) * CELL_H))

    if args.walk:
        for col, path in enumerate(args.walk):
            frames = split_walk_strip(path)
            for i in range(WALK_COUNT):
                atlas.paste(frames[i % len(frames)], (col * CELL_W, (WALK_START + i) * CELL_H))

    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    atlas.save(args.out)
    print("saved", args.out, atlas.size)


if __name__ == "__main__":
    main()
