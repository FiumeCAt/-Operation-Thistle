extends SceneTree
## M3 演示录制：连射 → 打空自动换弹 → 手动换弹 → 切枪到 M870 → 逐发装填 → 切回手枪
## godot --path . --write-movie out/m3/frame.png --fixed-fps 30 --script res://tests/record_m3.gd

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var main = load("res://scenes/core/Main2D.tscn").instantiate()
	main.mouse_aim_enabled = false
	root.add_child(main)
	for i in 10:
		await process_frame
	var doll = main.doll
	var rig: WeaponRig2D = doll.weapon_rig
	# 特写：默认 zoom 2 时角色太小，换弹动画看不清
	main.camera.zoom = Vector2(3.2, 3.2)
	doll.aim_target = doll.global_position + Vector2(240, 20)
	for i in 12:
		await process_frame

	# 连射 5 发
	for i in 5:
		rig.try_fire()
		for f in 8:
			await process_frame

	# 剩 1 发打空，再扣一次扳机触发自动换弹
	rig.mag = 1
	await process_frame
	rig.try_fire()
	for f in 8:
		await process_frame
	rig.try_fire()
	for f in 24:
		await process_frame

	# 打两发后手动按 R 换弹
	rig.try_fire()
	for f in 10:
		await process_frame
	rig.try_fire()
	for f in 10:
		await process_frame
	rig.reload()
	for f in 30:
		await process_frame

	# 切枪到 M870：下沉 → 换枪 → 抬起
	rig.switch_to(&"m870")
	for f in 22:
		await process_frame
	rig.try_fire()
	for f in 14:
		await process_frame
	rig.reload()
	for f in 26:
		await process_frame

	# 切回 G17
	rig.switch_to(&"g17")
	for f in 22:
		await process_frame
	quit()
