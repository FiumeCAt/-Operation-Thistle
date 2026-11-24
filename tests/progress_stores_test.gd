extends SceneTree
## Progress 五大子存储单测：SaveStore（含版本迁移与激光/准心颜色持久化）、
## SettingsStore、MetaProgress、LoadoutStore、TalentStore。
## godot --headless --path . --script res://tests/progress_stores_test.gd

const SAVE_STORE := preload("res://scripts/core/progress/SaveStore.gd")
const SETTINGS_STORE := preload("res://scripts/core/progress/SettingsStore.gd")
const META_STORE := preload("res://scripts/core/progress/MetaProgress.gd")
const LOADOUT_STORE := preload("res://scripts/core/progress/LoadoutStore.gd")
const TALENT_STORE := preload("res://scripts/core/progress/TalentStore.gd")

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
	# 1. SaveStore：版本迁移框架（v0 -> v1、拒绝未来高版本、规范化裁剪与 settings_rev 迁移）
	var v0 := {"version": 0, "resources": 250}
	var mig := SAVE_STORE.migrate_save_version(v0)
	_check(bool(mig["migrated"]) and int((mig["data"] as Dictionary).get("version", -1)) == SAVE_STORE.VERSION
		and int((mig["data"] as Dictionary).get("resources", 0)) == 250,
		"SaveStore migrates v0 save dictionary to current version")
	var future := SAVE_STORE.migrate_save_version({"version": 99, "resources": 10})
	_check((future["data"] as Dictionary).is_empty(),
		"SaveStore rejects unsupported future save version")

	var raw := SAVE_STORE.defaults()
	raw["settings_rev"] = 1
	raw["bright_test"] = false
	raw["view_zoom"] = 999.0
	raw["laser_color"] = "not-a-color"
	raw["reticle_color"] = "#11aaff"
	var norm_mig := SAVE_STORE.normalize_data(raw, {"hp": 5}, {"hp": 5})
	_check(norm_mig and int(raw["settings_rev"]) == 2 and bool(raw["bright_test"]),
		"SaveStore.normalize_data migrates legacy settings_rev < 2")
	_check(is_equal_approx(float(raw["view_zoom"]), 200.0)
		and String(raw["laser_color"]) == SAVE_STORE.DEFAULT_LASER_COLOR
		and String(raw["reticle_color"]) == "#11aaff",
		"SaveStore.normalize_data clamps zoom and validates laser/reticle colors")

	# 2. SettingsStore：外观颜色、显示偏好、调试开关隔离
	var d := SAVE_STORE.defaults()
	SETTINGS_STORE.set_laser_color(d, Color(0.2, 0.9, 0.4))
	SETTINGS_STORE.set_reticle_color(d, Color(1.0, 0.3, 0.2))
	_check(absf(SETTINGS_STORE.laser_color(d).g - 0.9) < 0.02
		and absf(SETTINGS_STORE.reticle_color(d).r - 1.0) < 0.02,
		"SettingsStore round-trips laser and reticle hex colors")
	_check(not SETTINGS_STORE.set_armor_display(d, "invalid")
		and SETTINGS_STORE.set_armor_display(d, "rha_mm")
		and SETTINGS_STORE.armor_display(d) == "rha_mm",
		"SettingsStore validates armor_display enum")
	SETTINGS_STORE.set_debug_value(d, "damage", 3.5)
	_check(is_equal_approx(SETTINGS_STORE.debug_mul(d, "damage"), 1.0),
		"SettingsStore debug_mul returns 1.0 when debug disabled")
	SETTINGS_STORE.set_debug_enabled(d, true)
	_check(is_equal_approx(SETTINGS_STORE.debug_mul(d, "damage"), 3.5),
		"SettingsStore debug_mul returns multiplier when debug enabled")
	SETTINGS_STORE.reset_debug(d)
	_check(is_equal_approx(SETTINGS_STORE.debug_value(d, "damage"), 1.0),
		"SettingsStore reset_debug restores 1.0 defaults")

	# 3. MetaProgress：经济倍率、物资入库、XP 等级与部署校验
	var m := SAVE_STORE.defaults()
	META_STORE.add_resources(m, 100, 0.5)
	META_STORE.add_materials(m, {"electronics": 4, "weapon_parts": 2, "unknown": 99})
	META_STORE.add_xp(m, 45)
	_check(META_STORE.credits(m) == 50
		and META_STORE.material_count(m, &"electronics") == 4
		and META_STORE.advanced_count(m, &"weapon_parts") == 2
		and int(m["skill_level"]) == 3,
		"MetaProgress applies credit gain multiplier, material buckets, and XP level")
	_check(not META_STORE.set_deployment(m, &"bogus", &"east")
		and META_STORE.set_deployment(m, &"abandoned", &"south")
		and String(META_STORE.deployment(m)["spawn"]) == "abandoned",
		"MetaProgress validates deployment spawn and extract IDs")

	# 4. LoadoutStore：双武器防重、配件安装扣费与幂等
	var l := SAVE_STORE.defaults()
	_check(not LOADOUT_STORE.set_loadout_2d(l, &"akm", &"akm")
		and LOADOUT_STORE.set_loadout_2d(l, &"akm", &"g17")
		and LOADOUT_STORE.loadout_2d(l) == ["akm", "g17"],
		"LoadoutStore enforces distinct primary and secondary weapons")
	l["resources"] = 500
	l["advanced_2d"]["weapon_parts"] = 10
	l["advanced_2d"]["electronic_core"] = 10
	var first_install := LOADOUT_STORE.install_weapon_mod(l, &"akm", &"grip", &"laser")
	var credits_after := int(l["resources"])
	var repeat_install := LOADOUT_STORE.install_weapon_mod(l, &"akm", &"grip", &"laser")
	_check(bool(first_install["ok"]) and bool(first_install["changed"])
		and bool(repeat_install["ok"]) and not bool(repeat_install["changed"])
		and int(l["resources"]) == credits_after,
		"LoadoutStore charges once on mod install and is idempotent on repeat")

	# 5. TalentStore：前置校验、购买扣费与级联重置全额返还
	var t := SAVE_STORE.defaults()
	var t_max := {"hp": 5, "move": 4, "armor": 3}
	var t_pre := {"move": "hp", "armor": "move"}
	var t_mat := {"hp": "energy", "move": "energy", "armor": "parts"}
	t["resources"] = 500
	t["materials_2d"]["energy"] = 20
	t["materials_2d"]["parts"] = 20
	_check(not TALENT_STORE.buy_talent_2d(t, t_max, t_pre, t_mat, 3.0, &"move"),
		"TalentStore blocks dependent talent before prerequisite is unlocked")
	_check(TALENT_STORE.buy_talent_2d(t, t_max, t_pre, t_mat, 3.0, &"hp")
		and TALENT_STORE.buy_talent_2d(t, t_max, t_pre, t_mat, 3.0, &"move")
		and TALENT_STORE.buy_talent_2d(t, t_max, t_pre, t_mat, 3.0, &"armor"),
		"TalentStore unlocks prerequisite chain cleanly")
	var refund := TALENT_STORE.reset_talent_2d(t, t_pre, t_mat, 3.0, &"hp")
	_check((refund["nodes"] as Array).size() == 3
		and int(t["resources"]) == 500
		and int(t["materials_2d"]["energy"]) == 20
		and int(t["materials_2d"]["parts"]) == 20,
		"TalentStore cascading reset refunds 100% of credits and materials across dependents")

	# 6. 端到端回归：自定义激光与准星颜色经 Progress.save_data -> load_data 持久化不丢失
	var p = root.get_node_or_null("Progress")
	if p != null:
		p.reset_for_test()
		p.set_laser_color(Color(0.25, 0.75, 1.0))
		p.set_reticle_color(Color(1.0, 0.25, 0.65))
		p.data = {}
		_check(p.load_data()
			and absf(p.laser_color().b - 1.0) < 0.02
			and absf(p.reticle_color().r - 1.0) < 0.02,
			"Progress persists custom laser_color and reticle_color across full reload")

	print("\n=== progress stores: %s (%d ok / %d fail) ===" % [
		"PASS" if _fail == 0 else "FAIL", _pass, _fail])
	quit()
