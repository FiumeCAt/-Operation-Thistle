extends SceneTree
## WeaponPoseIK2D 独立单元测试：验证武器元数据读取、像素→Pivot 锚点映射（含镜像）、两段臂 IK 与背向层级判定。
## godot --headless --path . --script res://tests/weapon_pose_ik_test.gd

const POSE_IK := preload("res://scripts/weapons/WeaponPoseIK2D.gd")

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
	# 1. 元数据与平直武器尺度加载
	var m_g17: Dictionary = POSE_IK.load_weapon_metrics(&"g17", WeaponDB.get_weapon(&"g17").visual_length)
	var m_akm: Dictionary = POSE_IK.load_weapon_metrics(&"akm", WeaponDB.get_weapon(&"akm").visual_length)
	_check(m_g17["tex"] != null and float(m_g17["gun_len"]) > 15.0,
		"load_weapon_metrics loads g17 texture and scaled length")
	_check(float(m_akm["gun_len"]) > float(m_g17["gun_len"]),
		"rifle world gun_len is longer than pistol")

	# 2. pixel_to_pivot：握把像素永远映射到 wrist_local；枪口与握把距离恒等于 gun_len（左右对称）
	var wrist := Vector2(20.0, 0.0)
	var grip_r := POSE_IK.pixel_to_pivot(m_akm["grip_px"], m_akm["grip_px"],
		float(m_akm["barrel_angle"]), float(m_akm["gun_scale"]), wrist, false)
	var muzzle_r := POSE_IK.pixel_to_pivot(m_akm["muzzle_px"], m_akm["grip_px"],
		float(m_akm["barrel_angle"]), float(m_akm["gun_scale"]), wrist, false)
	var muzzle_l := POSE_IK.pixel_to_pivot(m_akm["muzzle_px"], m_akm["grip_px"],
		float(m_akm["barrel_angle"]), float(m_akm["gun_scale"]), wrist, true)
	_check(grip_r.distance_to(wrist) < 0.001, "grip pixel maps identically to wrist_local")
	_check(absf(muzzle_r.distance_to(wrist) - float(m_akm["gun_len"])) < 0.05,
		"right-facing muzzle distance matches gun_len")
	_check(absf(muzzle_l.distance_to(wrist) - float(m_akm["gun_len"])) < 0.05,
		"flipped muzzle distance preserves exact gun_len")

	# 3. 两段臂 IK：完全伸直时无弯角，收回时肘部按 elbow_sign 弯曲
	var upper := Sprite2D.new()
	var fore := Sprite2D.new()
	var straight_w := POSE_IK.solve_primary_arm(upper, fore, 30.0, 1.0)
	_check(is_equal_approx(straight_w.x, POSE_IK.UPPER_ARM_LEN + POSE_IK.FOREARM_LEN)
		and is_equal_approx(upper.rotation, 0.0) and is_equal_approx(fore.rotation, 0.0),
		"full reach straightens upper arm and forearm")
	var bent_w := POSE_IK.solve_primary_arm(upper, fore, 18.0, 1.0)
	_check(is_equal_approx(bent_w.x, 18.0) and upper.rotation > 0.1 and fore.rotation < -0.1,
		"short ADS reach bends elbow positively and forearm back to wrist")
	upper.queue_free()
	fore.queue_free()

	# 4. 背向层级判定：朝左瞄而身朝右画在后面；背向朝正上画在前面，朝左上画在后面
	_check(POSE_IK.is_behind_body(PI, 3), "aiming opposite right-facing body draws behind")
	_check(not POSE_IK.is_behind_body(0.0, 3), "aiming with right-facing body draws in front")
	_check(not POSE_IK.is_behind_body(-PI * 0.5, 1), "up-facing body keeps straight-up aim in front")
	_check(POSE_IK.is_behind_body(-2.1, 1), "up-facing body sends up-left aim behind head")

	await process_frame
	print("\n=== weapon pose ik: %s (%d ok / %d fail) ===" % [
		"PASS" if _fail == 0 else "FAIL", _pass, _fail])
	quit(0 if _fail == 0 else 1)
