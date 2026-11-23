extends SceneTree
## ModInstallService 单元测试：锁死定置排序、主副武器互换写档、费用/材料校验与安装逻辑。
## godot --headless --path . --script res://tests/mod_install_service_test.gd

const SERVICE := preload("res://scripts/ui/armory/ModInstallService.gd")

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
	var p = root.get_node_or_null("Progress")
	_check(p != null, "Progress autoload exists")
	if p == null:
		quit(1)
		return
	p.reset_for_test()
	p.set_loadout_2d(&"m870", &"g17")

	# 1. 定置排序：主副武器置顶，总数与 WeaponDB.WEAPON_ORDER 一致且无重复
	var order := SERVICE.pinned_weapon_order(&"akm", &"awm")
	_check(order.size() == WeaponDB.WEAPON_ORDER.size()
		and order[0] == "akm" and order[1] == "awm",
		"pinned_weapon_order pins primary and secondary to top")

	# 2. 装备写档与主副互换
	var eq1 := SERVICE.equip_weapon(p, &"g17", &"m870", &"g17", true)
	_check(bool(eq1["ok"]) and eq1["primary"] == &"g17" and eq1["secondary"] == &"m870"
		and p.loadout_2d() == ["g17", "m870"],
		"equipping secondary into primary swaps slots cleanly")
	var eq2 := SERVICE.equip_weapon(p, &"akm", &"g17", &"m870", false)
	_check(bool(eq2["ok"]) and eq2["secondary"] == &"akm"
		and p.loadout_2d() == ["g17", "akm"],
		"equipping new weapon into secondary updates loadout")

	# 3. 费用/材料文案与瞄具摘要
	var comp := ModDB.option("muzzle", "compensator", false, "m870")
	_check(SERVICE.cost_line(comp).contains("信用点")
		and SERVICE.material_line(comp) != "无材料",
		"cost_line and material_line format non-free weapon mod")
	_check(SERVICE.cost_line({"credits": 0}) == "免费"
		and SERVICE.material_line({"cost": {}}) == "无材料",
		"cost_line and material_line handle free entries")
	var scope := ModDB.option("sight", "scope", false, "m870")
	var sight_line := SERVICE.sight_stats_line(scope)
	_check(sight_line.contains("4.0×") and sight_line.contains("视野") and sight_line.contains("射程"),
		"sight_stats_line summarizes magnification, vision, range, and ads time")
	_check(SERVICE.reticle_styles_for(scope).size() == 5
		and SERVICE.reticle_styles_for({"scope": false}).size() == 2,
		"reticle_styles_for distinguishes scope vs reflex styles")

	# 4. 支付校验与安装扣费（不足拒绝 / 充足扣费成功）
	p.data["resources"] = 0
	p.data["advanced_2d"] = {}
	_check(not SERVICE.can_pay_mod(p, comp), "can_pay_mod rejects when credits/materials insufficient")
	var fail_res := SERVICE.install_mod(p, "m870", "muzzle", "compensator")
	_check(not bool(fail_res["ok"]) and String(fail_res["message"]).contains("不足"),
		"install_mod returns failure message when resources insufficient")

	p.data["resources"] = 2000
	p.data["advanced_2d"] = {
		"weapon_parts": 10, "electronic_core": 10,
		"high_energy_cell": 10, "military_alloy": 10,
	}
	_check(SERVICE.can_pay_mod(p, comp), "can_pay_mod accepts when credits/materials sufficient")
	var ok_res := SERVICE.install_mod(p, "m870", "muzzle", "compensator")
	_check(bool(ok_res["ok"]) and String(p.weapon_mods_2d(&"m870").get("muzzle", "")) == "compensator",
		"install_mod installs weapon mod and persists to Progress")
	var armor_res := SERVICE.install_mod(p, "armor", "plate", "ceramic")
	_check(bool(armor_res["ok"]) and String(p.armor_mods_2d().get("plate", "")) == "ceramic",
		"install_mod installs armor component and persists to Progress")

	p.reset_for_test()
	print("\n=== mod install service: %s (%d ok / %d fail) ===" % [
		"PASS" if _fail == 0 else "FAIL", _pass, _fail])
	quit(0 if _fail == 0 else 1)
