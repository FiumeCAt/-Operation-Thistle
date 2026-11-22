extends RefCounted
class_name BallisticsModel

## 2D 弹道纯计算模型（无节点依赖、无全局状态）：
## 集中管理射程换算、武器/弹药初速优先级、时间压缩、指数空气阻力衰减与理论飞行时间，
## 统一使用 GameUnits.PIXELS_PER_METER（64 px/m），供 Main2D 与自动化测试共用。

const UNITS := preload("res://scripts/core/GameUnits.gd")
const DEFAULT_RANGE_M := 20.0
const FALLBACK_SPEED_PX_S := 6000.0


## 武器最大射程（像素）。
static func shot_range_px(weapon_data: WeaponData,
		px_per_m: float = UNITS.PIXELS_PER_METER) -> float:
	var range_m := weapon_data.range_m if weapon_data != null else DEFAULT_RANGE_M
	return range_m * px_per_m


## 实际枪口初速（m/s）：优先武器逐把配置（bullet_speed_mps），缺失时回退弹种默认初速。
static func muzzle_speed_mps(ammo: AmmoData, weapon_data: WeaponData = null) -> float:
	if ammo == null:
		return 0.0
	var real_speed := float(ammo.muzzle_velocity_mps)
	if weapon_data != null and float(weapon_data.bullet_speed_mps) > 0.0:
		real_speed = float(weapon_data.bullet_speed_mps)
	return real_speed


## 游戏内像素初速（px/s）= 真实初速 × bullet_time_scale × px_per_m。
static func bullet_speed_px_s(ammo: AmmoData, weapon_data: WeaponData = null,
		px_per_m: float = UNITS.PIXELS_PER_METER) -> float:
	if ammo == null:
		return FALLBACK_SPEED_PX_S
	var real_speed := muzzle_speed_mps(ammo, weapon_data)
	return maxf(real_speed * float(ammo.bullet_time_scale) * px_per_m, 1.0)


## 每像素阻力系数：drag_per_px = drag_per_m / px_per_m。
static func drag_per_px(ammo: AmmoData,
		px_per_m: float = UNITS.PIXELS_PER_METER) -> float:
	if ammo == null or px_per_m <= 0.0:
		return 0.0
	return maxf(float(ammo.drag_per_m), 0.0) / px_per_m


## 带指数衰减的理论飞行时间（秒）：t = (e^(d·s) - 1) / (v·d)，d 为每米衰减系数。
static func bullet_travel_time(ammo: AmmoData, distance_m: float,
		weapon_data: WeaponData = null,
		px_per_m: float = UNITS.PIXELS_PER_METER) -> float:
	if ammo == null or distance_m <= 0.0:
		return 0.0
	var v := bullet_speed_px_s(ammo, weapon_data, px_per_m) / px_per_m
	var d := maxf(float(ammo.drag_per_m), 0.0)
	if d <= 0.000001:
		return distance_m / v
	return (exp(d * distance_m) - 1.0) / (v * d)


## 飞行 distance_m 米后的瞬时速度：v(s) = v0 * exp(-drag_per_m * s)。
static func speed_after_distance(v0: float, drag_per_m: float,
		distance_m: float) -> float:
	return v0 * exp(-maxf(drag_per_m, 0.0) * maxf(distance_m, 0.0))
