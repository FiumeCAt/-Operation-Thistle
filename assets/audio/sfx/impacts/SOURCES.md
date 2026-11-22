# 子弹命中音效素材（备用）

来源均为 [OpenGameArt.org](https://opengameart.org)，授权统一为 **CC0 1.0（公共领域）**：
可商用、可修改、无需署名。本目录只存放整理后的素材，尚未接入 `Sfx.gd` 的运行时音效表，
需要时用 `load("res://assets/audio/sfx/impacts/...")` 读取即可。

## 分类与文件

### concrete/ — 混凝土 / 石墙
| 文件 | 时长 | 原始文件 | 来源包 / 作者 |
|---|---|---|---|
| concrete_hit_01.ogg | 0.11s | bfh1_rock_hit_01.ogg | [75 CC0 breaking / falling / hit sfx](https://opengameart.org/content/75-cc0-breaking-falling-hit-sfx) / rubberduck |
| concrete_hit_02.ogg | 0.73s | bfh1_hit_01.ogg | 同上 |
| concrete_hit_03.ogg | 0.80s | bfh1_hit_02.ogg | 同上 |
| concrete_shatter_01.ogg | 1.15s | bfh1_rock_breaking_01.ogg | 同上 |

### metal/ — 金属装甲 / 硬表面
| 文件 | 时长 | 原始文件 | 来源包 / 作者 |
|---|---|---|---|
| metal_hit_01.ogg | 0.24s | bfh1_metal_hit_01.ogg | 75 CC0 breaking / falling / hit sfx / rubberduck |
| metal_hit_02.ogg | 0.55s | bfh1_metal_hit_02.ogg | 同上 |
| metal_hit_03.ogg | 0.46s | bfh1_metal_hit_03.ogg | 同上 |
| metal_ping_01.wav | 0.72s | bing1.wav | [Metal Impact Sounds](https://opengameart.org/content/metal-impact-sounds) / BMacZero |
| metal_clink_01.wav | 0.31s | clink1.wav | 同上 |
| metal_thud_01.wav | 0.58s | thud2.wav | 同上 |

### ricochet/ — 跳弹 / 金属回响
| 文件 | 时长 | 原始文件 | 来源包 / 作者 |
|---|---|---|---|
| ricochet_01.ogg | 2.83s | ding.1.ogg | [4 Metal Dings/Rings](https://opengameart.org/content/4-metal-dingsrings) / StarNinjas |
| ricochet_02.ogg | 2.17s | ding.2.ogg | 同上 |
| ricochet_03.ogg | 2.04s | ding.3.ogg | 同上 |
| metal_ring_long.wav | 2.11s | bong1.wav | Metal Impact Sounds / BMacZero |

### flesh/ — 血肉命中
| 文件 | 时长 | 原始文件 | 来源包 / 作者 |
|---|---|---|---|
| flesh_hit_01.mp3 | 0.45s | squish_01.mp3 | [Squish Sounds Effects](https://opengameart.org/content/squish-sounds-effects) / EZduzziteh |
| flesh_hit_02.mp3 | 0.46s | squish_02.mp3 | 同上 |
| flesh_hit_03.mp3 | 0.46s | squish_03.mp3 | 同上 |
| flesh_hit_04.mp3 | 0.54s | squish_04.mp3 | 同上 |
| flesh_rip_01.mp3 | 29.39s | rippingintomeat.mp3 | [Ripping Into Meat](https://opengameart.org/content/ripping-into-meat) / Eldritch Grim（整段撕裂，适合处决/过场，不建议当单发命中） |

### generic/ — 通用子弹弹着
| 文件 | 时长 | 原始文件 | 来源包 / 作者 |
|---|---|---|---|
| bullet_impact_01.wav | 1.87s | Impact 1.wav | [Impacts/Gun/sfx](https://opengameart.org/content/impactsgunsfx) / Eldritch Grim |
| bullet_impact_02.wav | 1.92s | Impact 2.wav | 同上 |
| bullet_impact_03.wav | 1.88s | Impact 3.wav | 同上 |
| bullet_impact_heavy_01.wav | 2.14s | Impact Gun 1.wav | 同上 |
| bullet_impact_heavy_02.wav | 1.85s | Impact Gun 2.wav | 同上 |
| impact_rash_01.wav | 2.02s | Impact Rash 1.wav | 同上 |
| impact_rash_02.wav | 1.88s | Impact Rash 2.wav | 同上 |

## 接入状态与回退方式

已经接入 `scripts/audio/Sfx.gd`（`IMPACT_SAMPLE_SETS` 映射表）：

- `play_hit(material)`：敌人命中按材质取 `metal` / `flesh`，采样 + 合成低频垫底；
  金属有 35% 概率叠一记 `ricochet/` 尾音。
- `play_wall_impact()`：玩家子弹打墙取 `concrete/`，45ms 节流。
- 敌人子弹打中玩家取 `flesh/`。
- 未知材质或采样缺失自动落到 `generic/`，再不可用则回到旧的程序化三层。

**想整体退回旧音效（保留的退路）：**

1. 设置 → 打击感 → 「采样命中音效」切到「关」；或
2. 把 `Progress.gd` 里 `"sample_impacts": true` 改成 `false`（新存档默认即回退）；或
3. 清空 `Sfx.gd` 的 `IMPACT_SAMPLE_SETS`（代码层彻底回退）。

三种方式都不会报错：`play_hit` / `play_wall_impact` 会自动走 `_play_hit_procedural()`。

## 说明

- 当前游戏内命中音效 = 外部采样 + 程序化低频层；没有采样时退回原有的
  `hit_low` / `hit_mid` / `hit_air` / `metal_hit` 三层合成。
- 接入建议：通用弹着用 `generic/`，墙面按材质换 `concrete/`，机器人用 `metal/`，
  跳弹单发叠加 `ricochet/` 的低音量层，血肉用 `flesh/flesh_hit_01–04` 随机取一条。
- 所有素材保持原始采样率（44.1 kHz）；WAV 体积较大，接入后可统一转 OGG 压缩。
