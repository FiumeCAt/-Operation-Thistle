extends SceneTree
## 临时：用 movie writer 录一段 360° 瞄准 + ADS，检查两段 IK 手臂的连续性。
## godot --path . --write-movie out/arm/frame.png --fixed-fps 30 --script res://tests/_arm_record.gd

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var main = load("res://scenes/core/Main2D.tscn").instantiate()
	main.mouse_aim_enabled = false
	root.add_child(main)
	for i in 10:
		await process_frame
	var doll = main.doll
	doll.aim_enabled = true
	for i in 4:
		await process_frame
	# 冻住 Main2D 的镜头逻辑，放大到能看清手臂
	main.set_process(false)
	var cam: Camera2D = main.get_node("Camera2D")
	cam.position_smoothing_enabled = false
	cam.zoom = Vector2(4.0, 4.0)
	cam.global_position = doll.global_position + Vector2(0, -60)

	# 360° 慢扫，每帧 6°
	for i in 180:
		var a := TAU * float(i) / 180.0
		doll.aim_target = doll.global_position + Vector2.from_angle(a) * 240.0
		await process_frame

	# 朝右 ADS 收枪
	Input.action_press("aim")
	doll.aim_target = doll.global_position + Vector2(240, 0)
	for i in 45:
		await process_frame
	doll.weapon_rig.try_fire()
	for i in 15:
		await process_frame
	Input.action_release("aim")
	for i in 20:
		await process_frame
	quit()
