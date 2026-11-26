# 音频素材来源、许可与热插拔替换指南（Phase 6B）

本目录包含《蓟花行动 / Operation Thistle》的全部音效与背景音乐资产，所有文件均经过统一峰值与响度归一化，配合 `default_bus_layout.tres` 的 `Master` 压限器（Limiter `-0.5 dB` ceiling）杜绝削波爆音。

---

## 1. 第三方外部素材（CC0 1.0 Public Domain）

位于 `assets/audio/sfx/impacts/{concrete,metal,ricochet,flesh,generic}/`，详情见 [SOURCES.md](sfx/impacts/SOURCES.md)：

| 目录 | 数量 | 许可 | 原作者 / 来源 |
| :--- | :---: | :--- | :--- |
| `sfx/impacts/concrete/` | 4 | CC0 1.0 | rubberduck — *75 CC0 breaking / falling / hit sfx* (OpenGameArt) |
| `sfx/impacts/metal/` | 6 | CC0 1.0 | rubberduck & BMacZero — *Metal Impact Sounds* (OpenGameArt) |
| `sfx/impacts/ricochet/` | 4 | CC0 1.0 | StarNinjas & BMacZero — *4 Metal Dings/Rings* (OpenGameArt) |
| `sfx/impacts/flesh/` | 5 | CC0 1.0 | EZduzziteh & Eldritch Grim (OpenGameArt) |
| `sfx/impacts/generic/` | 7 | CC0 1.0 | Eldritch Grim — *Impacts/Gun/sfx* (OpenGameArt) |

---

## 2. 项目原创离线 DSP 合成资产（本项目自有 / 公共领域等效）

由离线 Python/NumPy 多层声学 DSP 管线生成（含 FFT 巴特沃斯分频滤波、软饱和 `tanh`、战术室内/室外早期反射卷积尾响、机械瞬态叠加与零交叉无缝循环），全部 16-bit PCM WAV：

| 目录 | 采样规格 | 归一化标准 | 内容说明 |
| :--- | :--- | :--- | :--- |
| `sfx/weapons/` | 32 kHz Mono 16-bit | 枪声 `-1.0 dBFS` / 消音 `-2.8 dBFS` / 操作 `-3.5~-9.0 dBFS` | **18 把武器独立开火音色**（每把 2 变体 `<id>_fire_01..02.wav` + 1 消音 `<id>_sup_01.wav`，其中 VSS 为一体亚音速消音）+ 弹匣/管仓/左轮装填、泵动/栓动上膛、空仓、切弹、切枪、快慢机、开镜 |
| `sfx/impacts/weakspot/` | 32 kHz Mono 16-bit | `-2.5 dBFS` | Phase 4 弱点暴击（`weakspot_hit_01..02.wav`）与破甲（`armor_pierce_01..02.wav`） |
| `sfx/impacts/ground/` | 32 kHz Mono 16-bit | `-5.5 dBFS` | Phase 4 伪 3D 子弹落地扬尘（`ground_dust_01..02.wav`） |
| `sfx/combat/` | 32 kHz Mono 16-bit | `-1.0~-6.0 dBFS` | Phase 5 翻滚正式音效（`dodge_01..02.wav`）、护甲格挡/碎甲/掉血受击、敌人近战/冲锋/撞击/炮台锁定射击/歌利亚引信与爆炸/死亡与警戒 |
| `sfx/ui/` | 32 kHz Mono 16-bit | `-4.0~-10.0 dBFS` | 按键悬浮/点击/确认、改枪安装、天赋升级、三档拾取（基础/稀有/弹药）、开箱、波次开始/清波、撤离成功/任务失败 |
| `bgm/` | 24 kHz Stereo 16-bit | `-3.5~-4.5 dBFS` / `-14.5~-17.0 dB RMS` | 3 首无缝循环状态化 BGM：`bgm_menu.wav`（Vaporwave 88 BPM）、`bgm_explore.wav`（Dark Synth Ambient 96 BPM）、`bgm_combat.wav`（Outrun/Darksynth 124 BPM） |

---

## 3. 热插拔替换与扩展规范

`scripts/audio/SfxSamples.gd` 在启动/预热时自动扫描上述目录并按**逻辑 ID 前缀**聚类变体；缺失任意外部文件时自动无缝回退到 `SfxSynth.gd` 程序化合成兜底。

1. **替换单条音效**：直接覆盖对应 `.wav`（或放置同名 `.ogg` / `.mp3`）即可，无需改动任何脚本。
   - 例如替换 AKM 枪声：覆盖 `assets/audio/sfx/weapons/akm_fire_01.wav`，或追加 `akm_fire_03.wav` 自动加入随机防重复轮播池！
   - 例如替换 AKM 消音枪声：覆盖 `assets/audio/sfx/weapons/akm_sup_01.wav`。
2. **替换 BGM**：替换 `assets/audio/bgm/bgm_menu.{ogg,wav}`、`bgm_explore.{ogg,wav}`、`bgm_combat.{ogg,wav}`（存在 `.ogg` 时优先于 `.wav` 加载）。
3. **导入刷新**：在 Godot 编辑器打开项目，或执行 `--headless --import` 自动更新 `.import` 缓存即可生效。
