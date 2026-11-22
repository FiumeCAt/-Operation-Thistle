extends SceneTree
## Esc 设置菜单、音量、动态模糊与三档摄像机预设。

var _main: Node3D
var _checks := 0
var _fails := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	_checks += 1
	if ok:
		print("  [ok] ", message)
	else:
		_fails += 1
		push_error("  [FAIL] " + message)

func _frames(count := 4) -> void:
	for i in count:
		await physics_frame
		await process_frame

func _press_escape(pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.physical_keycode = KEY_ESCAPE
	event.pressed = pressed
	Input.parse_input_event(event)
	await _frames(3)

func _run() -> void:
	print("=== Operation Thistle settings test ===")
	create_timer(90.0).timeout.connect(func() -> void: quit(2))
	var progress = root.get_node_or_null("Progress")
	_check(progress != null, "Progress autoload 存在")
	if progress == null:
		quit(1)
		return

	progress.reset_for_test()
	_check(is_equal_approx(float(progress.data["volume"]), 0.8), "默认音量 0.8")
	_check(bool(progress.data["motion_blur"]), "默认开启动态模糊")
	_check(int(progress.data["camera_mode"]) == 1, "默认标准镜头")
	progress.set_volume(2.0)
	_check(is_equal_approx(float(progress.data["volume"]), 1.0), "音量上限裁剪")
	progress.set_volume(-1.0)
	_check(is_equal_approx(float(progress.data["volume"]), 0.0), "音量下限裁剪")
	progress.set_camera_mode(9)
	_check(int(progress.data["camera_mode"]) == 2, "镜头模式上限裁剪")
	progress.set_volume(0.5)
	progress.set_motion_blur(false)
	progress.set_camera_mode(2)
	progress.load_data()
	_check(is_equal_approx(float(progress.data["volume"]), 0.5)
		and not bool(progress.data["motion_blur"])
		and int(progress.data["camera_mode"]) == 2, "设置项可持久化")

	change_scene_to_file("res://scenes/core/Main.tscn")
	await _frames(10)
	_main = current_scene
	for actor in get_nodes_in_group("enemies"):
		actor.set_physics_process(false)
	var rig: CameraRig = _main.rig

	_check(_main.camera_mode == 2, "启动时读取镜头模式")
	_check(is_equal_approx(rig.pitch_deg, 70.0) and is_equal_approx(rig.distance, 14.5)
		and is_equal_approx(rig.fov, 35.0), "折中镜头参数生效")
	_check(not _main.motion_blur.enabled and not _main.motion_blur._rect.visible, "动态模糊按存档关闭")
	_check(is_equal_approx(AudioServer.get_bus_volume_db(0), linear_to_db(0.5)), "音量应用到 Master 总线")

	_main.apply_camera_mode(0)
	_check(is_equal_approx(rig.pitch_deg, 74.0) and is_equal_approx(rig.distance, 15.0)
		and is_equal_approx(rig.fov, 36.0), "完全俯视参数")
	_main.apply_camera_mode(1)
	_check(is_equal_approx(rig.pitch_deg, 66.0) and is_equal_approx(rig.distance, 14.0)
		and is_equal_approx(rig.fov, 34.0), "标准镜头参数")
	_main.apply_camera_mode(2)

	_main.apply_volume(0.0)
	_check(AudioServer.is_bus_mute(0), "音量 0 静音")
	_main.apply_volume(0.5)
	_check(not AudioServer.is_bus_mute(0) and is_equal_approx(AudioServer.get_bus_volume_db(0), linear_to_db(0.5)), "音量恢复非静音")
	_main.apply_volume(0.8)

	var pause: PauseMenu = _main.pause_menu
	_check(pause != null and not pause.visible, "暂停菜单默认隐藏")
	pause._on_blur_pressed()
	_check(bool(progress.data["motion_blur"]) and _main.motion_blur.enabled, "菜单开关动态模糊并写入存档")

	await _press_escape(true)
	_check(pause.visible and paused, "ESC 打开暂停菜单并暂停")
	await _press_escape(false)
	await _press_escape(true)
	_check(not pause.visible and not paused, "再次 ESC 关闭菜单并恢复")
	await _press_escape(false)

	pause._on_camera_pressed(2)
	_check(int(progress.data["camera_mode"]) == 2 and is_equal_approx(rig.pitch_deg, 70.0), "菜单切换镜头并写入存档")

	paused = false
	_main.free()
	await process_frame
	print("=== SETTINGS %s (%d checks, %d failures) ===" % ["PASS" if _fails == 0 else "FAILED", _checks, _fails])
	quit(0 if _fails == 0 else 1)
