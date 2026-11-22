extends SceneTree
## 临时截图：高倍镜镜内放大、PSO/十字/全息准心。
## godot --path . --script res://tests/_capture_scope.gd

func _initialize() -> void:
	call_deferred("_run")


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://" + path)


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var p = root.get_node_or_null("Progress")
	if p != null:
		# 只改内存，不写盘。
		p.data["run_mode"] = "raid"
		p.data["map_id"] = "facility"
		p.data["loadout_2d"] = ["m870", "g17"]
		p.data["weapon_mods_2d"]["m870"] = {
			"stock": "heavy", "grip": "laser", "sight": "pso",
		}
		p.data["laser_color"] = "#39ff88"
		p.data["reticle_color"] = "#ff7a3c"

	var menu = load("res://scenes/ui/StartMenu2D.tscn").instantiate()
	root.add_child(menu)
	for i in 30:
		await process_frame
	menu._open_armory()
	for i in 12:
		await process_frame
	menu.armory._show_page("mods")
	menu.armory._select_mod_item("m870")
	for i in 12:
		await process_frame
	await _shot("screenshots/ui_attachment_colors.png")
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
	main.doll.set_physics_process(false)
	var target: Vector2 = origin + Vector2.RIGHT * 500.0
	var guard := Enemy2D.new()
	guard.setup(&"rifleman", target, 1)
	main.sort_layer.add_child(guard)
	guard.set_physics_process(false)
	main.doll.aim_target = target
	main.doll.weapon_rig.setup(&"m870")
	main.doll.weapon_rig.ads = true
	main.doll.ads = true
	for i in 30:
		await process_frame
	var ct: Transform2D = main.get_viewport().get_canvas_transform()
	print("player_screen=", ct * main.doll.global_position,
		" camera=", main.camera.global_position, " zoom=", main.camera.zoom,
		" ads_t=", main._ads_t, " scope_mul=", main.scope_magnification)
	await _shot("screenshots/ui_scope_pso.png")

	if p != null:
		p.data["weapon_mods_2d"]["m870"]["sight"] = "scope"
	main.doll.weapon_rig.setup(&"m870")
	main.doll.weapon_rig.ads = true
	for i in 20:
		await process_frame
	await _shot("screenshots/ui_scope_cross.png")

	if p != null:
		p.data["weapon_mods_2d"]["m870"]["sight"] = "holo"
	main.doll.weapon_rig.setup(&"m870")
	main.doll.weapon_rig.ads = true
	main.doll.aim_target = origin + Vector2.UP * 2.2 * main.TILE
	for i in 20:
		await process_frame
	await _shot("screenshots/ui_sight_holo.png")

	print("scope capture done")
	quit()
