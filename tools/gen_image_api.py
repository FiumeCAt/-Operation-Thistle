#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Operation Thistle（蓟花行动）— 外部生图接口（中转站）调用器

通过 OpenAI 兼容的 Images API 调你自己的中转站模型，只依赖标准库。

配置优先级：命令行参数 > 环境变量 > 项目根目录 .env
  IMAGE_API_BASE    中转站地址，例如 https://api.example.com  （可带 /v1）
  IMAGE_API_KEY     API Key（Bearer）
  IMAGE_API_MODEL   模型名，默认 gpt-image-2.5-flare

常用命令：
  # 查看中转站可用模型（确认模型名）
  python tools/gen_image_api.py --list-models

  # 文生图
  python tools/gen_image_api.py --prompt "..." --out assets/art/concepts/doll_a.png --size 1024x1536

  # 带参考图（图生图 / 改图）
  python tools/gen_image_api.py --prompt "..." --out ... --ref ref1.png ref2.png

  # 只检查配置和请求，不发网络请求
  python tools/gen_image_api.py --prompt "..." --out ... --dry-run
"""

import argparse
import base64
import json
import mimetypes
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
IMAGE_EXTS = {".png", ".jpg", ".jpeg", ".webp"}


def load_env_file() -> dict:
    path = ROOT / ".env"
    data = {}
    if not path.exists():
        return data
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        k = k.strip()
        if k.startswith("export "):
            k = k[len("export "):].strip()
        data[k] = v.strip().strip("'\"")
    return data


def load_env_config() -> dict:
    """项目根 .env + 系统环境变量；系统环境变量优先级更高。"""
    env = load_env_file()
    for k in ("IMAGE_API_BASE", "IMAGE_API_KEY", "IMAGE_API_MODEL"):
        v = os.environ.get(k)
        if v:
            env[k] = v
    return env


def pick(cli_value, env, key, default=None):
    if cli_value:
        return cli_value
    if env.get(key):
        return env[key]
    return default


def redact(key: str) -> str:
    return "[REDACTED]" if key else "(未设置)"


def sanitize(value, key=None) -> str:
    text = value.decode("utf-8", "replace") if isinstance(value, bytes) else str(value)
    if key:
        for secret in sorted({key, urllib.parse.quote(key, safe=""), json.dumps(key)[1:-1]}, key=len, reverse=True):
            text = text.replace(secret, "[REDACTED]")
    text = re.sub(r"(?i)\bBearer\s+[^\r\n]+", "Bearer [REDACTED]", text)
    text = re.sub(r"(?i)\b(?:[a-z_]*token|api[_-]?key|authorization)\b[\"']?\s*[:=]\s*[^\r\n]+", "credential=[REDACTED]", text)
    return text


def report_error(status, body, key, label="请求失败"):
    print(f"{label} HTTP {status}")
    print(sanitize(body, key)[:2000])


def build_url(base: str, endpoint: str | None, kind: str) -> str:
    if endpoint:
        return endpoint
    b = base.rstrip("/")
    if b.endswith("/images/generations") or b.endswith("/images/edits"):
        root = b.rsplit("/images/", 1)[0]
        return f"{root}/images/{kind}"
    suffix = f"/images/{kind}"
    if b.endswith("/v1"):
        return b + suffix
    return b + "/v1" + suffix


def models_url(base: str) -> str:
    b = base.rstrip("/")
    if b.endswith("/images/generations") or b.endswith("/images/edits"):
        b = b.rsplit("/images/", 1)[0]
    if b.endswith("/v1"):
        return b + "/models"
    return b + "/v1/models"


def request_json(url: str, key: str, payload=None, timeout=60):
    headers = {"Authorization": f"Bearer {key}", "Accept": "application/json"}
    data = None
    method = "GET"
    if payload is not None:
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        headers["Content-Type"] = "application/json"
        method = "POST"
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.status, resp.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()
    except urllib.error.URLError as e:
        return 0, str(e.reason).encode("utf-8", "replace")


def build_multipart(fields: dict, files: list[tuple[str, Path]]):
    boundary = "----OperationThistle" + uuid.uuid4().hex
    body = bytearray()
    for name, value in fields.items():
        body += f"--{boundary}\r\n".encode()
        body += f'Content-Disposition: form-data; name="{name}"\r\n\r\n'.encode()
        body += f"{value}\r\n".encode()
    for name, path in files:
        ctype = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
        body += f"--{boundary}\r\n".encode()
        body += (
            f'Content-Disposition: form-data; name="{name}"; filename="{path.name}"\r\n'
        ).encode()
        body += f"Content-Type: {ctype}\r\n\r\n".encode()
        body += path.read_bytes() + b"\r\n"
    body += f"--{boundary}--\r\n".encode()
    return bytes(body), f"multipart/form-data; boundary={boundary}"


def post_multipart(url: str, key: str, body: bytes, ctype: str, timeout: float):
    headers = {"Authorization": f"Bearer {key}", "Content-Type": ctype, "Accept": "application/json"}
    req = urllib.request.Request(url, data=body, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.status, resp.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()
    except urllib.error.URLError as e:
        return 0, str(e.reason).encode("utf-8", "replace")


def save_image(name: Path, fmt: str | None, items: int, idx: int) -> Path:
    if name.suffix.lower() in IMAGE_EXTS:
        base = name.with_suffix("")
    else:
        base = name
    ext = ".png"
    if fmt == "jpeg":
        ext = ".jpg"
    elif fmt == "webp":
        ext = ".webp"
    suffix = f"_{idx + 1}" if items > 1 else ""
    path = Path(str(base) + suffix + ext)
    path.parent.mkdir(parents=True, exist_ok=True)
    return path


def main() -> int:
    ap = argparse.ArgumentParser(description="调用中转站的 OpenAI 兼容图片接口")
    ap.add_argument("--prompt", help="生图提示词")
    ap.add_argument("--out", help="输出文件路径（可含扩展名）")
    ap.add_argument("--size", default="1024x1024", help="尺寸，如 1024x1024 / 1536x1024")
    ap.add_argument("--n", type=int, default=1, help="生成张数")
    ap.add_argument("--model", help="模型名，默认取 IMAGE_API_MODEL")
    ap.add_argument("--quality", choices=["low", "medium", "high", "auto"], help="质量参数（可选）")
    ap.add_argument("--background", choices=["transparent", "opaque", "auto"], help="背景模式（transparent 输出透明底）")
    ap.add_argument("--format", choices=["png", "jpeg", "webp"], help="输出格式（可选，部分模型支持）")
    ap.add_argument("--response-format", choices=["b64_json", "url"], help="返回格式（可选）")
    ap.add_argument("--ref", nargs="*", default=[], help="参考图路径（走 /images/edits）")
    ap.add_argument("--base", help="中转站 base URL")
    ap.add_argument("--key", help="API Key（建议写在 .env 里，不要直接传）")
    ap.add_argument("--endpoint", help="完整接口 URL，覆盖自动拼接")
    ap.add_argument("--timeout", type=float, default=300, help="超时秒数")
    ap.add_argument("--list-models", action="store_true", help="GET /v1/models 列出可用模型名")
    ap.add_argument("--dry-run", action="store_true", help="只打印请求信息，不发请求")
    args = ap.parse_args()

    env = load_env_config()
    base = pick(args.base, env, "IMAGE_API_BASE")
    key = pick(args.key, env, "IMAGE_API_KEY")
    model = pick(args.model, env, "IMAGE_API_MODEL", "gpt-image-2.5-flare")

    if args.list_models:
        if not base:
            print("缺少 IMAGE_API_BASE：请写入项目根目录 .env 或用 --base 传入")
            return 2
        if not key and not args.dry_run:
            print("缺少 IMAGE_API_KEY：请写入项目根目录 .env 或用 --key 传入")
            return 2
        url = models_url(base)
        print(sanitize(f"GET {url}", key))
        if args.dry_run:
            return 0
        status, body = request_json(url, key, timeout=30)
        if status != 200:
            report_error(status, body, key)
            return 1
        try:
            data = json.loads(body)
            if data.get("error"):
                report_error(status, body, key, "接口返回错误")
                return 1
            ids = [m.get("id") for m in data.get("data", []) if m.get("id")]
            print(sanitize("\n".join(ids), key) if ids else sanitize(body, key)[:2000])
        except json.JSONDecodeError:
            report_error(status, body, key, "响应不是 JSON")
            return 1
        return 0

    if not args.prompt or (not args.out and not args.dry_run):
        ap.print_help()
        print("\n错误：需要 --prompt 和 --out")
        return 2
    if args.ref and len(args.ref) > 9:
        print("错误：--ref 最多 9 张参考图")
        return 2
    if not base and not args.endpoint:
        print("缺少 IMAGE_API_BASE：请在项目根目录 .env 写入：")
        print("  IMAGE_API_BASE=https://你的中转站地址")
        print("  IMAGE_API_KEY=sk-...")
        print(f"  IMAGE_API_MODEL={model}")
        return 2
    if not key and not args.dry_run:
        print("缺少 IMAGE_API_KEY：请写入项目根目录 .env 或用 --key 传入")
        return 2

    kind = "edits" if args.ref else "generations"
    url = build_url(base or "", args.endpoint, kind)

    payload = {"model": model, "prompt": args.prompt, "n": args.n, "size": args.size}
    if args.quality:
        payload["quality"] = args.quality
    if args.background:
        payload["background"] = args.background
    if args.format:
        payload["output_format"] = args.format
    if args.response_format:
        payload["response_format"] = args.response_format

    print(sanitize(f"POST {url}", key))
    print(sanitize(f"model={model} size={args.size} n={args.n}", key) + f" key={redact(key)}")
    print(sanitize(f"prompt={args.prompt}", key))

    if args.dry_run:
        if args.ref:
            print(sanitize("ref=" + ", ".join(args.ref), key))
            print("fields=" + sanitize(json.dumps({k: str(v) for k, v in payload.items()}, ensure_ascii=False), key)[:800])
        else:
            print("body=" + sanitize(json.dumps(payload, ensure_ascii=False), key)[:800])
        return 0

    if args.ref:
        files = []
        field_name = "image" if len(args.ref) == 1 else "image[]"
        for r in args.ref:
            p = Path(r)
            if not p.exists():
                print(f"参考图不存在：{r}")
                return 2
            files.append((field_name, p))
        body, ctype = build_multipart({k: str(v) for k, v in payload.items()}, files)
        status, raw = post_multipart(url, key, body, ctype, args.timeout)
    else:
        status, raw = request_json(url, key, payload, timeout=args.timeout)

    if status != 200:
        report_error(status, raw, key)
        return 1

    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        report_error(status, raw, key, "响应不是 JSON")
        return 1

    if "error" in data and data["error"]:
        report_error(status, raw, key, "接口返回错误")
        return 1

    items = data.get("data") or []
    if not items:
        report_error(status, raw, key, "响应里没有 data 字段")
        return 1

    out_name = Path(args.out)
    saved = []
    for i, item in enumerate(items):
        b64 = item.get("b64_json")
        item_url = item.get("url")
        if b64:
            payload = base64.b64decode(b64.split(",", 1)[-1])
            target = save_image(out_name, args.format, len(items), i)
            target.write_bytes(payload)
            saved.append(target)
        elif item_url:
            try:
                with urllib.request.urlopen(item_url, timeout=args.timeout) as resp:
                    payload = resp.read()
                    ctype = resp.headers.get("Content-Type", "")
            except urllib.error.HTTPError as e:
                report_error(e.code, e.read(), key, "下载图片失败")
                return 1
            except urllib.error.URLError as e:
                report_error(0, str(e.reason), key, "下载图片失败")
                return 1
            fmt = args.format
            if not fmt:
                if "jpeg" in ctype:
                    fmt = "jpeg"
                elif "webp" in ctype:
                    fmt = "webp"
            target = save_image(out_name, fmt, len(items), i)
            target.write_bytes(payload)
            saved.append(target)

    if not saved:
        report_error(status, raw, key, "响应里既没有 b64_json 也没有 url")
        return 1

    for p in saved:
        print(f"已保存：{p}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
