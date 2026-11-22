extends SceneTree
## 临时诊断：真实鼠标瞄准下，比较准心、激光、中心弹方向。
## godot --path . --script res://tests/_capture_real_aim.gd

func _initialize() -> void:
	call_deferred("_run")


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://" + path)


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var p = root.get_node_or_null("Progress")
	if p != null:
		p.data["run_mode"] = "waves"
		p.data["map_id"] = "goliath_arena"
		p.data["loadout_2d"] = ["m870", "g17"]
		p.data["weapon_mods_2d"]["m870"] = {
			"stock": "heavy", "grip": "laser", "sight": "red_dot",
		}
		p.data["laser_color"] = "#39ff88"
	var main = load("res://scenes/core/Main2D.tscn").instantiate()
	root.add_child(main)
	for i in 30:
		await process_frame
	var origin: Vector2 = Vector2(50.0, 30.0) * main.TILE
	main.doll.global_position = origin
	Input.warp_mouse(Vector2(1200, 650))
	for i in 24:
		await process_frame
	Input.warp_mouse(Vector2(1200, 650))
	await process_frame
	await process_frame
	var aim: Vector2 = main.doll.aim_target
	var from: Vector2 = main.laser_sight._from
	var laser_dir: Vector2 = (main.laser_sight._to - from).normalized()
	var aim_dir: Vector2 = (aim - from).normalized()
	print("aim=", aim, " muzzle=", from)
	print("aim_dir=", aim_dir, " laser_dir=", laser_dir,
		" dot=", aim_dir.dot(laser_dir))
	main.doll.weapon_rig.cooldown = 0.0
	main.doll.weapon_rig.try_fire()
	await process_frame
	await process_frame
	print("shot_origin=", main.last_shot_origin, " shot_dir=", main.last_shot_dir,
		" shot_dot=", main.last_shot_dir.dot(aim_dir))
	await _shot("screenshots/ui_real_aim.png")
	print("real aim capture done")
	quit()
