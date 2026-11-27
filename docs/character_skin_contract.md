# Modular Doll Rig v2 角色皮肤包 1:1 像素换皮契约

> **核心定位红线**：
> - `mannequin`（功能分色标准体模）仅用于 **骨架动作基准验收 + 1:1 换皮尺寸契约**；
> - **严禁**把体模导出的动作序列帧喂给 AI 逐帧重绘；
> - 新增正式角色时，只需用静态立绘（正/背/侧静态视图）按本契约裁切为 **18 个核心静态身体分件 + 3 个持枪臂分件**（`gun_case.png` 背包/枪盒改为**可选额外组件**，后续新角色默认**不再生成背包**），放入 `assets/art/characters/<skin_id>/`，**零改代码即可继承全部步态、瞄准、持枪、弹簧物理与翻滚动画**。

---

## 1. 画布与骨架全局基准

| 项 | 锁定值 | 说明 |
|---|---|---|
| 世界身高规格 | `128px × 1` | 与 `GameUnits.DOLL_WORLD_HEIGHT_PX`（2 格地砖）1:1 同密 |
| 光栅化视口 | `160 × 160` (`SubViewport`) | `transparent_bg = true`、`MSAA_DISABLED`、`TEXTURE_FILTER_NEAREST` |
| 脚底世界原点 | `GROUND_ORIGIN = (80, 148)` | 站立鞋底紧贴 `y = 148`，头顶约 `y = 20` |
| 骨盆高度 `PELVIS_HEIGHT` | `58 px` | `THIGH_LEN = 28` + `SHIN_LEN = 30` |
| 躯干与颈/肩锚点 | `TORSO_HEIGHT = 40` / `NECK_OFFSET_Y = -39` / `SHOULDER_OFFSET_Y = -33` | 相对 `Pelvis` 局部坐标 |
| 收枪双臂段长 | `UPPER_ARM_LEN = 16` / `FOREARM_LEN = 16` | 肘关节位于上臂 `y = +14` |
| 持枪双臂（`arm2`） | `ARM_SCALE = 0.5` | `WeaponRig2D` 以 0.5× 缩放贴合 12px+12px 双段 IK |

---

## 2. 目录结构与热切换入口

每个皮肤包均位于 `res://assets/art/characters/<skin_id>/`：

```text
assets/art/characters/<skin_id>/
├── skin_manifest.json        # 元清单（声明分色模式、extra_components_default、精确尺寸与枢轴）
├── parts/                    # 18 个核心身体分件 PNG + 可选 gun_case.png（严格 height == target_h，1:1 零畸变）
└── arm2/                     # 3 个横置持枪双臂分件 PNG（供 WeaponRig2D 加载）
```

- **已实装皮肤包（全部严格 1:1 `target_h` 整数锁定）**：
  - **`doll_v2`**（默认正式皮）：灰蓝猫耳少女（19+3，保留专属背挂枪盒 `gun_case.png`，`extra_components_default.back_gear = true`）；
  - **`doll_thistle`**（第二套正式皮）：白发高马尾红白水手战术人偶（18+3 轻装无背包，`extra_components_default.back_gear = false`）；
  - **`mannequin`**（动作基准体模）：功能分色标准体模（19+3，含背挂基准框用于前后遮挡验收）。
- **回退机制**：`Doll2D.set_skin(id)` 会同步切换 `DollRigV2` 与 `WeaponRig2D`；传入非法 ID 或缺失核心分件时自动按分件/整包安全回退至 `doll_v2`。**可选分件（如 `gun_case.png`）绝不会跨皮肤回退串用**——无 `gun_case.png` 的角色（如 `doll_thistle`）自动保持无背挂状态。
- **切换入口**：
  1. 主菜单「角色 // OPERATOR」界面（`CharacterMenu2D`）：支持 4 向实机骨骼预览（待机/行走/冲刺/持枪/翻滚）并一键切换正式角色（`doll_v2` / `doll_thistle`），自动持久化至存档；
  2. 命令行：`-- --skin=doll_v2`、`-- --skin=doll_thistle` 或 `-- --skin=mannequin`（`Main2D._apply_visual_override()` 解析）；
  3. 调试终端：`DebugMenu2D` 顶部栏一键轮切「角色外观：灰蓝猫耳 / 蓟花白裙 / 分色体模」（局内即时生效并持久化至存档偏好）。

---

## 3. 精确 1:1 像素尺寸框、枢轴与层级表

> **1:1 像素硬要求**：`DollRigV2._make_sprite()` 会按 `target_h / tex.get_height()` 缩放贴图。当 PNG 实际高度严格等于下表 `精确尺寸 (W×H)` 中的 `H`（即 `target_h`）时，运行时缩放恒为 **`1.0 × 1.0`**，杜绝非整数缩放畸变与像素抖动。
>
> **关节圆角包边要求**：所有旋转关节切口（髋/膝/踝/肩/肘/颈）均须向外保留 **2–4 px 圆角重叠包边**，保证大角度屈膝、摆臂与团身翻滚绝不露缝。

### 3.1 身体 19 分件（`parts/*.png`）

朝向索引约定：`0 = 下(正)`、`1 = 上(背)`、`2 = 左(侧)`、`3 = 右(侧)`。

| # | 文件名 (`parts/`) | 精确尺寸 `W×H` | `Sprite2D.offset` | 关键关节枢轴（图内像素 `(x, y)`） | `z_index`（按朝向） | 镜像/显隐规则 |
|---|---|---|---|---|---|---|
| 1 | `head_front.png` | **38 × 36** | `(0, -14)` | 颈 `(18.5, 32)`（底部 3–4px 压领） | `0: 5` | 无 |
| 2 | `head_front_blink.png` | **38 × 36** | `(0, -14)` | 与 `head_front` 像素对齐 | `0: 6` | 眨眼/受击/翻滚叠加显示 |
| 3 | `head_back.png` | **38 × 36** | `(0, -14)` | 颈 `(18.5, 32)` | `1: 5` | 无 |
| 4 | `head_left.png` | **36 × 36** | `(0, -14)` | 颈 `(18, 32)`，面朝左 `-X` | `2/3: 5` | 朝右 (`3`) 水平翻转 |
| 5 | `head_left_blink.png` | **36 × 36** | `(0, -14)` | 与 `head_left` 像素对齐 | `2/3: 6` | 朝右 (`3`) 水平翻转 |
| 6 | `torso_front.png` | **36 × 46** | `(0, -20)` | 颈 `(18, 4)`、肩 `(8/28, 11)`、髋 `(18, 43)` | `0: 1` | 无（无臂躯干） |
| 7 | `torso_back.png` | **34 × 46** | `(0, -20)` | 颈 `(17, 4)`、肩 `(7/27, 11)`、髋 `(17, 43)` | `1: 1` | 无（无臂躯干） |
| 8 | `torso_left.png` | **26 × 46** | `(0, -20)` | 颈 `(13, 4)`、肩 `(13, 10)`、髋 `(13, 43)`，面朝左 `-X` | `2/3: 1` | 朝右 (`3`) 水平翻转 |
| 9 | `hair_back_root.png` | **26 × 18** | `(0, 5)` | 挂点 `(13, 4)`（挂于 `Neck (0, -4)`） | `1: 4`；`0/2/3: -1` | 朝右 (`3`) 水平翻转 |
| 10 | `hair_back_tip.png` | **20 × 12** | `(0, 4)` | 挂点 `(10, 2)`（挂于 `HairBack (0, 9)`） | `1: 4`；`0/2/3: -1` | 朝右 (`3`) 水平翻转 |
| 11 | `hair_side.png` | **6 × 12** | `(0, 5)` | 挂点 `(3, 1)`（挂于 `Head (±10, -8)`） | `0: 4` | 仅正面显示，右侧镜像 |
| 12 | `coat_flap_root.png` | **14 × 21** | `(0, 9)` | 挂点 `(7, 1.5)`（挂于 `Torso (±8, -12)`） | 全向 `0` | 右摆镜像；侧面仅显背后单摆 |
| 13 | `coat_flap_tip.png` | **12 × 13** | `(0, 5)` | 挂点 `(6, 1.5)`（挂于 `CoatTail (0, 14)`） | 全向 `0` | 随父摆镜像 |
| 14 | `skirt_hem.png` | **34 × 13** | `(0, 3)` | 挂点 `(17, 3.5)`（挂于 `Torso (0, -2)`） | `0/1: -1` | 侧面隐藏防双裙边 |
| 15 | `thigh.png` | **10 × 33** | `(0, 13)` | 髋 `(5, 3.5)`、膝 `(5, 29.5)` | 正/背 `-3`；侧近 `-2` / 侧远 `-4` | 侧朝右 (`3`) 翻转；正/背按左右外展翻转 |
| 16 | `shin_boot.png` | **14 × 34** | `(0, 14)` | 膝 `(7, 3)`、踝 `(7, 25)`、鞋底 `y = 33`，鞋尖朝左 `-X` | 正/背 `-3`；侧近 `-2` / 侧远 `-4` | 侧朝右 (`3`) 翻转；正/背鞋尖略向外撇 |
| 17 | `gun_case.png` *(可选)* | **18 × 64** | `(0, -6)` | 挂点 `(9, 38)`（挂于 `Torso/BackGear`） | `0: -6`、`1: 7`、`2/3: -2` | **可选额外组件**（仅 `doll_v2` / `mannequin` 使用；后续新角色默认不生成） |
| 18 | `arm_upper.png` | **10 × 20** | `(0, 7)` | 肩 `(5, 3)`、肘 `(5, 17)` | `0: 4`、`1: -2`；侧近 `4` / 侧远 `-3` | 持枪时自动隐藏交由 `WeaponRig2D` |
| 19 | `arm_forearm.png` | **10 × 20** | `(0, 7)` | 肘 `(5, 3)`、腕 `(5, 15)` | `0: 4`、`1: -2`；侧近 `4` / 侧远 `-3` | 持枪时自动隐藏交由 `WeaponRig2D` |

### 3.2 持枪双臂 3 分件（`arm2/*.png`）

贴图方向水平向右（`+X`），由 `WeaponRig2D` 以 `ARM_SCALE = 0.5` 渲染并执行 2-Bone IK：

| # | 文件名 (`arm2/`) | 精确尺寸 `W×H` | 世界渲染尺寸 | `Sprite2D.offset` | 枢轴（图内像素 `(x, y)`） | 说明 |
|---|---|---|---|---|---|---|
| 1 | `upper_arm.png` | **26 × 14** | `13.0 × 7.0 px` | `(13.0, 0)` | 肩 `(4, 7)`、肘 `(21, 7)` | 与 `SUPPORT_UPPER_BASE = 13.0` 严格对齐 |
| 2 | `forearm.png` | **27 × 13** | `13.5 × 6.5 px` | `(13.5, 0)` | 肘 `(4, 6)`、腕 `(22, 6)` | 与 `SUPPORT_FORE_BASE = 13.5` 严格对齐 |
| 3 | `hand.png` | **12 × 10** | `6.0 × 5.0 px` | `(0, 0)` | 握把中心 `(6, 5)` | 自动匹配 4 大持枪模板握把与护木 |

---

## 4. 功能分色体模（`mannequin`）工程图例

- **左肢冷蓝 / 右肢暖橙**：解剖学左侧（`LegL` / `ArmL` / 持枪副手 `SupportPivot`）呈冷蓝，解剖学右侧（`LegR` / `ArmR` / 持枪扳机手 `Pivot`）呈暖橙；360° 转向时近/远景压暗与左右位置严格保持 3D 一致，绝不混淆或顺拐。
- **高对比关节圆心**：主枢轴（髋/肩/颈/踝/腕）为纯红 `#ff2a2a`，铰链枢轴（膝/肘）为纯黄 `#ffe420`，运行期着色跳过高饱和像素以保证圆心清晰可读。
- **朝向与眨眼标**：躯干正面为金中线 + 青绿 `V` 标、背面为暗灰脊柱 + 珊瑚红 `X` 标、侧面为胸前青绿箭头；头模带深色面罩视线标，眨眼层以亮黄/洋红横条高亮验证。
- **软结构与背挂**：头发/衣摆/裙摆用半透明青色占位片，枪盒用深灰框体，便于直观验收弹簧滞后与 `z_index` 前后遮挡。

---

## 5. 角色额外组件显隐接口与光照防过曝规范

### 5.1 额外组件显隐接口（`Doll2D` / `DollRigV2`）

为支持后续背挂、战术护甲、独立背包、衣摆与副发等部件化装备/换装，`DollRigV2` 与 `Doll2D` 统一暴露以下运行期接口：

- 支持组件键（`DollRigV2.EXTRA_COMPONENT_KEYS`）：
  - `&"back_gear"`：背后战术挂件总控（含皮肤自带 `gun_case` 与 `BackpackSlot`）
  - `&"backpack"`：独立外挂背包槽（`Torso/BackGear/BackpackSlot`）
  - `&"armor"`：胸甲/护甲外观挂点（`Torso/ArmorSlot`）
  - `&"coat_flaps"`：左右弹簧衣摆（`CoatTailL/R`）
  - `&"hair_secondary"`：动态后发与鬓发（`HairBack` / `HairSideL/R`）
- 清单默认声明：在 `skin_manifest.json` 中通过 `"extra_components_default": {"back_gear": false, ...}` 声明皮肤默认显隐；切换皮肤时自动重载默认态。
- 运行期控制 API：
  - `set_extra_component_visible(component_id: StringName, enabled: bool) -> bool`
  - `is_extra_component_visible(component_id: StringName) -> bool`
  - `set_extra_components(overrides: Dictionary) -> void`
  - `clear_extra_component_overrides() -> void`
  - `get_extra_components() -> Dictionary`
  - `has_extra_component_asset(component_id: StringName) -> bool`

### 5.2 实机光照防过曝

- `VisionFog2D` 的贴身角色补光 `player_self_light` 默认关闭（可在「设置 → 光学与特效 → 角色贴身补光」手动开启）；
- `DollRigV2.get_player_light_material()` 挂载防过曝 `ShaderMaterial` 到角色画布、持枪双臂与武器贴图，压制多重 `PointLight2D` 叠加增益，避免银白发/白裙等高明度皮肤被过曝成纯白。

---

## 6. 新角色换皮步骤（零改代码）

1. 准备新角色的静态正/背/侧立绘（推荐单一锁定 32–48 色板 + 1px 暗描边）。
2. 新建目录 `assets/art/characters/<new_skin_id>/parts/` 与 `arm2/`，按第 3 节精确 `W×H` 与关节枢轴裁切导出 **18 核心分件 + 3 arm2** 透明 PNG（默认**不生成** `gun_case.png` 背包，可使用 `tools/build_doll_thistle_parts.py` + `tools/skin_part_helpers.py` 作为裁剪管线模板）。
3. 在 `skin_manifest.json` 中配置 `skin_id`、`color_coding.limb_side_coloring = false` 与 `extra_components_default`（默认 `back_gear = false`）。
4. 运行 `Godot --headless --path . --import` 导入新贴图，再用 `-- --skin=<new_skin_id>` 启动实机或录屏验收即可。
