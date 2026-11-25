extends Resource
class_name WeaponData
## 武器基础数据。先用代码库生成，后续可改成 .tres。
## visual_path / grip_px / muzzle_px / visual_length 由 assets/art/weapons/<id>/meta.json 覆盖。

@export var id: StringName = &"m870"
@export var slot: int = 1
@export var category: StringName = &"shotgun"
@export var display_name: String = "M870 // 12 GAUGE"
@export var caliber: StringName = &"12gauge"
## 面板口径短标与默认弹种；ammo_id 决定使用哪条弹药数据。
@export var caliber_label: String = "12 GAUGE"
@export var ammo_id: StringName = &"buckshot"
## 通用弹药种类：同类弹药共享备弹（light / medium / heavy / shotgun / special）。
@export var ammo_category: StringName = &"shotgun"
## 开火音色与屏幕抖动（霰弹/手枪/冲锋枪/步枪/狙击）。
@export var sfx_kind: String = "shotgun"
@export var shake_amount: float = 2.4
## 抖动风格：shake_roll 是镜头旋转幅度（度），shake_decay 是衰减速度（越大收得越快）。
@export var shake_roll: float = 0.2
@export var shake_decay: float = 32.0
## 停止力：每颗弹丸命中时给敌人的击退速度（像素/秒）。
@export var knockback: float = 40.0
## 武器固有属性加成（Phase 3B）：解决同口径武器共用弹药时缺乏定位差异的问题。
@export var damage_mul: float = 1.0
@export var ap_bonus: float = 0.0
@export var weakspot_mul: float = 1.0
@export var mag_capacity: int = 5
@export var chamber_size: int = 1
@export var fire_interval: float = 0.28
@export var pump_time: float = 0.35
@export var load_time: float = 0.30
## 基础开镜耗时（秒）：手枪最快，狙击最慢；由 WeaponStatsModel 叠加配件后驱动举枪与镜头/散布。
@export var ads_time: float = 0.24
@export var range_m: float = 28.0
@export var base_spread: float = 0.0
## 该武器的现实枪口初速（m/s），已包含弹种基准与枪管长度差异。
@export var bullet_speed_mps: float = 400.0
## 连发散布累积：每发增加量 / 上限 / 停火后每秒回落量（弧度）。
@export var spread_growth: float = 0.006
@export var spread_max: float = 0.06
@export var spread_recovery: float = 0.40
## 后坐力：垂直/水平分别为每发上跳与左右摆动的像素量；上限控制累计封顶。
@export var recoil_vertical: float = 10.0
@export var recoil_horizontal: float = 6.0
@export var recoil_max_vertical: float = 110.0
@export var recoil_max_horizontal: float = 72.0
@export var recoil_spread_mul: float = 1.9
## 首发散布乘数：停火超过窗口后的第一发按此倍率收紧（1.0 = 不收紧）。
@export var first_shot_spread_mul: float = 0.35
@export var sound_radius: float = 32.0

## 供弹方式
@export var auto_cycle: bool = false        # true=半自动自动上膛，false=需手动泵动
@export var feed_mode: StringName = &"shell" # shell=逐发压入管仓，mag=整匣更换
## 图形化弹药容器样式（curved_mag / stick_mag / tube / cylinder / top_mag / drum / box）与加长比例。
@export var mag_style: StringName = &"stick_mag"
@export var mag_scale: float = 1.0
## 全自动射击：由「全自动改件」写入，按住左键持续开火。
@export var auto_fire: bool = false
## 武器自带全自动（如 G18 / AKM），改件只在基础上追加。
@export var default_auto_fire: bool = false

# 3D 低模武器（程序化构建，见 WeaponModel.gd）
@export var model_kind: StringName = &"m870"
@export var visual_length := 0.98

# 旧 2D 贴图字段（保留兼容，3D 模型方案不再使用）
@export var visual_path: String = ""
@export var grip_px := Vector2.ZERO
@export var muzzle_px := Vector2.ZERO


## 返回当前武器数据的独立副本，供运行期叠加配件属性时避免原地污染基础模板。
func clone() -> WeaponData:
	return duplicate() as WeaponData
