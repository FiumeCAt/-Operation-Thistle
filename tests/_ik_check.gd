extends SceneTree
## 临时：8 向瞄准特写，检查两段 IK 手臂。
## godot --path . --script res://tests/_ik_check.gd

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var main = load("res://scenes/core/Main2D.tscn").instantiate()
	main.mouse_aim_enabled = false
	root.add_child(main)
	await process_frame
	var cam: Camera2D = main.get_node("Camera2D")
	cam.position_smoothing_enabled = false
	cam.limit_left = -10000
	cam.limit_top = -10000
	cam.limit_right = 10000
	cam.limit_bottom = 10000
	cam.zoom = Vector2(3.0, 3.0)
	var doll = main.doll
	doll.aim_enabled = true
	for i in 16:
		await process_frame
	# Main2D 每帧会把镜头 zoom 拉回 2.0，这里冻结它以便拍特写
	main.set_process(false)
	cam.zoom = Vector2(6.0, 6.0)
	cam.global_position = doll.global_position + Vector2(0, -70)
	for i in 4:
		await process_frame

	for i in 8:
		var a := TAU * float(i) / 8.0
		doll.aim_target = doll.global_position + Vector2.from_angle(a) * 220.0
		for j in 10:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://screenshots/ik_%d.png" % i)
		var rig: WeaponRig2D = doll.weapon_rig
		print("dir %d aim=%.1f barrel=%s" % [i, rad_to_deg(rig.aim_angle), rig.get_barrel_direction()])

	# ADS 姿态
	Input.action_press("aim")
	doll.aim_target = doll.global_position + Vector2(220, 0)
	for i in 30:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://screenshots/ik_ads.png")
	Input.action_release("aim")
	print("saved ik checks")
	quit()
