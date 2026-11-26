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

## 三、骨架方案定型（已修订）：Modular Doll Rig v2（模块化像素骨骼 + 次级物理飘动 + 统一像素光栅化）

经 Phase 7 规格复核，最终**放弃纯整身 24 行逐帧图集与旧版僵硬单节木棍 `DollRig2D`**，正式定型为参考《Zed Zone / 末日地带》纸娃娃模块化思路并针对战术人偶升级的 **Modular Doll Rig v2**（像素规格锁死 **`128px×1`**，画布 `160×160`）：

1. **纸娃娃模块化分层（预留未来换装/护甲槽位）**：
   - `Shadow`：脚底软像素阴影，随迈步抬脚高度与翻滚腾空实时缩放；
   - `Legs`：**左/右二段式关节（大腿 `Thigh` + 小腿/靴 `Shin`）**，带真实屈膝步态循环（静止 / 行走 / 冲刺 / 侧步 / 倒退走），踩实帧触发轻脚步扬尘；
   - `Torso`：上身躯干/藏蓝外套主体 + 预留 `ArmorSlot`（未来护甲/胸挂外观挂点）；
   - `BackGear`：背后战术枪盒/挂件，按朝向自动切换躯干前后 `z_index` 遮挡；
   - `Head`：正/背/左/右 4 向头部 + **独立眨眼层 `BlinkLayer`**，颈部做 2–4px 圆角包边重叠，大角度摆头绝不露缝；
   - `SecondaryMotion`（灵动感核心）：拆出 **后发/发梢** 与 **外套左右衣摆/格裙下摆**，挂载 2 节轻量弹簧阻尼物理，随移动加速度、急停惯性、转向、开火后坐与翻滚自然滞后飘动；
   - `Arms + Weapon`：与 `WeaponRig2D` 360° 双臂 IK + 4 大持枪姿态模板深度整合，衣袖/手套配色与主角 100% 统一；收枪时由骨架驱动双臂自然垂摆，持枪时动态跟随躯干呼吸/前倾/后坐肩点，换弹时副手向弹匣井靠拢。
2. **解决旋转“锯齿 / 露缝 / 剪纸木偶感”的核心机制**：
   - 所有旋转零件在关节处制作 **2–4px 圆润重叠包边**；
   - 整套模块化骨骼渲染在独立 **`160×160` 透明 `SubViewport`**（关闭抗锯齿 `MSAA_DISABLED`，显示节点 `RigCanvas` 挂 `TEXTURE_FILTER_NEAREST`、`scale = 1.0`），确保所有旋转四肢、头发与衣摆统一光栅化对齐到世界 1:1 像素格，彻底消除斜向高分锯齿与“剪纸贴图感”，同时完全兼容 `VisionFog2D` 2D 光照、受击闪白与翻滚像素残影。
3. **衔接 Phase 5 翻滚与受击演出**：
   - 受击时上半身短暂后仰闪白并触发发梢/衣摆轻震；
   - 翻滚时驱动骨架执行**下蹲前扑 → 团身前滚（屈膝收枪、发梢衣摆甩动）→ 落地缓冲起身**，彻底替代占位压扁旋转。

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

## 五、Seedream 5.5 模块化分件生产管线（Phase 7B 标准作业流程）

严禁让文生图模型一次直接生成 64/96 帧小图（会导致角色脸型、服饰与比例严重漂移闪烁）。标准流程如下：

1. **Step 1 — 参考图透明三视图预处理**：
   - 将选定主角参考图（`灰蓝猫耳少女三视图设定稿.png`）抠除白底生成透明三视图 `assets/art/characters/doll_v2/source/catgirl_3view_transparent.png`。
2. **Step 2 — Seedream 5.5 图生图生成精修三视图与独立分件母版**：
   - 以透明三视图 + 肖像细节作为参考输入 [gen_seedream.py](file:///D:/AI%20Game/HellWalker/HellWalker_DollProtocol/tools/gen_seedream.py)（`--image` + `--transparent`），生成统一画风、克制赛璐璐阴影、无持枪的高清三视图母版与纸娃娃独立分件母版（4 向头部 + 闭眼眨眼、无臂躯干外套、独立后发/发梢、独立外套下摆/格裙摆、二段式大腿/小腿+球鞋、二段式衣袖手臂与背后枪盒）。
3. **Step 3 — 统一像素格下采样 + 48 色锁定色板 + 关节圆润包边**：
   - 统一经 [build_doll_v2_parts.py](file:///D:/AI%20Game/HellWalker/HellWalker_DollProtocol/tools/build_doll_v2_parts.py) 调用 [pixel_char_pipeline.py](file:///D:/AI%20Game/HellWalker/HellWalker_DollProtocol/tools/pixel_char_pipeline.py)，以 **128px 世界身高**精确缩放所有分件、提取全局 48 色锁定色板、添加 1px 选择性暗色轮廓（`sel-out`）并在髋/膝/肩/肘/颈节点保留 2–4px 圆润重叠包边，输出至 `assets/art/characters/doll_v2/parts/`。
4. **Step 4 — SubViewport 像素光栅化与实机验收**：
   - 在 [DollRigV2.gd](file:///D:/AI%20Game/HellWalker/HellWalker_DollProtocol/scripts/actors/DollRigV2.gd) 内通过 `160×160` 无抗锯齿 `SubViewport` 统一光栅化，实拍多姿态截图与短录屏 GIF 验收灵动度、4 持枪模板融合与翻滚动画。

---

## 六、Phase 7B 锁定配置（已由用户确认）

1. **像素规格锁死**：**方案 B：`128px×1`（单画布 `160×160` SubViewport 统一像素光栅化，48 色锁定色板 + 1px 选择性暗轮廓）**。
2. **主角参考图锁死**：沿用并升级 **灰蓝猫耳少女**（`灰蓝猫耳少女三视图设定稿.png` + 肖像参考），已抠除白底并接入 Seedream 5.5 模块化分件管线。
