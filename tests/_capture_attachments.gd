extends SceneTree
## 临时截图：新配件槽位界面 + 下挂激光。
## godot --path . --script res://tests/_capture_attachments.gd

func _initialize() -> void:
	call_deferred("_run")


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://" + path)


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var p = root.get_node_or_null("Progress")
	if p != null:
		# 只改内存，不写盘，避免把截图用配件留进玩家存档。
		p.data["run_mode"] = "raid"
		p.data["map_id"] = "facility"
		p.data["resources"] = 3000
		p.data["advanced_2d"] = {
			"weapon_parts": 10, "electronic_core": 10,
			"high_energy_cell": 10, "military_alloy": 10,
		}
		p.data["loadout_2d"] = ["m870", "g17"]
		p.data["weapon_mods_2d"]["m870"] = {
			"stock": "heavy", "grip": "laser", "sight": "red_dot",
		}

	var menu = load("res://scenes/ui/StartMenu2D.tscn").instantiate()
	root.add_child(menu)
	for i in 30:
		await process_frame
	menu._open_armory()
	for i in 15:
		await process_frame
	menu.armory._show_page("mods")
	menu.armory._select_mod_item("m870")
	menu.armory._select_mod_slot("grip")
	for i in 15:
		await process_frame
	await _shot("screenshots/ui_attachments_mods.png")
	menu.armory._show_page("weapon")
	menu.armory._select(&"m870")
	for i in 10:
		await process_frame
	await _shot("screenshots/ui_attachments_data.png")
	menu.queue_free()
	await process_frame

	var main = load("res://scenes/core/Main2D.tscn").instantiate()
	main.mouse_aim_enabled = false
	root.add_child(main)
	for i in 30:
		await process_frame
	for enemy in main.enemies.duplicate():
		enemy.queue_free()
	main.enemies.clear()
	await process_frame
	var origin: Vector2 = Vector2(39.5, 60.5) * main.TILE
	main.doll.global_position = origin
	main.doll.aim_target = origin + Vector2.RIGHT * 500.0
	for i in 20:
		await process_frame
	await _shot("screenshots/ui_laser_sight.png")

	print("attachments capture done")
	quit()
