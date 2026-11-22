#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""为 16 帧敌人图集生成 Godot 4 的 SpriteFrames(.tres) 资源。

输入：assets/art/enemies/<id>_anim_sheet.png / .json
输出：assets/art/enemies/<id>_anim_frames.tres

动画：alert / attack / move / death，各 4 帧（AtlasTexture），
直接拖到 AnimatedSprite2D 的 sprite_frames 上即可播放。
"""

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / "assets" / "art" / "enemies"

IDS = ["mobile_turret", "sentry_type1", "hunter_type1", "goliath"]


def build(enemy_id: str) -> int:
    meta = json.loads((ART / (enemy_id + "_anim_sheet.json")).read_text(encoding="utf-8"))
    cell_w, cell_h = meta["cell"]
    rows = meta["rows"]
    anims = meta["animations"]
    lines = []
    lines.append('[gd_resource type="SpriteFrames" load_steps=%d format=3]' % (rows * 4 + 2))
    lines.append("")
    lines.append('[ext_resource type="Texture2D" path="res://assets/art/enemies/%s_anim_sheet.png" id="1_sheet"]' % enemy_id)
    lines.append("")
    for state, info in anims.items():
        for frame in range(info["frames"]):
            lines.append('[sub_resource type="AtlasTexture" id="AtlasTexture_%s_%d"]' % (state, frame))
            lines.append('atlas = ExtResource("1_sheet")')
            lines.append("region = Rect2(%d, %d, %d, %d)" % (
                frame * cell_w, info["row"] * cell_h, cell_w, cell_h))
            lines.append("")
    lines.append("[resource]")
    lines.append("animations = [{")
    blocks = []
    for state, info in anims.items():
        frames = []
        for frame in range(info["frames"]):
            frames.append(
                '{\n"duration": 1.0,\n"texture": SubResource("AtlasTexture_%s_%d")\n}' % (state, frame))
        blocks.append(
            '"frames": [%s],\n"loop": %s,\n"name": &"%s",\n"speed": %.1f'
            % (", ".join(frames), "false" if state == "death" else "true",
               state, float(info["fps"])))
    lines.append("}, {\n".join(blocks))
    lines.append("}]")
    out = ART / (enemy_id + "_anim_frames.tres")
    out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("saved", out)
    return 0


def main() -> int:
    ids = sys.argv[1:] or IDS
    for enemy_id in ids:
        build(enemy_id)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
