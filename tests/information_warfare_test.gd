extends SceneTree

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

func _t(pressed: bool, echo := false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_T
	event.pressed = pressed
	event.echo = echo
	Input.parse_input_event(event)
	await _frames()

func _tap() -> void:
	await _t(true)
	await _t(false)

func _run() -> void:
	print("=== Operation Thistle information warfare test ===")
	create_timer(60.0).timeout.connect(func() -> void: quit(2))
	change_scene_to_file("res://scenes/core/Main.tscn")
	await _frames(10)
	_main = current_scene
	for actor in get_nodes_in_group("enemies"):
		actor.set_physics_process(false)
	var doll: Doll = _main.doll
	_check(not doll.flashlight_on and not doll.flashlight.visible, "出生默认关灯")
	_check(doll.flashlight.spot_range == 14.0 and doll.flashlight.shadow_enabled, "14米聚光灯启用阴影")
	_check(doll.flashlight.get_parent() == doll and doll.flashlight != doll.muzzle_light, "独立于枪口灯并跟随角色")
	for angle in [0.0, 90.0, 180.0, 270.0]:
		doll.debug_set_facing(angle)
		_check((-doll.flashlight.global_basis.z).is_equal_approx(doll.global_basis.z), "灯沿角色+Z方向 %.0f度" % angle)
	await _t(true)
	_check(doll.flashlight_on and doll.flashlight.visible, "物理T事件单次开灯")
	await _frames(30)
	_check(doll.flashlight_on, "长按30帧不重复切换")
	await _t(true, true)
	_check(doll.flashlight_on, "键盘echo不重复切换")
	await _t(false)
	_check(doll.flashlight_on, "松键不切换")
	_check(_main.run_hud._hint.text.contains("开 · 更易被发现"), "HUD显示开灯风险")
	await _tap()
	_check(not doll.flashlight_on and doll.visibility_multiplier() == 1.0, "第二次T关闭且倍率恢复1")
	_check(_main.run_hud._hint.text.contains("T 手电：关"), "HUD显示关灯")
	doll.set_physics_process(false)
	var enemy := Enemy.new()
	_main.add_child(enemy)
	enemy.set_physics_process(false)
	enemy.player = doll
	enemy.view_range = 10.0
	enemy.position = Vector3(0, 100, 0)
	doll.position = Vector3(0, 100, 9.9)
	_check(enemy._can_see_player(), "关灯基础距离内可见")
	doll.position.z = 10.1
	_check(not enemy._can_see_player(), "关灯基础距离外不可见")
	doll.set_flashlight(true)
	_check(doll.visibility_multiplier() == 1.4 and enemy._can_see_player(), "开灯倍率1.4使原距离外可见")
	doll.position.z = 13.99
	_check(enemy._can_see_player(), "1.4倍距离内可见")
	doll.position.z = 14.01
	_check(not enemy._can_see_player(), "1.4倍距离外不可见")
	doll.position = Vector3(12, 100, 0)
	_check(not enemy._can_see_player(), "开灯仍不能越过视锥")
	doll.position = Vector3(0, 100, 12)
	var wall := StaticBody3D.new()
	wall.position = Vector3(0, 101, 6)
	wall.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4, 4, 0.5)
	shape.shape = box
	wall.add_child(shape)
	_main.add_child(wall)
	await _frames()
	_check(not enemy._can_see_player(), "开灯仍被真实物理墙遮挡")
	wall.free()
	await _frames()
	_check(enemy._can_see_player(), "移除墙恢复可见")
	doll.set_flashlight(false)
	_check(not enemy._can_see_player(), "同位置关灯立即失去远距发现")
	enemy.free()
	doll.set_flashlight(true)
	_main._reset_doll()
	doll.set_physics_process(true)
	_check(not doll.flashlight_on and not doll.flashlight.visible, "复位默认关灯")
	paused = true
	await _tap()
	_check(not doll.flashlight_on, "暂停期间T不能开灯")
	paused = false
	await _frames()
	_check(not doll.flashlight_on, "恢复后不补执行暂停输入")
	await _tap()
	paused = true
	await _tap()
	_check(doll.flashlight_on, "暂停期间T不能关灯")
	paused = false
	doll._hurt_cd = 0.0
	doll.take_damage(1000.0)
	_check(doll.is_dead and paused and not doll.flashlight_on and not doll.flashlight.visible, "死亡关闭手电并进入失败结算")
	await _tap()
	_check(not doll.flashlight_on, "死亡结算T不能切换")
	_main.restart_run()
	await _frames(2)
	_check(_main.run_hud._at_base and paused, "死亡结算先回同一实例基地")
	_main.restart_run()
	await _frames(10)
	doll = _main.doll
	_check(not paused and not doll.flashlight_on and not doll.flashlight.visible, "真实重开默认关灯")
	for actor in get_nodes_in_group("enemies"):
		actor.set_physics_process(false)
	await _tap()
	_main.resources = 1
	doll.global_position = _main.level.exit_position
	_main.finish_run(true)
	_check(paused and _main.run_state == _main.RunState.SUCCESS, "进入成功结算")
	await _tap()
	_check(doll.flashlight_on, "成功结算T不能切换")
	_main.restart_run()
	await _frames(2)
	_main.restart_run()
	await _frames(10)
	_check(not _main.doll.flashlight_on, "成功结算重开也默认关灯")
	await _frames(4)
	print("=== %s (%d checks, %d failures) ===" % ["PASS" if _fails == 0 else "FAILED", _checks, _fails])
	paused = false
	_main.free()
	await process_frame
	quit(0 if _fails == 0 else 1)
