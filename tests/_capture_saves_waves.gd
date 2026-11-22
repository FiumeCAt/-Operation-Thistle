extends SceneTree
## 截图：主菜单存档管理 + 浪潮第 11 波 HUD。
## godot --path . --script res://tests/_capture_saves_waves.gd -- --save-path user://capture_saves_waves.json

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
	if p == null or not String(p.save_path).contains("capture_saves_waves"):
		push_error("refusing to capture without an isolated save path")
		quit(1)
		return
	p.reset_for_test()

	# 槽位 1：常规行动存档。
	p.data["resources"] = 860
	p.data["xp"] = 120
	p.data["skill_level"] = 7
	p.data["talents_2d"] = {
		"hp": 3, "gun": 2, "move": 1, "reload": 1, "scavenge": 1, "loading": 0,
		"armor": 1, "magazine": 1, "reserve": 0, "magnet": 0,
	}
	p.data["materials_2d"] = {"electronics": 12, "energy": 6, "parts": 9}
	p.data["advanced_2d"] = {
		"weapon_parts": 3, "electronic_core": 2,
		"high_energy_cell": 1, "military_alloy": 2,
	}
	p.data["run_mode"] = "raid"
	p.save_to_slot(1)

	# 槽位 2：浪潮存档。
	p.data["resources"] = 1450
	p.data["xp"] = 260
	p.data["skill_level"] = 14
	p.data["talents_2d"] = {
		"hp": 5, "gun": 3, "move": 3, "reload": 3, "scavenge": 2, "loading": 1,
		"armor": 2, "magazine": 3, "reserve": 2, "magnet": 1,
	}
	p.data["materials_2d"] = {"electronics": 31, "energy": 18, "parts": 24}
	p.data["run_mode"] = "waves"
	p.save_to_slot(2)
	p.load_from_slot(1)

	var menu = load("res://scenes/ui/StartMenu2D.tscn").instantiate()
	root.add_child(menu)
	for i in 30:
		await process_frame
	await _shot(OUT_DIR + "/main_menu_saves.png")
	menu._open_saves()
	for i in 20:
		await process_frame
	await _shot(OUT_DIR + "/save_slots.png")
	menu.queue_free()
	await process_frame

	# 浪潮第 11 波：目标 70 个敌人。
	p.set_run_mode("waves")
	var main = load("res://scenes/core/Main2D.tscn").instantiate()
	main.mouse_aim_enabled = false
	root.add_child(main)
	for i in 20:
		await process_frame
	main._begin_wave(11)
	for i in 45:
		await process_frame
	# 把少量敌人挪到玩家附近入镜，总数仍保持第 11 波的 70。
	var offsets := [
		Vector2(260, -140), Vector2(340, 60), Vector2(-260, -160),
		Vector2(-340, 90), Vector2(140, 220), Vector2(-160, 240),
	]
	for i in mini(offsets.size(), main._wave_spawn_queue.size()):
		var entry: Dictionary = main._wave_spawn_queue.pop_front()
		entry["pos"] = main.doll.global_position + offsets[i]
		main._spawn_wave_enemy(entry)
	for enemy in main.enemies:
		enemy.set_physics_process(false)
	for i in 20:
		await process_frame
	await _shot(OUT_DIR + "/waves_wave11.png")

	print("saves/waves capture done")
	quit()
