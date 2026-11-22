extends SceneTree

var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
	else:
		print("[ok] ", message)

func middle(rig: CameraRig, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_MIDDLE
	event.pressed = pressed
	rig._input(event)

func drag(rig: CameraRig, pixels: float) -> void:
	var event := InputEventMouseMotion.new()
	event.relative = Vector2(pixels, 0)
	event.screen_relative = event.relative
	rig._input(event)

func _run() -> void:
	seed(20261026)
	var main = load("res://scenes/core/Main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	for i in 8:
		await physics_frame
	main.process_mode = Node.PROCESS_MODE_DISABLED
	var doll: Doll = main.doll
	var rig: CameraRig = main.rig
	var camera: Camera3D = rig.cam
	var reticle: AimReticle = main.reticle
	rig.trauma = 0.0
	check(is_equal_approx(rig.pitch_deg, 58.0) and is_equal_approx(camera.fov, 38.0) and is_equal_approx(rig.distance, 12.0), "默认构图58度 / FOV38 / 12米")
	check(reticle.layer > main.motion_blur.layer and reticle.layer > main.hud.layer and reticle.layer > rig.get_node("RearVisibility").layer, "准心高于世界遮罩、模糊和HUD")
	check(reticle.layer < main.run_hud.layer and reticle._view.mouse_filter == Control.MOUSE_FILTER_IGNORE, "准心低于结算且不拦截鼠标")
	var fixed_rotation := rig.rotation
	var flat := Vector3(doll.global_position.x, 0, doll.global_position.z)
	rig.global_position = flat
	for i in 8:
		doll.rotation.y = float(i) * TAU / 8.0
		var motion := InputEventMouseMotion.new()
		motion.position = Vector2(200 + i * 100, 200 + i * 30)
		motion.relative = Vector2(100, 30)
		Input.parse_input_event(motion)
		rig._input(motion)
		rig._process(1.0 / 60.0)
		check(rig.rotation.is_equal_approx(fixed_rotation) and rig.global_position.is_equal_approx(flat), "鼠标和人物八向转动不旋转或前探镜头 %d" % i)
		var forward: Vector2 = rig._shade.get_shader_parameter("forward_xz")
		check(forward.is_equal_approx(Vector2(sin(doll.rotation.y), cos(doll.rotation.y))), "背部暗化仍跟随人物朝向 %d" % i)
	# 通过真实 Viewport 分发，不再只直接调用 _input 掩盖路由故障。
	rig.process_mode = Node.PROCESS_MODE_ALWAYS
	rig.set_process(false)
	var button := InputEventMouseButton.new()
	button.button_index = MOUSE_BUTTON_MIDDLE
	button.pressed = true
	root.push_input(button)
	check(rig.orbit_dragging, "Viewport中键事件到达镜头")
	var routed_motion := InputEventMouseMotion.new()
	routed_motion.relative = Vector2(100, 0)
	root.push_input(routed_motion, true)
	check(absf(angle_difference(rig.rotation.y, fixed_rotation.y - deg_to_rad(18))) < 0.00001, "Viewport相对位移后备驱动中键旋转")
	button.pressed = false
	root.push_input(button)
	check(not rig.orbit_dragging, "Viewport中键松开停止旋转")
	rig.rotation = fixed_rotation
	button = InputEventMouseButton.new()
	button.button_index = MOUSE_BUTTON_RIGHT
	button.position = Vector2(1400, 350)
	button.pressed = true
	Input.parse_input_event(button)
	Input.flush_buffered_events()
	check(Input.is_action_pressed("aim"), "实际右键事件匹配aim输入映射")
	var direction := rig._aim_direction
	rig._process(1.0 / 60.0)
	check(camera.position.z > 12.0 and camera.position.z < 16.0, "右键平滑开始拉远")
	for i in 240:
		doll._update_aim()
		doll._update_facing(1.0 / 60.0)
		rig._process(1.0 / 60.0)
	check(rig.global_position.distance_to(flat + direction * 2.0) < 0.001 and rig.rotation.is_equal_approx(fixed_rotation), "右键锁存方向前探2米且不旋转")
	check(absf(camera.position.z - 16.0) < 0.001 and is_equal_approx(camera.fov, 38.0), "右键拉远至16米保留FOV38")
	check(rig._aim_direction.is_equal_approx(direction), "镜头/角色/aim_point反馈不改变前探方向")
	button = button.duplicate()
	button.pressed = false
	Input.parse_input_event(button)
	Input.flush_buffered_events()
	check(not Input.is_action_pressed("aim"), "实际右键松开取消瞄准")
	rig._process(1.0 / 60.0)
	check(camera.position.z > 12.0 and camera.position.z < 16.0, "松开平滑回落")
	for i in 240:
		rig._process(1.0 / 60.0)
	check(rig.global_position.distance_to(flat) < 0.001 and absf(camera.position.z - 12.0) < 0.001, "松开回12米且清除前探")
	for fps in [30, 60, 144]:
		rig.global_position = flat - Vector3(4, 0, 3)
		var start := rig.global_position
		rig._process(1.0 / float(fps))
		check(rig.global_position.is_equal_approx(start.lerp(flat, 1.0 - exp(-rig.follow_speed / float(fps)))), "%d FPS指数平滑跟随" % fps)
		for i in fps * 3:
			rig._process(1.0 / float(fps))
		check(rig.global_position.distance_to(flat) < 0.001 and rig.rotation.is_equal_approx(fixed_rotation), "%d FPS跟随收敛无偏移" % fps)
	for fps in [30, 60, 144]:
		rig.rotation = fixed_rotation
		var old_mode := Input.mouse_mode
		middle(rig, true)
		var anchor := rig.aim_screen_position()
		check(rig.orbit_dragging, "%d FPS中键开启独立旋转" % fps)
		if DisplayServer.get_name() != "headless":
			check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "窗口模式实际捕获鼠标无屏幕边界")
		for i in fps:
			drag(rig, 600.0 / float(fps))
			rig._process(1.0 / float(fps))
		check(absf(angle_difference(rig.rotation.y, deg_to_rad(-108))) < 0.00002, "%d FPS同位移同角度" % fps)
		check(rig.aim_screen_position() == anchor, "捕获时准心锚点不跳到屏幕中心")
		doll._update_aim()
		check(camera.unproject_position(doll.aim_point).distance_to(anchor) < 0.01, "旋转后瞄准射线仍对齐准心")
		middle(rig, false)
		var stopped := rig.rotation
		drag(rig, 900)
		for i in fps:
			rig._process(1.0 / float(fps))
		check(rig.rotation.is_equal_approx(stopped) and not rig.orbit_dragging and Input.mouse_mode == old_mode, "%d FPS释放立即停止且恢复模式" % fps)
	for degrees in [179.0, -179.0]:
		rig.rotation.y = deg_to_rad(degrees)
		middle(rig, true)
		drag(rig, -20 if degrees > 0 else 20)
		var expected := deg_to_rad(degrees + (3.6 if degrees > 0 else -3.6))
		check(absf(angle_difference(rig.rotation.y, expected)) < 0.00001 and absf(rig.rotation.y) <= PI, "跨越正负180度连续旋转")
		middle(rig, false)
	middle(rig, true)
	rig._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	var focus_yaw := rig.rotation.y
	drag(rig, 100)
	middle(rig, true)
	check(not rig.orbit_dragging and rig.rotation.y == focus_yaw and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED, "失焦释放捕获并拒绝旋转")
	rig._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	drag(rig, 100)
	check(rig.rotation.y == focus_yaw, "恢复焦点不自动续转")
	rig.rotation = fixed_rotation
	middle(rig, true)
	var before := rig.transform
	paused = true
	doll.global_position += Vector3.RIGHT
	rig._process(1.0)
	middle(rig, true)
	drag(rig, 100)
	check(rig.transform == before and not rig.orbit_dragging and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED, "暂停冻结镜头并取消拖动")
	paused = false
	doll.global_position -= Vector3.RIGHT
	var args := OS.get_cmdline_user_args()
	if args.has("--capture") and DisplayServer.get_name() != "headless":
		var folder := args[args.find("--capture") + 1]
		DirAccess.make_dir_recursive_absolute(folder)
		main.motion_blur.set_enabled(false)
		Input.mouse_mode = Input.MOUSE_MODE_CONFINED_HIDDEN
		Input.warp_mouse(Vector2(1180, 330))
		for pose in [0, 1]:
			doll.debug_set_state("aim" if pose == 1 else "idle")
			doll._update_aim()
			doll._update_facing(1.0)
			main.weapon_visual.sync_pose()
			rig._process(1.0)
			reticle._process(1.0)
			await process_frame
			await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png(folder.path_join("reticle_%d.png" % pose)) == OK, "真实准心截图")
	middle(rig, true)
	main.finish_run(false)
	check(not reticle.visible and paused and not rig.orbit_dragging and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "拖动中死亡结算隐藏准心、解除捕获、显示系统鼠标并暂停")
	paused = false
	print("CAMERA TEST: %d checks, %d failures" % [checks, failures])
	main.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)

