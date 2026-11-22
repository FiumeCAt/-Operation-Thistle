---
name: godot-art-pipeline
description: >-
  Use this skill when generating, resizing, keying, slicing, or importing 2D
  pixel art, player/enemy animation sheets, weapon sprites, container props, or
  UI icons for HellWalker_DollProtocol via tools/ Python scripts.
---

# HellWalker 2D 美术生成与精灵处理规范

## 1. 外部生图通道（配置来自项目根 `.env`）
- `.env` 含 6 个键（`IMAGE_API_BASE`、`IMAGE_API_KEY`、`IMAGE_API_MODEL`、`SEEDREAM_API_BASE`、`SEEDREAM_API_KEY`、`SEEDREAM_API_MODEL`），**严禁输出、打印或泄露任何真实密钥值**。
- **通道 A：中转站 OpenAI 兼容接口（`tools/gen_image_api.py`，角色与参考图改图首选）**
  ```powershell
  python tools/gen_image_api.py --list-models
  python tools/gen_image_api.py --prompt "..." --out out/preview.png --size 1024x1536 --dry-run
  python tools/gen_image_api.py --prompt "..." --out out/preview.png --ref ref1.png
  ```
- **通道 B：Seedream 5.5 火山方舟（`tools/gen_seedream.py`，图标/透明背景素材）**
  ```powershell
  python tools/gen_seedream.py --prompt "..." --out out/icon.png --size 2K --transparent --no-watermark
  ```
- **生图策略**：
  - 角色/敌人抠图统一使用**纯品红背景 `#FF00FF`**，配合偏差抠像 + 去溢色（**禁用白底**，否则腿间与地面线容易残留白边）；
  - 使用**单帧 img2img** 保持角色比例，不要整张 4×4 图集直接重绘（极易 Q 版化）；
  - 若接口返回 `504`，等待 **90–120 秒**后再重试。

## 2. 现役 2D 资产规格与管线

### 玩家角色（`Doll2D`）
- 图集布局：4 方向 × 4 帧/动作，`ANIM_BLOCKS = {idle:0, walk:4, run:8, aim:12}` → **16 行 × 4 列**；
- 帧尺寸：`DEFAULT_BODY_PX = 256`，`frame_size = body_px × 1.25 = 320×320`，`WORLD_BODY = 128`，`FEET_RATIO = 0.95`；
- 当前运行时资源：`assets/art/characters/doll_b/lod/doll_lod_256_body.png` 与 `doll_lod_256_head.png`；
- **现役管线**：`tools/build_doll_sheets.py` → `tools/add_aim_block.py` → `tools/cut_head_layer.py`（`FRAME=320`、`ROWS=16`、`COLS=4`）；
- **拆头与头部红线**：严禁用固定横坐标硬切头部；必须按肤色/头顶重心定位，且头部层绝不能包含枪箱。当前代码 `HEAD_MOTION_ENABLED = false`（因脖子接缝暂时关闭）。

### 敌人（`Enemy2D`）
- 旧 4 种静态敌人（`rifleman/rusher/heavy/hunter`）：`assets/art/enemies/<id>.png`（256×384，内容高 360，脚底 y=372），管线 `tools/prep_enemies.py`。
- 新 4 种动画敌人（`mobile_turret/sentry_type1/hunter_type1/goliath`）：`assets/art/enemies/<id>_anim_frames.tres`（`SpriteFrames`），管线 `tools/gen_enemy_anim.py` → `tools/build_enemy_anim.py`（4×4 640×384，脚底 y=372）→ `tools/build_enemy_frames.py`（另 `build_enemy_sheets.py` / `gen_enemy_sheets.py` 用于 12 行四向图集）。
- 注意：`EnemyDB.ORDER` 仅列旧 4 敌，实际 8 敌 roster 定义在 `Level2D.ROOM_DEFS` 与 `EnemyDB.new_units()`。

### 武器（`WeaponRig2D`）
- 资源：`assets/art/weapons/<id>/side.png`、`icon.png`、`meta.json`；
- `meta.json` 必填 `grip_px`、`muzzle_px`；可选 `barrel_angle_deg`、`bolt_px`、`magazine_px`、`muzzle_mod_px`（新增武器或槽位务必补全 `meta.json`，避免仅靠比例估算锚点）；
- 管线：新枪用 `tools/prep_new_weapons.py`（清边/摆正/48 色/4× nearest），旧枪/兜底用 `tools/prep_weapons.py`，枪口焰/手部用 `tools/make_weapon_fx.py`；
- 朝左渲染必须 `flip_v` 并重算镜像握把，禁止直接旋转 180°。

### 容器、环境与图标
- 容器：`tools/prep_containers.py`（输出 512×512，即 64 逻辑像素 × 8；底部 y=62，32 色量化，1px 深描边）。
- 地砖/家具：`tools/make_pixel_tiles.py`。
- 资源图标：**当前使用 `tools/gen_resource_icons_seedream.py`**（128×128 覆盖 `assets/art/ui/icons/res_*.png`）；**严禁误跑 `tools/gen_resource_icons.py`**（32×32 手绘兜底，会直接覆盖同名图标）。

## 3. 图像处理硬性约束与禁用旧管线
1. **缩放必须预乘 Alpha**：统一复用 `tools/sprite_utils.py`；像素资产使用整数倍 `NEAREST` 放大与统一色板量化，禁止直接对 RGBA 精灵做普通双线性/Lanczos 缩放。
2. **游戏内渲染**：`project.godot` 默认纹理过滤为 `0`（nearest），UI/精灵保持 `TEXTURE_FILTER_NEAREST`。
3. **以下旧/一次性脚本不要作为现役管线调用**：
   `build_character_sheet.py`、`build_doll_atlas.py`、`bake_sprite_relief.py`、`build_doll4_atlas.py`、`build_doll_lods.py`、`add_armed_block.py`、`gen_armed_frames.py`、`gen_placeholder_art.py`、`make_lineart_textures.py`、`image25_generate.ps1`、`ART_BIBLE.md`（旧 3D 规范）。
4. 中间产物输出到 `out/` 或 `D:\AI Game\temp_20261027_01\`，不要污染 `tools/` 或源码目录。

## 4. 入库验收
1. 最终素材归位到 `assets/art/...`；
2. 执行 `D:\Godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --import`；
3. 用 `read_file` 检查最终 PNG 透明度与构图，并在窗口模式截图核对游戏内比例与层级。
