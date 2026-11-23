# 更新日志（CHANGELOG）

> 项目：**Operation Thistle / 蓟花行动（HellWalker 2D）**  
> 本日志按重要里程碑以中文记录玩法机制、美术资产、架构重构与测试门禁演进。

---

## [2026-11-23] 架构重构阶段 2~3 · RHA 护甲与穿甲系统重做 · 全武器 0° 平直修正

### 新机制与战斗平衡
- **RHA 均质装甲与穿甲体系重做**（回滚标签：`backup/pre-rha-rework`）：
  - 统一以 **`1 点护甲/穿深 = 0.1 mm RHA（均质装甲钢）`** 为内部数值基准（例如 `46` = `4.6mm RHA`），取消穿甲随距离衰减。
  - **对敌结算**：当前小怪采用固定 RHA 防御；击穿时触发余穿加伤 `伤害 + (穿甲 - 护甲) × 0.1`，未击穿按 `(穿甲 / 护甲)²` 平滑衰减至最低 `12%` 钝伤。
  - **12 种弹药口径与 8 种敌人护甲重标**：按现实近距离 RHA 钢板穿深重标弹药 `ap`（鹿弹 `8` ~ `.338 Lapua` `180`）与敌人护甲（突击者 `0` / 哨兵 `10` / 歌利亚 `20` / 声呐猎手 `35` / 哨兵一型 `55` / 移动哨戒炮 `75` / 巡猎者一型 `100` / 重装 `140`），武器自身伤害/射速/后坐力等数值保持不变。
  - **玩家护甲“偏护罩碎甲”平衡**：基础 RHA 分档 `Lv1=30 / Lv2=50 / Lv3=70 / Lv4=90`，随耐久在 `100% → 50%` 缓降，归零失防（预留 `min_damage_reduction` 给后续组件/天赋最低减伤）；未击穿主扣耐久 + `5%~20%` 极轻钝伤，击穿 `25%~50%` 穿血 + `100%~130%` 碎甲损耗，并加入破甲边界平滑插值，确保常规战斗与穿甲打击下**护甲优先于血条掉光**，避免“人死甲还在”。
- **设置页 / 武备库 / 图鉴双显示模式**：
  - 设置页新增「护甲 / 穿深显示」切换（`穿深值 // 46` ↔ `RHA // 4.6mm`），同步联动武备库（武器/护甲/改枪）与图鉴（敌人/弹药）。
  - 优化设置页右侧开关排版为紧凑单行，修复添加选项后的纵向溢出问题。

### 美术与视觉修正（为可视化配件铺路）
- **全 18 把武器统一修正为 0° 完全水平平直**：
  - 修复 `tools/prep_new_weapons.py` 中因护木/准星与细枪管落差而把水平原图误旋转 `+3° ~ +10°` 的 Bug。
  - 重新生成 14 把新枪（`g18`、`m1911`、`fn57`、`python`、`mp7`、`tmp`、`p90`、`ump45`、`fal`、`akm`、`l85a2`、`sr25`、`vss`、`awm`）的 0° 平直锐利 `side.png`、`icon.png` 与 `meta.json`，并精调 `mp7` / `p90` 握把锚点。
  - 清零 4 把老枪（`g17`、`m870`、`m1014`、`saiga12k`）`meta.json` 中残留的非零 `barrel_angle_deg`，解决游戏内持枪偏斜。

### 架构重构（阶段 2 + 阶段 3）
- **阶段 2 — 抽离 4 个无状态纯计算模型（单一真相源）**：
  - `WeaponStatsModel.gd`：统一 `WeaponRig2D` 与 `ArmoryMenu2D` 的武器/配件/天赋属性计算，并顺带修复改枪页安装非全自动枪机组件误将原生全自动武器覆盖为单发的漂移 Bug。
  - `SpreadModel.gd` & `BallisticsModel.gd`：从 `Main2D` 抽离散布（首发收紧、开镜、连发累积/回落）与弹道（射程、弹速、飞行时间、空气阻力）公式。
  - `DamageModel.gd`：统一敌我 RHA 护甲与伤害结算逻辑。
- **阶段 3 — 解除私有回调与 UI 反向强耦合**：
  - `PlayerBullet2D.gd`：移除 `main` 反向指针及对 `Main2D` 私有方法的硬调用，改为 `create(parent, config)` + `enemy_hit` / `wall_hit` / `finished` 信号 + 可注入/内置 `wall_check`，可完全脱离 `Main2D` 独立运行与单测。
  - `Main2D.gd` & UI 层：暴露 5 个行动事件信号（`shot_fired`、`hit_resolved`、`loot_gained`、`wave_changed`、`run_finished`）及只读快照接口（`get_map_snapshot()`、`get_loot_snapshot()`）；`Minimap2D`、`MapOverlay2D`、`BackpackMenu2D` 改为只读快照 + `opened`/`closed` 信号解耦；清理 `RunHUD2D.WEAPON_SHORT_NAME` 死代码。

### 工程与测试门禁
- 核心 2D 自动化回归从 **34 项 / 1,206 断言** 扩充至 **39 项 / 1,369 断言（全绿，0 失败，0 ScriptErrors）**，新增：`weapon_stats_model_test`、`spread_ballistics_model_test`、`damage_model_test`、`player_bullet_test`、`run_events_hud_test`。
- 截图与 MovieWriter 录屏介质迁出游戏本体至工程外 `D:\AI Game\HellWalker\captures\`，释放游戏目录约 **597 MB**，并在 `GEMINI.md` 固化“本地原子提交 + 截图/录像双重检验”规范。

---

## [2026-11-22] 阶段 0~1 · Git 安全网与全游戏 64 px/m 单位统一

- 建立 Git 仓库与 `.gitignore`，归档历史文档与临时文件，修复 `stage1_2d_test` 过时断言。
- 新增单一单位来源 `GameUnits.gd`，将全游戏世界距离统一为 **`1 格 = 1 米 = 64 px`**（回滚标签：`backup/pre-unit-unify`）；`SPRITE_PX_PER_METER` 仅保留给 `WeaponRig2D` 枪械贴图视觉缩放，并完成武器射程与弹道时间压缩倍率的手感等价换算。
