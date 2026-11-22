#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""按参考图生成敌人四向 / 三状态动作条带（品红底，供 build_enemy_sheets.py 切图）。

每台敌人生成 3 个源视角 × 3 个状态：
  down 正面 / left 左侧（右向由构建器镜像） / up 背面
  walk 4 帧 / attack 3 帧 / alert 1 帧

视角策略：
  - down 始终用原始参考图作设计锚点；
  - left / up 若也用正面参考，模型会照抄正面机位，因此改用逐视角文字描述；
  - left / up 的 attack / alert 再拿同视角 walk 条带做设计锚点，保证三套动作同一台机。

用法：
  python tools/gen_enemy_sheets.py --enemy quad_warden            # 补齐缺失条带
  python tools/gen_enemy_sheets.py --enemy quad_warden --force     # 全部重生成
  python tools/gen_enemy_sheets.py --enemy quad_warden --only walk
  python tools/gen_enemy_sheets.py --enemy quad_warden --view left --force
"""

import argparse
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "tools" / "art_sources" / "enemies_sprites"
GEN = ROOT / "tools" / "gen_image_api.py"

STYLE = (
    "Clean semi-realistic hard-surface sci-fi game asset in the style of a tactical shooter enemy, "
    "crisp dark line art, hard-edged two-tone cel shading, cool key light from the upper-left with a "
    "thin cyan-white rim light, slightly desaturated steel palette. "
    "Flat solid pure magenta #FF00FF chroma-key background, no shadow, no ground, no smoke, "
    "no text, no labels, no grid lines, no watermark, no frame borders."
)

VIEWS = {
    "down": "front view facing the camera",
    "left": "strict left side profile, robot pointing to the left edge of the image",
    "up": "back view facing away from the camera",
}

ENEMIES = {
    "quad_warden": {
        "desc": (
            "fictional sci-fi quadrupedal military walker robot with a boxy sensor head, "
            "layered gray steel armor plates, four long splayed insect-like legs ending in claw feet, "
            "and a compact under-slung weapon module"
        ),
        "side": (
            "a heavy fictional sci-fi quadrupedal military walker robot in strict left side profile, "
            "a machine and NOT an animal: a large wide rectangular box sensor head on a short thick neck, "
            "slanted armored brow, dark horizontal sensor slot on its side, layered gray steel slab torso "
            "with an underslung gun barrel, four long mechanical legs each with a big round shoulder joint, "
            "long upper strut, prominent knee joint and long lower strut ending in a heavy two-toed claw foot, "
            "legs splayed wide, tall heavy silhouette, the four legs overlapping in a front-to-back row"
        ),
        "back": (
            "the same heavy quadrupedal military walker robot seen from behind: the rear of the rectangular "
            "box head with vent slats and a short antenna, rear armor plates of the torso, four long splayed "
            "mechanical legs with claw feet seen from the back, the under-slung gun barrel mostly hidden"
        ),
        "walk": "the four splayed legs alternate in a stable marching gait, the boxy head stays level, the armored torso bobs only slightly",
        "attack": [
            "the walker plants all four legs, lowers its body and aims its under-slung weapon module forward, a small orange charge glow at the muzzle",
            "the weapon fires with a bright orange muzzle flash and the body recoils backward slightly",
            "the walker settles back onto its legs as the flash fades, returning to a ready stance",
        ],
        "alert": "body raised tall on all four legs, sensor head snapped forward, a red-orange scanning light lit in the head visor",
    },
    "wheel_sentinel": {
        "desc": (
            "fictional sci-fi quadrupedal sentry robot with four articulated legs ending in black wheels, "
            "a heavy armored turret body with cables, and a large glowing green circular lens eye"
        ),
        "side": (
            "a fictional sci-fi quadrupedal sentry robot in strict left side profile: a heavy armored turret "
            "body with riveted plates and thick cables, a huge glowing green circular lens on the front of the "
            "turret pointing left, four articulated mechanical legs ending in black wheels arranged front-to-back"
        ),
        "back": (
            "the same quadrupedal sentry robot seen from behind: the back of the heavy armored turret, cable "
            "bundles, exhaust vents, four articulated legs with black wheels splayed behind it, no green lens visible"
        ),
        "walk": "the four wheels roll forward as the legs flex alternately, the turret body sways slightly, the green lens stays locked forward",
        "attack": [
            "the turret braces low, the green lens eye flares and charges with concentric light rings",
            "a bright green energy blast erupts from the lens with a strong flash, the body kicks back on its legs",
            "the green glow dims and the sentry settles back into its stance",
        ],
        "alert": "legs braced wide, turret spun forward, green lens flaring brightly",
    },
    "pmc_spider": {
        "desc": (
            "fictional sci-fi six-legged PMC spider drone with a flat circular armored body marked PMC, "
            "a red painted ring around the top hatch, beige fabric-wrapped armored legs, "
            "and a small sensor turret on top"
        ),
        "side": (
            "a fictional sci-fi six-legged PMC spider drone in strict left side profile: a low flat circular "
            "armored body marked PMC with a red painted ring around its top hatch, a small sensor turret on top, "
            "six beige fabric-wrapped armored legs splayed front-to-back with pointed tips"
        ),
        "back": (
            "the same six-legged PMC spider drone seen from behind: the rear of the flat circular armored body, "
            "the red hatch ring on top, the small sensor turret, six beige fabric-wrapped armored legs splayed "
            "toward the viewer"
        ),
        "walk": "the six armored legs scuttle in alternating tripod groups, the flat body sways side to side, the top sensor turret stays steady",
        "attack": [
            "the spider crouches low, front legs raised and spread wide, red ring lights flaring",
            "the spider lunges forward and stabs with its two front pointed legs, a short compact red flash at the leg tips, body stretched forward, no long beam or streak",
            "the spider pulls its legs back and settles into a low ready crouch",
        ],
        "alert": "legs planted wide and body lifted, top sensor turret snapped toward the camera, red ring glowing",
    },
    "orb_ball": {
        "desc": (
            "fictional sci-fi spherical assault drone, matte black armored ball body with glowing orange "
            "neon seams, a worn metal smiley face plate, and three clawed mechanical arms"
        ),
        "side": (
            "a fictional sci-fi spherical assault drone in strict left side profile: a matte black armored "
            "sphere with glowing orange neon seams and a worn metal smiley face plate on its front, seen "
            "edge-on from the side, three clawed mechanical arms, hovering low"
        ),
        "back": (
            "the same spherical assault drone seen from behind: the back of the matte black armored sphere "
            "with glowing orange neon seams and three spread clawed mechanical arms, no face plate visible"
        ),
        "walk": "the drone hovers low while its claw arms paddle and swing, the sphere bobs and rolls forward slightly, orange seams pulsing",
        "attack": [
            "the sphere rears back, claw arms pulled up and back, orange seams glowing intensely",
            "the sphere lunges forward and slams both front claws down, an orange impact flash",
            "the claws retract and the sphere rocks back into a hover",
        ],
        "alert": "the sphere rises and tilts toward the camera, claw arms spread wide, orange neon seams blazing",
    },
}


def subject_for(enemy: dict, view: str) -> str:
    if view == "down":
        return "the exact same %s as the reference image" % enemy["desc"]
    return enemy["side" if view == "left" else "back"]


def prompt_for(enemy: dict, view: str, state: str, has_ref: bool) -> str:
    subject = subject_for(enemy, view)
    view_note = "" if view == "down" else " Keep the framing fixed and identical across frames; do not switch to a front view."
    if state == "walk":
        body = (
            "A clean 4-frame walk cycle sprite strip of %s. One horizontal row of 4 full-body frames, "
            "equal spacing, identical scale, each robot centered in its cell, fixed camera, "
            "no perspective change between frames.%s Walk cycle: %s."
            % (subject, view_note, enemy["walk"])
        )
    elif state == "attack":
        frames = enemy["attack"]
        body = (
            "A clean 3-frame attack animation sprite strip of %s. One horizontal row of 3 full-body frames, "
            "equal spacing, identical scale, each robot centered in its cell, fixed camera, "
            "no perspective change between frames.%s Frame 1: %s. Frame 2: %s. Frame 3: %s."
            % (subject, view_note, frames[0], frames[1], frames[2])
        )
    else:
        body = (
            "A single full-body illustration of %s, in an aggressive alert stance: %s. "
            "Complete robot fully visible and centered." % (subject, enemy["alert"])
        )
    if has_ref:
        body += " Match the robot design, colors and scale of the reference image exactly."
    return body + " " + STYLE


def ref_for(enemy_id: str, view: str, state: str) -> Path | None:
    if view == "down":
        return SRC / "refs" / (enemy_id + ".png")
    if state == "walk":
        return None
    # 侧/背视角：用同视角行走条带做设计锚点，避免三套动作变成三台机。
    walk = SRC / enemy_id / ("%s_walk_raw.png" % view)
    return walk if walk.exists() else None


def gen_one(enemy_id: str, view: str, state: str, force: bool) -> bool:
    enemy = ENEMIES[enemy_id]
    out = SRC / enemy_id / ("%s_%s_raw.png" % (view, state))
    if out.exists() and not force:
        print("[skip] " + out.name)
        return True
    out.parent.mkdir(parents=True, exist_ok=True)
    ref = ref_for(enemy_id, view, state)
    if ref is not None and not ref.exists():
        print("缺少参考图：" + str(ref), file=sys.stderr)
        return False
    size = "1024x1024" if state == "alert" else "1536x1024"
    cmd = [sys.executable, str(GEN), "--size", size, "--out", str(out)]
    if ref is not None:
        cmd += ["--ref", str(ref)]
    cmd += ["--prompt", prompt_for(enemy, view, state, ref is not None)]
    result = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace")
    tail = (result.stdout or "").strip().splitlines()[-1:] + (result.stderr or "").strip().splitlines()[-2:]
    print("[%s] %s/%s -> %s" % ("ok" if result.returncode == 0 else "fail", view, state, " | ".join(tail)))
    return result.returncode == 0


def main() -> int:
    ap = argparse.ArgumentParser(description="生成敌人四向动作条带")
    ap.add_argument("--enemy", required=True, choices=sorted(ENEMIES))
    ap.add_argument("--only", choices=["walk", "attack", "alert"], default=None)
    ap.add_argument("--view", choices=sorted(VIEWS), default=None)
    ap.add_argument("--force", action="store_true")
    args = ap.parse_args()

    states = [args.only] if args.only else ["walk", "attack", "alert"]
    views = [args.view] if args.view else ["down", "left", "up"]
    fails = 0
    for view in views:
        for state in states:
            if not gen_one(args.enemy, view, state, args.force):
                fails += 1
    print("=== %s: %d ok / %d fail ===" % (args.enemy, len(views) * len(states) - fails, fails))
    return 0 if fails == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
