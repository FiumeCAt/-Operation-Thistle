extends SceneTree
## M2 背向层级 / M4 收枪拔枪 + 冲刺持枪测试。
## godot --headless --path . --script res://tests/weapon_m2_m4_test.gd

var _pass := 0
var _fail := 0


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
		await process_frame


func _run() -> void:
	create_timer(20.0).timeout.connect(func() -> void: quit(2))
	var main = load("res://scenes/core/Main2D.tscn").instantiate()
	root.add_child(main)
	main.mouse_aim_enabled = false
	main.doll.aim_enabled = true
	main.doll.aim_target = main.doll.global_position + Vector2(240, 0)
	await _wait(20)
	var doll = main.doll
	var rig: WeaponRig2D = doll.weapon_rig
	_check(InputMap.has_action("holster"), "holster input action exists")
	_check(rig != null and not rig.is_holstered(), "weapon starts drawn")
	_check(rig.get_side_texture() != null, "side texture is available for the back mount")

	# --- M2：手动摆身体/枪角度，验证背向层级与远侧手 ---
	doll.set_physics_process(false)
	rig.set_process(false)
	rig.holstered = false
	rig.aiming = false
	rig.body_direction = 3  # 身体朝右
	rig.aim_angle = PI      # 枪指向左（身体背面）
	rig._update_layer()
	rig._apply_pose()
	_check(rig.z_index < 0, "weapon draws behind the body when aiming opposite facing")
	_check(rig.get_node("Pivot/UpperArm").visible, "arm stays attached to the gun when behind")
	rig.aim_angle = 0.0
	rig._update_layer()
	rig._apply_pose()
	_check(rig.z_index > 0, "weapon draws in front when aiming with the body")
	rig.aim_angle = -PI * 0.5
	rig._update_layer()
	rig._apply_pose()
	_check(rig.z_index < 0, "weapon still draws behind when aiming up")

	# --- M4：收枪 ---
	rig.set_process(true)
	rig.aim_enabled = false
	rig.aim_world = doll.global_position + Vector2(240, 0)
	_check(rig.holster(), "holster accepted")
	_check(rig.is_stowing(), "holster animation is running")
	_check(not rig.try_fire(), "cannot fire while stowing")
	await _wait(40)
	_check(rig.is_holstered(), "weapon is holstered")
	_check(not rig.get_node("Pivot/Gun").visible, "in-hand gun is hidden when holstered")
	_check(doll.get_node_or_null("WeaponMount/Weapon") != null, "back mount shows the stowed weapon")
	main.hud.update_weapon(rig)
	_check(main.hud._state.text == "已收枪", "hud shows the holstered state")

	# --- M4：扣扳机自动拔枪 ---
	var shots_before: int = rig.shots
	_check(not rig.try_fire(), "trigger while holstered does not fire")
	_check(rig.is_drawing(), "trigger starts drawing")
	_check(rig.shots == shots_before, "no shot during the draw")
	await _wait(50)
	_check(not rig.is_holstered() and not rig.is_drawing(), "draw finished")
	_check(rig.get_node("Pivot/Gun").visible, "gun is visible after drawing")
	_check(doll.get_node_or_null("WeaponMount/Weapon") == null, "back mount is cleared after drawing")

	# --- M4：收枪状态下换枪，背后模型跟着换 ---
	rig.holster()
	await _wait(40)
	_check(rig.switch_to(&"m870"), "switching while holstered is accepted")
	_check(rig.weapon_id == &"m870", "weapon actually switched while holstered")
	await _wait(2)
	_check(doll.get_node_or_null("WeaponMount/Weapon") != null, "back mount refreshes for the new weapon")

	# --- M4：冲刺持枪不自动收枪 ---
	rig.draw()
	await _wait(40)
	rig.sprinting = true
	rig.aiming = false
	rig.aim_angle = 0.0
	rig.body_direction = 3
	rig._update_layer()
	rig._apply_pose()
	_check(not rig.is_holstered(), "sprinting keeps the weapon drawn")
	_check(rig.get_node("Pivot/Gun").visible, "gun stays visible while sprinting")

	_finish()


func _finish() -> void:
	print("\n=== weapon m2/m4: %s (%d ok / %d fail) ===" % ["PASS" if _fail == 0 else "FAIL", _pass, _fail])
	quit()
