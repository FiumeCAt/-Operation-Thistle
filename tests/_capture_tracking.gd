extends SceneTree
## 截图：浪潮收尾时小地图/大地图全敌人标红。
## godot --path . --script res://tests/_capture_tracking.gd -- --save-path user://capture_tracking.json

const OUT_DIR := "D:/AI Game/temp_20261027_01/screenshots"


func _initialize() -> void:
	call_deferred("_run")


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)


func _run() -> void:
	root.size = Vector2i(1600, 900)
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var p = root.get_node_or_null("Progress")
	if p == null or not String(p.save_path).contains("capture_tracking"):
		push_error("refusing to capture without an isolated save path")
		quit(1)
		return
	p.reset_for_test()
	p.set_run_mode("waves")

	var main = load("res://scenes/core/Main2D.tscn").instantiate()
	main.mouse_aim_enabled = false
	root.add_child(main)
	for i in 20:
		await process_frame

	# 第 10 波共 59 只，留下 5 只，触发「少于 10 只 / 少于 10%」追踪。
	main._begin_wave(10)
	while not main._wave_spawn_queue.is_empty():
		main._spawn_wave_enemy(main._wave_spawn_queue.pop_front())
	var keep := 5
	var victims: Array = main.enemies.duplicate()
	for i in victims.size():
		if i < keep:
			continue
		victims[i].take_damage(999999.0)
	for enemy in main.enemies:
		enemy.set_physics_process(false)
	for i in 45:
		await process_frame
	print("remaining=", main.wave_alive, " tracking=", main.waves_tracking_active())
	await _shot(OUT_DIR + "/waves_tracking_minimap.png")

	main.map_overlay.open()
	for i in 20:
		await process_frame
	await _shot(OUT_DIR + "/waves_tracking_map.png")
	main.map_overlay.close()

	print("tracking capture done")
	quit()
