extends RefCounted
class_name CombatSystem2D
## 2D 战斗、开火、散布/后坐力累积、弹丸生成与多弹丸命中聚合子系统。
## 从 Main2D 抽离，复用 SpreadModel / BallisticsModel / PlayerBullet2D。

signal shot_fired(weapon_id: StringName, ammo_id: StringName, pellet_count: int)
signal hit_resolved(target: Node, damage: float, killed: bool, material: String)

const UNITS := preload("res://scripts/core/GameUnits.gd")
const WORLD_PER_METER := UNITS.PIXELS_PER_METER
const SPREAD_MODEL := preload("res://scripts/combat/SpreadModel.gd")
const BALLISTICS_MODEL := preload("res://scripts/combat/BallisticsModel.gd")
const PLAYER_BULLET := preload("res://scripts/fx/PlayerBullet2D.gd")
const HIT_FX := preload("res://scripts/fx/HitFX2D.gd")

const RECOIL_LIMIT := Vector2(52.0, 78.0)
const RECOIL_RECOVER := 95.0
const RECOIL_ADS_MUL := 0.55
const RECOIL_CAM_SCALE := 0.95
const RECOIL_CAM_LIMIT := 26.0
const RECOIL_BUILD_GAIN := 0.55
const RECOIL_ROLL_SCALE := 0.0016
const RECOIL_ROLL_LIMIT := 0.028
const FIRST_SHOT_WINDOW := SPREAD_MODEL.FIRST_SHOT_WINDOW
const BULLET_HIT_BATCH_WINDOW := 0.05
const SHOT_ORIGIN_OFFSET := Vector2(0, -8)

## 本局战斗统计
var shots_fired := 0
var shots_hit := 0
var damage_dealt := 0.0

## 散布 / 后坐力状态
var burst_spread := 0.0
var burst_weapon: StringName = &""
var recoil_offset := Vector2.ZERO
var recoil_cam := Vector2.ZERO
var recoil_roll := 0.0
var recoil_side := 1.0
var shot_clock := 0.0
var last_shot_time := -100.0

## 最近一次射击调试/测试采样
var last_shot_origin := Vector2.ZERO
var last_shot_dir := Vector2.RIGHT
var last_pellet_dirs: Array[Vector2] = []
var last_pellet_spread := 0.0
var last_shot_flat := true
var last_hit_weakspot := false

var _owner: Node2D
var _doll: Doll2D
var _fx_layer: Node2D
var _reticle: AimReticle2D
var _enemies: Array[Enemy2D]
var _is_active_fn: Callable = Callable()
var _ads_t_fn: Callable = Callable()
var _talent_accuracy_fn: Callable = Callable()
var _trail_enabled_fn: Callable = Callable()
var _hit_fx_level_fn: Callable = Callable()
var _muzzle_fx_fn: Callable = Callable()
var _shake_fn: Callable = Callable()
var _hitstop_fn: Callable = Callable()
var _sfx_fn: Callable = Callable()
## 可选手感配置资源（CombatFeelConfig）；缺省时平滑回退上方 const 常量。
var config: Resource


func apply_config(cfg: Resource) -> void:
	config = cfg


func _cfg_float(prop: StringName, fallback: float) -> float:
	if config != null and prop in config:
		return float(config.get(prop))
	return fallback


func setup(owner_node: Node2D, doll: Doll2D, fx_layer: Node2D, reticle: AimReticle2D,
		enemies_ref: Array[Enemy2D], is_active_fn: Callable, ads_t_fn: Callable,
		talent_accuracy_fn: Callable, trail_enabled_fn: Callable,
		hit_fx_level_fn: Callable, muzzle_fx_fn: Callable,
		shake_fn: Callable, hitstop_fn: Callable, sfx_fn: Callable) -> void:
	_owner = owner_node
	_doll = doll
	_fx_layer = fx_layer
	_reticle = reticle
	_enemies = enemies_ref
	_is_active_fn = is_active_fn
	_ads_t_fn = ads_t_fn
	_talent_accuracy_fn = talent_accuracy_fn
	_trail_enabled_fn = trail_enabled_fn
	_hit_fx_level_fn = hit_fx_level_fn
	_muzzle_fx_fn = muzzle_fx_fn
	_shake_fn = shake_fn
	_hitstop_fn = hitstop_fn
	_sfx_fn = sfx_fn


func _is_active() -> bool:
	return bool(_is_active_fn.call()) if _is_active_fn.is_valid() else true


func _ads_t() -> float:
	return float(_ads_t_fn.call()) if _ads_t_fn.is_valid() else 0.0


func _talent_accuracy() -> float:
	return float(_talent_accuracy_fn.call()) if _talent_accuracy_fn.is_valid() else 1.0


func _trail_enabled() -> bool:
	return bool(_trail_enabled_fn.call()) if _trail_enabled_fn.is_valid() else true


func _hit_fx_level() -> int:
	return int(_hit_fx_level_fn.call()) if _hit_fx_level_fn.is_valid() else 1


func _progress_node() -> Node:
	if _owner != null:
		return _owner.get_node_or_null("/root/Progress")
	return null


func update(delta: float) -> void:
	shot_clock += delta
	update_burst_spread(delta)
	recoil_offset = recoil_offset.move_toward(Vector2.ZERO, _cfg_float(&"recoil_recover", RECOIL_RECOVER) * delta)
	recoil_cam = recoil_cam.move_toward(Vector2.ZERO, _cfg_float(&"recoil_cam_recover", 70.0) * delta)
	recoil_roll = move_toward(recoil_roll, 0.0, _cfg_float(&"recoil_roll_recover", 0.16) * delta)


## 射击原点用视觉枪口：弹道、tracer、枪口闪光和准心才能三点一线。
func get_shot_origin() -> Vector2:
	if _doll != null and _doll.weapon_rig != null:
		return _doll.weapon_rig.get_muzzle_position()
	if _doll != null:
		return _doll.global_position + SHOT_ORIGIN_OFFSET
	return Vector2.ZERO


func get_safe_shot_origin(muzzle_override: Vector2 = Vector2.INF) -> Vector2:
	var muzzle: Vector2 = muzzle_override
	if muzzle == Vector2.INF:
		muzzle = get_shot_origin()
	if _doll == null or _owner == null:
		return muzzle
	var center := _doll.global_position + Vector2(0, -34)
	var to_muzzle := muzzle - center
	if to_muzzle.length_squared() < 4.0:
		return muzzle
	var query := PhysicsRayQueryParameters2D.create(center, muzzle, 1)
	query.hit_from_inside = true
	var hit := _owner.get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return muzzle
	var dir := to_muzzle.normalized()
	var point: Vector2 = hit["position"]
	var safe := point - dir * 1.5
	if (safe - center).dot(dir) <= 0.0:
		# 玩家贴在北墙下方时，胸口参考点 (0, -34) 可能落在北墙碰撞体内；
		# 改从必定位于可行走地面的脚底圆心 (0, -6) 向枪口投影，把起射点退回墙面外侧。
		var foot := _doll.global_position + Vector2(0, -6)
		var from_foot := muzzle - foot
		if from_foot.length_squared() >= 4.0:
			var fq := PhysicsRayQueryParameters2D.create(foot, muzzle, 1)
			fq.hit_from_inside = true
			var fhit := _owner.get_world_2d().direct_space_state.intersect_ray(fq)
			if fhit.is_empty():
				return muzzle
			var fdir := from_foot.normalized()
			var fsafe: Vector2 = fhit["position"] - fdir * 1.5
			if (fsafe - foot).dot(fdir) > 0.0:
				return fsafe
			return foot
		return muzzle
	return safe


## 当前后坐力/开火抖动强度倍率：腰射 1.0，开镜逐步降到 recoil_ads_mul。
func recoil_strength() -> float:
	return lerpf(1.0, _cfg_float(&"recoil_ads_mul", RECOIL_ADS_MUL), _ads_t())


## 子弹与激光共用的射击方向：始终从起点指向准心 + 当前后坐力偏移。
func aim_direction_from(origin: Vector2) -> Vector2:
	if _doll == null:
		return Vector2.RIGHT
	var aim := _doll.aim_target + recoil_offset
	if aim.distance_to(origin) < 8.0 and _doll.weapon_rig != null:
		aim = origin + _doll.weapon_rig.get_barrel_direction() * 120.0
	var dir := aim - origin
	if dir.length_squared() < 0.0001:
		return Vector2.RIGHT
	return dir.normalized()


## 两点之间是否有墙/实体遮挡；用于拒绝“只打到探出墙外贴图”的伤害。
func wall_between(origin: Vector2, point: Vector2) -> Dictionary:
	if _owner == null or origin.distance_squared_to(point) < 1.0:
		return {}
	var query := PhysicsRayQueryParameters2D.create(origin, point, 1)
	query.hit_from_inside = true
	return _owner.get_world_2d().direct_space_state.intersect_ray(query)


## 当前弹种：跟随武器装配表里的 ammo 字段，支持全部口径。
func current_ammo() -> AmmoData:
	var table := WeaponDB.ammo_table()
	var data: WeaponData = _doll.weapon_rig.data if (_doll != null and _doll.weapon_rig != null) else null
	if data != null and table.has(data.ammo_id):
		return table[data.ammo_id]
	return table[&"buckshot"]


## 全锥角（弧度）。统一委托 SpreadModel 计算，供准心圆环与开火共用。
func get_aim_spread() -> float:
	var ammo := current_ammo()
	var has_rig := _doll != null and _doll.weapon_rig != null
	var weapon_data: WeaponData = _doll.weapon_rig.data if has_rig else null
	var rig_mul := float(_doll.weapon_rig.spread_mul) if has_rig else 1.0
	var dbg_progress := _progress_node()
	var dbg_mul := float(dbg_progress.debug_mul("spread")) if dbg_progress != null else 1.0
	return SPREAD_MODEL.compute_aim_spread(
		ammo, weapon_data, burst_spread, recoil_offset,
		rig_mul, has_rig, dbg_mul, _ads_t(), _talent_accuracy()
	)


func spread_offset(spread: float) -> float:
	return SPREAD_MODEL.sample_offset(spread)


func add_burst_spread(data: WeaponData) -> void:
	if data == null or data.spread_growth <= 0.0:
		return
	var ads := _doll.ads if _doll != null else false
	burst_spread = SPREAD_MODEL.next_burst_spread(burst_spread, data, ads)
	# 立刻标记当前武器，避免下一帧因 burst_weapon 还是空而把首发累积清掉。
	burst_weapon = data.id


func update_burst_spread(delta: float) -> void:
	var data: WeaponData = _doll.weapon_rig.data if (_doll != null and _doll.weapon_rig != null) else null
	if data == null:
		burst_spread = 0.0
		burst_weapon = &""
		return
	if data.id != burst_weapon:
		burst_spread = 0.0
		burst_weapon = data.id
		return
	burst_spread = SPREAD_MODEL.recover_burst_spread(
		burst_spread, data, _doll.weapon_rig.is_busy(), delta)


## 准心遮挡提示：身体中心到鼠标之间是否有墙。
func get_aim_block() -> Dictionary:
	if _doll == null or _owner == null:
		return {"blocked": false, "point": Vector2.ZERO}
	var origin := get_safe_shot_origin()
	var aim := _doll.aim_target
	if aim.distance_to(origin) < 4.0:
		return {"blocked": false, "point": aim}
	var query := PhysicsRayQueryParameters2D.create(origin, aim, 1)
	query.hit_from_inside = true
	var hit := _owner.get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return {"blocked": false, "point": aim}
	return {"blocked": true, "point": hit["position"]}


func shot_range() -> float:
	var data: WeaponData = _doll.weapon_rig.data if (_doll != null and _doll.weapon_rig != null) else null
	return BALLISTICS_MODEL.shot_range_px(data, WORLD_PER_METER)


func bullet_speed_px_s(ammo: AmmoData, weapon_data: WeaponData = null) -> float:
	return BALLISTICS_MODEL.bullet_speed_px_s(ammo, weapon_data, WORLD_PER_METER)


func bullet_travel_time(ammo: AmmoData, distance_m: float,
		weapon_data: WeaponData = null) -> float:
	return BALLISTICS_MODEL.bullet_travel_time(ammo, distance_m, weapon_data, WORLD_PER_METER)


func trace_pellet(origin: Vector2, direction: Vector2, length: float) -> Dictionary:
	if _owner == null or _doll == null:
		return {}
	var query := PhysicsRayQueryParameters2D.create(
		origin, origin + direction * length, 1 | 2, [_doll.get_rid()])
	query.hit_from_inside = true
	query.collide_with_areas = true
	return _owner.get_world_2d().direct_space_state.intersect_ray(query)


## 按武器口径与弹种计算枪口火光与局部点亮强度：手枪/冲锋枪 0.88~0.96，步枪 1.15，霰弹/大口径狙击 1.38。
static func calc_muzzle_flash_intensity(data: WeaponData, ammo: AmmoData) -> float:
	if data == null:
		return 1.0
	match data.ammo_category:
		&"shotgun":
			return 1.38
		&"heavy":
			return 1.34
		&"medium":
			return 1.15
		&"special":
			return 0.78
		_:
			if ammo != null and ammo.pellets > 1:
				return 1.32
			return 0.92


func on_weapon_fired(muzzle: Vector2, _dir: Vector2) -> void:
	if not _is_active() or _doll == null or _doll.weapon_rig == null:
		return
	var data: WeaponData = _doll.weapon_rig.data
	if data == null:
		return
	var ammo := current_ammo()
	shots_fired += 1
	var origin := get_safe_shot_origin(muzzle)
	# 第一发始终走准心；本发的后坐力在出膛后再累积，避免首发就偏。
	var aim_world := _doll.aim_target + recoil_offset
	var base_dir := aim_direction_from(origin)
	last_shot_origin = origin
	last_shot_dir = base_dir
	last_pellet_dirs.clear()

	var ads_mul := recoil_strength()
	var dbg: Node = _progress_node()
	var dbg_v: float = float(dbg.debug_mul("recoil_v")) if dbg != null else 1.0
	var dbg_h: float = float(dbg.debug_mul("recoil_h")) if dbg != null else 1.0
	var dbg_cap: float = float(dbg.debug_mul("recoil_cap")) if dbg != null else 1.0
	var cap_v: float = maxf(data.recoil_max_vertical * dbg_cap, data.recoil_vertical)
	var cap_h: float = maxf(data.recoil_max_horizontal * dbg_cap, 1.0)
	var build := clampf(absf(recoil_offset.y) / cap_v, 0.0, 1.0)
	var build_gain := _cfg_float(&"recoil_build_gain", RECOIL_BUILD_GAIN)
	var kick_v := data.recoil_vertical * dbg_v * ads_mul \
		* lerpf(1.0, 1.0 + build_gain, build)
	var kick_h := (randf_range(-0.7, 0.7) + recoil_side * 0.3) \
		* data.recoil_horizontal * dbg_h * ads_mul * lerpf(1.0, 1.25, build)
	recoil_side = -recoil_side
	recoil_offset += Vector2(kick_h, -kick_v)
	recoil_offset.x = clampf(recoil_offset.x, -cap_h, cap_h)
	recoil_offset.y = clampf(recoil_offset.y, -cap_v, 14.0)
	recoil_cam += Vector2(kick_h, -kick_v) * _cfg_float(&"recoil_cam_scale", RECOIL_CAM_SCALE)
	recoil_cam = recoil_cam.limit_length(_cfg_float(&"recoil_cam_limit", RECOIL_CAM_LIMIT))
	var roll_limit := _cfg_float(&"recoil_roll_limit", RECOIL_ROLL_LIMIT)
	recoil_roll = clampf(recoil_roll + kick_h * _cfg_float(&"recoil_roll_scale", RECOIL_ROLL_SCALE),
		-roll_limit, roll_limit)

	var suppressed := bool(_doll.weapon_rig.has_suppressor) if _doll.weapon_rig != null else false
	if _muzzle_fx_fn.is_valid():
		var flash_intensity := calc_muzzle_flash_intensity(data, ammo)
		if _muzzle_fx_fn.get_argument_count() >= 4:
			_muzzle_fx_fn.call(muzzle, base_dir.angle(), flash_intensity, suppressed)
		else:
			_muzzle_fx_fn.call(muzzle, base_dir.angle())
	var spread := get_aim_spread()
	var first_shot := SPREAD_MODEL.is_first_shot(shot_clock, last_shot_time, FIRST_SHOT_WINDOW)
	last_shot_time = shot_clock
	var pellet_spread := SPREAD_MODEL.apply_first_shot(spread, data, first_shot)
	last_pellet_spread = pellet_spread
	add_burst_spread(data)
	var length := shot_range()
	var damage_mul: float = _doll.weapon_rig.damage_mul * clampf(float(data.damage_mul), 0.2, 3.0)
	if dbg != null:
		damage_mul *= float(dbg.debug_mul("damage"))
	var effective_ap := maxf(0.0, float(ammo.ap) + float(data.ap_bonus))
	var is_flesh_ammo := ammo.role == &"flesh"
	var speed := bullet_speed_px_s(ammo, data)
	var drag_px := BALLISTICS_MODEL.drag_per_px(ammo, WORLD_PER_METER)

	var enemies_info: Array = []
	for enemy in _enemies:
		if is_instance_valid(enemy) and not enemy._dead and float(enemy.hp) > 0.0:
			enemies_info.append({
				"pos": enemy.global_position,
				"body": enemy.body_center(),
				"vel": enemy.velocity,
				"radius": float(enemy.def.collision_radius),
			})
	var p3d := BALLISTICS_MODEL.compute_pseudo3d_profile(
		origin, aim_world, base_dir, length, speed, enemies_info)
	last_shot_flat = bool(p3d["flat_shot"])

	var pellet_count := maxi(1, ammo.pellets)
	var ctx := {
		"data": data,
		"ap": effective_ap,
		"is_flesh": is_flesh_ammo,
		"weapon_weakspot_mul": clampf(float(data.weakspot_mul), 0.5, 3.0),
		"z_start": float(p3d["z_start"]),
		"vz_per_px": float(p3d["vz_per_px"]),
		"knockback": float(data.knockback),
		"multi": pellet_count > 1,
		"pending": pellet_count,
		"origin": origin,
		"buckets": {},
		"fx_targets": {},
		"first_hit": false,
		"first_kill": false,
		"wall_fx": 0,
		"ground_fx": 0,
		"flush_scheduled": false,
	}
	for i in pellet_count:
		var direction := base_dir.rotated(spread_offset(pellet_spread)).normalized()
		last_pellet_dirs.append(direction)
		var bullet := spawn_player_bullet(origin, direction, speed, drag_px,
			ammo.damage * damage_mul, effective_ap, length, ammo.color, ctx, data.knockback)
		if bullet == null:
			ctx["pending"] = int(ctx["pending"]) - 1

	Shot2D.noise_ring(_fx_layer, muzzle, 240.0, ammo.color)
	for enemy in _enemies:
		if is_instance_valid(enemy):
			enemy.hear_noise(muzzle, data.sound_radius)
	if _shake_fn.is_valid():
		_shake_fn.call(data.shake_amount * ads_mul * lerpf(1.0, 1.35, build),
			data.shake_roll * ads_mul, data.shake_decay)
	if _sfx_fn.is_valid():
		var sfx_kind := data.sfx_kind + "_sup" if suppressed else data.sfx_kind
		var sfx_db := -4.5 if suppressed else -3.0
		_sfx_fn.call(sfx_kind, sfx_db)
	shot_fired.emit(data.id, ammo.id, pellet_count)


## 生成一颗解耦后的玩家弹丸，并接入本系统的命中/结束结算。
func spawn_player_bullet(origin: Vector2, direction: Vector2, speed_px_s: float,
		drag_px: float, dmg: float, pen: float, range_px: float,
		bullet_color: Color, ctx: Dictionary, knock: float) -> PlayerBullet2D:
	var exclude_rid := _doll.get_rid() if _doll != null else RID()
	var bullet := PLAYER_BULLET.create(_fx_layer, {
		"origin": origin,
		"direction": direction,
		"speed_px_s": speed_px_s,
		"drag_per_px": drag_px,
		"damage": dmg,
		"ap": pen,
		"max_distance": range_px,
		"color": bullet_color,
		"shot_ctx": ctx,
		"knockback": knock,
		"exclude_rid": exclude_rid,
		"trail_enabled": _trail_enabled(),
		"wall_check": wall_between,
		"z_start": float(ctx.get("z_start", 1.0)),
		"vz_per_px": float(ctx.get("vz_per_px", 0.0)),
	})
	if bullet != null:
		bullet.enemy_hit.connect(on_bullet_hit_enemy)
		bullet.wall_hit.connect(on_bullet_hit_wall)
		bullet.ground_hit.connect(on_bullet_hit_ground)
		bullet.finished.connect(on_bullet_finished)
	return bullet


func on_bullet_hit_wall(bullet, point: Vector2, dir: Vector2) -> void:
	var ctx: Dictionary = bullet.shot_ctx
	if int(ctx.get("wall_fx", 0)) >= 3:
		return
	ctx["wall_fx"] = int(ctx.get("wall_fx", 0)) + 1
	Shot2D.wall_hit(_fx_layer, point, dir)
	if _owner != null:
		var audio := _owner.get_node_or_null("/root/Sfx")
		if audio != null:
			audio.play_wall_impact(-15.0)


func on_bullet_hit_ground(bullet, point: Vector2, dir: Vector2) -> void:
	var ctx: Dictionary = bullet.shot_ctx
	if int(ctx.get("ground_fx", 0)) >= 3:
		return
	ctx["ground_fx"] = int(ctx.get("ground_fx", 0)) + 1
	Shot2D.ground_dust(_fx_layer, point, dir)
	if _owner != null:
		var audio := _owner.get_node_or_null("/root/Sfx")
		if audio != null and audio.has_method("play_ground_impact"):
			audio.play_ground_impact(-18.0)


func on_bullet_hit_enemy(bullet, target, point: Vector2, dir: Vector2) -> void:
	var ctx: Dictionary = bullet.shot_ctx
	var is_ws := bool(bullet.hit_weakspot) if bullet is PlayerBullet2D else bool(bullet.get("hit_weakspot", false))
	if bool(ctx.get("multi", false)):
		var bucket: Dictionary = ctx["buckets"].get(target, {})
		if bucket.is_empty():
			bucket = {
				"damage": 0.0, "ws_damage": 0.0,
				"point": point, "ws_point": point, "dir": dir, "weakspot": false,
			}
			ctx["buckets"][target] = bucket
		if is_ws:
			bucket["ws_damage"] = float(bucket["ws_damage"]) + float(bullet.damage)
			bucket["ws_point"] = point
			bucket["weakspot"] = true
		else:
			bucket["damage"] = float(bucket["damage"]) + float(bullet.damage)
		_schedule_shot_flush(ctx)
		return
	apply_hit_batch(ctx, target, float(bullet.damage), point, dir, is_ws)


func _schedule_shot_flush(ctx: Dictionary) -> void:
	if bool(ctx.get("flush_scheduled", false)) or _owner == null:
		return
	ctx["flush_scheduled"] = true
	_owner.get_tree().create_timer(BULLET_HIT_BATCH_WINDOW).timeout.connect(
		flush_shot_buckets.bind(ctx))


## 窗口到点或弹丸全部结束时，把同一目标累计的弹丸伤害一次性结算。
func flush_shot_buckets(ctx: Dictionary) -> void:
	ctx["flush_scheduled"] = false
	var buckets: Dictionary = ctx.get("buckets", {})
	if buckets.is_empty():
		return
	for target in buckets.keys():
		var bucket: Dictionary = buckets[target]
		buckets.erase(target)
		if is_instance_valid(target):
			var body_dmg := float(bucket.get("damage", 0.0))
			var ws_dmg := float(bucket.get("ws_damage", 0.0))
			if ws_dmg > 0.0 and body_dmg > 0.0:
				apply_hit_batch(ctx, target, body_dmg, bucket["ws_point"], bucket["dir"], true, ws_dmg)
			elif ws_dmg > 0.0:
				apply_hit_batch(ctx, target, ws_dmg, bucket["ws_point"], bucket["dir"], true)
			else:
				apply_hit_batch(ctx, target, body_dmg, bucket["point"], bucket["dir"], false)


func on_bullet_finished(bullet) -> void:
	var ctx: Dictionary = bullet.shot_ctx
	ctx["pending"] = maxi(0, int(ctx.get("pending", 0)) - 1)
	if int(ctx["pending"]) <= 0:
		flush_shot_buckets(ctx)


func apply_hit_batch(ctx: Dictionary, target, amount: float,
		point: Vector2, dir: Vector2, is_weakspot: bool = false,
		weakspot_amount: float = -1.0) -> void:
	if not _is_active():
		return
	var before := float(target.hp)
	var ap := float(ctx.get("ap", 0.0))
	var impulse := dir * float(ctx.get("knockback", 0.0))
	var is_flesh := bool(ctx.get("is_flesh", false))
	var ws_mul := float(ctx.get("weapon_weakspot_mul", 1.0))
	var any_ws := is_weakspot or weakspot_amount > 0.0
	var dealt := 0.0
	if target is Enemy2D:
		if weakspot_amount > 0.0:
			if amount > 0.0:
				dealt += target.take_damage(amount, ap, impulse * 0.5, is_flesh, false, ws_mul)
			dealt += target.take_damage(weakspot_amount, ap, impulse * 0.5, is_flesh, true, ws_mul)
		else:
			dealt = target.take_damage(amount, ap, impulse, is_flesh, any_ws, ws_mul)
	else:
		var total_in := amount + (weakspot_amount if weakspot_amount > 0.0 else 0.0)
		dealt = target.take_damage(total_in, ap, impulse)
	last_hit_weakspot = any_ws
	damage_dealt += dealt
	var killed := before > 0.0 and float(target.hp) <= 0.0
	var material := "metal"
	var weight := 1.0
	if target.has_method("hit_material"):
		material = String(target.hit_material())
		weight = float(target.hit_weight())
	if not ctx["fx_targets"].has(target):
		ctx["fx_targets"][target] = true
		if _fx_layer != null:
			HIT_FX.enemy_hit(_fx_layer, point, dir, material, weight, killed, _hit_fx_level(), any_ws)
	if _fx_layer != null:
		var tint := DamageNumber2D.WEAKSPOT_COLOR if any_ws else (
			Color(1.0, 0.84, 0.52) if material == "flesh" else Color(1.0, 0.95, 0.72))
		DamageNumber2D.spawn(_fx_layer, point, int(round(dealt)), tint,
			"weakspot" if any_ws else material, killed or any_ws or dealt >= 40.0)
	_shot_hit_feedback(ctx, killed, any_ws)
	hit_resolved.emit(target, dealt, killed, material)


func _shot_hit_feedback(ctx: Dictionary, killed: bool, is_weakspot: bool = false) -> void:
	var data: WeaponData = ctx.get("data")
	if data == null:
		return
	if not bool(ctx.get("first_hit", false)):
		ctx["first_hit"] = true
		shots_hit += 1
		if _reticle != null:
			_reticle.show_hit(is_weakspot)
		if _shake_fn.is_valid():
			var ws_shake := 1.25 if is_weakspot else 1.0
			_shake_fn.call((1.1 + data.shake_amount * 0.35) * ws_shake,
				data.shake_roll * 0.5, data.shake_decay)
		if _hitstop_fn.is_valid():
			_hitstop_fn.call(0.022 + data.shake_amount * 0.012 + (0.03 if killed else 0.0) + (0.015 if is_weakspot else 0.0))
	elif is_weakspot and _reticle != null:
		_reticle.show_hit(true)
	elif killed and not bool(ctx.get("first_kill", false)):
		if _hitstop_fn.is_valid():
			_hitstop_fn.call(0.03)
	if killed and not bool(ctx.get("first_kill", false)):
		ctx["first_kill"] = true
		if _shake_fn.is_valid():
			_shake_fn.call(1.4, maxf(data.shake_roll, 0.2), 26.0)
