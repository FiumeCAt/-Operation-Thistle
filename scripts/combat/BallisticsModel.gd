extends RefCounted
class_name BallisticsModel

## 2D 弹道纯计算模型（无节点依赖、无全局状态）：
## 集中管理射程换算、武器/弹药初速优先级、时间压缩、指数空气阻力衰减与理论飞行时间，
## 统一使用 GameUnits.PIXELS_PER_METER（64 px/m），供 Main2D 与自动化测试共用。

const UNITS := preload("res://scripts/core/GameUnits.gd")
const DEFAULT_RANGE_M := 20.0
const FALLBACK_SPEED_PX_S := 6000.0
## Phase 4 轻量伪 3D 子弹落点阈值：仅在近中距空地（1.5m ~ 12m）且非瞄敌/非预判走廊时自然斜降触地。
const GROUND_AIM_MIN_DIST_PX := 96.0
const GROUND_AIM_MAX_DIST_PX := 768.0
const FLAT_AIM_CURSOR_PAD_PX := 96.0
const FLAT_AIM_RAY_CORRIDOR_PX := 110.0
const FLAT_AIM_LEAD_PAD_PX := 148.0


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


## Phase 4 轻量伪 3D 子弹高度判定（纯计算，无节点依赖）：
##   - 瞄准敌人、位于瞄准射线走廊内、或位于移动敌人提前量预判路径附近 → 保持平射（vz_per_px = 0），绝不截断预判提前量；
##   - 瞄准超近身（< 1.5m）或远距架枪（> 12m）空地 → 保持平射；
##   - 瞄准近中距纯空地（1.5m ~ 12m）→ 从枪口高度 z=1.0 自然斜降并在准心附近触地扬尘。
static func compute_pseudo3d_profile(origin: Vector2, aim_target: Vector2, aim_dir: Vector2,
		max_range_px: float, speed_px_s: float, enemies_info: Array) -> Dictionary:
	var dir := aim_dir.normalized() if aim_dir.length_squared() > 0.0001 else Vector2.RIGHT
	var aim_dist := origin.distance_to(aim_target)
	if aim_dist < GROUND_AIM_MIN_DIST_PX or aim_dist > minf(GROUND_AIM_MAX_DIST_PX, max_range_px):
		return {"flat_shot": true, "z_start": 1.0, "vz_per_px": 0.0, "ground_dist_px": -1.0}
	for item in enemies_info:
		if not (item is Dictionary):
			continue
		var e_pos: Vector2 = item.get("pos", Vector2.ZERO)
		var e_body: Vector2 = item.get("body", e_pos)
		var e_vel: Vector2 = item.get("vel", Vector2.ZERO)
		var e_rad := maxf(float(item.get("radius", 18.0)), 12.0)
		# 1) 光标直接瞄准或贴近敌人（含身体与弱点区）
		var cursor_pad := maxf(e_rad + FLAT_AIM_CURSOR_PAD_PX, 128.0)
		if aim_target.distance_to(e_body) <= cursor_pad or aim_target.distance_to(e_pos) <= cursor_pad:
			return {"flat_shot": true, "z_start": 1.0, "vz_per_px": 0.0, "ground_dist_px": -1.0}
		# 2) 敌人位于射线走廊内（确保打穿近空地直奔后方敌人时永不提前砸地）
		var to_e := e_body - origin
		var proj := to_e.dot(dir)
		if proj >= -32.0 and proj <= max_range_px + 64.0:
			var perp := (to_e - dir * proj).length()
			if perp <= maxf(e_rad + 80.0, FLAT_AIM_RAY_CORRIDOR_PX):
				return {"flat_shot": true, "z_start": 1.0, "vz_per_px": 0.0, "ground_dist_px": -1.0}
		# 3) 移动敌人提前量预判保护：瞄准敌人在飞行时间内的预判走位路径时强制平射
		if e_vel.length() > 8.0:
			var est_dist := maxf(maxf(proj, origin.distance_to(e_body)), aim_dist)
			var t_flight := clampf(est_dist / maxf(speed_px_s, 120.0), 0.05, 1.30)
			var lead_end := e_body + e_vel * clampf(t_flight * 1.35, 0.28, 1.50)
			var closest := Geometry2D.get_closest_point_to_segment(aim_target, e_body, lead_end)
			if aim_target.distance_to(closest) <= maxf(e_rad + FLAT_AIM_LEAD_PAD_PX, 180.0):
				return {"flat_shot": true, "z_start": 1.0, "vz_per_px": 0.0, "ground_dist_px": -1.0}
			var pred_body := e_body + e_vel * t_flight
			var to_pred := pred_body - origin
			var pred_proj := to_pred.dot(dir)
			if pred_proj > 0.0 and pred_proj <= max_range_px + 96.0:
				var pred_perp := (to_pred - dir * pred_proj).length()
				if pred_perp <= maxf(e_rad + 120.0, 150.0):
					return {"flat_shot": true, "z_start": 1.0, "vz_per_px": 0.0, "ground_dist_px": -1.0}
	return {
		"flat_shot": false,
		"z_start": 1.0,
		"vz_per_px": -1.0 / maxf(aim_dist, 1.0),
		"ground_dist_px": aim_dist,
	}
