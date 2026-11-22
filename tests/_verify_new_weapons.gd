extends SceneTree
## 新枪实装冒烟：装配 → 开局携带 → 开火伤害 → 切枪 → HUD 口径。
## godot --headless --path . --script res://tests/_verify_new_weapons.gd -- --save-path user://verify_new_weapons.json

var _pass := 0
var _fail := 0


func _check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("ok] ", label)
	else:
		_fail += 1
		print("FAIL ", label)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var p = root.get_node_or_null("Progress")
	if p == null or not String(p.save_path).contains("verify_new_weapons"):
		print("FAIL isolated save path required")
		quit(1)
		return
	p.reset_for_test()
	p.data["loadout_2d"] = ["akm", "mp7"]
	p.data["resources"] = 9999
	p.data["advanced_2d"] = {
		"weapon_parts": 20, "electronic_core": 20,
		"high_energy_cell": 20, "military_alloy": 20,
	}

	var main = load("res://scenes/core/Main2D.tscn").instantiate()
	main.mouse_aim_enabled = false
	root.add_child(main)
	await process_frame
	await physics_frame
	var rig: WeaponRig2D = main.doll.weapon_rig
	_check(rig != null and rig.weapon_id == &"akm", "开局携带 AKM")
	_check(rig.data.ammo_id == &"762x39", "AKM 使用 7.62×39 弹药")
	_check(rig.get_reserve() == 120, "AKM 中型弹初始备弹 120")
	_check(rig.data.auto_fire, "AKM 默认全自动")
	_check(main.current_ammo().id == &"762x39", "Main2D 当前弹种同步")
	_check(main.hud._title.text.contains("AKM") and main.hud._title.text.contains("7.62×39"),
		"HUD 显示 AKM 与口径")
	_check(main.hud._ammo_name.text == "7.62×39", "HUD 显示弹药短名")

	# 对靶开火：直接触发开火回调，确认伤害与曳光走新弹药数据。
	for e in main.enemies.duplicate():
		e.queue_free()
	main.enemies.clear()
	await process_frame
	var target := Enemy2D.new()
	target.setup(&"sentry_type1", main.doll.global_position + Vector2(210, 0), 1)
	main.sort_layer.add_child(target)
	target.set_physics_process(false)
	main.enemies.append(target)
	main.doll.aim_target = target.global_position + Vector2(0, -40)
	await physics_frame
	var hp_before := target.hp
	var mag_before := rig.mag
	rig.cooldown = 0.0
	var fired: bool = rig.try_fire()
	_check(fired and rig.mag == mag_before - 1, "AKM 扣一发弹")
	await physics_frame
	await physics_frame
	_check(target.hp < hp_before or main.shots_fired > 0, "AKM 开火产生伤害/弹道")

	# 切副武器 MP7
	rig.switch_t = 0.0
	rig.switch_to(&"mp7")
	for i in 90:
		await physics_frame
		if rig.data.id == &"mp7":
			break
	_check(rig.data.id == &"mp7", "切换到 MP7")
	_check(rig.data.ammo_id == &"5.7x28", "MP7 使用 5.7×28 弹药")
	_check(rig.get_reserve() == 108, "MP7 轻型弹初始备弹 108")
	for i in 10:
		await process_frame
		if main.hud._title.text.contains("MP7"):
			break
	_check(main.hud._title.text.contains("MP7") and main.hud._title.text.contains("5.7×28"),
		"切枪后 HUD 同步口径：" + main.hud._title.text)

	# 通用弹药池：给 MP7 补 18 发轻型弹，切到同为轻型弹的 G18 应共享。
	main._grant_ammo(&"light", 18)
	rig.setup(&"g18")
	_check(rig.get_reserve() == 126, "轻型弹在 MP7 / G18 之间共享")

	# 改枪界面读取新枪数据
	var menu = load("res://scenes/ui/StartMenu2D.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	menu._open_armory()
	await process_frame
	menu.armory._select(&"awm")
	_check(menu.armory._detail_title.text.contains("AWM"), "武备库可选中 AWM")
	_check(menu.armory._detail_values["口径"].text.contains(".338"), "AWM 口径显示")
	_check(menu.armory._detail_values["弹匣容量"].text.contains("5"), "AWM 弹容显示")
	menu.armory._show_page("mods")
	menu.armory._select_mod_item("akm")
	await process_frame
	_check(menu.armory._mod_stat_values.has("spread"), "改枪数据窗含散布行")
	menu.queue_free()
	main.queue_free()
	await process_frame
	print("VERIFY NEW WEAPONS: %d checks, %d fail" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
