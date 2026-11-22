extends RefCounted
class_name SpreadModel

## 2D 散布与连发累积纯计算模型（无节点依赖、无全局状态）：
## 集中管理腰射/开镜散布、配件按弹种缩放、后坐撑开散布、首发收紧与连发增减公式，
## 供 Main2D 与自动化测试共用。

const MIN_SPREAD := 0.004
## 首发散布窗口（秒）：停火超过该时长后的第一发按武器 first_shot_spread_mul 收紧。
const FIRST_SHOT_WINDOW := 0.25
## 连发累积：开镜（ADS）时每发增长更慢；换弹/切枪期间回落更快。
const BURST_ADS_GROWTH_MUL := 0.55
const BURST_RECOVERY_BUSY_MUL := 1.8


## 累积后坐力带来的额外散布（弧度）：后坐越接近武器上限，弹着锥撑得越大。
static func recoil_spread(weapon_data: WeaponData, recoil_offset: Vector2) -> float:
	if weapon_data == null:
		return 0.0
	var cap := Vector2(
		weapon_data.recoil_max_horizontal, weapon_data.recoil_max_vertical).length()
	if cap <= 1.0:
		return 0.0
	return weapon_data.spread_max * weapon_data.recoil_spread_mul \
		* clampf(recoil_offset.length() / cap, 0.0, 1.0)


## 计算当前瞄准全锥角（弧度）：
## S0 = ammo.spread + weapon.base_spread + burst_spread + recoil_spread
## S  = max(S0, 0.004) * lerp(1, rig_spread_mul, ammo.attachment_spread_scale)
##      * debug_spread_mul * lerp(1, ammo.ads_spread_mul, ads_t) * talent_accuracy
static func compute_aim_spread(ammo: AmmoData, weapon_data: WeaponData,
		burst_spread: float, recoil_offset: Vector2,
		rig_spread_mul: float = 1.0, has_rig: bool = true,
		debug_spread_mul: float = 1.0, ads_t: float = 0.0,
		talent_accuracy: float = 1.0) -> float:
	var ammo_spread := float(ammo.spread) if ammo != null else 0.0
	var base := float(weapon_data.base_spread) if weapon_data != null else 0.0
	var rec_spread := recoil_spread(weapon_data, recoil_offset)
	var spread := maxf(ammo_spread + base + burst_spread + rec_spread, MIN_SPREAD)
	if has_rig and ammo != null:
		var attach := clampf(float(ammo.attachment_spread_scale), 0.0, 1.0)
		spread *= lerpf(1.0, rig_spread_mul, attach)
	spread *= debug_spread_mul
	var ads_mul := clampf(float(ammo.ads_spread_mul), 0.05, 1.0) if ammo != null else 1.0
	return spread * lerpf(1.0, ads_mul, ads_t) * talent_accuracy


## 全锥角均匀采样：返回 [-spread/2, +spread/2] 内的偏角（弧度）。
static func sample_offset(spread: float) -> float:
	return randf_range(-spread * 0.5, spread * 0.5)


## 停火间隔是否满足首发收紧窗口。
static func is_first_shot(shot_clock: float, last_shot_time: float,
		window: float = FIRST_SHOT_WINDOW) -> bool:
	return shot_clock - last_shot_time >= window


## 对首发应用武器 first_shot_spread_mul 收紧。
static func apply_first_shot(spread: float, weapon_data: WeaponData,
		first_shot: bool) -> float:
	if first_shot and weapon_data != null:
		return spread * weapon_data.first_shot_spread_mul
	return spread


## 每扣一次扳机后的连发散布累积（开镜增长乘 BURST_ADS_GROWTH_MUL，夹至 spread_max）。
static func next_burst_spread(current: float, weapon_data: WeaponData,
		is_ads: bool) -> float:
	if weapon_data == null or weapon_data.spread_growth <= 0.0:
		return current
	var growth := weapon_data.spread_growth
	if is_ads:
		growth *= BURST_ADS_GROWTH_MUL
	return minf(current + growth, maxf(weapon_data.spread_max, 0.0))


## 逐帧连发散布回落（换弹/切枪期间按 BURST_RECOVERY_BUSY_MUL 加速回落）。
static func recover_burst_spread(current: float, weapon_data: WeaponData,
		is_busy: bool, delta: float) -> float:
	if weapon_data == null or current <= 0.0:
		return 0.0
	var recovery := maxf(weapon_data.spread_recovery, 0.0)
	if is_busy:
		recovery *= BURST_RECOVERY_BUSY_MUL
	return maxf(current - recovery * delta, 0.0)
