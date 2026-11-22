extends SceneTree
## 关卡截图：出生点、北侧房间、南侧房间、撤离点。
## godot --path . --script res://tests/capture_level.gd

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var main = load("res://scenes/core/Main2D.tscn").instantiate()
	main.mouse_aim_enabled = false
	root.add_child(main)
	for i in 24:
		await process_frame
	var doll = main.doll
	var level: Level2D = main.level
	# 截图时先冻住敌人，避免被打断
	for e in main.enemies:
		e.set_physics_process(false)

	var shots := [
		["spawn", level.player_spawn],
		["room0", level.rooms[0]["center"]],
		["room1", level.rooms[1]["center"]],
		["room2", level.rooms[2]["center"]],
		["exit", level.exit_position + Vector2(-160, 0)],
	]
	for entry in shots:
		doll.global_position = entry[1]
		main.camera.global_position = entry[1]
		main.camera.reset_smoothing()
		for f in 12:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://screenshots/lvl_%s.png" % entry[0])
		print("saved ", entry[0])
	print("done")
	quit()
