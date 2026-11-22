extends SceneTree
## M1 武器表现演示：站立瞄准扫射 → 边走边瞄准。
## godot --path . --write-movie out/weapon/frame.png --fixed-fps 30 --script res://tests/record_weapon.gd

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var main = load("res://scenes/core/Main2D.tscn").instantiate()
	main.mouse_aim_enabled = false
	root.add_child(main)
	for i in 10:
		await process_frame
	var doll = main.doll
	var center: Vector2 = doll.global_position

	# 360° 慢扫 + 每 12 帧开一枪
	var sweep := 72
	for i in sweep:
		var a := TAU * float(i) / float(sweep)
		doll.aim_target = center + Vector2.from_angle(a) * 240.0
		if i % 12 == 6:
			doll.weapon_rig.try_fire()
		await process_frame

	# 持枪四向行走：验证走动中仍是双手举枪
	var walk_dirs := [
		["move_right", Vector2(200.0, 0.0)],
		["move_back", Vector2(0.0, 200.0)],
		["move_forward", Vector2(0.0, -200.0)],
		["move_left", Vector2(-200.0, 0.0)],
	]
	for entry in walk_dirs:
		Input.action_press(entry[0])
		for i in 22:
			doll.aim_target = doll.global_position + entry[1]
			await process_frame
		Input.action_release(entry[0])

	# 朝右前方边走边打
	doll.aim_target = doll.global_position + Vector2(200, 40)
	Input.action_press("move_right")
	for i in 40:
		doll.aim_target = doll.global_position + Vector2(200, 40)
		if i % 10 == 0:
			doll.weapon_rig.try_fire()
		await process_frame
	Input.action_release("move_right")

	# 冲刺时朝上（武器在身后）
	doll.aim_target = doll.global_position + Vector2(0, -200)
	Input.action_press("sprint")
	Input.action_press("move_forward")
	for i in 34:
		doll.aim_target = doll.global_position + Vector2(0, -200)
		await process_frame
	Input.action_release("move_forward")
	Input.action_release("sprint")
	for i in 10:
		await process_frame
	quit()
