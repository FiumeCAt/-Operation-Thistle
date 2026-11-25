extends Resource
class_name AmmoData
## 弹种数据：弹丸数、单丸伤害、散布、穿甲、初始备弹。

@export var id: StringName = &"buckshot"
@export var display_name: String = "鹿弹"
## HUD 用短名（如 9mm / 5.7 / 7.62×39）。
@export var short_name: String = "鹿弹"
## 所属口径（如 12gauge / 9mm / 762nato），决定局内 Q 键可切换的同口径 3 档弹种。
@export var caliber: StringName = &"12gauge"
## 通用弹药种类：light / medium / heavy / shotgun / special。
@export var category: StringName = &"shotgun"
## 弹药定位：flesh（肉伤）/ std（常规）/ ap（穿甲）。
@export var role: StringName = &"std"
## 穿甲档位：0（纯肉伤 T0）~ 6（特穿 T6）。
@export var tier: int = 1
## 每发弹药消耗该通用备弹池的点数（T0-T3 常规/肉伤 1.0，T4-T5 高穿 1.5，T6 顶穿 2.0）。
@export var reserve_cost: float = 1.0
@export var pellets: int = 8
@export var damage: float = 8.0
@export var spread: float = 0.33
## 现实世界常见初速（m/s），用于建立弹种之间的相对速度排序。
@export var muzzle_velocity_mps: float = 400.0
## 游戏时间压缩：游戏内初速 = 真实初速 × 该系数；0.294 对应统一 64 px/m 后维持旧 75.29 px/m 屏幕弹速体感。
@export var bullet_time_scale: float = 0.294
## 每米速度衰减：v(s) = v0 * exp(-drag_per_m * s)，s 为已飞行米数。
@export var drag_per_m: float = 0.005
## 开镜散布收紧系数（1 = 不收，越小越准）；按弹种区分。
@export var ads_spread_mul: float = 0.45
## 配件散布效果的生效比例（0 = 配件不影响散布，1 = 完整生效）。
@export var attachment_spread_scale: float = 1.0
@export var ap: float = 0.0
@export var reserve_max: int = 24
@export var color: Color = Color(1.0, 0.62, 0.25)
