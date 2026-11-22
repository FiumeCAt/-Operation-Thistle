extends SceneTree
## 2D 扇形视野回归：视野角、贴脸察觉、朝向转动与盲眼单位。
## godot --headless --path . --script res://tests/vision_2d_test.gd

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
		enemy.queue_free()
	main.enemies.clear()
	await process_frame

	var hall: Dictionary = {}
	for room in main.level.rooms:
		if StringName(room["type"]) == &"hall":
			hall = room
			break
	var rect: Rect2 = hall["rect"]
	var spot: Vector2 = rect.position + Vector2(4.0, 5.0) * main.TILE
	var guard := _spawn(main, &"rifleman", spot)
	await process_frame
	await physics_frame
	var doll = main.doll

	_check(guard.view_half > 0.0 and guard.view_half < PI, "guard has a sector view angle")
	_check(is_equal_approx(rad_to_deg(guard.view_half) * 2.0, 110.0),
		"rifleman vision cone is 110 degrees")

	guard.view_dir = Vector2.RIGHT
	doll.global_position = spot + Vector2(-5.0, 0.0) * main.TILE
	await physics_frame
	_check(not guard.can_see_player(), "player behind the cone is not seen")

	guard.view_dir = Vector2.LEFT
	_check(guard.can_see_player(), "player in front of the cone is seen")

	var at_50 := Vector2.from_angle(deg_to_rad(50.0))
	var at_60 := Vector2.from_angle(deg_to_rad(60.0))
	guard.view_dir = Vector2.RIGHT
	doll.global_position = spot + at_50 * 5.0 * main.TILE
	_check(guard.can_see_player(), "50 degrees stays inside the 110-degree cone")
	doll.global_position = spot + at_60 * 5.0 * main.TILE
	_check(not guard.can_see_player(), "60 degrees falls outside the cone")

	# 贴脸：即使扇形背对也会察觉。
	guard.view_dir = Vector2.RIGHT
	doll.global_position = spot + Vector2(-1.2, 0.0) * main.TILE
	await physics_frame
	_check(guard.can_see_player(), "point-blank player is noticed even behind the cone")

	# 视野距离上限。
	guard.view_dir = Vector2.RIGHT
	doll.global_position = spot + Vector2(16.0, 0.0) * main.TILE
	await physics_frame
	_check(not guard.can_see_player(), "player beyond view range is not seen")

	# 战斗时朝向会转向玩家。
	doll.global_position = spot + Vector2(-5.0, 0.0) * main.TILE
	guard.view_dir = Vector2.RIGHT
	guard.state = "combat"
	var before := guard.view_dir.angle()
	guard._update_view_direction(0.2)
	var after := guard.view_dir.angle()
	var to_player: float = (doll.global_position - guard.global_position).angle()
	_check(absf(angle_difference(after, to_player)) < absf(angle_difference(before, to_player)),
		"combat vision turns toward the player")

	# 站岗时扇形缓慢扫视。
	guard.state = "patrol"
	guard.velocity = Vector2.ZERO
	var patrol_angle := guard.view_dir.angle()
	guard._update_view_direction(0.2)
	_check(not is_equal_approx(guard.view_dir.angle(), patrol_angle),
		"idle guard sweeps its vision cone")

	# 盲眼猎手不参与视觉扇形。
	var hunter := _spawn(main, &"hunter", spot + Vector2(2.0, 0.0) * main.TILE)
	await process_frame
	await physics_frame
	doll.global_position = hunter.global_position + Vector2(40, 0)
	_check(not hunter.can_see_player(), "blind hunter does not use visual sight")

	# 头顶警觉图标：看见玩家时播放 8 帧红色感叹号，随后淡出。
	guard.set_physics_process(true)
	guard.view_dir = Vector2.LEFT
	doll.global_position = spot + Vector2(-5.0, 0.0) * main.TILE
	await physics_frame
	await physics_frame
	_check(guard._alert_icon != null and guard._alert_icon.visible,
		"discovering the player shows the alert icon")
	_check(guard._alert_icon.hframes == 8, "alert icon has eight animation frames")
	_check(guard._alert_icon.position.y < -guard._sprite_h,
		"alert icon floats above the enemy head")
	var first_frame: int = guard._alert_icon.frame
	for i in 8:
		await physics_frame
	_check(guard._alert_icon.frame != first_frame,
		"alert icon advances through its frames")
	for i in 90:
		await physics_frame
	_check(not guard._alert_icon.visible, "alert icon fades out after being noticed")

	main.queue_free()
	await process_frame
	print("\n=== vision 2d: %s (%d ok / %d fail) ===" % [
		"PASS" if _fail == 0 else "FAIL", _pass, _fail])
	quit()


func _spawn(main, kind: StringName, pos: Vector2) -> Enemy2D:
	var enemy := Enemy2D.new()
	enemy.setup(kind, pos, 1)
	main.sort_layer.add_child(enemy)
	enemy.set_physics_process(false)
	main.enemies.append(enemy)
	return enemy
