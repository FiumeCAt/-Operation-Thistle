extends SceneTree
## 连发散布累积回归：逐武器参数、连射增长与上限、停火回落、换枪清零、开镜减速。
## godot --headless --path . --script res://tests/spread_accumulation_test.gd

var _pass := 0
var _fail := 0
## 与 Main2D.BURST_RECOVERY_BUSY_MUL 一致：换弹/切枪时回落加速。
const BUSY_RECOVERY_MUL := 1.8


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
	var p = root.get_node_or_null("Progress")
	if p != null:
		p.reset_for_test()

	# 1) 数据层：每把武器在 JSON 里有自己的连发累积参数，且档位有区分度。
	var table: Dictionary = GameData.table("weapons").get("data", {})
	var growth_values := {}
	for id in WeaponDB.WEAPON_ORDER:
		var rec: Dictionary = table.get(String(id), {})
		_check(rec.has("spread_growth") and rec.has("spread_max") \
			and rec.has("spread_recovery"),
			"%s writes burst profile into weapons.json" % id)
		var w: WeaponData = WeaponDB.get_weapon(id)
		_check(w.spread_growth > 0.0 and w.spread_max > w.spread_growth \
			and w.spread_recovery > 0.0,
			"%s burst profile valid (%.4f / %.3f / %.2f)" % [
				id, w.spread_growth, w.spread_max, w.spread_recovery])
		growth_values[snappedf(w.spread_growth, 0.00001)] = true
	_check(growth_values.size() >= 10,
		"weapons use distinct burst growth values (%d kinds)" % growth_values.size())
	_check(WeaponDB.get_weapon(&"mp7").spread_growth < WeaponDB.get_weapon(&"akm").spread_growth,
		"smg accumulates slower than rifle")
	_check(WeaponDB.get_weapon(&"awm").spread_max > WeaponDB.get_weapon(&"g17").spread_max,
		"sniper reaches a wider burst cone than pistol")
	var akm: WeaponData = WeaponDB.get_weapon(&"akm")
	var akm_ammo: AmmoData = WeaponDB.ammo_table()[akm.ammo_id]
	var akm_max_deg := rad_to_deg(akm.spread_max + akm.base_spread + akm_ammo.spread)
	_check(akm_max_deg > 10.0 and akm_max_deg < 17.0,
		"akm full-auto cone visibly widens (~%.1f degrees)" % akm_max_deg)

	# 2) 运行时：连射逐发累积，单发用累积前的散布。
	var main = load("res://scenes/core/Main2D.tscn").instantiate()
	main.mouse_aim_enabled = false
	root.add_child(main)
	await process_frame
	await physics_frame
	for enemy in main.enemies:
		enemy.set_physics_process(false)

	var doll = main.doll
	var rig = doll.weapon_rig
	_check(rig != null and rig.data != null, "weapon rig ready")
	doll.ads = false
	main._ads_t = 0.0
	main._burst_spread = 0.0
	main._burst_weapon = rig.data.id
	doll.aim_target = doll.global_position + Vector2(0, -420)
	var g17: WeaponData = WeaponDB.get_weapon(&"g17")
	var spread_before: float = main.get_aim_spread()
	var acc := 0.0
	for i in 3:
		rig.cooldown = 0.0
		rig.mag = rig.data.mag_capacity
		_check(rig.try_fire(), "shot %d fired" % (i + 1))
		acc += main.doll.weapon_rig.data.spread_growth
	_check(is_equal_approx(main._burst_spread, acc),
		"burst spread grows per trigger pull (%.4f)" % main._burst_spread)
	_check(main.get_aim_spread() > spread_before, "aim spread widens after burst")

	# 3) 上限：持续扫射只到武器自己的 spread_max。
	for i in 30:
		rig.cooldown = 0.0
		rig.mag = rig.data.mag_capacity
		rig.try_fire()
	_check(is_equal_approx(main._burst_spread, g17.spread_max),
		"burst spread clamps at weapon cap (%.3f)" % main._burst_spread)
	_check(main.get_aim_spread() > spread_before * 1.5,
		"sustained fire visibly widens the cone")

	# 4) 停火回落：按 spread_recovery 每秒回落，换弹期间加速。
	main._burst_spread = g17.spread_max
	main._burst_weapon = rig.data.id
	var rest: float = main._burst_spread - g17.spread_recovery * 0.1
	main._update_burst_spread(0.1)
	_check(is_equal_approx(main._burst_spread, maxf(rest, 0.0)),
		"burst spread recovers while not firing (%.4f)" % main._burst_spread)

	main._burst_spread = 0.03
	rig.reload_t = 0.4
	main._update_burst_spread(0.025)
	_check(is_equal_approx(main._burst_spread,
		maxf(0.03 - g17.spread_recovery * BUSY_RECOVERY_MUL * 0.025, 0.0)),
		"reloading recovers burst spread faster (%.4f)" % main._burst_spread)
	rig.reload_t = 0.0
	main._update_burst_spread(4.0)
	_check(is_equal_approx(main._burst_spread, 0.0),
		"burst spread never goes below zero")

	# 5) 换枪清零：旧枪的累积不会带到新枪上。
	main._burst_spread = 0.02
	doll.equip_weapon_id(&"akm")
	main._update_burst_spread(0.01)
	_check(doll.weapon_rig != null and doll.weapon_rig.data.id == &"akm",
		"switched to akm")
	_check(is_equal_approx(main._burst_spread, 0.0),
		"switching weapons resets burst spread")

	# 6) 开镜时每发增长更慢（55%），但上限不变。
	var next_rig = doll.weapon_rig
	next_rig.cooldown = 0.0
	next_rig.mag = next_rig.data.mag_capacity
	main._burst_spread = 0.0
	doll.ads = true
	next_rig.try_fire()
	_check(is_equal_approx(main._burst_spread, akm.spread_growth * 0.55),
		"aiming down sights slows burst growth (%.4f)" % main._burst_spread)
	doll.ads = false

	print("\n=== spread accumulation: %s (%d ok / %d fail) ===" % [
		"PASS" if _fail == 0 else "FAIL", _pass, _fail])
	quit()
