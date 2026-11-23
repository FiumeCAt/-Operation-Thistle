extends SceneTree
## 墙边敌人受击回归测试：
## 复现并锁死“敌人贴在北墙/掩体下方或门框拐角旁时，子弹明明命中却被反穿墙或 2.5D 墙面投影吞掉”的 bug，
## 同时保证真正的隔墙穿射（敌人位于墙另一侧、仅头部/受击盒探出墙外）依然被严格拦截。
## godot --headless --path . --script res://tests/wall_edge_hit_test.gd

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


func _make_wall(parent: Node, center: Vector2, size: Vector2) -> StaticBody2D:
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	wall.collision_mask = 2
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	wall.add_child(shape)
	parent.add_child(wall)
	wall.global_position = center
	return wall


func _wait_bullets(main: Node) -> void:
	for _i in 35:
		await physics_frame
		var pending := false
		for child in main.fx_layer.get_children():
			if child is PlayerBullet2D:
				pending = true
				break
		if not pending:
			break
	for _i in 6:
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
	for _i in 10:
		await physics_frame
	rig.try_fire()
	await _wait_bullets(main)
	data.base_spread = old_base
	ammo.spread = old_ammo
	main._burst_spread = 0.0


func _run() -> void:
	var p = root.get_node_or_null("Progress")
	if p != null:
		p.reset_for_test()
		p.data["loadout_2d"] = ["g17"]

	var main = load("res://scenes/core/Main2D.tscn").instantiate()
	main.mouse_aim_enabled = false
	root.add_child(main)
	await process_frame
	await physics_frame
	for e in main.enemies:
		e.set_physics_process(false)

	var doll = main.doll
	var base_pos: Vector2 = main.level.player_spawn + Vector2(180, 120)
	# 清空合成测试墙附近的随机装卸区货箱/货架，避免不同随机种子在斜射射线上刷出障碍导致偶发假失败。
	for child in main.sort_layer.get_children():
		if child is StaticBody2D and child.global_position.distance_to(base_pos) < 380.0:
			child.queue_free()
	await process_frame
	await physics_frame
	doll.global_position = base_pos + Vector2(0, 170)

	var enemy := Enemy2D.new()
	enemy.setup(&"rifleman", base_pos + Vector2(0, 28), 1)
	enemy.nav_level = main.level
	enemy.hp = 160.0
	enemy.hp_max = 160.0
	main.sort_layer.add_child(enemy)
	enemy.set_physics_process(false)
	main.enemies.append(enemy)
	await physics_frame
	await physics_frame

	# 1) 核心复现：敌人紧贴北墙南侧（墙底 y = base_pos.y，敌人脚底在 base_pos.y + 28，
	#    脚底碰撞圆完全在开阔地面，但立绘与 body_center() 投影进了北墙内）。
	var north_wall := _make_wall(main, base_pos + Vector2(0, -32), Vector2(360, 64))
	await physics_frame
	await physics_frame

	# 1a) 正南瞄准下身/腿部
	var hp_before: float = enemy.hp
	await _fire_zero_spread(main, enemy.global_position + Vector2(0, -14))
	_check(enemy.hp < hp_before,
		"enemy hugging south side of north wall takes damage when shot from south (hp=%.1f -> %.1f)" % [hp_before, enemy.hp])

	# 1b) 正南偏左瞄准敌人视觉胸口 body_center()（胸口视觉上盖在北墙前，斜线会先擦到北墙底边）
	doll.global_position = base_pos + Vector2(-48, 165)
	hp_before = enemy.hp
	await _fire_zero_spread(main, enemy.body_center())
	_check(enemy.hp < hp_before,
		"aiming directly at chest of enemy hugging north wall deals damage (hp=%.1f -> %.1f)" % [hp_before, enemy.hp])

	# 2) 西南大角度斜射同一贴北墙敌人（瞄准胸口 & 下身均应命中）
	doll.global_position = base_pos + Vector2(-130, 145)
	hp_before = enemy.hp
	await _fire_zero_spread(main, enemy.body_center())
	_check(enemy.hp < hp_before,
		"diagonal chest shot at enemy hugging north wall deals damage (hp=%.1f -> %.1f)" % [hp_before, enemy.hp])

	# 3) 大体型敌人（hunter_type1，body_scale=0.5，body_center 高达 -72px）贴北墙也能正常击杀
	var big := Enemy2D.new()
	big.setup(&"hunter_type1", base_pos + Vector2(96, 34), 1)
	big.nav_level = main.level
	big.hp = 100.0
	big.hp_max = 100.0
	main.sort_layer.add_child(big)
	big.set_physics_process(false)
	main.enemies.append(big)
	await physics_frame
	await physics_frame
	doll.global_position = base_pos + Vector2(60, 190)
	var big_before: float = big.hp
	await _fire_zero_spread(main, big.body_center())
	_check(big.hp < big_before,
		"tall enemy (hunter_type1) hugging north wall takes chest damage (hp=%.1f -> %.1f)" % [big_before, big.hp])

	# 4) 玩家自己贴在北墙下方，向右水平射击贴同一面北墙的敌人也能命中
	doll.global_position = base_pos + Vector2(-95, 28)
	hp_before = enemy.hp
	await _fire_zero_spread(main, enemy.global_position + Vector2(0, -10))
	_check(enemy.hp < hp_before,
		"player hugging north wall can shoot enemy along the same wall (hp=%.1f -> %.1f)" % [hp_before, enemy.hp])

	# 5) 反穿墙防线不能退化：玩家站在北墙另一侧（北房间），向探出北墙顶部的敌人头顶开火仍必须拦截！
	doll.global_position = base_pos + Vector2(-120, -82)
	var big_wallbang_before: float = big.hp
	await _fire_zero_spread(main, Vector2(big.global_position.x, base_pos.y - 74))
	_check(is_equal_approx(big.hp, big_wallbang_before),
		"anti-wallbang preserved: shooting head protruding north through wall deals 0 damage (hp=%.1f)" % big.hp)

	# 5b) 反穿墙防线 2：敌人位于北墙北侧、玩家位于南侧，穿墙开火仍必须为 0 伤害
	var behind := Enemy2D.new()
	behind.setup(&"rifleman", base_pos + Vector2(0, -76), 1)
	behind.nav_level = main.level
	behind.hp = 100.0
	behind.hp_max = 100.0
	main.sort_layer.add_child(behind)
	behind.set_physics_process(false)
	main.enemies.append(behind)
	await physics_frame
	await physics_frame
	doll.global_position = base_pos + Vector2(0, 150)
	await _fire_zero_spread(main, behind.body_center())
	_check(is_equal_approx(behind.hp, 100.0),
		"anti-wallbang preserved: enemy behind north wall cannot be shot through wall (hp=%.1f)" % behind.hp)

	north_wall.queue_free()
	big.queue_free()
	behind.queue_free()
	await physics_frame
	await physics_frame

	# 6) 门框/竖墙拐角探身：敌人站在竖墙右侧空地，body_center() 被墙角斜线遮挡，
	#    但右半身清晰露出在门洞内，绕过墙角命中露出部位必须正常结算伤害。
	var corner_wall := _make_wall(main, base_pos + Vector2(-40, 0), Vector2(64, 96))
	enemy.global_position = base_pos + Vector2(2, 12)
	enemy.hp = 100.0
	enemy.hp_max = 100.0
	doll.global_position = base_pos + Vector2(-34, 240)
	await physics_frame
	await physics_frame
	hp_before = enemy.hp
	var aim_exposed: Vector2 = enemy.global_position + Vector2(14, -22)
	await _fire_zero_spread(main, aim_exposed)
	var corner_blocked_center: bool = not main._wall_between(main.last_shot_origin, enemy.body_center()).is_empty()
	_check(corner_blocked_center and enemy.hp < hp_before,
		"enemy peeking beside wall corner takes damage on exposed side even when body_center is clipped (hp=%.1f -> %.1f)" % [hp_before, enemy.hp])

	corner_wall.queue_free()
	if p != null:
		p.reset_for_test()
	main.queue_free()
	await process_frame
	await process_frame
	print("\n=== wall edge hit: %s (%d ok / %d fail) ===" % [
		"PASS" if _fail == 0 else "FAIL", _pass, _fail])
	quit(0 if _fail == 0 else 1)
