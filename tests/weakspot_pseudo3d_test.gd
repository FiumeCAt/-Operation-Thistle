extends SceneTree
## Phase 4 专项回归：可配置部位弱点系统（Weakspot）+ 轻量伪 3D 子弹高度落点修正。
## godot --headless --path . --script res://tests/weakspot_pseudo3d_test.gd

const DAMAGE := preload("res://scripts/combat/DamageModel.gd")
const BALLISTICS := preload("res://scripts/combat/BallisticsModel.gd")
const ENEMY_DEF := preload("res://scripts/actors/enemy/EnemyDef.gd")

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


func _wait_bullets(main: Node, max_frames := 90) -> void:
	for _i in max_frames:
		await physics_frame
		var alive := false
		for child in main.fx_layer.get_children():
			if child is PlayerBullet2D:
				alive = true
				break
		if not alive:
			break
	for _i in 4:
		await physics_frame


func _fire_zero_spread(main: Node, aim_pos: Vector2) -> void:
	var rig = main.doll.weapon_rig
	var data = rig.data
	var ammo = main.current_ammo()
	var old_base: float = data.base_spread
	var old_ammo: float = ammo.spread
	data.base_spread = 0.0
	ammo.spread = 0.0
	main._burst_spread = 0.0
	main._recoil_offset = Vector2.ZERO
	main.doll.aim_target = aim_pos
	for _i in 6:
		await physics_frame
	rig.cooldown = 0.0
	rig.try_fire()
	await _wait_bullets(main)
	data.base_spread = old_base
	ammo.spread = old_ammo
	main._burst_spread = 0.0


func _run() -> void:
	create_timer(40.0).timeout.connect(func() -> void: quit(2))

	# ---- 1) 可配置弱点数据解析（不写死头部 + 三系默认 + 宽容度 +15%~20%） ----
	var rifle: EnemyDef = ENEMY_DEF.from_dict(&"rifleman", EnemyDB.stats(&"rifleman"))
	var heavy: EnemyDef = ENEMY_DEF.from_dict(&"heavy", EnemyDB.stats(&"heavy"))
	var hunter: EnemyDef = ENEMY_DEF.from_dict(&"hunter", EnemyDB.stats(&"hunter"))
	var ht1: EnemyDef = ENEMY_DEF.from_dict(&"hunter_type1", EnemyDB.stats(&"hunter_type1"))
	var goliath: EnemyDef = ENEMY_DEF.from_dict(&"goliath", EnemyDB.stats(&"goliath"))
	var turret: EnemyDef = ENEMY_DEF.from_dict(&"mobile_turret", EnemyDB.stats(&"mobile_turret"))
	var mutant_mock: EnemyDef = ENEMY_DEF.from_dict(&"mutant_mock", {"name": "变异样本", "archetype": "mutant", "hp": 300.0, "armor": 50.0})
	var no_ws_mock: EnemyDef = ENEMY_DEF.from_dict(&"no_ws", {"name": "无弱点样本", "archetype": "mech", "weakspot": null})

	_check(rifle.weakspot_part == "head" and heavy.weakspot_part == "visor"
		and hunter.weakspot_part == "optic_eye" and ht1.weakspot_part == "chest_reactor"
		and goliath.weakspot_part == "detonator_core" and turret.weakspot_part == "barrel_core",
		"each enemy configures its own anatomical weakspot part rather than hardcoding head")
	_check(mutant_mock.weakspot_enabled and mutant_mock.weakspot_part == "exposed_core"
		and is_equal_approx(mutant_mock.weakspot_armor_mul, 0.50)
		and is_equal_approx(mutant_mock.weakspot_damage_mul, 2.00),
		"mutant archetype inherits exposed_core weakspot with 0.50x armor and 2.00x damage")
	_check(is_equal_approx(rifle.weakspot_damage_mul, 2.0) and is_equal_approx(rifle.weakspot_armor_mul, 0.5)
		and is_equal_approx(heavy.weakspot_damage_mul, 2.0) and is_equal_approx(heavy.weakspot_armor_mul, 0.5)
		and is_equal_approx(hunter.weakspot_damage_mul, 1.5) and is_equal_approx(hunter.weakspot_armor_mul, 0.5)
		and is_equal_approx(ht1.weakspot_damage_mul, 1.5) and is_equal_approx(ht1.weakspot_armor_mul, 0.5)
		and is_equal_approx(goliath.weakspot_damage_mul, 1.5) and is_equal_approx(goliath.weakspot_armor_mul, 0.5)
		and is_equal_approx(turret.weakspot_damage_mul, 1.5) and is_equal_approx(turret.weakspot_armor_mul, 0.5),
		"data-driven weakspot baseline sets mech=1.5x, human/mutant=2.0x, armor_mul=0.50 across all enemies")
	_check(not no_ws_mock.weakspot_enabled, "weakspot: null cleanly disables weakspot on a unit")
	_check(rifle.weakspot_tolerance >= 1.15 and rifle.weakspot_tolerance <= 1.20
		and rifle.effective_weakspot_radius() > rifle.weakspot_radius * 1.15,
		"weakspot hitbox grants +15%..+20% forgiveness tolerance (%.2f)" % rifle.weakspot_tolerance)
	_check(hunter.weakspot_flip_x
		and hunter.weakspot_local_offset(100.0, false).x > 0.0
		and hunter.weakspot_local_offset(100.0, true).x < 0.0,
		"forward-offset weakspot (hunter optic_eye) flips X with facing direction")

	# ---- 2) DamageModel 弱点护甲折减 × 武器弱点倍率 × 单位弱点倍率 ----
	# 重装（148 RHA，面罩护甲倍率 0.45 -> 66.6 RHA，单位弱点倍率 1.70）：
	# 9mm AP (104+3=107) 打躯干未击穿（107 < 148），但打面罩弱点（107 >= 66.6）直接击穿并吃满倍率！
	var body_vs_heavy: float = DAMAGE.resolve_enemy_damage(15.75, 107.0, 148.0, 0.10, 1.0)
	var ws_vs_heavy: float = DAMAGE.resolve_enemy_weakspot_damage(
		15.75, 107.0, 148.0, 0.10, 1.0, heavy.weakspot_armor_mul, heavy.weakspot_damage_mul, 1.15)
	_check(ws_vs_heavy > body_vs_heavy * 3.0,
		"weakspot armor thinning lets 9mm AP penetrate heavy visor and deal >3x torso dmg (%.1f vs %.1f)" % [
			ws_vs_heavy, body_vs_heavy])
	# AWM (weapon_weakspot_mul=1.40) 对比 G17 (1.15) 弱点倍率精确线性体现
	var ws_awm: float = DAMAGE.resolve_enemy_weakspot_damage(100.0, 200.0, 100.0, 0.08, 1.0, 0.5, 1.6, 1.40)
	var ws_g17: float = DAMAGE.resolve_enemy_weakspot_damage(100.0, 200.0, 100.0, 0.08, 1.0, 0.5, 1.6, 1.15)
	_check(is_equal_approx(ws_awm / ws_g17, 1.40 / 1.15),
		"weapon inherent weakspot_mul scales weakspot damage linearly (AWM 1.40 vs G17 1.15)")

	# ---- 3) BallisticsModel 轻量伪 3D 高度与预判提前量保护 ----
	var p_open := BALLISTICS.compute_pseudo3d_profile(
		Vector2.ZERO, Vector2(320, 0), Vector2.RIGHT, 1500.0, 1200.0, [])
	_check(not bool(p_open["flat_shot"]) and float(p_open["vz_per_px"]) < 0.0
		and is_equal_approx(float(p_open["ground_dist_px"]), 320.0),
		"aiming at near-mid empty ground (5m) computes descending pseudo-3D z slope")

	var p_far := BALLISTICS.compute_pseudo3d_profile(
		Vector2.ZERO, Vector2(960, 0), Vector2.RIGHT, 2000.0, 1200.0, [])
	_check(bool(p_far["flat_shot"]) and is_equal_approx(float(p_far["vz_per_px"]), 0.0),
		"aiming at far empty ground (>12m) stays flat for downrange suppression")

	var p_cqb := BALLISTICS.compute_pseudo3d_profile(
		Vector2.ZERO, Vector2(48, 0), Vector2.RIGHT, 1500.0, 1200.0, [])
	_check(bool(p_cqb["flat_shot"]), "point-blank shot (<1.5m) stays flat")

	# 关键约束：瞄准移动敌人前方的空地（预判提前量）必须保持平射，绝不截断！
	var moving_enemies := [{
		"pos": Vector2(420, -140),
		"body": Vector2(420, -180),
		"vel": Vector2(0, 260),
		"radius": 18.0,
	}]
	var p_lead := BALLISTICS.compute_pseudo3d_profile(
		Vector2.ZERO, Vector2(420, -60), Vector2(420, -60).normalized(), 1500.0, 1100.0, moving_enemies)
	_check(bool(p_lead["flat_shot"]) and is_equal_approx(float(p_lead["vz_per_px"]), 0.0),
		"leading ahead of a moving enemy stays strictly flat and never truncates lead shots")

	# 敌人位于射线后方走廊时，瞄准敌人身前的空地也必须保持平射，不会中途砸地
	var corridor_enemies := [{
		"pos": Vector2(680, 0),
		"body": Vector2(680, -40),
		"vel": Vector2.ZERO,
		"radius": 18.0,
	}]
	var p_corridor := BALLISTICS.compute_pseudo3d_profile(
		Vector2.ZERO, Vector2(300, -18), Vector2(300, -18).normalized(), 1500.0, 1200.0, corridor_enemies)
	_check(bool(p_corridor["flat_shot"]),
		"aiming in front of a downrange enemy along the aim corridor stays flat")

	# ---- 4) 实机 Main2D 验证：弱点优先命中 + 金红飘字 + 准心标记 + 空地落地扬尘 ----
	var p = root.get_node_or_null("Progress")
	if p != null:
		p.reset_for_test()
		p.data["loadout_2d"] = ["g17", "awm"]

	var main = load("res://scenes/core/Main2D.tscn").instantiate()
	main.mouse_aim_enabled = false
	root.add_child(main)
	await process_frame
	await physics_frame

	for node in main.find_children("*", "StaticBody2D", true, false):
		if node.collision_layer & 1:
			node.collision_layer = 0
	for e in main.enemies:
		e.set_physics_process(false)
		e.global_position = Vector2(-10000, -10000)

	var doll = main.doll
	var base_pos := Vector2(1800, 1800)
	doll.global_position = base_pos

	# 4a) 瞄准近中距纯空地（320px = 5m）：自然斜向落地并触发扬尘特效，而非飞满 23.5m 射程
	var dust_before := 0
	for child in main.fx_layer.get_children():
		if child.get_meta("ground_dust_fx", false):
			dust_before += 1
	await _fire_zero_spread(main, base_pos + Vector2(320, -20))
	var dust_after := 0
	for child in main.fx_layer.get_children():
		if child.get_meta("ground_dust_fx", false):
			dust_after += 1
	_check(not main.combat_system.last_shot_flat and dust_after > dust_before,
		"open-ground near-mid shot pitches down and spawns ground_dust_fx (flat=%s, dust=%d->%d)" % [
			str(main.combat_system.last_shot_flat), dust_before, dust_after])

	# 4b) 实机弱点优先命中对比：同一把 G17 对巡猎者一型（胸口反应核）射击下身 vs 弱点
	var elite := Enemy2D.new()
	elite.setup(&"hunter_type1", base_pos + Vector2(320, 40), 1)
	elite.hp = 1000.0
	elite.hp_max = 1000.0
	main.sort_layer.add_child(elite)
	elite.set_physics_process(false)
	main.enemies.append(elite)
	await physics_frame
	await physics_frame
	_check(elite.has_weakspot() and elite.weakspot_radius() > 16.0,
		"live hunter_type1 builds Weakspot Area2D with tolerance radius (%.1f)" % elite.weakspot_radius())

	# 射下身/脚部（非弱点）
	var hp_a: float = elite.hp
	await _fire_zero_spread(main, elite.ground_center() + Vector2(0, -4))
	var body_dealt: float = hp_a - elite.hp
	var body_was_ws: bool = main.combat_system.last_hit_weakspot

	# 射胸口反应核弱点（子弹先过外层 Hitbox 胶囊再入弱点，验证射线优先弱点结算）
	var hp_b: float = elite.hp
	await _fire_zero_spread(main, elite.weakspot_world_pos())
	var ws_dealt: float = hp_b - elite.hp
	var ws_was_ws: bool = main.combat_system.last_hit_weakspot
	var has_ws_num := false
	for child in main.fx_layer.get_children():
		if child is DamageNumber2D and child.is_weakspot:
			has_ws_num = true
	_check(main.combat_system.last_shot_flat and not body_was_ws and ws_was_ws
		and ws_dealt > body_dealt * 2.0,
		"live weakspot shot prioritizes reactor core and deals >2x body dmg (ws=%.1f vs body=%.1f)" % [
			ws_dealt, body_dealt])
	_check(has_ws_num, "weakspot hit spawns dedicated gold-red DamageNumber2D (is_weakspot=true)")

	# 4c) 实机预判提前量：移动中的巡猎者前方 110px 空地开火，保持平射不提前砸地
	elite.global_position = base_pos + Vector2(440, -120)
	elite.velocity = Vector2(0, 240)
	await physics_frame
	var lead_aim := elite.body_center() + Vector2(0, 110)
	await _fire_zero_spread(main, lead_aim)
	_check(main.combat_system.last_shot_flat,
		"live lead shot ahead of moving enemy stays flat (never truncated into ground)")

	if p != null:
		p.reset_for_test()
	main.queue_free()
	await process_frame
	print("\n=== weakspot & pseudo3d: %s (%d ok / %d fail) ===" % [
		"PASS" if _fail == 0 else "FAIL", _pass, _fail])
	quit(0 if _fail == 0 else 1)
