extends SceneTree
## WeaponStatsModel 黄金基准与三端一致性测试：
## 1. 锁定代表武器（AKM / G17 / M870 / Saiga-12K / AWM）在裸枪、满配与天赋组合下的确定性数值。
## 2. 验证 WeaponStatsModel 与运行时 WeaponRig2D._apply_mods() 数值 100% 一致。
## 3. 验证 ArmoryMenu2D._mod_weapon_stats() 与 WeaponRig2D 一致（含自带全自动武器装非全自动枪机时不丢失全自动）。
## 4. 验证纯计算隔离：多次计算不会污染 WeaponDB.get_weapon() 返回的独立 WeaponData 实例。

const STATS_MODEL := preload("res://scripts/weapons/WeaponStatsModel.gd")

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
	print("=== weapon_stats_model_test ===")

	# ---- 1) 裸枪黄金基线（AKM / G17 / M870 / AWM） ----
	var akm_bare: Dictionary = STATS_MODEL.compute(&"akm", {})
	_check(int(akm_bare["mag"]) == 30, "AKM bare mag == 30")
	_check(is_equal_approx(float(akm_bare["interval"]), 0.10), "AKM bare fire_interval == 0.10")
	_check(is_equal_approx(float(akm_bare["range"]), 40.0), "AKM bare range == 40.0m")
	_check(is_equal_approx(float(akm_bare["speed"]), 715.0), "AKM bare bullet_speed == 715 m/s")
	_check(bool(akm_bare["auto"]), "AKM bare default_auto_fire == true")
	_check(is_equal_approx(float(akm_bare["damage"]), 38.0), "AKM bare damage == 38.0")
	_check(is_equal_approx(float(akm_bare["spread"]), 0.058), "AKM bare hip spread == 0.058 rad")

	var g17_bare: Dictionary = STATS_MODEL.compute(&"g17", {})
	_check(int(g17_bare["mag"]) == 17, "G17 bare mag == 17")
	_check(not bool(g17_bare["auto"]), "G17 bare default_auto_fire == false")
	_check(is_equal_approx(float(g17_bare["range"]), 23.5), "G17 bare range == 23.5m")
	_check(is_equal_approx(float(g17_bare["sound"]), 7.0), "G17 bare sound == 7.0m")

	var m870_bare: Dictionary = STATS_MODEL.compute(&"m870", {})
	_check(int(m870_bare["mag"]) == 5, "M870 bare mag == 5")
	_check(int(m870_bare["pellets"]) == 8, "M870 bare pellets == 8")
	_check(is_equal_approx(float(m870_bare["damage"]), 64.0), "M870 bare total damage == 64.0 (8*8)")
	_check(is_equal_approx(float(m870_bare["range"]), 33.0), "M870 bare range == 33.0m")

	var awm_bare: Dictionary = STATS_MODEL.compute(&"awm", {})
	_check(int(awm_bare["mag"]) == 5, "AWM bare mag == 5")
	_check(is_equal_approx(float(awm_bare["damage"]), 110.0), "AWM bare damage == 110.0")
	_check(is_equal_approx(float(awm_bare["range"]), 70.5), "AWM bare range == 70.5m")
	_check(is_equal_approx(float(awm_bare["speed"]), 918.0), "AWM bare speed == 918 m/s")
	var fal_bare: Dictionary = STATS_MODEL.compute(&"fal", {})
	_check(bool(fal_bare["auto"]), "FN FAL bare default_auto_fire == true")

	# ---- 2) 满配 + 天赋黄金基线（验证叠乘、绝对容量、枪机覆盖、瞄具、天赋） ----
	var akm_full_mods := {
		"muzzle": "suppressor",   # speed*1.06, spread*0.92, sound*0.55（不再减伤）
		"magazine": "mag_drum",   # capacity=75, reload*1.35
		"core": "tuned",          # fire*0.90, damage*1.05（不含 full_auto 字段，AKM 仍须保持全自动）
		"stock": "heavy",         # recoil*0.75, spread*0.92
		"grip": "laser",          # spread*0.88, ads_speed*1.30, laser=true
		"sight": "scope",         # 4x, scope=true, vision*1.75, spread*0.86, range*1.10, ads_time*1.20
	}
	var talents := {"magazine": 2, "reload": 3, "gun": 2}
	var akm_mod: Dictionary = STATS_MODEL.compute(&"akm", akm_full_mods, talents)
	_check(int(akm_mod["mag"]) == int(round(75.0 * 1.20)), "AKM drum + mag lv2 == %d" % int(akm_mod["mag"]))
	_check(bool(akm_mod["auto"]), "AKM with tuned core preserves default full-auto")
	_check(is_equal_approx(float(akm_mod["interval"]), 0.09), "AKM tuned interval == 0.09s")
	_check(is_equal_approx(float(akm_mod["range"]), 44.0), "AKM + 4x scope range == 44.0m")
	_check(is_equal_approx(float(akm_mod["speed"]), 715.0 * 1.06), "AKM + suppressor speed == 757.9 m/s (+6%)")
	_check(is_equal_approx(float(akm_mod["sound"]), 14.0 * 0.55), "AKM + suppressor sound == 7.7m")
	_check(is_equal_approx(float(akm_mod["damage_mul"]), 1.05), "AKM suppressor+tuned damage_mul == 1.05 (no suppressor penalty)")
	_check(is_equal_approx(float(akm_mod["recoil_mul"]), 0.75), "AKM heavy stock recoil_mul == 0.75")
	_check(is_equal_approx(float(akm_mod["vision_mul"]), 1.75), "AKM 4x scope vision_mul == 1.75")
	_check(is_equal_approx(float(akm_mod["ads_speed_mul"]), 1.30), "AKM laser ads_speed_mul == 1.30")
	_check(is_equal_approx(float(akm_mod["sight_ads_time_mul"]), 1.20), "AKM 4x scope ads_time_mul == 1.20")
	_check(bool(akm_mod["has_laser"]) and bool(akm_mod["has_scope_sight"]) and bool(akm_mod["has_suppressor"]),
		"AKM laser, scope & suppressor flags set")
	_check(is_equal_approx(float(akm_mod["sight_magnification"]), 4.0), "AKM 4x scope magnification == 4.0")
	_check(
		is_equal_approx(float(akm_mod["load_modded"]), 0.7 * 1.35),
		"AKM load_modded excludes reload talent (%.4f)" % float(akm_mod["load_modded"])
	)
	_check(
		is_equal_approx(float(akm_mod["load"]), 0.7 * 1.35 * 0.85),
		"AKM effective load includes reload lv3 talent (-15%%, %.4f)" % float(akm_mod["load"])
	)
	# 7.62×39 attachment_spread_scale == 0.80；gun lv2 = -10% (×0.90)
	var expect_spread_mul := 0.92 * 0.92 * 0.88 * 0.86
	var expect_spread := 0.058 * lerpf(1.0, expect_spread_mul, 0.80) * 0.90
	_check(
		absf(float(akm_mod["spread"]) - expect_spread) < 0.0001,
		"AKM full-mod + gun lv2 spread matches formula (%.5f)" % float(akm_mod["spread"])
	)

	# G17 全自动改件（固定 0.10s / 600 RPM）+ 50 发弹鼓 + 准星自定义回调
	var g17_auto: Dictionary = STATS_MODEL.compute(
		&"g17",
		{"core": "auto", "magazine": "mag_drum", "sight": "pso"},
		{},
		func(sight_id: String, _def: String) -> String: return "mildot" if sight_id == "pso" else _def
	)
	_check(bool(g17_auto["auto"]), "G17 auto kit enables full-auto")
	_check(is_equal_approx(float(g17_auto["interval"]), 0.10), "G17 auto kit fixes interval to 0.10s")
	_check(int(g17_auto["mag"]) == 50, "G17 drum mag == 50")
	_check(String(g17_auto["sight_reticle"]) == "mildot", "reticle_resolver overrides default sight reticle")

	# 不可变隔离：build_weapon_data 克隆新实例，绝不原地修改基础模板
	var base_g17: WeaponData = WeaponDB.get_weapon(&"g17")
	var built_g17: WeaponData = STATS_MODEL.build_weapon_data(base_g17, g17_auto)
	_check(built_g17 != null and built_g17 != base_g17,
		"build_weapon_data returns a cloned WeaponData instance")
	_check(base_g17.mag_capacity == 17 and not base_g17.auto_fire,
		"build_weapon_data never mutates the base WeaponData template")
	_check(built_g17.mag_capacity == 50 and built_g17.auto_fire,
		"cloned WeaponData carries modded capacity and auto_fire")

	# Saiga-12K 全自动改件 + 20 发弹鼓 + 收束器（鹿弹 attachment_spread_scale=0.55）
	var saiga_mod: Dictionary = STATS_MODEL.compute(
		&"saiga12k",
		{"core": "auto", "magazine": "mag_drum", "muzzle": "choke"},
		{}
	)
	_check(bool(saiga_mod["auto"]), "Saiga-12K auto kit enables full-auto")
	_check(int(saiga_mod["mag"]) == 20, "Saiga-12K drum mag == 20")
	_check(is_equal_approx(float(saiga_mod["spread_mul"]), 1.50 * 0.75), "Saiga spread_mul == 1.125")

	# ---- 3) 与 WeaponRig2D + ArmoryMenu2D 实机节点三端一致 ----
	var p = root.get_node_or_null("Progress")
	if p != null:
		p.reset_for_test()
		p.data["weapon_mods_2d"]["akm"] = akm_full_mods.duplicate()
		p.data["talents_2d"]["magazine"] = 2
		p.data["talents_2d"]["reload"] = 3
		p.data["talents_2d"]["gun"] = 2

		var rig := WeaponRig2D.new()
		rig.weapon_id = &"akm"
		root.add_child(rig)
		await process_frame

		var model_via_p: Dictionary = STATS_MODEL.compute_for_progress(&"akm", p)
		_check(rig.data.mag_capacity == int(model_via_p["mag"]), "WeaponRig2D mag matches WeaponStatsModel")
		_check(is_equal_approx(rig.data.fire_interval, float(model_via_p["interval"])), "WeaponRig2D interval matches WeaponStatsModel")
		_check(is_equal_approx(rig.data.load_time, float(model_via_p["load_modded"])), "WeaponRig2D load_time matches load_modded")
		_check(is_equal_approx(rig.data.range_m, float(model_via_p["range"])), "WeaponRig2D range_m matches WeaponStatsModel")
		_check(is_equal_approx(rig.data.bullet_speed_mps, float(model_via_p["speed"])), "WeaponRig2D bullet_speed_mps matches WeaponStatsModel")
		_check(is_equal_approx(rig.data.sound_radius, float(model_via_p["sound"])), "WeaponRig2D sound_radius matches WeaponStatsModel")
		_check(rig.data.auto_fire == bool(model_via_p["auto"]), "WeaponRig2D auto_fire matches WeaponStatsModel")
		_check(is_equal_approx(rig.damage_mul, float(model_via_p["damage_mul"])), "WeaponRig2D damage_mul matches WeaponStatsModel")
		_check(is_equal_approx(rig.spread_mul, float(model_via_p["spread_mul"])), "WeaponRig2D spread_mul matches WeaponStatsModel")
		_check(is_equal_approx(rig.recoil_mul, float(model_via_p["recoil_mul"])), "WeaponRig2D recoil_mul matches WeaponStatsModel")
		_check(is_equal_approx(rig.vision_mul, float(model_via_p["vision_mul"])), "WeaponRig2D vision_mul matches WeaponStatsModel")
		_check(is_equal_approx(rig.ads_speed_mul, float(model_via_p["ads_speed_mul"])), "WeaponRig2D ads_speed_mul matches WeaponStatsModel")
		_check(rig.has_laser == bool(model_via_p["has_laser"]), "WeaponRig2D has_laser matches WeaponStatsModel")
		_check(rig.has_scope_sight == bool(model_via_p["has_scope_sight"]), "WeaponRig2D has_scope_sight matches WeaponStatsModel")

		var armory := ArmoryMenu2D.new()
		root.add_child(armory)
		await process_frame
		var armory_stats: Dictionary = armory._mod_weapon_stats(&"akm", akm_full_mods)
		_check(int(armory_stats["mag"]) == rig.data.mag_capacity, "Armory mag matches WeaponRig2D")
		_check(is_equal_approx(float(armory_stats["interval"]), rig.data.fire_interval), "Armory interval matches WeaponRig2D")
		_check(is_equal_approx(float(armory_stats["range"]), rig.data.range_m), "Armory range matches WeaponRig2D")
		_check(bool(armory_stats["auto"]) == rig.data.auto_fire, "Armory auto_fire matches WeaponRig2D (no tuned-core drift)")

		armory.queue_free()
		rig.queue_free()
		await process_frame

	# ---- 4) 纯计算隔离验证：不污染 WeaponDB ----
	var fresh_akm := WeaponDB.get_weapon(&"akm")
	_check(fresh_akm.mag_capacity == 30 and is_equal_approx(fresh_akm.range_m, 40.0),
		"WeaponDB.get_weapon() remains unmutated after WeaponStatsModel & WeaponRig2D")

	print("=== weapon_stats_model_test: %d ok / %d fail ===" % [_ok, _fails])
	quit(0 if _fails == 0 else 1)
