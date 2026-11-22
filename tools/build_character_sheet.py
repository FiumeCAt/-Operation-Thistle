"""把 image2.5 生成的六帧行走条带拼成游戏用八方向图集。

流程：品红背景抠像 + 去溢色 -> 全图共享缩放 -> 脚底基线对齐 -> 输出 6 列 × 8 行。
输出单元格 128×184，行序对应引擎方向索引：
0=右 1=右下 2=下 3=左下 4=左 5=左上 6=上 7=右上
运行：python tools/build_character_sheet.py
"""

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SRC_DIR = ROOT / "assets" / "art" / "characters" / "doll_a"
OUT_PATH = SRC_DIR / "doll_a_8dir_walk_2_5.png"
PREVIEW_PATH = Path("C:/Users/81349/AppData/Local/Temp/doll_walk_sheet_preview.png")

SOURCE_ROWS = ["e", "se", "s", "sw", "w", "nw", "n", "ne"]
# image2.5 的右下与左下条带会镜像输出，按实际朝向重新指回文件。
SOURCE_FILES = {
	"e": "walk_e_chroma_2_5_1.jpg",
	"se": "walk_sw_chroma_2_5.jpg",
	"s": "walk_s_chroma_2_5.jpg",
	"sw": "walk_se_chroma_2_5.jpg",
	"w": "walk_w_chroma_2_5.jpg",
	"nw": "walk_nw_chroma_2_5.jpg",
	"n": "walk_n_chroma_2_5_1.jpg",
	"ne": "walk_ne_chroma_2_5.jpg",
}
COLS = 6
CELL_W = 128
CELL_H = 184
TARGET_H = 150
FEET_BAND = 0.22


def key_magenta(path: Path) -> Image.Image:
    """按品红偏差抠像，并对边缘做去溢色，避免粉色描边。"""
    src = Image.open(path).convert("RGB")
    px = src.load()
    out = Image.new("RGBA", src.size)
    op = out.load()

    for y in range(src.height):
        for x in range(src.width):
            r, g, b = px[x, y]
            score = min(r, b) - g
            if score >= 60:
                alpha = 0
            elif score <= 15:
                alpha = 255
            else:
                alpha = int(255 * (60 - score) / 45)
            if alpha and score > 12:
                r = min(r, g + 24)
                b = min(b, g + 24)
            op[x, y] = (r, g, b, alpha)

    return out


def split_figures(image: Image.Image, label: str = "") -> list[Image.Image]:
    """按空白列切出六帧，避免固定等分把相邻帧裁断。"""
    alpha = image.getchannel("A")
    width = image.width
    filled = []
    for x in range(width):
        filled.append(alpha.crop((x, 0, x + 1, image.height)).getbbox() is not None)

    segments = []
    start = None
    for x, has_pixel in enumerate(filled):
        if has_pixel and start is None:
            start = x
        elif not has_pixel and start is not None:
            segments.append((start, x))
            start = None
    if start is not None:
        segments.append((start, width))

    if len(segments) != COLS:
        print(f"警告：{label} 检测到 {len(segments)} 段，回退等分切帧")
        step = width // COLS
        return [image.crop((index * step, 0, (index + 1) * step, image.height)) for index in range(COLS)]

    return [image.crop((left, 0, right, image.height)) for left, right in segments]


def feet_anchor(image: Image.Image, box: tuple[int, int, int, int]) -> float:
    """返回 bbox 内的脚底锚点横坐标（相对 bbox 左上角）。"""
    left, top, right, bottom = box
    band_top = max(top, bottom - int((bottom - top) * FEET_BAND))
    alpha = image.getchannel("A").crop((left, band_top, right, bottom))
    width, height = alpha.size
    data = alpha.load()

    total = 0
    weight_x = 0
    for y in range(height):
        for x in range(width):
            value = data[x, y]
            if value:
                total += value
                weight_x += value * x
    return weight_x / total if total else width / 2


def main() -> None:
    frames = {}
    heights = []
    for row in SOURCE_ROWS:
        path = SRC_DIR / SOURCE_FILES[row]
        if not path.exists():
            raise SystemExit(f"缺少素材：{path}")
        image = key_magenta(path)
        cells = []
        for column, cell in enumerate(split_figures(image, row)):
            box = cell.getbbox()
            if box is None:
                raise SystemExit(f"{path.name} 第 {column} 帧为空")
            cells.append((cell, box, feet_anchor(cell, box)))
            heights.append(box[3] - box[1])
        frames[row] = cells

    scale = TARGET_H / max(heights)
    sheet = Image.new("RGBA", (CELL_W * COLS, CELL_H * len(SOURCE_ROWS)))

    for row_index, row in enumerate(SOURCE_ROWS):
        for column, (cell, box, anchor_x) in enumerate(frames[row]):
            figure = cell.crop(box)
            target = (max(1, round(figure.width * scale)), max(1, round(figure.height * scale)))
            figure = figure.resize(target, Image.LANCZOS)
            paste_x = round(CELL_W / 2 - anchor_x * scale)
            paste_y = CELL_H - 2 - target[1]
            sheet.alpha_composite(figure, (column * CELL_W + paste_x, row_index * CELL_H + paste_y))

    sheet.save(OUT_PATH)

    preview = Image.new("RGBA", sheet.size, (18, 24, 28, 255))
    preview.alpha_composite(sheet)
    preview.save(PREVIEW_PATH)
    print(f"sheet {sheet.size} -> {OUT_PATH}")
    print(f"scale {scale:.3f}  frames {COLS * len(SOURCE_ROWS)}")


if __name__ == "__main__":
    main()
