# Operation Thistle / HellWalker 2D — 项目开发规范

## 1. 工程与环境信息
- **工程根目录**：`D:\AI Game\HellWalker\HellWalker_DollProtocol`
- **Godot 无头/测试执行器（4.7.2 console，可正常输出 stdout）**：`D:\Godot\Godot_v4.7.2-stable_win64_console.exe`
- **Godot GUI 编辑器（4.7.2）**：`D:\AI Game\HellWalker\Godot_v4.7.2-stable_win64.exe`
- **Git 工具**：`D:\Program Files\Git\cmd\git.exe`（若终端 PATH 中暂无 `git`，直接调用此完整路径；本地仓库已初始化于 `main` 分支）
- **交付/文档/截图目录**：`D:\AI Game\temp_20261027_01`
- **真实入口与主场景**：`project.godot` 的 `run/main_scene` 为 `res://scenes/ui/StartMenu2D.tscn` → 部署进入 `res://scenes/core/Main2D.tscn`
- **代码构建 UI**：当前绝大多数 2D UI（如 `StartMenu2D`、`ArmoryMenu2D`、`SettingsMenu2D`、`CodexMenu2D`、`RunHUD2D` 等）均在脚本 `_build()` 中用代码生成节点，而非在 `.tscn` 中静态摆放。修改 UI 前不要只找场景文件。
- **已启用 Godot 插件**：
  - `addons/godot_ai`（4.4.1）：**必须保留**，这是 Antigravity 实时连接 Godot 编辑器的 MCP 通道（另注意：`HANDOFF_20261122.md` 第 7 节称其在 Antigravity 中“可能不再需要”这一说法已过时，请忽略）。
  - `addons/pixelfx`（0.3.0）：**不要随意升级或移除**，2D 枪口焰、命中特效与 `CombatFxWarmup` 强依赖 `PixelFx2D`。
  - `addons/phantom_camera`（0.11.0.3）：当前业务脚本与场景中 0 引用（无头 `--import` 时其内部 `update_button.gd:62` 有插件自带报错噪音）；仅在用户明确批准后移除。

## 2. 真相源与历史文档边界
- **当前真相源**：项目根目录 [HANDOFF_20261122.md](file:///D:/AI%20Game/HellWalker/HellWalker_DollProtocol/HANDOFF_20261122.md)。进行架构调整、大文件重构或排查跨系统耦合前，优先阅读其中对应章节（尤其是第 3 节技术债与雷区、第 4 节运行时链路与公式、第 5 节测试矩阵）。
- **过期历史文档**：`PLAN.md`（2026-11-04）、`迁移引导.md`（2026-11-16）、`tools/art_sources/ART_BIBLE.md`（旧 3D 规范）均已严重落后，**严禁当作现行规格遵循**。

## 3. 现役 2D 与遗留 3D 边界
- 当前主线为 **2D 俯视像素战术射击**。
- **遗留 3D 文件（仍可通过 `Main2D._unhandled_input()` 的 `KEY_F9` 切入 `res://scenes/core/Main.tscn`，不参与正式流程）**：
  - 场景：`scenes/core/Main.tscn`、`scenes/actors/Doll.tscn`、`scenes/fx/AimReticle.tscn`
  - 脚本：`scripts/core/Main.gd`、`scripts/core/SupportDB.gd`、`scripts/actors/Doll.gd`、`scripts/actors/BillboardVisual.gd`、`scripts/actors/Enemy.gd`、`scripts/weapons/PlayerWeapon.gd`、`scripts/weapons/WeaponVisual.gd`、`scripts/weapons/WeaponModel.gd`、`scripts/camera/CameraRig.gd`、`scripts/level/{LevelGenerator,AutoDoor,PropKit,FlickerLight}.gd`、`scripts/fx/{AimReticle,VisionCone,HearingIndicator,HealthBar3D,ImpactFX,ProjectileVisual}.gd`、`scripts/ui/{RunHUD,WeaponHUD,TitleMenu,PauseMenu,DebugHUD,RunMap,MotionBlur,PixelGrade,HealthVignette,ScreenVignette}.gd`
  - Shader：`shaders/*.gdshader`（全部为 3D 时代产物；2D `ScopeSight2D` 使用内联 shader）
  - 测试：第 5.4 节所列 21 个 3D 测试（如 `ballistics_test`、`combat_feedback_test`、`m3_test`、`m4_*_test`、`m5_test` 等）
- **实验/封存文件**：`scripts/actors/DollRig2D.gd`（仅 `--rig=normal|chibi` 启用）、`tools/add_armed_block.py`、`tools/gen_armed_frames.py`、`assets/art/characters/doll_b/armed/`。
- **2D / 3D 共享模块**：`WeaponData`、`WeaponDB`、`EnemyDB`、`Progress`、`Sfx`、`SegmentBar`、`PixelUI`。修改任何共享类或 `Progress.data` schema 时，必须核查两端兼容性。
- 未经用户明确要求，**不要修改或删除遗留 3D 代码**，也不要在 2D 新代码中引入对 3D 场景或节点的依赖。

## 4. 关键数值、单位债与数据规范
1. **单位不统一设计债（高风险）**：
   - 所有 2D 单位常量已收口至单一来源 [GameUnits.gd](file:///D:/AI%20Game/HellWalker/HellWalker_DollProtocol/scripts/core/GameUnits.gd)（`Main2D`、`Level2D`、`Enemy2D`、`VisionFog2D`、`HearingIndicator2D`、`WeaponRig2D`、`Doll2D` 均直接引用其常量，禁止再散落硬编码）。
   - 当前仍保留历史两套换算标尺：地图格、寻路、敌人感知与视野迷雾使用 `TILE = VISION_PIXELS_PER_METER = 64.0 px/m`；武器射程、枪长、弹速与角色身高使用 `WORLD_PER_METER = 128.0 / 1.7 ≈ 75.294 px/m`。
   - 不同系统中的“米”不能直接横向换算；**未经用户明确决策，不要擅自调整射程/视野数值或合并两套换算比例**。
2. **数据单一真相源**：
   - 武器、弹药、敌人、配件、资源、成长数值以 `data/*.json` 为准。
   - `GameData.table()` 使用 `static var _cache` 进程内缓存，修改 JSON 后必须开启新进程/重启游戏才生效。
   - **已知双真相源**：`data/weapons.json` 的 `bullet_speed_mps` 与 `data/ammo.json` 的 `muzzle_velocity_mps`（`Main2D.bullet_speed_px_s()` 优先读武器字段），改动初速时需注意同步。

## 5. 强制执行红线
1. **改完脚本先刷新导入**：新增、重命名 `.gd` 或修改 `class_name` 后，必须先运行：
   ```powershell
   & "D:\Godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path "D:\AI Game\HellWalker\HellWalker_DollProtocol" --import
   ```
   否则会触发全局类缓存缺失导致的连锁解析错误。（注：若编辑器正在运行且未修改脚本/资源，跑纯测试时可跳过 `--import` 避免竞争 `.godot` 缓存。）
2. **核心测试门禁（34 个 2D 回归）**：
   - 改动代码或数据后，使用 `.agents/skills/godot-verify/scripts/run_core_tests.ps1` 跑对应子集或全部 34 个核心 2D 测试（基线 1202 条断言，0 失败，含 `stage1_2d_test` 与 `game_units_test`）。
   - 21 个 3D 遗留测试**不纳入 2D 回归门禁**。
3. **版本控制与回滚规范**：
   - 在 Git 仓库正式初始化并完成首提交前，重大修改须沿用 `backups/<YYYYMMDD_topic>/` + `ROLLBACK.txt` 备份机制；**严禁混用不同检查点文件回滚**（注意 `backups/20261122_bullet_velocity/ROLLBACK.txt` 已过期）。
   - Git 建仓后，严格以原子 commit 作为安全回滚点。
4. **密钥安全**：`.env` 共含 6 个键（`IMAGE_API_BASE`、`IMAGE_API_KEY`、`IMAGE_API_MODEL`、`SEEDREAM_API_BASE`、`SEEDREAM_API_KEY`、`SEEDREAM_API_MODEL`）。严禁打印、回显、提交或外传任何真实密钥值。
5. **大文件重构护栏**：修改或拆分 `Main2D.gd`、`ArmoryMenu2D.gd`、`Level2D.gd`、`Enemy2D.gd`、`Progress.gd`、`WeaponRig2D.gd`、`Sfx.gd`、`SettingsMenu2D.gd` 前，必须先启用 `godot-refactor-guard` skill，锁定相关核心测试基线再动刀。
6. **视觉与编辑器协同**：修改 UI、武器锚点、视野或特效后必须截屏并用 `read_file` 查看 PNG 确认；需要实时检查运行状态/日志/场景树时使用 `godot-ai` MCP，批量无头测试走命令行脚本。
