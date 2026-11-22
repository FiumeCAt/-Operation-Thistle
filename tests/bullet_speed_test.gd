extends SceneTree
## 子弹速度系统专项回归：真实初速 → 游戏内速度、飞行时间、指数衰减、扫掠命中。
## godot --headless --path . --script res://tests/bullet_speed_test.gd

var _pass := 0
var _fail := 0
var _main
var _doll
var _enemy


func _initialize() -> void:
	call_deferred("_run")


func _check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("ok] ", label)
	else:
		_fail += 1
		print("FAIL ", label)


func _run() -> void:
	var p = root.get_node_or_null("Progress")
	if p != null:
		p.reset_for_test()
	_main = load("res://scenes/core/Main2D.tscn").instantiate()
	_main.mouse_aim_enabled = false
	root.add_child(_main)
	await process_frame
	await physics_frame
	_doll = _main.doll
	# 本测试只验证弹道，不验证掩体：把关卡静态墙体碰撞关掉，留出干净射界。
	for node in _main.find_children("*", "StaticBody2D", true, false):
		if node.collision_layer & 1:
			node.collision_layer = 0
	for i in _main.enemies.size():
		var e = _main.enemies[i]
		e.set_physics_process(false)
		if i == 0:
			_enemy = e
		else:
			e.global_position = Vector2(-10000, -10000)
	_doll.global_position = Vector2(39.5, 60.5) * _main.TILE
	_enemy.global_position = _doll.global_position + Vector2(640, 0)
	_enemy.hp = 100000.0
	_enemy.hp_max = 100000.0

	# ---- 1) 数据与设计表：15m 飞行时间误差 ≤ 5%（bullet_time_scale=0.294 旧手感补偿），30m 因衰减更慢 ----
	var design := {
		&"buckshot": 0.128, &"slug": 0.109, &"ap_slug": 0.102,
		&"9mm": 0.134, &"5.7x28": 0.071, &"45acp": 0.196,
		&"357mag": 0.111, &"762x39": 0.071, &"762nato": 0.060,
		&"556nato": 0.054, &"9x39": 0.176, &"338lapua": 0.057,
	}
	var table := WeaponDB.ammo_table()
	for id in design:
		var a: AmmoData = table[id]
		var v0: float = _main.bullet_speed_px_s(a)
		var expect_v0: float = float(a.muzzle_velocity_mps) * float(a.bullet_time_scale) \
			* float(_main.WORLD_PER_METER)
		_check(absf(v0 - expect_v0) < 0.5,
			"%s 游戏初速 %.0f px/s" % [String(id), v0])
		var t15: float = _main.bullet_travel_time(a, 15.0)
		var err: float = absf(t15 - float(design[id])) / float(design[id])
		_check(err <= 0.05,
			"%s 15m 飞行 %.3fs（设计 %.3fs，误差 %.1f%%）" % [
				String(id), t15, float(design[id]), err * 100.0])
		var t30: float = _main.bullet_travel_time(a, 30.0)
		_check(t30 > t15 * 1.8 and t30 < t15 * 2.4,
			"%s 30m 因衰减变慢（%.3fs vs 15m %.3fs）" % [String(id), t30, t15])
		var v30: float = exp(-float(a.drag_per_m) * 30.0)
		_check(v30 >= 0.80 and v30 <= 0.98,
			"%s 30m 保留 %.0f%% 初速" % [String(id), v30 * 100.0])
	var s556: float = _main.bullet_speed_px_s(table[&"556nato"])
	var snato: float = _main.bullet_speed_px_s(table[&"762nato"])
	var s338: float = _main.bullet_speed_px_s(table[&"338lapua"])
	var s57: float = _main.bullet_speed_px_s(table[&"5.7x28"])
	var s762: float = _main.bullet_speed_px_s(table[&"762x39"])
	var s9: float = _main.bullet_speed_px_s(table[&"9mm"])
	var s45: float = _main.bullet_speed_px_s(table[&"45acp"])
	_check(s556 > s338 and s338 > snato and snato > s57 and s57 > s762
		and s762 > s9 and s9 > s45,
		"弹速排序：5.56 > .338 > 7.62N > 5.7 > 7.62×39 > 9mm > .45")
	var g17_data: WeaponData = WeaponDB.get_weapon(&"g17")
	var tmp_data: WeaponData = WeaponDB.get_weapon(&"tmp")
	var mm9: AmmoData = table[&"9mm"]
	_check(g17_data.bullet_speed_mps > tmp_data.bullet_speed_mps
		and _main.bullet_speed_px_s(mm9, g17_data) > _main.bullet_speed_px_s(mm9, tmp_data),
		"武器弹速字段接入运行时：G17 380 > TMP 334 m/s")

	# ---- 2) 实测飞行时间：5.56 / 9mm / .45 三种节奏 ----
	var results := {}
	for id in [&"g17", &"m1911", &"l85a2"]:
		var r: Dictionary = await _measure_weapon(id, Vector2(640, 0))
		results[id] = r
		if r.get("fired", false):
			_check(bool(r.get("hit", false)), "%s 弹丸命中 10m 目标" % String(id))
			_check(absf(float(r["measured"]) - float(r["expected"])) <= 0.05,
				"%s 实测 %.3fs / 理论 %.3fs（%.0f px）" % [
					String(id), float(r["measured"]), float(r["expected"]), float(r["dist_px"])])
	var f556: float = float(results.get(&"l85a2", {}).get("measured", 99.0))
	var f9: float = float(results.get(&"g17", {}).get("measured", 99.0))
	var f45: float = float(results.get(&"m1911", {}).get("measured", 99.0))
	_check(f556 < f9 and f9 < f45,
		"实际节奏：5.56(%.2fs) < 9mm(%.2fs) < .45(%.2fs)" % [f556, f9, f45])

	# ---- 3) 不同距离：5m / 10m 的实测飞行时间 ----
	var r5: Dictionary = await _measure_weapon(&"g17", Vector2(320, 0))
	var r10: Dictionary = await _measure_weapon(&"g17", Vector2(640, 0))
	_check(bool(r5.get("hit", false)) and bool(r10.get("hit", false)),
		"5m / 10m 两次测试均命中")
	_check(float(r10["measured"]) > float(r5["measured"]) * 1.5,
		"10m 飞行明显长于 5m（%.3fs vs %.3fs）" % [
			float(r10["measured"]), float(r5["measured"])])

	# ---- 4) 高速扫掠：50000 px/s 也不穿过 10m 外的敌人 ----
	_enemy.hp = 100000.0
	var origin: Vector2 = _main.get_safe_shot_origin()
	var aim: Vector2 = _enemy.body_center()
	var ctx := {
		"data": _doll.weapon_rig.data,
		"ap": 0.0, "knockback": 0.0, "multi": false, "pending": 1,
		"origin": origin, "buckets": {}, "fx_targets": {},
		"first_hit": false, "first_kill": false, "wall_fx": 0,
		"flush_scheduled": false,
	}
	var hp_before: float = _enemy.hp
	var bullet = PlayerBullet2D.spawn(_main.fx_layer, _main, origin,
		(aim - origin).normalized(), 50000.0, 0.0, 7.0, 0.0, 2000.0,
		Color.WHITE, ctx, 0.0)
	_check(bullet != null, "高速测试弹丸生成")
	for i in 6:
		await physics_frame
	_check(_enemy.hp < hp_before,
		"50000 px/s 仍能扫掠命中（hp %.0f -> %.0f）" % [hp_before, _enemy.hp])

	print("\n=== bullet speed: %s (%d ok / %d fail) ===" % [
		"PASS" if _fail == 0 else "FAIL", _pass, _fail])
	quit()


## 换武器 → 清零散布 → 对准目标 → 开火，返回实测/理论飞行时间。
func _measure_weapon(id: StringName, offset: Vector2) -> Dictionary:
	_doll.equip_weapon_id(id)
	await physics_frame
	await physics_frame
	var rig = _doll.weapon_rig
	var data: WeaponData = rig.data
	var ammo: AmmoData = _main.current_ammo()
	var old_base: float = data.base_spread
	var old_spread: float = ammo.spread
	data.base_spread = 0.0
	ammo.spread = 0.0
	_main._burst_spread = 0.0
	_main._recoil_offset = Vector2.ZERO
	_main._ads_t = 0.0
	_doll.ads = false
	_enemy.global_position = _doll.global_position + offset
	_enemy.hp = 100000.0
	_enemy.hp_max = 100000.0
	_doll.aim_target = _enemy.body_center()
	for i in 24:
		await physics_frame
		_main._recoil_offset = Vector2.ZERO
	var before: float = _enemy.hp
	rig.cooldown = 0.0
	var fired: bool = rig.try_fire()
	var result := {"fired": fired, "hit": false, "measured": 0.0,
		"expected": 0.0, "dist_px": 0.0}
	if not fired:
		data.base_spread = old_base
		ammo.spread = old_spread
		return result
	var origin: Vector2 = _main.last_shot_origin
	var dist_px: float = origin.distance_to(_enemy.body_center())
	result["dist_px"] = dist_px
	result["expected"] = _main.bullet_travel_time(ammo,
		dist_px / float(_main.WORLD_PER_METER), data)
	var frames := 0
	while frames < 180:
		await physics_frame
		frames += 1
		if _enemy.hp < before - 0.01:
			break
	result["hit"] = _enemy.hp < before - 0.01
	result["measured"] = float(frames) / float(Engine.physics_ticks_per_second)
	data.base_spread = old_base
	ammo.spread = old_spread
	return result
