# Godot 编辑器可调固定场景与配置资源速查表（Phase 1）

本文档列出《蓟花行动 / Operation Thistle》全部可在 **Godot 编辑器检查器（Inspector）** 中直接修改并持久生效的固定场景属性与 `.tres` 配置资源，以及刻意保留为**运行时动态计算（严禁固化）**的数据边界。

---

## 一、场景节点直接可调属性（`.tscn`）

| 所属场景 | 节点路径 / 位置 | 属性名 | 默认值 | 生效说明（Phase 1 改造点） |
| :--- | :--- | :--- | :--- | :--- |
| [Main2D.tscn](file:///D:/AI%20Game/HellWalker/HellWalker_DollProtocol/scenes/core/Main2D.tscn) | 根节点 `Main2D` | `clear_color` | `#08090a` | 启动写入 `RenderingServer.set_default_clear_color()`，替代原先硬编码覆盖 |
| [Main2D.tscn](file:///D:/AI%20Game/HellWalker/HellWalker_DollProtocol/scenes/core/Main2D.tscn) | 根节点 `Main2D` | `camera_config` | `camera_feel_default.tres` | 镜头抬升、缩放范围与前探参数资源槽 |
| [Main2D.tscn](file:///D:/AI%20Game/HellWalker/HellWalker_DollProtocol/scenes/core/Main2D.tscn) | 根节点 `Main2D` | `combat_config` | `combat_feel_default.tres` | 后坐力、震屏基数与受击红屏参数资源槽 |
| [Main2D.tscn](file:///D:/AI%20Game/HellWalker/HellWalker_DollProtocol/scenes/core/Main2D.tscn) | 根节点 `Main2D` | `vision_config` | `vision_lighting_default.tres` | 视野锥与近身暗视野灯光亮度/色温资源槽 |
| [Main2D.tscn](file:///D:/AI%20Game/HellWalker/HellWalker_DollProtocol/scenes/core/Main2D.tscn) | `Camera2D` | `zoom` | `Vector2(0.95, 0.95)` | 运行时作为 100% 基准缩放 `_base_zoom`，不再被 `const ZOOM` 无条件盖回 |
| [Main2D.tscn](file:///D:/AI%20Game/HellWalker/HellWalker_DollProtocol/scenes/core/Main2D.tscn) | `Camera2D` | `position_smoothing_enabled` / `position_smoothing_speed` | `true` / `9.0` | 腰射镜头跟随平滑直接生效（开镜时临时关闭防漂移，松手自动恢复） |
| [Main2D.tscn](file:///D:/AI%20Game/HellWalker/HellWalker_DollProtocol/scenes/core/Main2D.tscn) | `World2D/CanvasModulate` | `color` | `Color(0.40, 0.43, 0.48, 1)` | 视野迷雾基础环境色；`VisionFog2D` 读取此色并在关闭 `F7` 调试照明后精确恢复 |
| [Main2D.tscn](file:///D:/AI%20Game/HellWalker/HellWalker_DollProtocol/scenes/core/Main2D.tscn) | `DebugOverlay2D` | `visible` / `Panel` 边距与 `StyleBoxFlat` / `Label` 样式 | `false` / `(24, 24, 520, 250)` | 勾选 `visible=true` 即默认以调试照明启动；面板位置与字体样式完全保留 |
| [Doll2D.tscn](file:///D:/AI%20Game/HellWalker/HellWalker_DollProtocol/scenes/actors/Doll2D.tscn) | 根节点 `Doll2D` | `config` | `doll_default.tres` | 角色动画帧率、步伐起伏、背枪倾角、受击反馈参数资源槽 |
| [Doll2D.tscn](file:///D:/AI%20Game/HellWalker/HellWalker_DollProtocol/scenes/actors/Doll2D.tscn) | 根节点 `Doll2D` | `walk_speed` / `sprint_speed` | `250.0` / `380.0` | 基础移动速度（行动中再叠加移速天赋与护甲移速组件倍率） |
| [Doll2D.tscn](file:///D:/AI%20Game/HellWalker/HellWalker_DollProtocol/scenes/actors/Doll2D.tscn) | `Body` | `offset` | `Vector2(0, -144)` | 已对齐 256px 默认 LOD 脚底基准；在编辑器微调 XY 偏移时运行时保留差值 |
| [Doll2D.tscn](file:///D:/AI%20Game/HellWalker/HellWalker_DollProtocol/scenes/actors/Doll2D.tscn) | `Collision` / `Shadow` | `position` / `shape.radius` / `texture` | `(0,-6)` / `15.0` / `pixel_shadow_64.png` | 物理碰撞圆与脚底投影贴图位置直接生效，不被脚本覆写 |
| [StartMenu2D.tscn](file:///D:/AI%20Game/HellWalker/HellWalker_DollProtocol/scenes/ui/StartMenu2D.tscn) | 根节点 `StartMenu2D` | `config` | `start_menu_default.tres` | 背景轮播图集、停留/淡入时长、暗角渐变蒙版与扫描线参数资源槽 |

---

## 二、成组调优配置资源（`resources/config/*.tres`）

在 Godot 文件系统双击任意 `.tres` 文件（或在对应场景根节点的检查器中展开）即可可视化修改并保存：

| 资源文件 | 脚本类 | 挂载场景 | 可调分组与核心属性 |
| :--- | :--- | :--- | :--- |
| [camera_feel_default.tres](file:///D:/AI%20Game/HellWalker/HellWalker_DollProtocol/resources/config/camera_feel_default.tres) | [CameraFeelConfig.gd](file:///D:/AI%20Game/HellWalker/HellWalker_DollProtocol/scripts/config/CameraFeelConfig.gd) | `Main2D.tscn` → `camera_config` | **Base & Zoom**: `camera_lift` (44), `view_zoom_min` (20), `view_zoom_max` (200), `view_zoom_step` (10), `view_zoom_lerp` (260)<br>**ADS & Look-Ahead**: `ads_zoom_speed` (6), `ads_look_ahead` (340), `ads_look_smooth` (10), `scope_keep_player_ratio_x/y` (0.88/0.82), `scope_zoom_out_min_mag/max_mag` (0.85/0.62), `scope_deadzone_px` (6), `scope_look_smooth` (10) |
| [combat_feel_default.tres](file:///D:/AI%20Game/HellWalker/HellWalker_DollProtocol/resources/config/combat_feel_default.tres) | [CombatFeelConfig.gd](file:///D:/AI%20Game/HellWalker/HellWalker_DollProtocol/scripts/config/CombatFeelConfig.gd) | `Main2D.tscn` → `combat_config` | **Recoil**: `recoil_limit`, `recoil_recover` (95), `recoil_ads_mul` (0.55), `recoil_build_gain` (0.55), `recoil_cam_scale/limit/recover` (0.95/26/70), `recoil_roll_scale/limit/recover` (0.0016/0.028/0.16)<br>**Shake & Feedback**: `shake_scale_base` (5), `hitstop_time_scale` (0.12), `hurt_flash_color`, `hurt_flash_fade_sec` (0.34), `hurt_shake_amount/roll_deg/decay` (2.2/0.3/24) |
| [vision_lighting_default.tres](file:///D:/AI%20Game/HellWalker/HellWalker_DollProtocol/resources/config/vision_lighting_default.tres) | [VisionLightingConfig.gd](file:///D:/AI%20Game/HellWalker/HellWalker_DollProtocol/scripts/config/VisionLightingConfig.gd) | `Main2D.tscn` → `vision_config` | **Vision Light Energy**: `clear_energy` (0.60), `ring_dim` (0.40), `dark_energy` (0.18), `self_energy` (0.18), `ring_enemy_alpha` (0.80)<br>**Vision Light Color**: `light_color`, `dark_color`, `self_color` |
| [doll_default.tres](file:///D:/AI%20Game/HellWalker/HellWalker_DollProtocol/resources/config/doll_default.tres) | [DollConfig.gd](file:///D:/AI%20Game/HellWalker/HellWalker_DollProtocol/scripts/config/DollConfig.gd) | `Doll2D.tscn` → `config` | **Movement & Animation**: `ads_speed_mul` (0.5), `walk_fps` (10.4), `run_fps` (14.8), `step_bob_px` ([1.2,0,1.2,0])<br>**Combat Feedback & Stowed Weapon**: `hurt_invuln_sec` (0.12), `hurt_flash_sec` (0.16), `hurt_flash_tint`, `fire_flinch_px` (2.2), `flinch_recover_speed` (40), `stow_rotation` (-0.62), `stow_offset`, `stow_tint`<br>**Head Tracking**: `head_motion_enabled` (false), `head_max_tilt` (0.18), `head_tilt_speed` (9), `head_max_shift` (0.01) |
| [start_menu_default.tres](file:///D:/AI%20Game/HellWalker/HellWalker_DollProtocol/resources/config/start_menu_default.tres) | [StartMenuConfig.gd](file:///D:/AI%20Game/HellWalker/HellWalker_DollProtocol/scripts/config/StartMenuConfig.gd) | `StartMenu2D.tscn` → `config` | **Background Carousel**: `bg_hold_seconds` (8.5), `bg_fade_seconds` (1.8), `base_bg_color`, `slide_paths`, `slide_labels`<br>**Vignette & Readability Mask**: `left/right_mask_width_ratio`, `left/right_mask_alpha`, `top/bottom_vignette_ratio/alpha`, `mask_tint`<br>**Scanline & Tactical Frame**: `scanline_alpha`, `scanline_step_px`, `sweep_speed`, `sweep_alpha`, `corner_bracket_alpha/margin/length` |

> [!TIP]
> **零耦合回退保证**：所有脚本均保留原有 `const` 默认值；如果某个测试直接 `new()` 或清空了资源槽，运行时会自动回退到等价默认值，不会产生空引用报错。

---

## 三、刻意保留为运行时动态计算的值（严禁固化）

| 运行时状态 / 属性 | 动态来源 | 为什么不能在 `.tscn` / `.tres` 中固化 |
| :--- | :--- | :--- |
| `Camera2D.limit_left / top / right / bottom` | `Level2D.camera_bounds()` + 低缩放/高倍镜动态边界外扩 | 关卡为程序化生成，常规设施与歌利亚竞技场尺寸不同，且低缩放开镜必须动态外扩避免边界推挤 |
| `Doll2D.global_position` 与 `Doll2D.bounds` | `Level2D.player_spawn` 与 `Level2D.map_size()` | 不同部署点（北门/废弃翼）与地图尺寸决定出生坐标与可活动范围 |
| `Doll2D.hp` / `hp_max` / `armor` / `armor_max` / `armor_level` / 最终移速 | `Progress` 存档 + 天赋树等级 + 护甲组件 | 属于局外成长与装配系统，开局在 `Main2D._apply_talents()` 实时结算 |
| `StartMenu2D` 主题配色、作战档案、当前主/副武器预览 | `Progress` 存档与 `PixelUI` 主题调色板 | 允许玩家在主菜单实时切换 4 套预设 + 自定义配色并随存档持久化 |
| 音频主音量 / 音效 / 音乐、视角缩放档位、震屏开关/倍率、弹药显示模式 | `Progress` 存档 + `SettingsMenu2D` | 属于玩家个性化偏好，须跨场景与局内 ESC 实时同步 |
