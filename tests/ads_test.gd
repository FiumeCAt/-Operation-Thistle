extends SceneTree
## 右键瞄准（ADS）与头身接缝回归测试。
## godot --headless --path . --script res://tests/ads_test.gd

var _pass := 0
var _fail := 0
var _main


func _initialize() -> void:
	call_deferred("_run")


func _check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("ok] ", label)
	else:
		_fail += 1
		print("FAIL ", label)


func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame


func _run() -> void:
	create_timer(30.0).timeout.connect(func() -> void: quit(2))
	_main = load("res://scenes/core/Main2D.tscn").instantiate()
	_main.mouse_aim_enabled = false
	root.add_child(_main)
	var doll = _main.doll
	doll.aim_enabled = true
	doll.aim_target = doll.global_position + Vector2(200, 0)
	await _wait(12)
	var rig: WeaponRig2D = doll.weapon_rig

	var spread_hip: float = _main.get_aim_spread()
	var zoom_hip: float = _main.camera.zoom.x
	var aim_dir: Vector2 = (doll.aim_target - doll.global_position).normalized()
	var grip_hip: float = (rig.get_grip_position() - doll.global_position).dot(aim_dir)
	_check(not doll.ads, "aim is off by default")
	_check(rig.get_ads_blend() < 0.01, "weapon rig starts at hip pose")
	await process_frame
	var gap_hip: float = _main.reticle.get_node("RetView").gap
	_check(_main.reticle.get_node("RetView").visible, "crosshair is visible outside ADS")
	_check(not _main.reticle.get_node("AdsVignette").visible, "ADS vignette is hidden outside ADS")

	# --- 按住右键 ---
	Input.action_press("aim")
	await _wait(30)
	_check(doll.ads, "holding aim sets the ADS flag")
	_check(rig.ads, "weapon rig receives the ADS flag")
	# 开镜收紧系数按弹种配置，测试按当前弹种的实际倍率判断。
	var ads_factor := float(_main.current_ammo().ads_spread_mul)
	var spread_ads: float = _main.get_aim_spread()
	_check(spread_ads < spread_hip * (ads_factor + 0.08),
		"spread tightens while aiming (%.4f -> %.4f, factor %.2f)" % [
			spread_hip, spread_ads, ads_factor])
	_check(absf(_main.camera.zoom.x - zoom_hip) < 0.02, "ADS no longer changes camera zoom")
	_check(rig.get_ads_blend() > 0.9, "ADS pose blends in")
	await process_frame
	var gap_ads: float = _main.reticle.get_node("RetView").gap
	_check(_main.reticle.get_node("RetView").visible, "crosshair stays visible while ADS")
	_check(gap_ads < gap_hip - 1.0,
		"crosshair gap tightens while ADS (%.1f -> %.1f)" % [gap_hip, gap_ads])
	_check(_main.reticle.get_node("AdsVignette").visible, "ADS vignette appears")
	var grip_ads: float = (rig.get_grip_position() - doll.global_position).dot(aim_dir)
	_check(grip_ads < grip_hip - 4.0, "weapon is pulled closer along the barrel")

	# --- 瞄准方向前探（不再改变镜头倍率） ---
	await _wait(20)
	_check(_main._ads_look.x > 0.85 and absf(_main._ads_look.y) < 0.2,
		"camera looks ahead along the aim direction")

	# --- 整体视角缩放：松开右键也能用 Alt+滚轮调整 ---
	Input.action_release("aim")
	await _wait(30)
	var zoom_100: float = _main.camera.zoom.x
	Input.action_press("view_zoom")
	await process_frame
	var wheel_up := InputEventMouseButton.new()
	wheel_up.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel_up.pressed = true
	_main._unhandled_input(wheel_up)
	_check(_main.view_zoom_pct == 110.0, "Alt+wheel scales the whole view outside ADS")
	await _wait(20)
	_check(_main.camera.zoom.x > zoom_100 * 1.04, "view zoom animates smoothly")
	await process_frame
	_check(_main.reticle.get_node("RetView").zoom_pct == 110.0,
		"reticle shows the view zoom percent")
	var wheel_down := InputEventMouseButton.new()
	wheel_down.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel_down.pressed = true
	_main._unhandled_input(wheel_down)
	_main._unhandled_input(wheel_down)
	_check(_main.view_zoom_pct == 90.0, "wheel down shrinks the view")
	_main._set_view_zoom(999.0)
	_check(_main.view_zoom_pct == 200.0, "view zoom caps at 200%")
	_main._set_view_zoom(-50.0)
	_check(_main.view_zoom_pct == 20.0, "view zoom floors at 20%")
	_main._set_view_zoom(100.0)
	Input.action_release("view_zoom")
	await _wait(20)

	# --- 瞄准时移速减半 ---
	Input.action_press("aim")
	Input.action_press("move_right")
	await _wait(10)
	_check(doll.velocity.length() < doll.walk_speed * 0.6, "movement is slowed while aiming")
	_check(absf(doll.velocity.length() - doll.walk_speed * 0.5) < 12.0, "aim speed is about half")
	Input.action_release("move_right")

	# --- 冲刺时不进入瞄准 ---
	Input.action_press("sprint")
	Input.action_press("move_right")
	await _wait(6)
	_check(not doll.ads, "sprinting cancels ADS")
	await process_frame
	_check(_main.reticle.get_node("RetView").visible, "crosshair stays visible when sprint cancels ADS")
	Input.action_release("move_right")
	Input.action_release("sprint")

	# --- 松开右键恢复 ---
	Input.action_release("aim")
	await _wait(40)
	_check(not doll.ads, "releasing aim clears the flag")
	_check(absf(_main.get_aim_spread() - spread_hip) < 0.0001, "spread returns to hip value")
	_check(absf(_main.camera.zoom.x - zoom_hip) < 0.02, "camera returns to normal zoom")

	# --- 倍镜缩放：由武器瞄具倍率驱动，只在 ADS 过渡里叠加 ---
	_check(_main.get_scope_magnification() == 1.0, "scope interface defaults to 1x")
	var zoom_scope_hip: float = _main.camera.zoom.x
	var saved_aim_zoom: float = rig.aim_zoom_mul
	rig.aim_zoom_mul = 2.0
	await _wait(4)
	_check(absf(_main.get_scope_magnification() - 2.0) < 0.001,
		"scope interface follows the equipped sight magnification")
	_check(absf(_main.camera.zoom.x - zoom_scope_hip) < 0.02,
		"scope magnification does nothing outside ADS")
	Input.action_press("aim")
	await _wait(30)
	_check(_main.camera.zoom.x > zoom_scope_hip * 1.6, "scope magnification applies during ADS")
	Input.action_release("aim")
	rig.aim_zoom_mul = saved_aim_zoom
	await _wait(30)
	_check(absf(_main.camera.zoom.x - zoom_hip) < 0.02, "clearing the scope returns to base zoom")

	# --- 头身接缝：头部不再独立旋转/横移 ---
	var pivot: Node2D = doll._head_pivot
	_check(absf(pivot.rotation) < 0.001, "head does not rotate independently")
	_check(absf(pivot.position.x - doll._neck_base.x) < 0.001, "head does not shift sideways")
	_check(pivot.position.y > doll._neck_base.y - 1.0, "head still follows the walk bob")

	print("\n=== ads: %s (%d ok / %d fail) ===" % ["PASS" if _fail == 0 else "FAIL", _pass, _fail])
	quit()
