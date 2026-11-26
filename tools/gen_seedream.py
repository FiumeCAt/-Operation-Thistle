#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Seedream 5.5（火山方舟）文生图调用器。

配置来自项目根目录 .env：
  SEEDREAM_API_BASE   默认 https://ark.cn-beijing.volces.com/api/v3
  SEEDREAM_API_KEY    方舟 API Key
  SEEDREAM_API_MODEL  默认 doubao-seedream-5-5-261028

示例：
  python tools/gen_seedream.py --prompt "刺绣贴布..." --out out/sticker.png \
      --size 2K --transparent

  python tools/gen_seedream.py --prompt "..." --out out/opaque.png --size 2K
"""

import argparse
import base64
import json
import mimetypes
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_BASE = "https://ark.cn-beijing.volces.com/api/v3"
DEFAULT_MODEL = "doubao-seedream-5-5-261028"


def _endpoint_url(base: str) -> str:
    b = base.rstrip("/")
    if b.endswith("/images/generations"):
        return b
    return b + "/images/generations"


def _encode_image_data_uri(path: Path) -> str:
    mime, _ = mimetypes.guess_type(str(path))
    if not mime:
        mime = "image/png"
    b64 = base64.b64encode(path.read_bytes()).decode("ascii")
    return f"data:{mime};base64,{b64}"


def load_env() -> dict:
    data = {}
    path = ROOT / ".env"
    if not path.exists():
        return data
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        if key.startswith("export "):
            key = key[len("export "):].strip()
        data[key] = value.strip().strip("'\"")
    for key in ("SEEDREAM_API_BASE", "SEEDREAM_API_KEY", "SEEDREAM_API_MODEL"):
        if os.environ.get(key):
            data[key] = os.environ[key]
    return data


def main() -> int:
    parser = argparse.ArgumentParser(description="Seedream 5.5 image generation (text2img & ref img2img)")
    parser.add_argument("--prompt", required=True, help="生成提示词")
    parser.add_argument("--out", required=True, help="输出图片路径")
    parser.add_argument("--image", nargs="*", default=[], help="参考图路径（1 张或多张，自动转 base64 data URI 传入 Seedream 5.5）")
    parser.add_argument("--size", default="2K", help="2K / 1K / 4K 或宽x高")
    parser.add_argument("--format", default="png", choices=["png", "jpeg", "webp"])
    parser.add_argument("--transparent", action="store_true", help="透明背景")
    parser.add_argument("--no-watermark", action="store_true")
    parser.add_argument("--model", default=None)
    args = parser.parse_args()

    env = load_env()
    key = env.get("SEEDREAM_API_KEY", "")
    if not key:
        print("缺少 SEEDREAM_API_KEY（写入项目 .env 或设置环境变量）", file=sys.stderr)
        return 1
    base = env.get("SEEDREAM_API_BASE", DEFAULT_BASE).rstrip("/")
    model = args.model or env.get("SEEDREAM_API_MODEL", DEFAULT_MODEL)

    payload = {
        "model": model,
        "prompt": args.prompt,
        "size": args.size,
        "response_format": "url",
        "output_format": args.format,
        "background": "transparent" if args.transparent else "opaque",
        "stream": False,
        "watermark": not args.no_watermark,
    }
    if args.image:
        ref_uris = [_encode_image_data_uri(Path(p)) for p in args.image]
        payload["image"] = ref_uris[0] if len(ref_uris) == 1 else ref_uris
    request = urllib.request.Request(
        _endpoint_url(base),
        data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {key}"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=300) as response:
            result = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        print(f"HTTP {exc.code}", file=sys.stderr)
        print(exc.read().decode("utf-8", "replace"), file=sys.stderr)
        return 1
    except urllib.error.URLError as exc:
        print(f"请求失败：{exc.reason}", file=sys.stderr)
        return 1

    items = result.get("data") or []
    if not items or not items[0].get("url"):
        print("响应中没有图片 URL：", json.dumps(result, ensure_ascii=False)[:800], file=sys.stderr)
        return 1

    item = items[0]
    out_path = Path(args.out)
    if not out_path.is_absolute():
        out_path = ROOT / out_path
    out_path.parent.mkdir(parents=True, exist_ok=True)
    urllib.request.urlretrieve(item["url"], out_path)
    print(f"model={model} size={item.get('size')} background={item.get('background')}")
    print(f"已保存：{out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
