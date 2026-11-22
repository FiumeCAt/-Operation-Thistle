extends SceneTree
## M4.4：弹药显示偏好（图形/数值）切换与持久化。

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

func _run() -> void:
	print("=== Operation Thistle M4.4 ammo display test ===")
	create_timer(60.0).timeout.connect(func() -> void: quit(2))
	var progress = root.get_node_or_null("Progress")
	_check(progress != null, "Progress autoload 存在")
	_check(InputMap.has_action("ammo_display"), "存在弹药显示切换输入")

	change_scene_to_file("res://scenes/core/Main.tscn")
	await _frames(10)
	_main = current_scene
	for actor in get_nodes_in_group("enemies"):
		actor.set_physics_process(false)
	var hud: WeaponHUD = _main.weapon_hud
	_check(hud != null, "武器 HUD 存在")

	progress.reset_for_test()
	progress.set_ammo_display("numeric")
	hud._load_display_mode()
	hud._apply_display_mode()
	_check(hud.display_mode == "numeric", "读取仅数值偏好")
	_check(not hud._strip.visible and hud._count_label.visible, "仅数值模式隐藏图形弹仓")

	progress.set_ammo_display("graphic")
	hud._load_display_mode()
	hud._apply_display_mode()
	_check(hud.display_mode == "graphic", "读取仅图形偏好")
	_check(hud._strip.visible and not hud._count_label.visible, "仅图形模式隐藏数字")

	progress.set_ammo_display("both")
	hud._load_display_mode()
	hud._apply_display_mode()
	_check(hud._strip.visible and hud._count_label.visible, "默认同时显示图形与数字")

	_check(not progress.set_ammo_display("invalid"), "非法显示模式被拒绝")
	_check(progress.data["ammo_display"] == "both", "非法值不写入存档")

	hud._cycle_display_mode()
	_check(hud.display_mode == "numeric" and progress.data["ammo_display"] == "numeric", "H 切换写入偏好")
	progress.load_data()
	_check(progress.data["ammo_display"] == "numeric", "重新读档保留显示偏好")

	print("=== M4.4 %s (%d checks, %d failures) ===" % ["PASS" if _fails == 0 else "FAILED", _checks, _fails])
	_main.free()
	await process_frame
	quit(0 if _fails == 0 else 1)
