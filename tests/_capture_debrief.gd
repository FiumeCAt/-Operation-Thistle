extends SceneTree
## 临时截图：主菜单资源图标、行动结算、TAB 背包。
## godot --path . --script res://tests/_capture_debrief.gd -- --save-path user://capture_debrief.json


func _initialize() -> void:
	call_deferred("_run")


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://" + path)


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var p = root.get_node_or_null("Progress")
	if p == null or not String(p.save_path).contains("capture_debrief"):
		push_error("refusing to capture without an isolated save path")
		quit(1)
		return
	p.data["resources"] = 260
	p.data["xp"] = 40
	p.data["skill_level"] = 3
	p.data["materials_2d"] = {"electronics": 12, "energy": 8, "parts": 15}
	p.data["advanced_2d"] = {
		"weapon_parts": 6, "electronic_core": 2,
		"high_energy_cell": 3, "military_alloy": 1,
	}

	var menu = load("res://scenes/ui/StartMenu2D.tscn").instantiate()
	root.add_child(menu)
	for i in 30:
		await process_frame
	await _shot("screenshots/ui_start.png")
	menu._open_stash()
	for i in 15:
		await process_frame
	await _shot("screenshots/ui_stash.png")
	menu.stash.close_menu()
	menu.queue_free()
	await process_frame

	var main = load("res://scenes/core/Main2D.tscn").instantiate()
	main.mouse_aim_enabled = false
	root.add_child(main)
	for i in 20:
		await process_frame
	main.loot = {"electronics": 3, "energy": 2, "parts": 4}
	main.advanced_loot = {"weapon_parts": 2, "electronic_core": 1}
	main.resources = 12
	main.kills = 5
	main.shots_fired = 23
	main.shots_hit = 15
	main.damage_dealt = 812.0
	main.run_elapsed = 252.0
	main._finish_run(true)
	for i in 10:
		await process_frame
	await _shot("screenshots/ui_result.png")

	main.backpack.open()
	for i in 10:
		await process_frame
	await _shot("screenshots/ui_backpack.png")
	main.backpack.close()

	print("debrief capture done")
	quit()
