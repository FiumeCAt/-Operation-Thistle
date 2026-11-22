extends SceneTree
## 完整玩法流程录制：出生 → 走廊推进 → 进房交火 → 搜刮资源 → 撤离结算
## godot --path . --write-movie out/flow/frame.png --fixed-fps 30 --script res://tests/record_flow.gd

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var main = load("res://scenes/core/Main2D.tscn").instantiate()
	main.mouse_aim_enabled = false
	root.add_child(main)
	for i in 14:
		await process_frame
	var doll = main.doll
	var level: Level2D = main.level
	main.camera.zoom = Vector2(2.2, 2.2)

	# 出生点：向右推进一小段走廊
	doll.aim_target = doll.global_position + Vector2(200, 0)
	Input.action_press("move_right")
	for i in 44:
		await process_frame
	Input.action_release("move_right")
	for i in 8:
		await process_frame

	# 进入 0 号房间门口，瞄准最近的敌人开火
	var room: Dictionary = level.rooms[0]
	doll.global_position = room["door"] + Vector2(0, -56)
	main.camera.global_position = doll.global_position
	main.camera.reset_smoothing()
	for i in 8:
		await process_frame

	var nearest: Enemy2D = null
	var nearest_distance := 1e9
	for enemy in main.enemies:
		if not is_instance_valid(enemy):
			continue
		var d: float = enemy.global_position.distance_to(doll.global_position)
		if d < nearest_distance:
			nearest = enemy
			nearest_distance = d
	if nearest != null:
		doll.aim_target = nearest.global_position
	for i in 12:
		await process_frame
	for shot in 4:
		doll.weapon_rig.try_fire()
		for f in 9:
			await process_frame

	# 搜刮 0 号房间的补给箱
	var entry: Dictionary = level.containers[0]
	entry["loot"] = &"resource"
	doll.global_position = entry["position"] + Vector2(0, 54)
	main.camera.global_position = doll.global_position
	main.camera.reset_smoothing()
	for i in 10:
		await process_frame
	main._try_interact()
	for i in 20:
		await process_frame

	# 抵达撤离点并撤离
	doll.global_position = level.exit_position + Vector2(-150, 64)
	main.camera.global_position = level.exit_position + Vector2(-150, 64)
	main.camera.reset_smoothing()
	for i in 10:
		await process_frame
	doll.global_position = level.exit_position
	for i in 10:
		await process_frame
	main._try_interact()
	for i in 34:
		await process_frame
	quit()
