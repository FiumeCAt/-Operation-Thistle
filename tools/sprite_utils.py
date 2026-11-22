#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""角色素材通用处理：白底抠图、去除白色描边残留、预乘 alpha 缩放。

白边成因：image2.5 出图时角色边缘是抗锯齿的，像素颜色被白色背景混入，
直接 LANCZOS 缩放会把白色晕开成一圈白边。这里按顺序处理：
  1. 从画布边缘泛洪去掉纯白背景
  2. 迭代删除紧贴透明区域的浅色像素（白边本身）
  3. 用不透明邻居的颜色填补半透明像素（去白污染）
  4. 用预乘 alpha 重新采样，避免缩放再产生新的白边
"""

from collections import deque

import numpy as np
from PIL import Image


def cut_white_bg(img: Image.Image, threshold: int = 180) -> Image.Image:
    """从画布边缘泛洪抠白底。

    阈值取 180 而不是接近 255，是因为中转站返回的 PNG 是放大过的，
    角色轮廓与白色背景之间有一圈被插值出来的浅灰过渡（白边根源），
    只按纯白抠图会把这圈浅灰留在角色上。
    """
    img = img.convert("RGBA")
    w, h = img.size
    px = img.load()

    def is_bg(x: int, y: int) -> bool:
        r, g, b, a = px[x, y]
        return a > 0 and r >= threshold and g >= threshold and b >= threshold

    seen = bytearray(w * h)
    queue = deque()
    for x in range(w):
        queue.append((x, 0))
        queue.append((x, h - 1))
    for y in range(h):
        queue.append((0, y))
        queue.append((w - 1, y))

    while queue:
        x, y = queue.popleft()
        if not (0 <= x < w and 0 <= y < h):
            continue
        index = y * w + x
        if seen[index]:
            continue
        seen[index] = 1
        if not is_bg(x, y):
            continue
        px[x, y] = (0, 0, 0, 0)
        queue.append((x + 1, y))
        queue.append((x - 1, y))
        queue.append((x, y + 1))
        queue.append((x, y - 1))
    return img


def strip_white_fringe(img: Image.Image, iterations: int = 2, level: int = 224) -> Image.Image:
    """反复删掉紧贴透明区域、且接近白色的像素。"""
    for _ in range(iterations):
        arr = np.array(img)
        rgb = arr[..., :3].astype(np.int16)
        alpha = arr[..., 3]
        bright = (rgb[..., 0] >= level) & (rgb[..., 1] >= level) & (rgb[..., 2] >= level) & (alpha > 0)
        transparent = alpha == 0
        padded = np.pad(transparent, 1, mode="constant", constant_values=False)
        near = padded[:-2, 1:-1] | padded[2:, 1:-1] | padded[1:-1, :-2] | padded[1:-1, 2:]
        kill = bright & near
        if not kill.any():
            break
        arr[kill] = 0
        img = Image.fromarray(arr, "RGBA")
    return img


def decontaminate(img: Image.Image, passes: int = 3) -> Image.Image:
    """把半透明像素的颜色替换为周围不透明像素的均值，去掉白色污染。"""
    for _ in range(passes):
        arr = np.array(img).astype(np.float32)
        alpha = arr[..., 3]
        semi = (alpha > 0) & (alpha < 255)
        if not semi.any():
            break
        opaque = alpha >= 255
        acc = np.zeros_like(arr[..., :3])
        count = np.zeros(arr.shape[:2], dtype=np.float32)
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                if dx == 0 and dy == 0:
                    continue
                shifted_col = np.roll(np.roll(arr[..., :3], dy, axis=0), dx, axis=1)
                shifted_op = np.roll(np.roll(opaque, dy, axis=0), dx, axis=1)
                acc += shifted_col * shifted_op[..., None]
                count += shifted_op
        has = semi & (count > 0)
        if not has.any():
            break
        arr[has, :3] = acc[has] / count[has][:, None]
        img = Image.fromarray(arr.clip(0, 255).astype(np.uint8), "RGBA")
    return img


def erode_alpha(img: Image.Image, pixels: int = 1) -> Image.Image:
    """沿轮廓向内收缩 1 像素。

    源图轮廓最外一圈是「白背景与深色描边」的插值像素（约 88,92,101），
    留着它缩放到小尺寸就会变成一圈浅色白边，所以直接把最外圈削掉。
    """
    for _ in range(pixels):
        arr = np.array(img)
        alpha = arr[..., 3]
        transparent = alpha == 0
        padded = np.pad(transparent, 1, mode="constant", constant_values=False)
        near = padded[:-2, 1:-1] | padded[2:, 1:-1] | padded[1:-1, :-2] | padded[1:-1, 2:]
        arr[near] = 0
        img = Image.fromarray(arr, "RGBA")
    return img


def cut_chroma_bg(img: Image.Image, key=(255, 0, 255), low: float = 70.0, high: float = 170.0) -> Image.Image:
    """抠洋红幕布背景，并抑制洋红溢色。

    白底出图的角色轮廓总会被白色背景插值成一圈浅灰（缩放到游戏尺寸后就是白边），
    改用纯洋红背景后边缘只会沾到洋红，抠图时一并去掉即可，不会留下亮边。
    """
    arr = np.array(img.convert("RGBA")).astype(np.float32)
    rgb = arr[..., :3]
    distance = np.linalg.norm(rgb - np.array(key, dtype=np.float32), axis=2)
    alpha = np.clip((distance - low) / (high - low), 0.0, 1.0)

    red, green, blue = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    spill = (red > green) & (blue > green)
    limit = green + 18.0
    arr[..., 0] = np.where(spill, np.minimum(red, limit), red)
    arr[..., 2] = np.where(spill, np.minimum(blue, limit), blue)
    arr[..., 3] = alpha * 255.0
    return Image.fromarray(arr.clip(0, 255).astype(np.uint8), "RGBA")


def clean_auto(img: Image.Image) -> Image.Image:
    """按背景颜色自动选择抠图方式（洋红幕布优先）。"""
    corner = img.convert("RGB").getpixel((0, 0))
    if corner[0] > 200 and corner[1] < 90 and corner[2] > 200:
        return decontaminate(cut_chroma_bg(img))
    return clean(img)


def clean(img: Image.Image) -> Image.Image:
    return decontaminate(erode_alpha(strip_white_fringe(cut_white_bg(img)), 1))


def resize_premultiplied(img: Image.Image, size: tuple) -> Image.Image:
    """预乘 alpha 缩放，杜绝缩放阶段的白边。"""
    return img.convert("RGBa").resize(size, Image.LANCZOS).convert("RGBA")


def cut_transparent(img: Image.Image, threshold: int = 96) -> Image.Image:
    arr = np.array(img)
    arr[arr[..., 3] < threshold] = 0
    return Image.fromarray(arr, "RGBA")
