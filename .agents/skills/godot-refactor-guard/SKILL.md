---
name: godot-refactor-guard
description: >-
  Use this skill before refactoring or splitting large, tightly-coupled GDScript
  files (such as Main2D.gd, ArmoryMenu2D.gd, Level2D.gd, Enemy2D.gd, Progress.gd,
  WeaponRig2D.gd, Sfx.gd, or SettingsMenu2D.gd) in HellWalker_DollProtocol to
  prevent regressions.
---

# 屎山重构安全护栏协议

## 适用对象
超过 500 行、职责混杂或跨系统强耦合的核心脚本（重点：`Main2D.gd`、`ArmoryMenu2D.gd`、`Level2D.gd`、`Enemy2D.gd`、`Progress.gd`、`WeaponRig2D.gd`、`Sfx.gd`、`SettingsMenu2D.gd`）。

## 重构前（缺一不可）
1. **先读交接技术债与雷区**：查阅 `HANDOFF_20261122.md` 第 3.2 节（隐式耦合）、第 3.3 节（雷区）与第 3.4 节（阶段化重构顺序）。
2. **建立安全回滚点**：
   - 若项目已初始化 Git：确认工作树干净或先做安全 commit（如 `chore: checkpoint before refactoring <module>`）。
   - 若尚未初始化 Git：按 `backups/<YYYYMMDD_topic>/` 复制待改文件并写 `ROLLBACK.txt`（严禁混用不同检查点文件）。
3. **锁定测试基线**：
   - 运行 `powershell -ExecutionPolicy Bypass -File .agents/skills/godot-verify/scripts/run_core_tests.ps1` 确认全量 38 个核心 2D 测试 `PASS`（约 1352 条断言，0 失败）。**基线不绿，禁止开始重构。**
4. **盘点外部契约与已知陷阱**：
   - **纯计算模型已收口（Stage 2 完成）**：武器属性（`WeaponStatsModel`）、散布（`SpreadModel`）、弹道（`BallisticsModel`）、RHA 护甲/伤害（`DamageModel`）已抽离至单一纯模型，后续调整公式必须只在模型内修改。
   - **`WeaponData` 原地可变前提**：`WeaponDB.get_weapon()` 目前每次新建实例，而 `WeaponRig2D._apply_mods()` 会原地修改它；切勿在未做只读隔离前将 `WeaponDB.get_weapon()` 改为返回缓存共享实例。
   - **硬编码路径依赖**：`PlayerBullet2D` 已完成信号/回调解耦（Step 3.1）；`Level2D` 仍通过 `../World2D/SortLayer` 等相对路径访问 `Main2D.tscn` 节点；大量 UI 在 `_build()` 中手写构造且测试直接读取节点名和私有属性。
   - **初始化与缓存顺序**：`Main2D._ready()` 的调用顺序（HUD/准心 → 玩家位置/天赋 → `VisionFog2D.setup` → `_spawn_enemies` → FX 预热）及 `GameData.table()` 静态 `_cache` 不可随意打乱。
   - **`Progress.data` 共享与归档兼容**：2D/3D 共用同一份 `data`，`_normalize_data()` 决定旧存档能否读取；`save_data()` 含备份轮换逻辑。
   - **世界单位已统一**：所有世界距离常量统一在 `GameUnits.gd`（`64 px/m`）；`SPRITE_PX_PER_METER` 仅限枪械贴图缩放使用。

## 重构中（小步快跑原则）
1. **目标与边界**：目标逐步将超大文件拆分至 `< 600` 行/文件；每次只拆**一个明确子系统/职责**，结构调整与数值/玩法修改严格分离（保持纯结构等价）。
2. **外壳兼容委托**：
   - 优先从“上帝类”抽离**纯计算/无状态模型**（如 `WeaponStatsModel`、`SpreadModel`、`BallisticsModel`、`DamageModel`）或**独立子组件**；
   - 原类保留既有方法签名、信号名、测试依赖的节点命名与字段接口，内部转发给新模块。
3. **不重复造配置**：继续以 `data/*.json` 与 `*DB.gd` 为数据真相源。

## 重构后（验收闭环）
1. 新增或重命名 `.gd` 后必须先运行 `D:\Godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --import`。
2. 再次执行 `run_core_tests.ps1` 跑通全部 37 个核心 2D 测试：确认全部 `PASS` 且总断言数不下降、无新增 `SCRIPT ERROR`。
3. 如涉及 UI 或战斗表现，窗口模式截图并用 `read_file` 核对画面一致。
4. 在 Git 中提交原子 commit（或记录对应检查点），写明拆出职责与测试通过数。
