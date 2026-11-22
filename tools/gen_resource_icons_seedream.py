#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""用 Seedream 5.5 生成一套高清像素风资源 / 信用点图标。

流程：调用方舟 images/generations（透明背景）→ 按 alpha 裁切 → 方形留白 →
缩到 128×128 → 覆盖 assets/art/ui/icons/res_*.png。

用法：python tools/gen_resource_icons_seedream.py
原始大图保存在 tools/_seed_icons/raw/，方便重新裁切。
"""

import json
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gen_seedream import DEFAULT_BASE, DEFAULT_MODEL, load_env  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / "tools" / "_seed_icons" / "raw"
OUT = ROOT / "assets" / "art" / "ui" / "icons"
TALENT_OUT = ROOT / "assets" / "art" / "ui" / "talents"
SIZE = 128

STYLE = (
    "单个游戏道具图标，高清像素画风，32 位像素艺术放大，硬边像素块，"
    "正面略俯视，物品居中占画面 80%，无文字、无边框、无阴影投射，"
    "透明背景，单件物品，轮廓清晰，高对比，配色克制"
)

ITEMS = {
    "res_credit": "金色六边形信用点代币，中央浮雕信用符号，金属高光",
    "res_electronics": "青色电子元件芯片，方形集成电路，两侧金属引脚",
    "res_energy": "琥珀色能量单元电池，单节圆柱电池，表面印有闪电标志",
    "res_parts": "银灰色机械零件，金属齿轮，中心轴孔",
    "res_weapon_parts": "橙铜色枪械改装零件：一枚竖立的黄铜步枪子弹、旁边一段短枪管与弹簧，零件紧凑堆叠",
    "res_electronic_core": "紫色发光电子核心，六边形晶体核心，内部亮光",
    "res_high_energy_cell": "绿色高能电池组，两节电池并排，带电量指示条",
    "res_military_alloy": "蓝灰色军用合金锭，梯形金属块，表面铆钉",
}

## 天赋图标：输出到 assets/art/ui/talents/，与资源图标共用生成流程。
TALENTS = {
    "armor_up": "银灰色重型护甲板，圆角胸甲片，金属包边与铆钉",
    "magazine_up": "深灰色步枪弹匣，扩容弹匣造型，侧面观察孔与弹簧",
    "ammo_reserve": "战术弹药箱，打开盖子露出整齐排列的子弹，金属箱体",
    "magnet": "U 形磁铁，红蓝双色磁极，周围有吸附光效",
}


def request_icon(prompt: str, out_path: Path, key: str, base: str, model: str) -> bool:
    payload = {
        "model": model,
        "prompt": prompt,
        "size": "1K",
        "response_format": "url",
        "output_format": "png",
        "background": "transparent",
        "stream": False,
        "watermark": False,
    }
    request = urllib.request.Request(
        base.rstrip("/") + "/images/generations",
        data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {key}"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=300) as response:
            result = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        print("HTTP", exc.code, exc.read().decode("utf-8", "replace")[:400], file=sys.stderr)
        return False
    except urllib.error.URLError as exc:
        print("请求失败：", exc.reason, file=sys.stderr)
        return False
    items = result.get("data") or []
    if not items or not items[0].get("url"):
        print("无图片 URL：", json.dumps(result, ensure_ascii=False)[:400], file=sys.stderr)
        return False
    out_path.parent.mkdir(parents=True, exist_ok=True)
    urllib.request.urlretrieve(items[0]["url"], out_path)
    return True


def process(raw_path: Path, out_path: Path) -> None:
    img = Image.open(raw_path).convert("RGBA")
    alpha = img.getchannel("A")
    bbox = alpha.getbbox()
    if bbox is None:
        bbox = (0, 0, img.width, img.height)
    img = img.crop(bbox)
    # 方形画布 + 6% 留白，保证各图标视觉大小一致
    side = max(img.width, img.height)
    pad = int(side * 0.06)
    canvas = Image.new("RGBA", (side + pad * 2, side + pad * 2), (0, 0, 0, 0))
    canvas.paste(img, ((canvas.width - img.width) // 2, (canvas.height - img.height) // 2), img)
    canvas = canvas.resize((SIZE, SIZE), Image.LANCZOS)
    # 轻微收敛调色板，减少渐变噪点，保持像素画质感
    rgb = canvas.convert("RGB").quantize(colors=48, method=Image.MEDIANCUT).convert("RGB")
    out = Image.new("RGBA", (SIZE, SIZE))
    out.paste(rgb, (0, 0))
    out.putalpha(canvas.getchannel("A"))
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out.save(out_path)


def main() -> int:
    env = load_env()
    key = env.get("SEEDREAM_API_KEY", "")
    if not key:
        print("缺少 SEEDREAM_API_KEY", file=sys.stderr)
        return 1
    base = env.get("SEEDREAM_API_BASE", DEFAULT_BASE)
    model = env.get("SEEDREAM_API_MODEL", DEFAULT_MODEL)

    only = sys.argv[1:] or (list(ITEMS.keys()) + list(TALENTS.keys()))
    for name in only:
        is_talent = name in TALENTS
        desc = TALENTS.get(name) if is_talent else ITEMS.get(name)
        if desc is None:
            print("未知图标：", name, file=sys.stderr)
            continue
        prompt = f"{desc}。{STYLE}"
        raw = RAW / f"{name}.png"
        ok = request_icon(prompt, raw, key, base, model)
        if not ok:
            print("失败：", name, file=sys.stderr)
            continue
        out_dir = TALENT_OUT if is_talent else OUT
        process(raw, out_dir / f"{name}.png")
        print("完成：", name)
        time.sleep(0.5)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
