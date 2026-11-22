"""把整身图集拆成「无头身体」+「独立头部」两张同尺寸图集。

头部裁剪按帧自适应：
  - 有脸的帧用脸部肤色定位头部，向四周扩一点留出头发和耳朵；
  - 背面没有脸，用头顶前十几行的横向重心估算头部位置，并避开右侧枪箱。
这样头部图层只含头本身，旋转时不会把背后的枪箱一起带走，
身体也不会残留第二个头。运行：python tools/cut_head_layer.py
"""
from PIL import Image

SRC = "assets/art/characters/doll_b/lod/doll_lod_256.png"
OUT_BODY = "assets/art/characters/doll_b/lod/doll_lod_256_body.png"
OUT_HEAD = "assets/art/characters/doll_b/lod/doll_lod_256_head.png"
FRAME = 320
ROWS = 16
COLS = 4
# 跑步的正面 / 背面素材只有一条腿在动（另一条永远踩地），
# 把中间两帧的腿部镜像一下，得到左右交替的落地节奏。
RUN_MIRROR_ROWS = (8, 9)   # run_0（下）、run_1（上）
RUN_MIRROR_COLS = (1, 3)
MIRROR_Y = 218             # 裙摆以下开始镜像
SKIRT_TOP = 190            # 镜像后再把原裙子这块盖回去，接缝被裙子挡住

## 侧向瞄准（aim 左 / 右）固定裁剪框：手臂抬到下巴高度，背后枪箱紧贴头发，
## 只保留头部本身，避免摆头时把枪箱上半截和半截胸腔一起带走。
SIDE_AIM_BOX = {
    14: (132, 186),   # aim 左：枪箱在右侧
    15: (126, 160),   # aim 右：枪箱在左侧
}


def face_bbox(frame):
    """脸部肤色（中性偏暖、中高亮度）的包围盒；找不到返回 None。

    y 上限卡在 92：侧向瞄准帧里抬起的手在同高度，放宽会把手指也算成脸。
    """
    px = frame.load()
    xs, ys = [], []
    for y in range(40, 92):
        for x in range(112, 202):
            p = px[x, y]
            if p[3] < 200:
                continue
            r, g, b = p[0], p[1], p[2]
            lum = (r + g + b) / 3.0
            if lum > 118 and abs(r - g) < 16 and abs(g - b) < 20 and b <= r + 8:
                xs.append(x)
                ys.append(y)
    if len(xs) < 25:
        return None
    return min(xs), min(ys), max(xs), max(ys)


def widest_run(alpha, top):
    """头顶下方那几行里最宽的一段（背面视角用它估头发左右边界，避开右侧枪箱）。"""
    best = None
    for y in range(top + 15, min(top + 25, FRAME)):
        start = None
        for x in range(FRAME + 1):
            solid = x < FRAME and alpha.getpixel((x, y)) > 8
            if solid and start is None:
                start = x
            elif not solid and start is not None:
                if best is None or (x - start) > (best[1] - best[0]):
                    best = (start, x - 1)
                start = None
    return best


def head_box(frame, alpha, row):
    """该帧头部的裁剪框（左, 上, 右, 下）。

    - 侧向瞄准：固定框，只切到下颌；
    - 其它有脸的帧：按脸部左右各留一点；
    - 背面：用头顶下方最宽的一段当头发边界，右侧枪箱不算进去。
    """
    top = alpha.getbbox()[1]
    if row in SIDE_AIM_BOX:
        x0, x1 = SIDE_AIM_BOX[row]
        return max(0, x0), max(0, top), min(FRAME, x1), min(FRAME, top + 54)
    fb = face_bbox(frame)
    if fb is not None:
        x0, x1 = fb[0] - 18, fb[2] + 6
    else:
        run = widest_run(alpha, top)
        if run is None:
            cx = 152
        else:
            cx = (run[0] + run[1]) // 2
        x0, x1 = cx - 26, cx + 20
    return max(0, x0), max(0, top), min(FRAME, x1), min(FRAME, top + 78)


def frame_head_mask(frame, row):
    """返回该帧的头部蒙版（L 通道，255 = 属于头）。"""
    alpha = frame.split()[3]
    mask = Image.new("L", alpha.size, 0)
    box = head_box(frame, alpha, row)
    mask.paste(alpha.crop(box), box)
    return mask


def fix_run_legs(sheet):
    """跑步正 / 背面的中间两帧：把裙摆以下的腿部左右镜像，形成左右脚交替落地。"""
    out = sheet.copy()
    for row in RUN_MIRROR_ROWS:
        for col in RUN_MIRROR_COLS:
            box = (col * FRAME, row * FRAME, (col + 1) * FRAME, (row + 1) * FRAME)
            frame = out.crop(box)
            original = frame.copy()
            legs = frame.crop((0, MIRROR_Y, FRAME, FRAME)).transpose(Image.FLIP_LEFT_RIGHT)
            frame.paste(legs, (0, MIRROR_Y))
            skirt = original.crop((0, SKIRT_TOP, FRAME, MIRROR_Y))
            frame.paste(skirt, (0, SKIRT_TOP), skirt)
            out.paste(frame, box)
    return out


def main():
    sheet = fix_run_legs(Image.open(SRC).convert("RGBA"))
    body = sheet.copy()
    head = Image.new("RGBA", sheet.size, (0, 0, 0, 0))
    cleared = 0
    for row in range(ROWS):
        for col in range(COLS):
            box = (col * FRAME, row * FRAME, (col + 1) * FRAME, (row + 1) * FRAME)
            frame = sheet.crop(box)
            alpha = frame.split()[3]
            mask = frame_head_mask(frame, row)
            head_frame = Image.new("RGBA", frame.size, (0, 0, 0, 0))
            head_frame.paste(frame, (0, 0), mask)
            head.paste(head_frame, box)
            cleared_frame = frame.copy()
            cleared_frame.putalpha(Image.composite(
                Image.new("L", frame.size, 0), alpha, mask))
            body.paste(cleared_frame, box)
            cleared += 1
    body.save(OUT_BODY)
    head.save(OUT_HEAD)
    print("frames:", cleared)
    print(OUT_BODY)
    print(OUT_HEAD)


if __name__ == "__main__":
    main()
