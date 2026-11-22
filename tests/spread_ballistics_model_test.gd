extends SceneTree
## SpreadModel & BallisticsModel 黄金基准与 Main2D 一致性测试：
## 1. 锁定散布（腰射/ADS/配件按弹种缩放/后坐撑开/首发窗口/连发增减与上限/最小保底）。
## 2. 锁定弹道（统一 64 px/m 射程、武器优先初速、时间压缩 0.294、阻力换算、理论飞行时间与衰减）。
## 3. 验证 Main2D 薄转发方法与两个纯计算模型 100% 一致。

const SPREAD := preload("res://scripts/combat/SpreadModel.gd")
const BALLISTICS := preload("res://scripts/combat/BallisticsModel.gd")
const UNITS := preload("res://scripts/core/GameUnits.gd")

var _ok := 0
var _fails := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(cond: bool, msg: String) -> void:
	if cond:
		_ok += 1
		print("  [ok] ", msg)
	else:
		_fails += 1
		push_error("  [FAIL] " + msg)


func _run() -> void:
	print("=== spread_ballistics_model_test ===")

	var ammo_table := WeaponDB.ammo_table()
	var akm := WeaponDB.get_weapon(&"akm")
	var g17 := WeaponDB.get_weapon(&"g17")
	var tmp := WeaponDB.get_weapon(&"tmp")
	var m870 := WeaponDB.get_weapon(&"m870")
	var awm := WeaponDB.get_weapon(&"awm")
	var l85 := WeaponDB.get_weapon(&"l85a2")

	var a_762: AmmoData = ammo_table[&"762x39"]
	var a_9mm: AmmoData = ammo_table[&"9mm"]
	var a_buck: AmmoData = ammo_table[&"buckshot"]
	var a_556: AmmoData = ammo_table[&"556nato"]
	var a_338: AmmoData = ammo_table[&"338lapua"]

	# ---- 1) SpreadModel: 基础、配件缩放、ADS 收紧、天赋、调试、最小保底 ----
	var akm_hip := SPREAD.compute_aim_spread(a_762, akm, 0.0, Vector2.ZERO)
	_check(is_equal_approx(akm_hip, 0.058), "AKM bare hip spread == 0.058 rad")
	var akm_ads := SPREAD.compute_aim_spread(a_762, akm, 0.0, Vector2.ZERO, 1.0, true, 1.0, 1.0, 1.0)
	_check(is_equal_approx(akm_ads, 0.058 * 0.55), "AKM full ADS tightens by 0.55")
	var akm_mod := SPREAD.compute_aim_spread(a_762, akm, 0.0, Vector2.ZERO, 0.5, true, 1.0, 0.0, 1.0)
	_check(
		is_equal_approx(akm_mod, 0.058 * lerpf(1.0, 0.5, 0.80)),
		"7.62x39 attachment spread scales at 80%"
	)
	var buck_mod := SPREAD.compute_aim_spread(a_buck, m870, 0.0, Vector2.ZERO, 0.5, true, 1.0, 0.0, 1.0)
	_check(
		is_equal_approx(buck_mod, a_buck.spread * lerpf(1.0, 0.5, 0.55)),
		"buckshot attachment spread scales at 55%"
	)
	var l85_full := SPREAD.compute_aim_spread(a_556, l85, 0.0, Vector2.ZERO, 0.5, true, 1.5, 1.0, pow(0.94, 2.0))
	var expect_l85: float = (a_556.spread + l85.base_spread) * 0.5 * 1.5 * 0.45 * pow(0.94, 2.0)
	_check(absf(l85_full - expect_l85) < 0.00001, "5.56 combined attachment+debug+ADS+talent formula exact")
	var awm_ads := SPREAD.compute_aim_spread(a_338, awm, 0.0, Vector2.ZERO, 1.0, true, 1.0, 1.0, 1.0)
	_check(is_equal_approx(awm_ads, (a_338.spread + awm.base_spread) * 0.35), "AWM .338 ADS tightens to 35%")
	var zero_ammo := AmmoData.new()
	zero_ammo.spread = 0.0
	zero_ammo.ads_spread_mul = 1.0
	var min_floor := SPREAD.compute_aim_spread(zero_ammo, null, 0.0, Vector2.ZERO)
	_check(is_equal_approx(min_floor, SPREAD.MIN_SPREAD), "spread clamps to MIN_SPREAD floor (0.004)")

	# 后坐力撑开散布
	_check(is_equal_approx(SPREAD.recoil_spread(akm, Vector2.ZERO), 0.0), "zero recoil adds 0 recoil_spread")
	var cap_len := Vector2(akm.recoil_max_horizontal, akm.recoil_max_vertical).length()
	var full_rec := SPREAD.recoil_spread(akm, Vector2(0.0, -cap_len * 2.0))
	_check(
		is_equal_approx(full_rec, akm.spread_max * akm.recoil_spread_mul),
		"recoil_spread caps at spread_max * recoil_spread_mul"
	)

	# 首发窗口与收紧
	_check(SPREAD.is_first_shot(10.0, 9.75), "0.25s pause triggers first-shot window")
	_check(not SPREAD.is_first_shot(10.0, 9.80), "0.20s pause does not trigger first-shot window")
	_check(
		is_equal_approx(SPREAD.apply_first_shot(0.10, akm, true), 0.10 * akm.first_shot_spread_mul),
		"apply_first_shot multiplies first_shot_spread_mul"
	)
	_check(is_equal_approx(SPREAD.apply_first_shot(0.10, akm, false), 0.10), "non-first-shot keeps full spread")

	# 连发累积与回落
	var b1 := SPREAD.next_burst_spread(0.0, akm, false)
	_check(is_equal_approx(b1, akm.spread_growth), "hip burst adds full spread_growth")
	var b1_ads := SPREAD.next_burst_spread(0.0, akm, true)
	_check(
		is_equal_approx(b1_ads, akm.spread_growth * SPREAD.BURST_ADS_GROWTH_MUL),
		"ADS burst adds 0.55x spread_growth"
	)
	var b_cap := SPREAD.next_burst_spread(akm.spread_max, akm, false)
	_check(is_equal_approx(b_cap, akm.spread_max), "burst spread clamps at spread_max")
	var rec_norm := SPREAD.recover_burst_spread(0.10, akm, false, 0.1)
	_check(is_equal_approx(rec_norm, maxf(0.10 - akm.spread_recovery * 0.1, 0.0)), "normal burst recovery exact")
	var rec_busy := SPREAD.recover_burst_spread(0.10, akm, true, 0.1)
	_check(
		is_equal_approx(rec_busy, maxf(0.10 - akm.spread_recovery * SPREAD.BURST_RECOVERY_BUSY_MUL * 0.1, 0.0)),
		"busy burst recovery uses 1.8x speed"
	)

	# 均匀采样边界
	var sample_ok := true
	for i in 40:
		var off := SPREAD.sample_offset(0.20)
		if off < -0.10001 or off > 0.10001:
			sample_ok = false
	_check(sample_ok, "sample_offset stays inside [-S/2, +S/2]")

	# ---- 2) BallisticsModel: 射程、武器优先初速、阻力、飞行时间、速度衰减 ----
	_check(is_equal_approx(BALLISTICS.shot_range_px(akm), 40.0 * UNITS.PIXELS_PER_METER), "AKM range == 2560 px")
	_check(is_equal_approx(BALLISTICS.shot_range_px(g17), 23.5 * UNITS.PIXELS_PER_METER), "G17 range == 1504 px")
	_check(is_equal_approx(BALLISTICS.shot_range_px(m870), 33.0 * UNITS.PIXELS_PER_METER), "M870 range == 2112 px")
	_check(is_equal_approx(BALLISTICS.shot_range_px(awm), 70.5 * UNITS.PIXELS_PER_METER), "AWM range == 4512 px")
	_check(is_equal_approx(BALLISTICS.shot_range_px(null), 20.0 * UNITS.PIXELS_PER_METER), "null weapon range defaults to 20m (1280 px)")

	_check(is_equal_approx(BALLISTICS.muzzle_speed_mps(a_9mm, g17), 380.0), "G17 uses weapon speed 380 m/s")
	_check(is_equal_approx(BALLISTICS.muzzle_speed_mps(a_9mm, tmp), 334.0), "TMP uses weapon speed 334 m/s")
	_check(is_equal_approx(BALLISTICS.muzzle_speed_mps(a_9mm, null), 380.0), "null weapon falls back to ammo muzzle velocity")
	_check(is_equal_approx(BALLISTICS.bullet_speed_px_s(null), 6000.0), "null ammo falls back to 6000 px/s")
	_check(
		is_equal_approx(BALLISTICS.bullet_speed_px_s(a_556, l85), 959.0 * 0.294 * 64.0),
		"L85A2 bullet_speed_px_s == 959 * 0.294 * 64"
	)
	_check(
		is_equal_approx(BALLISTICS.drag_per_px(a_556), 0.0035 / 64.0),
		"5.56 drag_per_px == 0.0035 / 64"
	)
	_check(is_equal_approx(BALLISTICS.bullet_travel_time(a_556, 0.0), 0.0), "0m travel time == 0.0")
	var nodrag := AmmoData.new()
	nodrag.muzzle_velocity_mps = 400.0
	nodrag.bullet_time_scale = 0.25
	nodrag.drag_per_m = 0.0
	_check(is_equal_approx(BALLISTICS.bullet_travel_time(nodrag, 20.0), 0.20), "zero-drag linear travel time == 20 / 100 == 0.20s")
	var t15_556 := BALLISTICS.bullet_travel_time(a_556, 15.0)
	_check(absf(t15_556 - 0.0557) < 0.002, "5.56 15m travel time matches formula (%.4fs)" % t15_556)
	var v30_556 := BALLISTICS.speed_after_distance(1000.0, a_556.drag_per_m, 30.0)
	_check(is_equal_approx(v30_556, 1000.0 * exp(-0.0035 * 30.0)), "speed_after_distance exponential decay exact")

	# ---- 3) 与 Main2D 运行时薄转发 100% 一致 ----
	var p = root.get_node_or_null("Progress")
	if p != null:
		p.reset_for_test()
	var main = load("res://scenes/core/Main2D.tscn").instantiate()
	main.mouse_aim_enabled = false
	root.add_child(main)
	await process_frame
	await physics_frame

	main.doll.equip_weapon_id(&"akm")
	await process_frame
	main._burst_spread = 0.04
	main._recoil_offset = Vector2(5.0, -18.0)
	main._ads_t = 0.6
	var expect_main_spread := SPREAD.compute_aim_spread(
		main.current_ammo(), main.doll.weapon_rig.data,
		main._burst_spread, main._recoil_offset,
		main.doll.weapon_rig.spread_mul, true, 1.0, main._ads_t, main.talent_accuracy
	)
	_check(
		absf(main.get_aim_spread() - expect_main_spread) < 0.00001,
		"Main2D.get_aim_spread() matches SpreadModel exactly"
	)
	_check(
		is_equal_approx(main._shot_range(), BALLISTICS.shot_range_px(main.doll.weapon_rig.data)),
		"Main2D._shot_range() matches BallisticsModel"
	)
	_check(
		is_equal_approx(
			main.bullet_speed_px_s(a_762, main.doll.weapon_rig.data),
			BALLISTICS.bullet_speed_px_s(a_762, main.doll.weapon_rig.data)
		),
		"Main2D.bullet_speed_px_s() matches BallisticsModel"
	)
	_check(
		is_equal_approx(
			main.bullet_travel_time(a_762, 25.0, main.doll.weapon_rig.data),
			BALLISTICS.bullet_travel_time(a_762, 25.0, main.doll.weapon_rig.data)
		),
		"Main2D.bullet_travel_time() matches BallisticsModel"
	)

	main.queue_free()
	await process_frame

	print("=== spread_ballistics_model_test: %d ok / %d fail ===" % [_ok, _fails])
	quit(0 if _fails == 0 else 1)
