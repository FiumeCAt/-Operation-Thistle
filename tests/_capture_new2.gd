extends SceneTree
## 临时截图：部署界面、护甲 HUD + 伤害飘字、M 键大地图。
## godot --path . --script res://tests/_capture_new2.gd -- --save-path user://capture_new2.json

func _initialize() -> void:
	call_deferred("_run")


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://" + path)


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var p = root.get_node_or_null("Progress")
	if p == null or not String(p.save_path).contains("capture_new2"):
		push_error("refusing to capture without an isolated save path")
		quit(1)
		return
	p.reset_for_test()
	p.data["deployment"] = {"spawn": "insertion", "extract": "east"}

	var menu = load("res://scenes/ui/StartMenu2D.tscn").instantiate()
	root.add_child(menu)
	for i in 30:
		await process_frame
	menu._start()
	menu.deployment._select(&"abandoned")
	for i in 20:
		await process_frame
	await _shot("screenshots/ui_deployment.png")
	menu.queue_free()
	await process_frame

	var main = load("res://scenes/core/Main2D.tscn").instantiate()
	main.mouse_aim_enabled = false
	root.add_child(main)
	for i in 25:
		await process_frame
	for enemy in main.enemies:
		enemy.set_process(false)
		enemy.set_physics_process(false)
	main.camera.position_smoothing_enabled = false
	main.doll.global_position = Vector2(60, 21) * 64.0
	for i in 20:
		await process_frame

	main.doll.invuln = 0.0
	main.doll.take_damage(30.0)
	var enemy = main.enemies[0]
	enemy.global_position = main.doll.global_position + Vector2(220, 0)
	enemy.hp = 100.0
	enemy.hp_max = 100.0
	main.doll.aim_target = enemy.global_position
	for i in 4:
		await physics_frame
	main.doll.weapon_rig.try_fire()
	for i in 2:
		await process_frame
	await _shot("screenshots/ui_hud_armor_damage.png")

	main.map_overlay.open()
	for i in 10:
		await process_frame
	await _shot("screenshots/ui_big_map.png")

	print("new2 capture done")
	quit()
