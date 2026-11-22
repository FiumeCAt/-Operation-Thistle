extends Node
class_name PlayerWeapon
## 多武器供弹状态机。
## - M870：泵动，1 发膛内 + 5 发管仓，R 泵动，F 逐发装填
## - M1014：半自动，自动上膛
## - SAIGA-12K / G17：弹匣供弹，R 整匣更换
## 1–4 切换武器；每把武器独立保存膛内/仓内/备弹状态。

signal state_changed
signal weapon_switched(id: StringName)

const AMMO_ORDER := [&"buckshot", &"slug", &"ap_slug"]

var doll: Doll
var weapon: WeaponData
var ammo_table: Dictionary = {}
var reserve: Dictionary = {}
var ammo_type: StringName = &"buckshot"

var weapon_id: StringName = &"m870"
var weapons: Dictionary = {}        # id -> WeaponData
var _saved: Dictionary = {}         # id -> {mag, chamber, reserve, ammo_type}

var chamber := "LOADED"   # LOADED / FIRED / EMPTY
var mag := 0
var fire_cd := 0.0
var cycle_t := 0.0
var load_t := 0.0
var busy_max := 0.0
var shots := 0
var state_text := "READY"
## 枪械成长带来的散布倍率；1.0 为未升级。
var accuracy_multiplier := 1.0
## 枪声波纹的显示节流：连发时不叠加多圈扩散。
var _wave_t := 0.0

var _pending_cycle := false
var _pending_load := 0
var last_shot: Dictionary = {}

func _ready() -> void:
	doll = get_parent() as Doll
	ammo_table = WeaponDB.ammo_table()
	for id in WeaponDB.WEAPON_ORDER:
		var w := WeaponDB.get_weapon(id)
		weapons[id] = w
		var r := {}
		for a in _ammo_order(id):
			r[a] = (ammo_table[a] as AmmoData).reserve_max
		_saved[id] = {
			"mag": w.mag_capacity,
			"chamber": "LOADED" if w.chamber_size > 0 else "EMPTY",
			"reserve": r,
			"ammo_type": _ammo_order(id)[0],
		}
	_select(&"m870")
	var progress := get_node_or_null("/root/Progress")
	if progress:
		var loadout: Dictionary = progress.data.get("loadout", {})
		var saved_weapon := StringName(loadout.get("weapon", "m870"))
		var saved_ammo := StringName(loadout.get("ammo", "buckshot"))
		if weapons.has(saved_weapon):
			_select(saved_weapon)
		if _ammo_order(weapon_id).has(saved_ammo):
			ammo_type = saved_ammo

func _ammo_order(id: StringName) -> Array:
	return [&"9mm"] if id == &"g17" else AMMO_ORDER

# ---------------------------------------------------------------- 切换武器

func switch_to(id: StringName) -> void:
	if not weapons.has(id) or id == weapon_id:
		return
	_save_current()
	weapon_id = id
	weapon = weapons[id]
	var st: Dictionary = _saved[id]
	mag = int(st["mag"])
	chamber = String(st["chamber"])
	reserve = st["reserve"]
	ammo_type = st["ammo_type"]
	cycle_t = float(st.get("cycle_t", 0.0))
	load_t = float(st.get("load_t", 0.0))
	fire_cd = float(st.get("fire_cd", 0.0))
	busy_max = float(st.get("busy_max", 0.0))
	_pending_cycle = bool(st.get("pending_cycle", false))
	_pending_load = int(st.get("pending_load", 0))
	_update_state_text()
	if doll:
		doll.set_action_state("reload", 0.35)
		var s := _sfx()
		if s:
			s.play_3d(doll.get_parent(), "switch", doll.get_muzzle_position(), -6.0)
	state_changed.emit()
	weapon_switched.emit(id)

func _select(id: StringName) -> void:
	weapon = weapons[id]
	weapon_id = id
	var st: Dictionary = _saved[id]
	mag = int(st["mag"])
	chamber = String(st["chamber"])
	reserve = st["reserve"]
	ammo_type = st["ammo_type"]

func apply_loadout(reset_ammo: bool = false) -> void:
	var progress := get_node_or_null("/root/Progress")
	var loadout: Dictionary = {} if progress == null else progress.data.get("loadout", {})
	var selected := StringName(loadout.get("weapon", "m870"))
	var selected_ammo := StringName(loadout.get("ammo", "buckshot"))
	if reset_ammo:
		for id in WeaponDB.WEAPON_ORDER:
			var w: WeaponData = weapons[id]
			var reserves := {}
			for ammo_id in _ammo_order(id):
				reserves[ammo_id] = (ammo_table[ammo_id] as AmmoData).reserve_max
			_saved[id] = {"mag": w.mag_capacity, "chamber": "LOADED" if w.chamber_size > 0 else "EMPTY", "reserve": reserves, "ammo_type": _ammo_order(id)[0]}
	if not weapons.has(selected):
		selected = &"m870"
	_select(selected)
	if _ammo_order(weapon_id).has(selected_ammo):
		ammo_type = selected_ammo
	_update_state_text()
	state_changed.emit()
	weapon_switched.emit(weapon_id)

func _save_current() -> void:
	if weapon == null:
		return
	_saved[weapon_id] = {
		"mag": mag,
		"chamber": chamber,
		"reserve": reserve,
		"ammo_type": ammo_type,
		"cycle_t": cycle_t,
		"load_t": load_t,
		"fire_cd": fire_cd,
		"busy_max": busy_max,
		"pending_cycle": _pending_cycle,
		"pending_load": _pending_load,
	}

# ---------------------------------------------------------------- 主循环

func _physics_process(dt: float) -> void:
	var main := get_parent().get_parent() as Node
	if main != null and bool(main.get("in_base")):
		return
	fire_cd = maxf(0.0, fire_cd - dt)
	_wave_t = maxf(0.0, _wave_t - dt)
	if cycle_t > 0.0:
		var before := cycle_t
		cycle_t = maxf(0.0, cycle_t - dt)
		if before > 0.0 and cycle_t <= 0.0:
			_resolve_cycle()
	if load_t > 0.0:
		var before2 := load_t
		load_t = maxf(0.0, load_t - dt)
		if before2 > 0.0 and load_t <= 0.0:
			_resolve_load()

	for i in 4:
		if InputMap.has_action("weapon_%d" % (i + 1)) and Input.is_action_just_pressed("weapon_%d" % (i + 1)):
			switch_to(WeaponDB.WEAPON_ORDER[i])

	if Input.is_action_just_pressed("fire"):
		try_fire()
	if Input.is_action_just_pressed("reload"):
		_reload_pressed()
	if Input.is_action_pressed("reload_mag"):
		try_load_shell()
	if Input.is_action_just_pressed("ammo_switch"):
		switch_ammo()

	_update_state_text()

func _sfx() -> Node:
	return get_tree().root.get_node_or_null("Sfx")

## 枪声广播：按传播范围（米）通知敌人；可视波纹同一时间只保留一条。
func _emit_noise(pos: Vector3, radius: float) -> void:
	if _wave_t <= 0.0:
		_wave_t = 0.72
		ImpactFX.gunshot_wave(doll.get_parent(), pos, radius)
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.has_method("hear_noise"):
			e.hear_noise(pos, radius)

# ---------------------------------------------------------------- 开火

func _has_round() -> bool:
	if weapon.chamber_size > 0:
		return chamber == "LOADED"
	return mag > 0

func try_fire() -> void:
	if fire_cd > 0.0 or cycle_t > 0.0 or load_t > 0.0:
		return
	if not _has_round():
		if doll:
			var s := _sfx()
			if s:
				s.play_3d(doll.get_parent(), "empty", doll.get_muzzle_position(), -4.0)
		return

	var ammo := current_ammo()
	if weapon.chamber_size > 0:
		chamber = "FIRED"
	else:
		mag -= 1
	fire_cd = weapon.fire_interval
	shots += 1
	if doll:
		doll.shots = shots
	if weapon.auto_cycle:
		_pending_cycle = true
		cycle_t = maxf(weapon.pump_time, 0.08)
		busy_max = cycle_t
	_shoot(ammo)
	state_changed.emit()

func current_ammo() -> AmmoData:
	return ammo_table.get(ammo_type, ammo_table[&"buckshot"]) as AmmoData

## 枪声素材：9mm 手枪使用更清脆的独立音效。
func shot_sound_kind() -> String:
	return "pistol" if weapon.caliber == &"9mm" else "shotgun"

func get_spread_half_angle() -> float:
	return clampf((current_ammo().spread + weapon.base_spread) * 0.5 * accuracy_multiplier, 0.0, PI * 0.49)

func get_cone_direction(axis: Vector3, radial: float, azimuth: float) -> Vector3:
	var forward := axis.normalized()
	var up := Vector3.UP if absf(forward.dot(Vector3.UP)) < 0.999 else Vector3.RIGHT
	var right := forward.cross(up).normalized()
	var vertical := right.cross(forward).normalized()
	var cosine := lerpf(1.0, cos(get_spread_half_angle()), clampf(radial, 0.0, 1.0))
	return (forward * cosine + (right * cos(azimuth) + vertical * sin(azimuth)) * sqrt(maxf(0.0, 1.0 - cosine * cosine))).normalized()

func _trace(from: Vector3, to: Vector3) -> Dictionary:
	if from.distance_squared_to(to) < 0.00000001:
		return {}
	var query := PhysicsRayQueryParameters3D.create(from, to, 1 | 8, [doll.get_rid()])
	query.hit_from_inside = true
	return doll.get_world_3d().direct_space_state.intersect_ray(query)

func query_aim(aiming_shot: bool = false) -> Dictionary:
	if doll == null or weapon == null:
		return {}
	var visual := doll.get_parent().get_node_or_null("WeaponVisual") as WeaponVisual
	if visual == null:
		return {}
	visual.sync_pose(aiming_shot)
	var origin := visual.get_muzzle_position()
	var grip := visual.get_grip_position()
	var barrel := visual.get_barrel_direction()
	var target := doll.aim_point - origin
	var behind := target.dot(barrel) <= 0.001 or target.length_squared() < 0.000001
	var direction := barrel if behind else target.normalized()
	var body := Vector3(doll.global_position.x, grip.y, doll.global_position.z)
	var obstruction := _trace(body, grip)
	if obstruction.is_empty():
		obstruction = _trace(grip, origin)
	if obstruction.is_empty():
		obstruction = _trace(body, origin)
	var context := {
		"origin": origin, "direction": direction, "aim_point": doll.aim_point,
		"aim_distance": minf(target.length(), weapon.range_m), "behind_muzzle": behind,
		"obstruction": obstruction, "muzzle_blocked": not obstruction.is_empty(),
		"spread_half_angle": get_spread_half_angle(),
	}
	var center := query_pellet(context)
	context.merge(center)
	context["blocked"] = not obstruction.is_empty() or (not center["hit"].is_empty() and origin.distance_to(center["end"]) < target.length() - 0.01)
	return context

func query_pellet(context: Dictionary, radial: float = 0.0, azimuth: float = 0.0) -> Dictionary:
	var origin: Vector3 = context["origin"]
	var direction := get_cone_direction(context["direction"], radial, azimuth)
	var end := origin + direction * weapon.range_m
	var obstruction: Dictionary = context["obstruction"]
	var hit := _trace(origin, end) if obstruction.is_empty() else obstruction
	if not hit.is_empty():
		end = hit["position"]
	return {"origin": origin, "direction": direction, "end": end, "hit": hit,
		"blocked": not obstruction.is_empty() or (not hit.is_empty() and origin.distance_to(end) < float(context["aim_distance"]) - 0.01),
		"muzzle_blocked": not obstruction.is_empty(), "obstruction": obstruction}

func _shoot(ammo: AmmoData) -> void:
	if doll == null:
		return
	var context := query_aim(true)
	if context.is_empty():
		return
	var muzzle: Vector3 = context["origin"]
	last_shot = context.duplicate(true)
	last_shot["pellets"] = []
	var accumulated := []   # [{collider,pos,normal,damage}]，同目标只结算一次
	var impact_points := []

	for i in ammo.pellets:
		var pellet := query_pellet(context, randf(), randf() * TAU)
		last_shot["pellets"].append(pellet)
		var res: Dictionary = pellet["hit"]
		if res.is_empty():
			continue
		var hp: Vector3 = pellet["end"]
		var normal: Vector3 = res.get("normal", Vector3.UP)
		var collider = res.get("collider")

		if collider and collider.has_method("on_hit"):
			var found = null
			for e in accumulated:
				if e["collider"] == collider:
					found = e
					break
			if found != null:
				found["damage"] = float(found["damage"]) + ammo.damage
				found["pos"] = hp
			else:
				accumulated.append({
					"collider": collider,
					"pos": hp,
					"normal": normal,
					"damage": ammo.damage,
				})
		else:
			if impact_points.size() < 3:
				impact_points.append(hp)

	ImpactFX.shot(doll.get_parent(), last_shot)
	for e in accumulated:
		var col = e["collider"]
		if col and is_instance_valid(col) and col.has_method("on_hit"):
			if col is Enemy:
				col.on_hit(e["pos"], e["normal"], e["damage"], ammo.ap)
			else:
				col.on_hit(e["pos"], e["normal"], e["damage"])
	for p in impact_points:
		ImpactFX.spawn(doll.get_parent(), p)

	ImpactFX.shell(doll.get_parent(), muzzle, context["direction"])

	doll.play_muzzle_flash()
	var s := _sfx()
	if s:
		s.play_3d(doll.get_parent(), shot_sound_kind(), muzzle, -2.0, randf_range(0.95, 1.05))
	if doll.camera_rig:
		doll.camera_rig.add_shake(0.55 if weapon.caliber == &"12gauge" else 0.3)
	_emit_noise(muzzle, weapon.sound_radius)
	doll.set_action_state("fire", 0.18)

# ---------------------------------------------------------------- 上膛 / 泵动

## 完成一次抛壳 + 上膛
func _resolve_cycle() -> void:
	if not _pending_cycle:
		return
	_pending_cycle = false
	if weapon.chamber_size <= 0:
		return
	chamber = "EMPTY"
	if doll:
		var facing := Vector3(sin(doll.rotation.y), 0.0, cos(doll.rotation.y))
		ImpactFX.shell(doll.get_parent(), doll.get_muzzle_position(), facing)
	if mag > 0:
		mag -= 1
		chamber = "LOADED"

## R：泵动武器手动泵动；弹匣武器整匣更换
func _reload_pressed() -> void:
	if weapon.feed_mode == &"mag":
		reload_magazine()
	else:
		pump_action()

func pump_action() -> void:
	if cycle_t > 0.0 or load_t > 0.0:
		return
	if weapon.chamber_size <= 0:
		return
	if chamber != "FIRED" and not (chamber == "EMPTY" and mag > 0):
		return
	_pending_cycle = true
	_resolve_cycle()
	cycle_t = maxf(weapon.pump_time, 0.08)
	busy_max = cycle_t
	if doll:
		doll.set_action_state("reload", weapon.pump_time + 0.05)
		var s := _sfx()
		if s:
			s.play_3d(doll.get_parent(), "pump", doll.get_muzzle_position(), -4.0, randf_range(0.95, 1.05))
	state_changed.emit()

## F：逐发压入管仓（仅 shell 供弹武器）
func try_load_shell() -> void:
	if weapon.feed_mode != &"shell":
		return
	if load_t > 0.0 or cycle_t > 0.0:
		return
	if mag >= weapon.mag_capacity:
		return
	var n := int(reserve.get(ammo_type, 0))
	if n <= 0:
		return
	reserve[ammo_type] = n - 1
	mag += 1
	load_t = weapon.load_time
	busy_max = load_t
	if doll:
		doll.set_action_state("reload", weapon.load_time + 0.05)
		var s := _sfx()
		if s:
			s.play_3d(doll.get_parent(), "load", doll.get_muzzle_position(), -6.0, randf_range(0.95, 1.05))
	state_changed.emit()

## 整匣更换（mag 供弹武器）
func reload_magazine() -> void:
	if weapon.feed_mode != &"mag":
		return
	if load_t > 0.0 or cycle_t > 0.0:
		return
	if mag >= weapon.mag_capacity:
		return
	var have := int(reserve.get(ammo_type, 0))
	if have <= 0:
		return
	_pending_load = mini(weapon.mag_capacity - mag, have)
	reserve[ammo_type] = have - _pending_load
	load_t = weapon.load_time
	busy_max = load_t
	if doll:
		doll.set_action_state("reload", weapon.load_time + 0.05)
		var s := _sfx()
		if s:
			s.play_3d(doll.get_parent(), "load", doll.get_muzzle_position(), -6.0, randf_range(0.95, 1.05))
	state_changed.emit()

func _resolve_load() -> void:
	if _pending_load > 0:
		mag += _pending_load
		_pending_load = 0
		if weapon.chamber_size > 0 and chamber != "LOADED" and mag > 0:
			mag -= 1
			chamber = "LOADED"

func switch_ammo() -> void:
	if cycle_t > 0.0 or load_t > 0.0:
		return
	var order := _ammo_order(weapon_id)
	if order.size() < 2:
		return
	var returned := mag + (1 if chamber == "LOADED" else 0)
	if returned > 0:
		reserve[ammo_type] = int(reserve.get(ammo_type, 0)) + returned
	chamber = "EMPTY"
	mag = 0

	var idx := order.find(ammo_type)
	ammo_type = order[(idx + 1) % order.size()]
	cycle_t = 0.2
	busy_max = cycle_t
	if doll:
		doll.set_action_state("reload", 0.25)
		var s := _sfx()
		if s:
			s.play_3d(doll.get_parent(), "switch", doll.get_muzzle_position(), -6.0)
	state_changed.emit()

# ---------------------------------------------------------------- 状态文本

func _update_state_text() -> void:
	if load_t > 0.0:
		state_text = "装填中..."
	elif cycle_t > 0.0:
		state_text = "上膛中..." if weapon.auto_cycle else "泵动中..."
	elif chamber == "FIRED":
		state_text = "需要泵动 R"
	elif not _has_round() and int(reserve.get(ammo_type, 0)) > 0:
		state_text = "换弹 R" if weapon.feed_mode == &"mag" else "上膛 R"
	elif not _has_round() and int(reserve.get(ammo_type, 0)) <= 0:
		state_text = "弹药耗尽"
	else:
		state_text = "READY"

func is_busy() -> bool:
	return load_t > 0.0 or cycle_t > 0.0

func get_progress() -> float:
	if busy_max <= 0.0:
		return 0.0
	if load_t > 0.0:
		return clampf(1.0 - load_t / busy_max, 0.0, 1.0)
	if cycle_t > 0.0:
		return clampf(1.0 - cycle_t / busy_max, 0.0, 1.0)
	return 0.0

func get_ammo() -> AmmoData:
	return current_ammo()

func supply_reserve() -> int:
	var maximum := current_ammo().reserve_max
	var amount := mini(ceili(maximum * 0.5), maxi(0, maximum - get_reserve()))
	reserve[ammo_type] = get_reserve() + amount
	_update_state_text()
	state_changed.emit()
	return amount

func get_reserve() -> int:
	return int(reserve.get(ammo_type, 0))

func get_loaded_total() -> int:
	return mag + (1 if (weapon.chamber_size > 0 and chamber == "LOADED") else 0)

func get_mag_capacity() -> int:
	return weapon.mag_capacity

func debug_fire_once() -> void:
	try_fire()
