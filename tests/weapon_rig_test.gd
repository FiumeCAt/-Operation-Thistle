extends SceneTree
## M1 武器表现测试：挂载、瞄准、层级、开火、枪口位置。
## godot --headless --path . --script res://tests/weapon_rig_test.gd

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


func _run() -> void:
	var main = load("res://scenes/core/Main2D.tscn").instantiate()
	root.add_child(main)
	main.mouse_aim_enabled = false
	main.doll.aim_enabled = true
	for i in 12:
		await process_frame
	var doll = main.doll
	var rig: WeaponRig2D = doll.weapon_rig
	_check(rig != null, "weapon rig created")
	if rig == null:
		_finish()
		return
	_check(rig.data != null and rig.data.id == &"g17", "default weapon is g17")
	_check(rig.get_node_or_null("Pivot/Gun") != null, "gun sprite exists")
	_check(rig.get_node_or_null("Pivot/Muzzle") != null, "muzzle marker exists")
	_check(rig.get_node_or_null("Pivot/UpperArm") != null, "upper arm layer exists")
	_check(rig.get_node_or_null("Pivot/Forearm") != null, "forearm layer exists")
	_check(rig.get_node_or_null("Pivot/Hand") != null, "hand layer exists")
	_check(rig.get_node("Pivot/Hand").get_index() > rig.get_node("Pivot/Gun").get_index(),
		"hand draws over the gun (child order)")
	# 髋射 21.5 < 两段总长 24，肘部应当有弯曲
	_check(absf(rig.get_node("Pivot/UpperArm").rotation) > 0.05, "elbow bends at hip pose")
	_check(absf(rig.get_node("Pivot/Forearm").rotation) > 0.05, "forearm angles toward the wrist")

	var center: Vector2 = doll.global_position

	# 朝右：枪管水平，枪口在握把右侧一个枪长处
	doll.aim_target = center + Vector2(240, 0)
	await _settle(rig, 0.0)
	_check(absf(rig.aim_angle) < 0.02, "aim right settles to 0 rad, got %.3f" % rig.aim_angle)
	var grip_global: Vector2 = rig.get_grip_position()
	var muzzle: Vector2 = rig.get_muzzle_position()
	var gun_len: float = rig.get_gun_length()
	_check(rig.aiming, "standing with a weapon uses the aim pose")
	_check(muzzle.distance_to(grip_global) > 5.0, "muzzle is offset from the hand")
	_check(absf((muzzle - grip_global).length() - gun_len) < 0.5,
		"muzzle distance matches gun length %.2f" % gun_len)
	var gun_sprite: Sprite2D = rig.get_node("Pivot/Gun")
	_check(absf(angle_difference(gun_sprite.global_rotation + rig.get_barrel_angle(), rig.aim_angle)) < 0.02,
		"gun barrel axis aligns with the aim direction")
	_check(absf(rig.get_node("Pivot/Muzzle").position.distance_to(rig.get_node("Pivot/Hand").position) - gun_len) < 0.5,
		"muzzle marker uses grip-to-muzzle metadata distance")

	# 朝上：背向视角下枪在右手侧，走前景才能看见手臂
	doll.aim_target = center + Vector2(0, -240)
	await _settle(rig, -PI * 0.5)
	_check(rig.z_index > 0, "weapon draws in front when aiming up so the arm stays visible, z=%d" % rig.z_index)
	# 左上：枪会横穿头部，仍压到身体后面
	doll.aim_target = center + Vector2(-240, -240)
	await _settle(rig, -PI * 0.75)
	_check(rig.z_index < 0, "weapon draws behind when aiming up-left across the head, z=%d" % rig.z_index)
	doll.aim_target = center + Vector2(240, 0)
	await _settle(rig, 0.0)
	_check(rig.z_index > 0, "weapon draws in front when aiming sideways, z=%d" % rig.z_index)
	_check(absf(angle_difference(gun_sprite.global_rotation + rig.get_barrel_angle(), rig.aim_angle)) < 0.02,
		"right-facing barrel remains on the aim axis")

	# 朝左：贴图上下镜像，而不是整体旋转 180°（否则枪托会倒过来）
	doll.aim_target = center + Vector2(-240, 0)
	await _settle(rig, PI)
	_check(gun_sprite.flip_v, "gun sprite flips when aiming left instead of drawing upside down")
	_check(rig.get_muzzle_position().x < rig.get_grip_position().x, "muzzle points left")
	_check(absf((rig.get_muzzle_position() - rig.get_grip_position()).length() - rig.get_gun_length()) < 0.5,
		"left-facing mirrored muzzle remains attached to the hand")
	var mirrored_barrel := gun_sprite.global_rotation - rig.get_barrel_angle()
	_check(absf(angle_difference(mirrored_barrel, rig.aim_angle)) < 0.02,
		"mirrored barrel stays on the aim axis")
	doll.aim_target = center + Vector2(240, 0)
	await _settle(rig, 0.0)
	_check(not gun_sprite.flip_v, "gun sprite unflips when aiming right")

	# 开火：后坐、枪口焰、射速间隔
	var before_shots: int = rig.shots
	_check(rig.try_fire(), "first shot accepted")
	_check(rig.shots == before_shots + 1, "shot counted")
	_check(rig.recoil > 0.5, "recoil applied, %.2f" % rig.recoil)
	var flash: Sprite2D = rig.get_node("Pivot/Flash")
	_check(flash.visible, "muzzle flash visible after firing")
	_check(not rig.try_fire(), "fire rate limits the next shot inside the interval")
	var cooldown_before: float = rig.cooldown
	for i in 12:
		await process_frame
	_check(rig.cooldown < cooldown_before, "cooldown ticks down")
	_check(rig.recoil < 0.5, "recoil recovers, %.2f" % rig.recoil)

	# Doll 对外接口：枪口坐标应来自武器层
	_check(doll.get_muzzle_position().distance_to(rig.get_muzzle_position()) < 0.01,
		"doll.get_muzzle_position delegates to the weapon rig")

	# 长枪：第二条支撑臂托住护木
	_check(not rig.get_node("SupportPivot").visible, "pistol does not show the support arm")
	_check(rig.switch_to(&"m870"), "switch to a long gun")
	for i in 200:
		await process_frame
		if not rig.is_busy():
			break
	for i in 3:
		await process_frame
	var support: Node2D = rig.get_node_or_null("SupportPivot")
	_check(support != null and support.visible, "long gun shows the support arm")
	if support != null and support.visible:
		_check(rig.get_node_or_null("SupportPivot/SupportUpperArm") != null, "support upper arm exists")
		_check(rig.get_node_or_null("SupportPivot/SupportForearm") != null, "support forearm exists")
		var shand: Node2D = rig.get_node_or_null("SupportPivot/SupportHand")
		_check(shand != null, "support hand exists")
		if shand != null:
			var sg := rig.get_grip_position()
			var sm := rig.get_muzzle_position()
			var hand_pos := shand.global_position
			var near := Geometry2D.get_closest_point_to_segment(hand_pos, sg, sm)
			_check(hand_pos.distance_to(near) < 5.0,
				"support hand sits on the gun line, gap %.2f" % hand_pos.distance_to(near))
			var along := hand_pos.distance_to(sg)
			_check(along > 4.0 and along < rig.get_gun_length() * 0.4,
				"support hand is ahead of the trigger hand, %.1f" % along)
	# 收枪后支撑臂一起隐藏
	_check(rig.holster(), "holster starts")
	for i in 120:
		await process_frame
		if rig.is_holstered() and not rig.is_busy():
			break
	_check(support == null or not support.visible, "support arm hides when holstered")

	_finish()


func _finish() -> void:
	print("\n=== weapon rig: %s (%d ok / %d fail) ===" % ["PASS" if _fail == 0 else "FAIL", _pass, _fail])
	quit()


## 等待瞄准角收敛到目标（headless 下帧间隔不稳定，按帧数轮询）。
func _settle(rig: WeaponRig2D, target: float, max_frames := 600) -> void:
	for i in max_frames:
		await process_frame
		if absf(angle_difference(rig.aim_angle, target)) < 0.015:
			return
