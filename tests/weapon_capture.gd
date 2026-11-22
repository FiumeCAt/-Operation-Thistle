extends SceneTree
## M1 武器表现检查：8 个瞄准角各一张 + 开火 3 帧。
## godot --path . --script res://tests/weapon_capture.gd

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var main = load("res://scenes/core/Main2D.tscn").instantiate()
	root.add_child(main)
	main.mouse_aim_enabled = false
	for i in 24:
		await process_frame
	var doll = main.doll
	var center: Vector2 = doll.global_position
	for i in 8:
		var a := TAU * float(i) / 8.0
		doll.aim_target = center + Vector2.from_angle(a) * 240.0
		for f in 18:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://screenshots/wp_angle%d.png" % i)

	doll.aim_target = center + Vector2(240, 0)
	for f in 16:
		await process_frame
	doll.weapon_rig.try_fire()
	for k in 3:
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://screenshots/wp_fire%d.png" % k)
		await process_frame
	print("saved weapon shots")
	quit()
