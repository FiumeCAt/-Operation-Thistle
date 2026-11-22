extends SceneTree
## 临时截图：射击中心线与激光、枪口起点对齐。
## godot --path . --script res://tests/_capture_shot_align.gd

func _initialize() -> void:
	call_deferred("_run")


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://" + path)


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var p = root.get_node_or_null("Progress")
	if p != null:
		p.data["run_mode"] = "raid"
		p.data["map_id"] = "facility"
		p.data["loadout_2d"] = ["m870", "g17"]
		p.data["weapon_mods_2d"]["m870"] = {
			"stock": "heavy", "grip": "laser", "sight": "red_dot",
		}
		p.data["laser_color"] = "#39ff88"
		p.data["reticle_color"] = "#ff7a3c"
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
	main.doll.aim_target = origin + Vector2(700.0, 300.0)
	main.doll.weapon_rig.setup(&"m870")
	for i in 12:
		await process_frame
	main.doll.weapon_rig.cooldown = 0.0
	main.doll.weapon_rig.try_fire()
	await process_frame
	await process_frame
	await _shot("screenshots/ui_shot_align.png")
	print("shot align capture done")
	quit()
