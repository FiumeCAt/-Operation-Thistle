extends SceneTree
## 分层视野 / 视野迷雾回归：三层光照、视野层级判定、敌人可见性与墙体遮挡。
## godot --headless --path . --script res://tests/vision_fog_2d_test.gd

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


func _run() -> void:
	create_timer(60.0).timeout.connect(func() -> void: quit(2))
	root.size = Vector2i(1600, 900)
	var p = root.get_node_or_null("Progress")
	if p != null:
		p.reset_for_test()
	var main = load("res://scenes/core/Main2D.tscn").instantiate()
	main.mouse_aim_enabled = false
	root.add_child(main)
	await process_frame
	await physics_frame

	# 清空预生成敌人，避免干扰视野判定。
	for enemy in main.enemies.duplicate():
		enemy.queue_free()
	main.enemies.clear()
	await process_frame

	var fog = main.vision
	_check(fog != null, "vision fog node exists")
	_check(fog._clear_light != null and fog._dark_light != null and fog._self_light != null,
		"three vision lights exist")
	_check(fog._clear_light.texture != null and fog._dark_light.texture != null,
		"layer light textures generated")
	_check(fog._clear_light.shadow_enabled and fog._dark_light.shadow_enabled
		and not fog._self_light.shadow_enabled,
		"vision cone and dark vision cast shadows; self light skips them")
	_check(main.canvas_modulate.color.is_equal_approx(fog.AMBIENT),
		"world ambient is darkened into fog")
	_check(fog._clear_light.get_parent() == fog and fog.get_parent() == main.get_node("World2D"),
		"vision lights live in the world canvas")

	# 几何层级测试：暂时去掉视线遮挡，保证只验证角度/距离分层。
	var saved_level = fog.level
	fog.level = null
	var tile: float = main.TILE
	var origin := Vector2(1728, 1088)
	main.doll.global_position = origin
	main.doll.aim_target = origin + Vector2.RIGHT * 600.0
	fog._aim_angle = 0.0

	_check(fog.tier_at(origin + Vector2(5, 0) * tile) == 2, "front point is clear vision")
	_check(fog.tier_at(origin + Vector2(30, 0) * tile) == 2, "far front point stays clear")
	_check(fog.tier_at(origin + Vector2(42, 0) * tile) == 0, "point beyond 40m is fog")
	_check(fog.tier_at(origin + Vector2(-2, 0) * tile) == 1,
		"close point behind is relative dark")
	_check(fog.tier_at(origin + Vector2(-9, 0) * tile) == 0, "far point behind is fog")
	var ring_point := origin + Vector2.from_angle(deg_to_rad(45.0)) * 5.0 * tile
	_check(fog.tier_at(ring_point) == 1, "peripheral ring is relative dark")
	var outside := origin + Vector2.from_angle(deg_to_rad(75.0)) * 5.0 * tile
	_check(fog.tier_at(outside) == 0, "outside total cone is fog")
	# 瞄具：视野距离倍率应扩大主锥可达距离。
	fog.vision_mul = 1.35
	_check(fog.tier_at(origin + Vector2(34, 0) * tile) == 2,
		"sight extends the clear vision range")
	fog.vision_mul = 1.0

	# 回归：玩家头部落在上方墙格、脚底在可走地面时，视野内的敌人不能被误隐藏。
	# 导航网格是地面占用，视线必须从脚底出发，不能用头部高度。
	var saved_player = fog.player
	var saved_process: bool = fog.is_processing()
	var fake_player := HeadBlockPlayer.new()
	fake_player.global_position = Vector2(1000, 1000)
	fake_player.aim_target = Vector2(1600, 1000)
	fog.player = fake_player
	fog.level = HeadBlockLevel.new()
	fog.set_process(false)
	fog._aim_angle = 0.0
	fog.vision_mul = 1.0
	_check(fog.tier_at(Vector2(1500, 1000)) == 2,
		"head in a blocked cell does not hide an enemy in clear view")
	fog.player = saved_player
	fog.level = saved_level
	fog.set_process(saved_process)
	fake_player.free()

	# 实图回归：找一处“脚底可走、头部在墙格”的玩家位置，前方敌人仍必须可见。
	var found_spot := false
	var spot := Vector2.ZERO
	for y in range(1, main.level._nav_h - 1):
		for x in range(1, main.level._nav_w - 1):
			var feet := Vector2(x + 0.5, y + 0.5) * tile
			if not main.level.is_nav_walkable(feet):
				continue
			if main.level.is_nav_walkable(feet + Vector2(0, -82.0)):
				continue
			var clear := true
			for k in range(1, 5):
				if not main.level.is_nav_walkable(feet + Vector2(k * tile, 0)):
					clear = false
					break
			if clear:
				spot = feet
				found_spot = true
				break
		if found_spot:
			break
	_check(found_spot, "found a spot with head in a wall cell and clear ground ahead")
	if found_spot:
		main.doll.global_position = spot
		main.doll.aim_target = spot + Vector2.RIGHT * 600.0
		fog._aim_angle = 0.0
		var real_enemy := _spawn(main, &"rifleman", spot + Vector2(4 * tile, 0))
		await process_frame
		fog.refresh_enemies()
		_check(fog.tier_at(real_enemy.global_position) == 2,
			"enemy in clear view is not culled when the player's head is in a wall cell")
		_check(real_enemy.visible, "enemy sprite stays visible in the same case")
		_check(not fog.line_clear(fog._eye_position(), real_enemy.global_position),
			"head-based LOS would have failed at this spot")
		real_enemy.queue_free()
		main.doll.global_position = origin
		main.doll.aim_target = origin + Vector2.RIGHT * 600.0
		fog._aim_angle = 0.0
		await process_frame

	# 敌人可见性：清晰=正常，近身/余光=压暗，迷雾=隐藏。
	var front := _spawn(main, &"rifleman", origin + Vector2(4, 0) * tile)
	var near := _spawn(main, &"rifleman", origin + Vector2(-2, 0) * tile)
	var far := _spawn(main, &"rifleman", origin + Vector2(-9, 0) * tile)
	await process_frame
	fog._aim_angle = 0.0
	fog.refresh_enemies()
	_check(front.visible, "enemy in clear cone is visible")
	_check(near.visible, "enemy inside darkvision stays visible")
	_check(not far.visible, "enemy in fog is hidden")
	_check(front.modulate == Color.WHITE, "clear enemy is not tinted")
	_check(near.modulate != Color.WHITE, "relative-dark enemy uses dim tint")

	# 墙体遮挡：导航网格在墙格上不可行走，视线必须被打断。
	fog.level = saved_level
	var wall_point := _find_wall(main, origin, 24)
	_check(wall_point != Vector2.INF, "found a wall cell near the test spot")
	if wall_point != Vector2.INF:
		var dir := (wall_point - origin).normalized()
		_check(not fog.line_clear(origin, wall_point + dir * tile),
			"walls block line of sight")
	var occluders: Array = main.sort_layer.find_children("*", "LightOccluder2D", true, false)
	_check(occluders.size() > 50, "walls and props carry light occluders")
	if not occluders.is_empty():
		var occ := occluders[0] as LightOccluder2D
		_check(occ != null and occ.occluder != null and occ.occluder.polygon.size() >= 4,
			"light occluders have closed polygons")

	# 灯光跟随与 F7 调试照明。
	main.doll.global_position = origin + Vector2(64, 0)
	await process_frame
	_check(fog._clear_light.global_position.distance_to(
		main.doll.head_position()) < 30.0,
		"vision light starts from the player's head")
	fog.set_debug(true)
	_check(main.canvas_modulate.color == Color.WHITE and not fog._clear_light.visible,
		"debug mode restores full brightness")
	_check(far.visible, "debug mode reveals all enemies")
	fog.set_debug(false)
	_check(main.canvas_modulate.color.is_equal_approx(fog.AMBIENT)
		and fog._clear_light.visible, "leaving debug mode restores the fog")

	front.queue_free()
	near.queue_free()
	far.queue_free()
	main.queue_free()
	await process_frame
	print("\n=== vision fog: %s (%d ok / %d fail) ===" % [
		"PASS" if _fail == 0 else "FAIL", _pass, _fail])
	quit()


func _spawn(main, kind: StringName, pos: Vector2) -> Enemy2D:
	var enemy := Enemy2D.new()
	enemy.setup(kind, pos, 1)
	main.sort_layer.add_child(enemy)
	enemy.set_physics_process(false)
	return enemy


## 从玩家位置向外找一格最近的不可行走格（墙体或家具）。
func _find_wall(main, origin: Vector2, radius_tiles: int) -> Vector2:
	var tile: float = main.TILE
	var base := Vector2i(int(origin.x / tile), int(origin.y / tile))
	for r in range(1, radius_tiles + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var probe := Vector2(base.x + dx + 0.5, base.y + dy + 0.5) * tile
				if not main.level.is_nav_walkable(probe):
					return probe
	return Vector2.INF


## 测试用关卡：只有 y >= 950 的地面可走，模拟“头部在墙格、脚底在可走地面”。
class HeadBlockLevel:
	func is_nav_walkable(pos: Vector2) -> bool:
		return pos.y >= 950.0


## 测试用玩家：头部比脚底高 100px。
class HeadBlockPlayer extends Node2D:
	var aim_target := Vector2.ZERO
	var weapon_rig = null

	func head_position() -> Vector2:
		return global_position + Vector2(0, -100.0)
