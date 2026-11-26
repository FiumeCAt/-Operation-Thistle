# Phase 7A：主角像素规格验证（`64px×2` vs `128px×1`）与模块化持枪骨骼定型方案

> 本文档为《蓟花行动 / Operation Thistle》Phase 7A 决策与工程规格书，配套实机同屏对比脚本、像素化批处理管线 [pixel_char_pipeline.py](file:///D:/AI%20Game/HellWalker/HellWalker_DollProtocol/tools/pixel_char_pipeline.py) 与 4 大持枪姿态模板（已落地至 [WeaponPoseIK2D.gd](file:///D:/AI%20Game/HellWalker/HellWalker_DollProtocol/scripts/weapons/WeaponPoseIK2D.gd) / [WeaponRig2D.gd](file:///D:/AI%20Game/HellWalker/HellWalker_DollProtocol/scripts/weapons/WeaponRig2D.gd)）。  
> **Phase 7B 启动门槛**：请审阅文末两项勾选（像素规格二选一 + 角色参考图确认）后，即可一次性进入 Seedream 5.5 母版生成与全套正式动画替换。

---

## 一、全项目现存资产像素密度（Texels / World-Px）实测审计

统一世界标尺由 [GameUnits.gd](file:///D:/AI%20Game/HellWalker/HellWalker_DollProtocol/scripts/core/GameUnits.gd) 定义：`1 米 = 1 格 = 64 px`，默认主角逻辑身高 `WORLD_BODY = 128 px`（2 格）。

| 资产类别 | 代表文件 | 原图尺寸 | 世界渲染尺寸 | 像素密度（纹素 / 世界像素） | 视觉观感 |
| :--- | :--- | :---: | :---: | :---: | :--- |
| 地面砖格 | `assets/art/env/pixel_floor_256.png` | `256×256`（4×4 格） | `256×256` | **`1.00×`** | 严格 1:1 清晰像素格 |
| 场景道具 | `pixel_barrel_40` / `crate_48` / `shelf_128` | `40~128 px` | `40~128 px` | **`1.00×`** | 严格 1:1 清晰像素格 |
| 人形/机械敌人 | `rifleman/heavy/dinergate.png` (`256×384`) | `384 px` 高 | `108~130 px` | `2.95~3.30×` | 高精细节微缩像素 |
| 新四台动画敌人 | `hunter_type1_anim_sheet.png` 等 | `512 px` 帧 | `~128 px` | `~3.0×` | 高精细节微缩像素 |
| 18 把枪械侧视图 | `assets/art/weapons/*/side.png` | `720~1382 px` | `36~78 px` | `>2.0×` | 高精枪械剪影 |
| **主角（旧版基准）** | `doll_lod_256_body/head.png` | `256 px` 身 / `320` 帧 | `128 px` | `2.00×` | 半平滑微缩，略缺像素颗粒 |
| **方案 A：`64px×2`** | `doll_lod_64.png`（本阶段样稿） | **`64 px` 身 / `80` 帧** | `128 px`（`×2`） | **`0.50×`** | 强复古 2×2 粗颗粒像素 |
| **方案 B：`128px×1`** | `doll_lod_128.png`（本阶段样稿） | **`128 px` 身 / `160` 帧** | `128 px`（`×1`） | **`1.00×`** | 与地面/道具完全 1:1 同密 |

---

## 二、`64px×2` vs `128px×1` 实机对比与选型结论

> **工程硬红线**：必须二选一锁死**单一像素规格**，严禁同时维护双规格（避免双倍美术返工与不同密度拼贴导致的 Mixels 视觉割裂）。

| 对比维度 | 方案 A：`64px×2`（单帧 `80×80`，`scale = 2.0`） | 方案 B：`128px×1`（单帧 `160×160`，`scale = 1.0`）⭐ 推荐 |
| :--- | :--- | :--- |
| **与地面/道具一致性** | 主角像素块是地砖/箱子的 **2 倍大**（轻度 Mixels 割裂，尤其 2× 镜头放大时明显） | **严格 1:1 同密**，像素颗粒与地砖/掩体/UI 边框完全契合 |
| **与现有敌人/武器融合** | 敌人和枪械细节远高于主角，手里的枪在 64px 躯干上容易显得“过于高清/画风跳戏” | 细节阶梯平滑过渡，手持 18 把枪械（含配件/瞄具）观感自然融洽 |
| **人物五官/服饰识别度** | 头部仅约 `14×14 px`，发饰/战术装备/面容较抽象，偏复古街机风 | 头部约 `28×28 px`，发型/瞳色/衣领/战术胸挂清晰锐利，保留强二次元战术辨识度 |
| **单张 24 行全动作图集体积** | `320×1920 px`（极小，~180 KB） | `640×3840 px`（轻量，~550 KB，显存与加载开销微乎其微） |
| **Seedream 5.5 下采样保真** | 下采样幅度过大，细发丝与衣摆易糊成色块，需更多人工手修 | 1024px 母版 8:1 规则盒式下采样，发丝、外套折痕与战术背带完整保留 |
| **实机对比截图** | 见 `D:\AI Game\HellWalker\captures\screenshots\phase7a_01_spec_ab_fullscene.png` 与 `phase7a_02_spec_ab_closeup.png` | 同左（中位样稿） |

**推荐结论**：优先锁死 **方案 B：`128px×1`（单帧 `160×160`，48 色锁定色板 + 1px 选择性暗轮廓）**；若你更偏好《迈阿密热线 / 挺进地牢》式的强复古大颗粒像素感，也可直接拍板锁死 **方案 A：`64px×2`（单帧 `80×80`，32 色锁定色板）**，管线已完全就绪。

---

## 三、骨架方案定型：混合图集身躯 + 解耦双臂 IK 武器层（彻底杜绝“剪纸木偶感”）

经过对比现存纯分件骨架 [DollRig2D.gd](file:///D:/AI%20Game/HellWalker/HellWalker_DollProtocol/scripts/actors/DollRig2D.gd) 与混合持枪架构 [Doll2D.gd](file:///D:/AI%20Game/HellWalker/HellWalker_DollProtocol/scripts/actors/Doll2D.gd) + [WeaponRig2D.gd](file:///D:/AI%20Game/HellWalker/HellWalker_DollProtocol/scripts/weapons/WeaponRig2D.gd)，Phase 7 正式采用 **「像素逐帧身躯图集 + 解耦双臂 IK 武器层」混合方案**：

1. **为什么否决纯分件木偶骨架（`DollRig2D`）**：
   - 纯 2D 刚体旋转分件在旋转手脚/头部时会暴露像素旋转锯齿、颈部/髋部接缝、以及衣摆/长发僵硬的“Flash 剪纸木偶感”。
2. **混合方案结构**：
   - **主体层（`Doll2D.Body` 整身无持枪双臂或收臂图集）**：统一 **4 列 × 24 行** 标准图集契约（已写入 `Doll2D.ANIM_BLOCKS`，100% 向下兼容旧 16 行图集）：
     - `Row 0–3`：`idle_0..3`（下 / 上 / 左 / 右 站立呼吸）
     - `Row 4–7`：`walk_0..3`（4 向战术行走）
     - `Row 8–11`：`run_0..3`（4 向冲刺前倾）
     - `Row 12–15`：`aim_0..3`（4 向举枪稳定躯干底架）
     - `Row 16–19`：`hurt_0..3`（4 向受击后仰，不循环，12 FPS）
     - `Row 20–23`：`dodge_0..3`（4 向 Phase 5 战术翻滚正式动画，不循环，13.3 FPS；加载 24 行图集时自动替代占位压缩旋转）
   - **持枪臂与武器层（`WeaponRig2D` + `WeaponPoseIK2D`）**：
     - 保持 360° 丝滑鼠标瞄准、左右镜像不倒置、背后/前景 `z_index` 自动遮挡、后坐力回弹、换弹掉匣插匣与 4 大标准持枪模板；
     - Phase 7B 重绘主角时同步替换 `assets/art/characters/<char>/parts/arm2/{upper_arm,forearm,hand}.png`（与新主角衣袖/手套配色完全一致）。

---

## 四、4 大标准持枪/瞄准姿态模板（已实装落地）

已在 [WeaponPoseIK2D.gd](file:///D:/AI%20Game/HellWalker/HellWalker_DollProtocol/scripts/weapons/WeaponPoseIK2D.gd) (`STANCE_TEMPLATES`) 与 [WeaponRig2D.gd](file:///D:/AI%20Game/HellWalker/HellWalker_DollProtocol/scripts/weapons/WeaponRig2D.gd) 完成 6 类武器 → 4 大标准模板的解耦映射与实时插值：

| 模板 ID | 涵盖武器 | 腰射臂长 | ADS 臂长 | ADS 抬枪 | 支撑手 / 护木比例 | 冲刺压枪 | 动作特征 |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :--- |
| **`pistol`** | `G17` / `G18` / `M1911` / `FN57` / `Python` | `22.4` | `17.8` | `+4.4 px` | 关闭（单/双紧凑） | `2.2 px` | 韦弗式紧凑敏捷持枪，举枪快、后坐跳动干脆 |
| **`smg`** | `TMP` / `UMP45` / `MP7` / `P90` | `21.8` | `17.0` | `+4.8 px` | 开启 · `0.16` | `2.6 px` | 胸前贴近 CQB 收紧姿态，短护木近托 |
| **`rifle`** | `AKM` / `L85A2` / `FAL` / `M870` / `M1014` / `Saiga12K` | `22.8` | `18.0` | `+5.4 px` | 开启 · `0.21` | `3.2 px` | 标准战术抵肩、中段护木托举与贴腮瞄准 |
| **`sniper`** | `SR25` / `VSS` / `AWM` | `23.4` | `16.6` | `+6.2 px` | 开启 · `0.27` | `4.0 px` | 长枪托深度抵肩、前探护木支撑与高倍率镜轴抬升 |

---

## 五、Seedream 5.5 生产管线规范（Phase 7B 标准作业流程）

严禁让文生图模型一次直接生成 64/96 帧小图（会导致角色脸型、服饰与比例严重漂移闪烁）。标准流程如下：

1. **Step 1 — 参考一致性母版（Seedream 5.5 图生图 / 角色参考）**：
   - 输入用户提供的主角参考立绘（如现有 `assets/art/concepts/angelia_3view.png` 或新提供参考图），用 [gen_seedream.py](file:///D:/AI%20Game/HellWalker/HellWalker_DollProtocol/tools/gen_seedream.py) 生成透明底 `2K` 正/背/左/右四向标准立绘母版，固定光照方向（顶部偏左柔光）、2.5D 俯斜视角（约 30° 俯角，与现有地图/敌人一致）与无持枪自然垂臂/收臂躯干。
2. **Step 2 — 分组动作关键帧生成（每批仅 4 帧同向）**：
   - 按「单方向 × 4 帧」（`walk` 接触-下沉-经过-抬脚、`run` 前倾步幅、`hurt` 受击后仰、`dodge` 翻滚起势-团身-滚过-起身）分批参考母版生成高清帧，保证每批角色身高、发色与装备 100% 锁定。
3. **Step 3 — 程序化像素格下采样 + 全局锁定色板 + 轮廓清理**：
   - 统一经 [pixel_char_pipeline.py](file:///D:/AI%20Game/HellWalker/HellWalker_DollProtocol/tools/pixel_char_pipeline.py) 执行：
     - 预乘 Alpha 盒式下采样至锁定规格（`128px` 或 `64px`）→ 硬透明二值化（零半透明脏边）→ 去孤立噪点 → 全图集提取**单一锁定色板**（`48` 色或 `32` 色，杜绝帧间色彩闪烁）→ 1px 选择性暗色轮廓（`sel-out`）→ 严格脚底基线对齐（`FEET_RATIO = 0.95`）打包为 24 行标准图集。
4. **Step 4 — 实机验收**：
   - 导出主角图集与配套衣袖手臂 `arm2`，进入 `Main2D` 实拍 4 向行走/冲刺、4 大武器持姿与翻滚连拍帧验收。

---

## 六、进入 Phase 7B 前的用户确认清单

请查看本次生成的 3 张实机同屏对比截图后，回复以下两项即可启动 Phase 7B：

1. **锁死单一像素规格**：选择 **方案 B：`128px×1`（推荐，与地砖/道具/敌人最协调）** 还是 **方案 A：`64px×2`（强复古粗像素风）**？
2. **主角参考图确认**：直接沿用仓库中已有的 [angelia_3view.png](file:///D:/AI%20Game/HellWalker/HellWalker_DollProtocol/assets/art/concepts/angelia_3view.png)（黑红汉风长袍/发饰战术化，或原样还原）作为主角母版，还是你会提供另一张新的主角参考图？
