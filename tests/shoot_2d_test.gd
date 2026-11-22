extends SceneTree
## 2D 射击回归：开火真的造成伤害、墙体遮挡、霰弹多弹丸、HUD 状态。
## godot --headless --path . --script res://tests/shoot_2d_test.gd

var _pass := 0
var _fail := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("ok] ", label)
	else:
		_fail += 1
		print("FAIL ", label)


## 等所有玩家弹丸飞行结束（命中/撞墙/超出射程），再断言命中结果。
func _wait_bullets(main, max_frames := 240) -> void:
	for i in max_frames:
		await physics_frame
		var alive := false
		for child in main.fx_layer.get_children():
			if child is PlayerBullet2D:
				alive = true
				break
		if not alive:
			return


func _run() -> void:
	var p = root.get_node_or_null("Progress")
	if p != null:
		p.reset_for_test()
	var main = load("res://scenes/core/Main2D.tscn").instantiate()
	main.mouse_aim_enabled = false
	root.add_child(main)
	await process_frame
	await physics_frame
	for enemy in main.enemies:
		enemy.set_physics_process(false)

	var doll = main.doll
	var enemy = main.enemies[0]
	enemy.global_position = doll.global_position + Vector2(240, 20)
	enemy.hp = 70.0
	enemy.hp_max = 70.0
	doll.aim_target = enemy.global_position + Vector2(0, -52)
	for i in 20:
		await physics_frame

	var rig = doll.weapon_rig
	var range_pistol: float = main._shot_range()
	_check(rig != null, "weapon rig exists")
	_check(is_equal_approx(main.shake_scale, 5.0),
		"100% shake slider maps to the new baseline (old 500%)")
	_check(is_equal_approx(WeaponDB.base_spread_mul(), 1.0),
		"global spread multiplier is removed")
	_check(WeaponDB.get_weapon(&"akm").base_spread > 0.0
		and WeaponDB.get_weapon(&"g17").base_spread > 0.0,
		"weapons carry their own base spread")
	_check(main.hud.hint_label != null and main.hud.result_label != null \
		and main.backpack != null, "pixel HUD and backpack built")

	# 1) 手枪命中：18 伤害，哨兵护甲 1 → 实际 17
	var hp_before: float = enemy.hp
	var mag_before: int = rig.mag
	rig.try_fire()
	# 弹道线条开关：默认可见；关闭后立即隐藏，但弹丸仍继续飞行与结算。
	var trail_bullet = null
	for child in main.fx_layer.get_children():
		if child is PlayerBullet2D:
			trail_bullet = child
			break
	_check(trail_bullet != null and trail_bullet.visible, "子弹实体默认可见")
	var trail_line = trail_bullet.trail_line if trail_bullet != null else null
	_check(trail_line != null and trail_line.visible, "弹道线条默认显示")
	if trail_bullet != null:
		p.data["bullet_trail_enabled"] = false
		main._on_settings_applied()
		_check(trail_bullet.visible, "关闭弹道线条后子弹实体仍可见")
		_check(trail_line == null or not trail_line.visible, "关闭后弹道线条隐藏")
		p.data["bullet_trail_enabled"] = true
		main._on_settings_applied()
		_check(trail_line != null and trail_line.visible, "重新开启后弹道线条恢复")
	await _wait_bullets(main)
	_check(enemy.hp < hp_before, "pistol hit damages enemy (%.0f -> %.0f)" % [hp_before, enemy.hp])
	_check(rig.mag == mag_before - 1, "shot consumes one round")
	_check(main.hud.hp_label.text.contains("/"), "HUD hp text refreshed")
	_check(enemy._hit_flash > 0.0 and enemy._squash > 0.0,
		"hit sets flash and squash deformation")
	_check(enemy._knock.length() > 1.0, "hit applies a knockback impulse")
	_check(enemy.hit_material() == "flesh", "rifleman uses flesh hit feedback")
	_check(main._shake > 0.0, "hits kick the camera")
	var has_number := false
	for child in main.fx_layer.get_children():
		if child is DamageNumber2D:
			has_number = true
	_check(has_number, "enemy hit spawns a floating damage number")

	# ---- 后坐力：垂直上跳 + 水平偏移；开镜明显比腰射稳 ----
	rig.cooldown = 0.0
	main._recoil_offset = Vector2.ZERO
	main._recoil_cam = Vector2.ZERO
	main.doll.ads = false
	main._ads_t = 0.0
	rig.try_fire()
	await process_frame
	var hip_kick: float = -main._recoil_offset.y
	_check(hip_kick > 0.5, "hip fire kicks the aim upward (%.1f px)" % hip_kick)
	_check(main._recoil_cam.length() > 0.1, "recoil also kicks the camera")
	main._ads_t = 0.0
	_check(is_equal_approx(main.recoil_strength(), 1.0), "hip fire uses full recoil strength")
	main._ads_t = 1.0
	_check(main.recoil_strength() < 0.7, "ADS reduces the recoil strength")
	# 后坐力上限：累积极大偏移后仍被武器上限夹住。
	var rig_data = rig.data
	main._recoil_offset = Vector2(0, -9999)
	rig.cooldown = 0.0
	rig.try_fire()
	await process_frame
	_check(absf(main._recoil_offset.y) <= float(rig_data.recoil_max_vertical) + 0.01,
		"recoil accumulation is capped by the weapon's max recoil")
	# 后坐力对散布的影响：累计越多，散布锥越大。
	main._recoil_offset = Vector2.ZERO
	main._burst_spread = 0.0
	var spread_rest: float = main.get_aim_spread()
	main._recoil_offset = Vector2(0, -float(rig_data.recoil_max_vertical))
	var spread_recoiled: float = main.get_aim_spread()
	_check(spread_recoiled > spread_rest + 0.004,
		"accumulated recoil widens the spread cone")
	_check(float(rig_data.recoil_vertical) > 0.0
		and float(rig_data.recoil_horizontal) > 0.0
		and float(rig_data.recoil_max_vertical) >= float(rig_data.recoil_vertical)
		and float(rig_data.recoil_max_horizontal) >= float(rig_data.recoil_horizontal),
		"weapons expose separate vertical/horizontal recoil and caps")
	# 调试模式：散布全局倍率立即生效，关闭后恢复。
	var dbg_progress = root.get_node_or_null("Progress")
	dbg_progress.set_debug_enabled(true)
	dbg_progress.set_debug_value("spread", 2.0)
	var spread_debug: float = main.get_aim_spread()
	dbg_progress.set_debug_enabled(false)
	dbg_progress.reset_debug()
	_check(spread_debug > spread_rest * 1.5,
		"debug spread multiplier applies globally and resets when disabled")
	# 逐弹种配件/开镜系数：同一次调用内对比，排除连发/后坐状态干扰。
	main._recoil_offset = Vector2.ZERO
	main._burst_spread = 0.0
	main._ads_t = 0.0
	var saved_rig_mul: float = rig.spread_mul
	rig.spread_mul = 1.0
	var spread_full: float = main.get_aim_spread()
	rig.spread_mul = 0.5
	var spread_mod: float = main.get_aim_spread()
	var ammo_9: AmmoData = main.current_ammo()
	var expect_attach_9 := lerpf(1.0, 0.5, float(ammo_9.attachment_spread_scale))
	_check(ammo_9.id == &"9mm"
		and absf(spread_mod / spread_full - expect_attach_9) < 0.02,
		"9mm 配件散布按 80%% 生效 (%.3f / %.3f)" % [
			spread_mod / spread_full, expect_attach_9])
	main._ads_t = 1.0
	var spread_mod_ads: float = main.get_aim_spread()
	main._ads_t = 0.0
	_check(absf(spread_mod_ads / spread_mod - float(ammo_9.ads_spread_mul)) < 0.02,
		"9mm 开镜收紧到 62%% (%.3f)" % (spread_mod_ads / spread_mod))
	# 换成鹿弹参数：配件收益更低、开镜收紧更弱。
	var saved_ammo: StringName = rig.data.ammo_id
	rig.data.ammo_id = &"buckshot"
	rig.spread_mul = 1.0
	var buck_full: float = main.get_aim_spread()
	rig.spread_mul = 0.5
	var buck_mod: float = main.get_aim_spread()
	var ammo_buck: AmmoData = main.current_ammo()
	var expect_attach_buck := lerpf(1.0, 0.5, float(ammo_buck.attachment_spread_scale))
	_check(absf(buck_mod / buck_full - expect_attach_buck) < 0.02,
		"鹿弹配件散布按 55%% 生效 (%.3f / %.3f)" % [
			buck_mod / buck_full, expect_attach_buck])
	main._ads_t = 1.0
	var buck_ads: float = main.get_aim_spread()
	main._ads_t = 0.0
	_check(absf(buck_ads / buck_mod - float(ammo_buck.ads_spread_mul)) < 0.02,
		"鹿弹开镜只收紧到 80%% (%.3f)" % (buck_ads / buck_mod))
	rig.data.ammo_id = saved_ammo
	rig.spread_mul = saved_rig_mul
	main._burst_spread = 0.0
	main._recoil_offset = Vector2.ZERO
	# 调试后坐力倍率在开火时立即生效。
	dbg_progress.set_debug_enabled(true)
	dbg_progress.set_debug_value("recoil_v", 2.0)
	main._recoil_offset = Vector2.ZERO
	main._recoil_cam = Vector2.ZERO
	main._ads_t = 0.0
	main.doll.ads = false
	for i in 14:
		await process_frame
	rig.cooldown = 0.0
	var debug_fired: bool = rig.try_fire()
	await process_frame
	var debug_kick: float = -main._recoil_offset.y
	dbg_progress.set_debug_enabled(false)
	dbg_progress.reset_debug()
	_check(debug_fired, "debug recoil shot fired")
	_check(debug_kick > hip_kick * 1.4,
		"debug recoil multiplier applies at runtime (%.2f vs %.2f)" % [debug_kick, hip_kick])
	main._recoil_offset = Vector2.ZERO
	main._recoil_cam = Vector2.ZERO
	# P0：第一颗弹丸也参与散布，且弹丸落在配置的散布锥内。
	main.doll.aim_target = main.doll.global_position + Vector2(0, 500)
	rig.mag = 60
	var max_dev := 0.0
	for shot in 6:
		main._burst_spread = 0.2
		main._recoil_offset = Vector2.ZERO
		main.last_pellet_dirs.clear()
		rig.cooldown = 0.0
		var spread_fired: bool = rig.try_fire()
		if not spread_fired:
			for i in 4:
				await process_frame
			rig.cooldown = 0.0
			main._burst_spread = 0.2
			spread_fired = rig.try_fire()
		if not spread_fired:
			continue
		for pellet_dir in main.last_pellet_dirs:
			max_dev = maxf(max_dev,
				absf(rad_to_deg(pellet_dir.angle_to(main.last_shot_dir))))
		for i in 3:
			await process_frame
	main._burst_spread = 0.0
	main._recoil_offset = Vector2.ZERO
	main._recoil_cam = Vector2.ZERO
	_check(max_dev > 0.5 and max_dev < 8.5,
		"the first pellet spreads inside the configured cone (%.2f deg)" % max_dev)
	# 首发散布乘数：停火窗口后的第一发更准，紧接着的第二发恢复全散布。
	main._shot_clock = 100.0
	main._last_shot_time = -100.0
	main._burst_spread = 0.2
	main._recoil_offset = Vector2.ZERO
	main.doll.aim_target = main.doll.global_position + Vector2(0, 500)
	rig.mag = 60
	var full_first: float = main.get_aim_spread()
	rig.cooldown = 0.0
	var fs_fired: bool = rig.try_fire()
	var first_spread: float = main.last_pellet_spread
	for i in 12:
		await process_frame
	main._burst_spread = 0.2
	main._recoil_offset = Vector2.ZERO
	main._shot_clock = main._last_shot_time + 0.05
	var full_second: float = main.get_aim_spread()
	rig.cooldown = 0.0
	var ss_fired: bool = rig.try_fire()
	var second_spread: float = main.last_pellet_spread
	_check(fs_fired and ss_fired, "first-shot spread shots fired")
	_check(first_spread < full_first * 0.6,
		"first shot uses the first-shot spread multiplier (%.3f / %.3f)" % [
			first_spread, full_first])
	_check(absf(second_spread - full_second) < 0.012,
		"the follow-up uses the full spread (%.3f / %.3f)" % [
			second_spread, full_second])
	main._burst_spread = 0.0
	main._recoil_offset = Vector2.ZERO
	main._recoil_cam = Vector2.ZERO
	main.doll.ads = false
	main._ads_t = 0.0
	main._recoil_offset = Vector2.ZERO
	main._recoil_cam = Vector2.ZERO
	main.doll.aim_target = enemy.global_position + Vector2(0, -52)

	# 2) 墙体遮挡：在中间加一堵墙，同样瞄准敌人，伤害不应结算
	enemy.hp = 70.0
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	var wall_shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(24, 260)
	wall_shape.shape = rect
	wall.add_child(wall_shape)
	main.add_child(wall)
	wall.global_position = doll.global_position + Vector2(120, -40)
	for i in 20:
		await physics_frame
	_check(bool(main.get_aim_block().get("blocked", false)), "aim reports wall blocked")
	rig.try_fire()
	await _wait_bullets(main)
	_check(is_equal_approx(enemy.hp, 70.0), "wall blocks the shot, enemy hp=%.0f" % enemy.hp)
	wall.queue_free()
	for i in 12:
		await physics_frame

	# 2b) 枪口探进墙里：起射点回退到墙前，不能隔墙命中。
	enemy.global_position = doll.global_position + Vector2(260, 20)
	enemy.hp = 70.0
	enemy.hp_max = 70.0
	doll.aim_target = doll.global_position + Vector2(300, 0)
	for i in 16:
		await physics_frame
	var muzzle: Vector2 = main.get_shot_origin()
	var body_center: Vector2 = doll.global_position + Vector2(0, -34)
	var wall_center: Vector2 = body_center + (muzzle - body_center) * 0.72
	var muzzle_wall := _make_wall(main, wall_center, Vector2(10, 180))
	await physics_frame
	var safe_origin: Vector2 = main.get_safe_shot_origin()
	_check(safe_origin.x < muzzle.x - 4.0 and safe_origin.x < wall_center.x - 2.0,
		"shot origin retreats in front of the muzzle wall")
	doll.aim_target = enemy.body_center()
	for i in 6:
		await physics_frame
	rig.try_fire()
	await _wait_bullets(main)
	_check(is_equal_approx(enemy.hp, 70.0),
		"muzzle inside a wall cannot shoot through it, hp=%.0f" % enemy.hp)
	muzzle_wall.queue_free()
	for i in 8:
		await physics_frame

	# 2c) 敌人贴墙只露出受击盒：射线能打到，但身体核心被墙挡住，伤害不结算。
	enemy.hp = 100.0
	enemy.hp_max = 100.0
	var enemy_center: Vector2 = enemy.body_center()
	var radius := float(enemy.stats.get("collision_radius", 17.0))
	var protrude := Vector2(enemy.global_position.x - radius + 1.0, enemy_center.y)
	var cover := _make_wall(main, Vector2(enemy.global_position.x - 8.0, enemy_center.y),
		Vector2(12, 150))
	await physics_frame
	var shot_origin: Vector2 = main.get_safe_shot_origin()
	var shot_dir := (protrude - shot_origin).normalized()
	var probe: Dictionary = main._trace_pellet(shot_origin, shot_dir, 2000.0)
	var probe_target = probe.get("collider")
	if probe_target is Area2D:
		probe_target = probe_target.get_parent()
	_check(probe_target == enemy,
		"ray still reaches the protruding hitbox part")
	_check(not main._wall_between(shot_origin, enemy_center).is_empty(),
		"enemy body core is behind the wall")
	var data = doll.weapon_rig.data
	var ammo = main.current_ammo()
	var old_base_spread: float = data.base_spread
	var old_ammo_spread: float = ammo.spread
	data.base_spread = 0.0
	ammo.spread = 0.0
	main._burst_spread = 0.0
	doll.aim_target = protrude
	for i in 6:
		await physics_frame
	rig.try_fire()
	await _wait_bullets(main)
	_check(is_equal_approx(enemy.hp, 100.0),
		"hitting only the protruding hitbox is rejected, hp=%.0f" % enemy.hp)
	cover.queue_free()
	data.base_spread = old_base_spread
	ammo.spread = old_ammo_spread
	main._burst_spread = 0.0
	for i in 8:
		await physics_frame
	rig.try_fire()
	await _wait_bullets(main)
	_check(enemy.hp < 100.0, "same shot damages the enemy once cover is gone")

	# 3) 换霰弹枪：8 颗弹丸，近距离总伤害应明显高于单发手枪
	doll.equip_weapon_id(&"m870")
	await physics_frame
	var shotgun = doll.weapon_rig
	_check(main._shot_range() > range_pistol + 100.0,
		"shotgun range exceeds pistol (%.0f -> %.0f)" % [range_pistol, main._shot_range()])
	enemy.hp = 200.0
	enemy.hp_max = 200.0
	doll.aim_target = enemy.global_position + Vector2(0, -52)
	for i in 20:
		await physics_frame
	var hp_shotgun: float = enemy.hp
	shotgun.try_fire()
	await _wait_bullets(main)
	_check(enemy.hp < hp_shotgun - 20.0,
		"shotgun pellets deal multi-hit damage (%.0f -> %.0f)" % [hp_shotgun, enemy.hp])
	_check(main.hud.ammo_label.text.contains("/"), "HUD ammo text refreshed")
	_check(WeaponDB.get_weapon(&"m870").knockback > WeaponDB.get_weapon(&"g17").knockback
		and WeaponDB.get_weapon(&"m870").shake_roll > WeaponDB.get_weapon(&"g17").shake_roll,
		"heavier weapons kick and shake harder")

	print("\n=== shoot 2d: %s (%d ok / %d fail) ===" % ["PASS" if _fail == 0 else "FAIL", _pass, _fail])
	quit()


## 测试用临时墙体。
func _make_wall(parent: Node, pos: Vector2, size: Vector2) -> StaticBody2D:
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	wall.add_child(shape)
	parent.add_child(wall)
	wall.global_position = pos
	return wall
