#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""批量生成「持枪行走/奔跑」四向单帧素材。

做法：以已有的 aim_{dir}_raw.png（双手举枪、无枪）为参考图，用 image2.5
逐帧编辑，只改腿部姿态，上半身/手臂/比例保持不变。

输出：assets/art/characters/doll_b/armed/{action}_{dir}_{i}_raw.png
运行：python tools/gen_armed_frames.py --action walk --workers 2
      python tools/gen_armed_frames.py --action run --workers 2
"""

import argparse
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CHAR = ROOT / "assets/art/characters/doll_b"
OUT = CHAR / "armed"
CLI = ROOT / "tools/gen_image_api.py"

DIRS = ("front", "back", "left", "right")
DIR_DESC = {
    "front": "front view, facing the camera",
    "back": "back view, seen from behind",
    "left": "side view, the character faces the left edge of the image",
    "right": "side view, the character faces the right edge of the image",
}

# 行走四帧：0 前脚落地 / 1 后腿低摆 / 2 换脚落地 / 3 另一腿低摆
# 关键：接触帧双脚都贴地，摆动帧只抬起几厘米，否则会变成高抬腿踏步。
WALK_LEGS = {
    "front": [
        "her RIGHT foot has just stepped forward and BOTH feet are FLAT ON THE GROUND, the right foot slightly ahead, weight on the right leg",
        "the LEFT foot lifts ONLY SLIGHTLY (a few centimeters) while swinging forward past the standing right leg; the right foot stays flat on the ground",
        "her LEFT foot has just stepped forward and BOTH feet are FLAT ON THE GROUND, the left foot slightly ahead, weight on the left leg",
        "the RIGHT foot lifts ONLY SLIGHTLY (a few centimeters) while swinging forward past the standing left leg; the left foot stays flat on the ground",
    ],
    "back": [
        "her RIGHT foot has just stepped forward and BOTH feet are FLAT ON THE GROUND, the right foot slightly ahead, weight on the right leg",
        "the LEFT foot lifts ONLY SLIGHTLY (a few centimeters) while swinging forward past the standing right leg; the right foot stays flat on the ground",
        "her LEFT foot has just stepped forward and BOTH feet are FLAT ON THE GROUND, the left foot slightly ahead, weight on the left leg",
        "the RIGHT foot lifts ONLY SLIGHTLY (a few centimeters) while swinging forward past the standing left leg; the left foot stays flat on the ground",
    ],
    "left": [
        "the FRONT foot (on the left side of the image) is planted ahead on the ground, the rear foot is FLAT ON THE GROUND too, both feet touching the floor",
        "the REAR foot lifts ONLY SLIGHTLY (a few centimeters) and swings forward past the standing front leg; the front foot stays flat on the ground",
        "the REAR foot has just landed ahead of the front foot, BOTH feet FLAT ON THE GROUND, weight shifting forward",
        "the FRONT foot lifts ONLY SLIGHTLY (a few centimeters) and swings forward past the standing leg; the other foot stays flat on the ground",
    ],
    "right": [
        "the FRONT foot (on the right side of the image) is planted ahead on the ground, the rear foot is FLAT ON THE GROUND too, both feet touching the floor",
        "the REAR foot lifts ONLY SLIGHTLY (a few centimeters) and swings forward past the standing front leg; the front foot stays flat on the ground",
        "the REAR foot has just landed ahead of the front foot, BOTH feet FLAT ON THE GROUND, weight shifting forward",
        "the FRONT foot lifts ONLY SLIGHTLY (a few centimeters) and swings forward past the standing leg; the other foot stays flat on the ground",
    ],
}

# 奔跑四帧：0 前脚蹬地 / 1 腾空收腿 / 2 换脚蹬地 / 3 腾空收腿
RUN_LEGS = {
    "front": [
        "her RIGHT leg is extended forward and planted on the ground, the LEFT leg kicked back behind her, a long horizontal running stride, hips level",
        "BOTH feet are just slightly off the ground, knees bent, legs gathered under the body, hips level, no jump",
        "her LEFT leg is extended forward and planted on the ground, the RIGHT leg kicked back behind her, a long horizontal running stride, hips level",
        "BOTH feet are just slightly off the ground, knees bent, legs gathered under the body, hips level, no jump",
    ],
    "back": [
        "her RIGHT leg is extended forward and planted on the ground, the LEFT leg kicked back behind her, a long horizontal running stride, hips level",
        "BOTH feet are just slightly off the ground, knees bent, legs gathered under the body, hips level, no jump",
        "her LEFT leg is extended forward and planted on the ground, the RIGHT leg kicked back behind her, a long horizontal running stride, hips level",
        "BOTH feet are just slightly off the ground, knees bent, legs gathered under the body, hips level, no jump",
    ],
    "left": [
        "the FRONT leg reaches far forward and is planted on the ground, the rear leg stretched back behind her, a long horizontal running stride, hips level",
        "BOTH feet are just slightly off the ground, knees bent, legs gathered under the body, hips level, no jump",
        "the FRONT leg is planted under the body, the rear leg swings forward and reaches ahead, long stride, hips level",
        "BOTH feet are just slightly off the ground, knees bent, legs gathered under the body, hips level, no jump",
    ],
    "right": [
        "the FRONT leg reaches far forward and is planted on the ground, the rear leg stretched back behind her, a long horizontal running stride, hips level",
        "BOTH feet are just slightly off the ground, knees bent, legs gathered under the body, hips level, no jump",
        "the FRONT leg is planted under the body, the rear leg swings forward and reaches ahead, long stride, hips level",
        "BOTH feet are just slightly off the ground, knees bent, legs gathered under the body, hips level, no jump",
    ],
}


def build_prompt(action: str, direction: str, index: int) -> str:
    legs = (WALK_LEGS if action == "walk" else RUN_LEGS)[direction][index]
    if action == "walk":
        style = (
            "This is one frame of a calm walking cycle. The step is LOW and natural: the knee is never lifted high, "
            "the lifted foot stays only a few centimeters above the floor, the hips and head stay at exactly the same height as the input image."
        )
    else:
        style = (
            "This is one frame of a running cycle. The stride is long and horizontal, but the head and hips stay at exactly the same height as the input image, no jumping up."
        )
    return (
        "Edit this exact image. Keep the same anime girl character, same face, same hair, same dark navy long coat "
        "and plaid skirt outfit, same body proportions, same camera angle (" + DIR_DESC[direction] + "), "
        "same flat plain background, same scale and framing. "
        "Keep BOTH arms exactly in the same two-handed gun-holding pose in front of the chest (hands together, no gun drawn). "
        "Do NOT change the upper body, arms, head, or the coat above the waist. "
        "Only change the LOWER BODY / legs pose: " + legs + ". "
        "Keep the coat hem and skirt length unchanged, let them sway naturally with the legs. "
        + style +
        " Output the full body, centered, same size as the input."
    )


def run_task(action: str, direction: str, index: int, attempts: int = 4) -> tuple:
    out = OUT / f"{action}_{direction}_{index}_raw.png"
    if out.exists():
        return (out.name, True, "skip")
    prompt = build_prompt(action, direction, index)
    ref = CHAR / f"aim_{direction}_raw.png"
    cmd = [
        sys.executable, str(CLI),
        "--prompt", prompt,
        "--out", str(out),
        "--size", "1024x1024",
        "--ref", str(ref),
        "--timeout", "280",
    ]
    for attempt in range(1, attempts + 1):
        proc = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace")
        if proc.returncode == 0 and out.exists():
            return (out.name, True, f"ok attempt {attempt}")
        tail = (proc.stdout or "")[-240:].replace("\n", " ")
        print(f"[fail] {out.name} attempt {attempt}: {tail}", flush=True)
        if attempt < attempts:
            time.sleep(90)
    return (out.name, False, "gave up")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--action", choices=["walk", "run"], required=True)
    ap.add_argument("--workers", type=int, default=2)
    args = ap.parse_args()

    OUT.mkdir(parents=True, exist_ok=True)
    tasks = [(args.action, d, i) for d in DIRS for i in range(4)]
    ok = 0
    failed = []
    with ThreadPoolExecutor(max_workers=max(1, args.workers)) as pool:
        for name, success, note in pool.map(lambda t: run_task(*t), tasks):
            print(f"[{'done' if success else 'FAIL'}] {name}  {note}", flush=True)
            if success:
                ok += 1
            else:
                failed.append(name)
    print(f"完成 {ok}/{len(tasks)}  失败: {failed or '无'}")
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
