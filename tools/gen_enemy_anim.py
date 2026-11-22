#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""用 image2.5 生成敌人 16 帧像素动作图集所需的 4 条动作条带。

每台敌人 4 个状态，每个状态一条 4 帧横向条带（同一行、等距、同比例、正面）：
  move 移动 / alert 发现 / attack 攻击 / death 死亡

输出：tools/art_sources/enemies_anim/<id>/<state>.png（透明底）
后续由 build_enemy_anim.py 拼成 4 行 × 4 列图集。

用法：
  python tools/gen_enemy_anim.py --enemy mobile_turret
  python tools/gen_enemy_anim.py --enemy mobile_turret --state move --force
"""

import argparse
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "tools" / "art_sources" / "enemies_anim"
GEN = ROOT / "tools" / "gen_image_api.py"

STYLE = (
    "Crisp high-resolution pixel art, clean dark 1-pixel outlines, hard-edged pixel shading, "
    "limited desaturated palette with {accent}, no anti-aliasing, no gradients, no blur. "
    "Fully transparent background, no shadow, no ground, no text, no labels, no grid lines, "
    "no watermark, no frame borders."
)

STATES = ["move", "alert", "attack", "death"]

ENEMIES = {
    "mobile_turret": {
        "name": "移动哨卫炮",
        "desc": (
            "fictional sci-fi quadrupedal mobile sentry cannon robot: large rectangular armored "
            "sensor head with a glowing red visor, layered gray steel armor plates, four long splayed "
            "insect-like legs with two-toed claw feet, and a compact twin under-slung cannon"
        ),
        "accent": "red and orange accents",
        "move": "the four splayed legs alternate in a stable marching gait, joints flex, the body bobs slightly, the twin cannon stays aimed forward",
        "alert": "frame 1 normal march; frame 2 it stops abruptly and braces all four legs; frame 3 the red visor flares wide and the head snaps forward; frame 4 an aggressive alert stance with the visor blazing",
        "attack": "frame 1 it plants all four legs and charges the twin cannon with two orange glows; frame 2 both barrels fire two bright orange bullets with strong muzzle flashes; frame 3 the body recoils backward from the double shot; frame 4 it settles back with the visor still hot",
        "death": "frame 1 a hit sparks across the armor and the visor flickers; frame 2 the legs buckle and the body tilts sideways; frame 3 the body collapses onto the ground with sparks and broken plates; frame 4 a dark lifeless wreck with the red visor dead and a few fading sparks",
    },
    "sentry_type1": {
        "name": "哨兵一型",
        "desc": (
            "fictional sci-fi quadrupedal sentry robot: four articulated mechanical legs ending in "
            "black wheels, a heavy armored turret body with riveted plates and cables, and one huge "
            "glowing green circular lens eye on the front"
        ),
        "accent": "green accents",
        "move": "the four wheels roll forward as the legs flex alternately, the turret body sways slightly, the green lens stays locked forward",
        "alert": "frame 1 rolling forward; frame 2 the wheels lock and the legs brace wide; frame 3 the green lens flares into a bright ring; frame 4 a lowered aggressive charge-ready stance with the lens blazing",
        "attack": "frame 1 it crouches and the green lens charges with light rings; frame 2 it rockets forward in a ramming charge, body leaning low, wheels spun up; frame 3 the charge continues with a green motion trail and the lens blazing; frame 4 it brakes hard after the impact, body pitched forward",
        "death": "frame 1 a hit sparks across the turret and the green lens cracks; frame 2 the legs give out and the body lists to one side; frame 3 the turret crashes down, wheels spinning loose, green light dying; frame 4 a slumped dark wreck with a dead lens and scattered sparks",
    },
    "hunter_type1": {
        "name": "巡猎者一型",
        "desc": (
            "fictional sci-fi six-legged PMC spider drone: low flat circular armored body with a "
            "weathered gray hull, a red painted ring around the top hatch, PMC stencil marking, six "
            "beige fabric-wrapped armored legs with pointed tips, and a small sensor turret on top "
            "with a red eye"
        ),
        "accent": "beige, steel and red accents",
        "move": "the six armored legs scuttle in alternating tripod groups, the flat body sways side to side, the top sensor turret stays steady",
        "alert": "frame 1 scuttling; frame 2 it halts and plants all six legs; frame 3 the body lifts and the red hatch ring glows; frame 4 a wide aggressive stance with the red sensor eye locked forward",
        "attack": "frame 1 it crouches low and raises its two front legs; frame 2 the front legs stab forward with red energy on the tips; frame 3 a second lunging stab with the body stretched forward; frame 4 it pulls back into a low ready crouch",
        "death": "frame 1 a hit sparks across the hull and the red ring flickers; frame 2 the legs curl inward and the body drops; frame 3 the flat hull crashes to the ground with broken leg tips and sparks; frame 4 a dark dead wreck with the red ring extinguished",
    },
    "goliath": {
        "name": "哥利亚",
        "desc": (
            "fictional sci-fi spherical assault drone: matte black armored ball body with glowing "
            "orange neon seams, a worn metal round smiley face plate on the front, and three clawed "
            "mechanical arms"
        ),
        "accent": "black, gunmetal and bright orange neon",
        "move": "the drone hovers low while its claw arms paddle and swing, the sphere bobs and rolls forward slightly, orange seams pulsing",
        "alert": "frame 1 hovering; frame 2 the sphere snaps upright and the claws spread; frame 3 the orange neon seams blaze brightly; frame 4 a raised aggressive stance, claws wide, face plate glowing",
        "attack": "frame 1 the sphere rears back with claws raised, orange seams charging; frame 2 it slams down and sits on the ground, body compressing; frame 3 a massive orange self-destruct explosion bursts around its base; frame 4 the blast swells outward with the sphere engulfed in orange fire",
        "death": "frame 1 a hit cracks the black shell and orange light leaks out; frame 2 the sphere splits apart with a burst of orange energy; frame 3 the shell breaks into flying scrap plates; frame 4 a burnt-out wreck with scattered black debris and dying orange embers",
    },
}


def prompt_for(enemy: dict, state: str, has_ref: bool) -> str:
    desc = enemy["desc"]
    view = "front view facing the camera"
    if state == "move":
        body = (
            "A clean 4-frame movement animation sprite strip of %s, in high-definition pixel art. "
            "One horizontal row of 4 full-body frames, equal spacing, identical scale, each robot "
            "centered in its cell, %s, fixed camera, no perspective change between frames. "
            "Movement cycle: %s." % (desc, view, enemy["move"])
        )
    elif state == "alert":
        body = (
            "A clean 4-frame discovery and alert reaction sprite strip of %s, in high-definition pixel art. "
            "One horizontal row of 4 full-body frames, equal spacing, identical scale, each robot "
            "centered in its cell, %s, fixed camera, no perspective change between frames. "
            "Reaction: %s." % (desc, view, enemy["alert"])
        )
    elif state == "attack":
        body = (
            "A clean 4-frame attack animation sprite strip of %s, in high-definition pixel art. "
            "One horizontal row of 4 full-body frames, equal spacing, identical scale, each robot "
            "centered in its cell, %s, fixed camera, no perspective change between frames. "
            "Attack sequence: %s." % (desc, view, enemy["attack"])
        )
    else:
        body = (
            "A clean 4-frame death animation sprite strip of %s, in high-definition pixel art. "
            "One horizontal row of 4 full-body frames, equal spacing, identical scale, each robot "
            "centered in its cell, %s, fixed camera, no perspective change between frames. "
            "Death sequence: %s." % (desc, view, enemy["death"])
        )
    if has_ref:
        body += " Match the robot design, proportions and colors of the reference image exactly."
    return body + " " + STYLE.format(accent=enemy["accent"])


def gen_one(enemy_id: str, state: str, force: bool) -> bool:
    enemy = ENEMIES[enemy_id]
    out = SRC / enemy_id / (state + ".png")
    if out.exists() and not force:
        print("[skip] " + str(out.name))
        return True
    out.parent.mkdir(parents=True, exist_ok=True)
    ref = None
    if state != "move":
        move = SRC / enemy_id / "move.png"
        if move.exists():
            ref = move
    cmd = [sys.executable, str(GEN), "--size", "1536x1024",
           "--background", "transparent", "--out", str(out)]
    if ref is not None:
        cmd += ["--ref", str(ref)]
    cmd += ["--prompt", prompt_for(enemy, state, ref is not None)]
    for attempt in range(2):
        result = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace")
        if result.returncode == 0:
            print("[ok] %s/%s" % (enemy_id, state))
            return True
        tail = ((result.stdout or "") + (result.stderr or "")).strip().splitlines()[-2:]
        print("[retry %d] %s/%s -> %s" % (attempt + 1, enemy_id, state, " | ".join(tail)))
    return False


def main() -> int:
    ap = argparse.ArgumentParser(description="生成敌人 4×4 像素动作条带")
    ap.add_argument("--enemy", required=True, choices=sorted(ENEMIES))
    ap.add_argument("--state", choices=STATES, default=None)
    ap.add_argument("--force", action="store_true")
    args = ap.parse_args()

    states = [args.state] if args.state else STATES
    fails = 0
    for state in states:
        if not gen_one(args.enemy, state, args.force):
            fails += 1
    print("=== %s: %d ok / %d fail ===" % (args.enemy, len(states) - fails, fails))
    return 0 if fails == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
