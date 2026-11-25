extends SceneTree
## 2D 天赋树回归：存档数据、前置/价格/上限、Main2D 生效、撤离奖励、开始菜单入口。
## godot --headless --path . --script res://tests/talents_2d_test.gd

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


func _near(a: float, b: float, eps := 0.001) -> bool:
	return absf(a - b) <= eps


func _run() -> void:
	create_timer(30.0).timeout.connect(func() -> void: quit(2))
	root.size = Vector2i(1600, 900)
	await process_frame

	var p = root.get_node_or_null("Progress")
	if p == null:
		print("FAIL progress autoload missing")
		quit(1)
		return
	p.reset_for_test()

	# ---- 数据层：默认值 / 价格 / 前置 / 上限 ----
	_check(p.talent_2d_level(&"hp") == 0 and p.talent_2d_level(&"scavenge") == 0
		and p.talent_2d_level(&"hearing") == 0,
		"talents_2d starts empty")
	_check(p.talent_2d_max(&"hp") == 5 and p.talent_2d_max(&"move") == 5
		and p.talent_2d_max(&"gun") == 5 and p.talent_2d_max(&"hearing") == 5,
		"stat-boost talents default to max level 5")
	_check(p.talent_2d_cost(&"hp") == 45 and p.talent_2d_cost(&"bogus") == -1,
		"talent cost and unknown id")
	_check(not p.buy_talent_2d(&"hp"), "cannot buy without resources")

	p.data["resources"] = 500
	p.data["materials_2d"] = {"electronics": 99, "energy": 99, "parts": 99}
	p.data["xp"] = 0
	_check(not p.buy_talent_2d(&"move"), "move locked until hp Lv.1")
	_check(not p.buy_talent_2d(&"hearing"), "hearing locked until hp Lv.1")
	_check(not p.buy_talent_2d(&"reload"), "reload locked until gun Lv.1")
	_check(p.buy_talent_2d(&"hp") and p.talent_2d_level(&"hp") == 1,
		"buy hp level 1")
	_check(int(p.data["resources"]) == 455, "hp purchase deducts credits")
	_check(p.material_count(&"energy") == 96, "hp purchase deducts energy cells")
	_check(int(p.data["xp"]) == 5 and int(p.data["skill_level"]) == 1,
		"purchase grants xp")
	_check(p.talent_2d_cost(&"hp") == 90, "hp price scales with level")
	_check(p.buy_talent_2d(&"move") and p.talent_2d_level(&"move") == 1,
		"move unlocks after hp")
	_check(p.buy_talent_2d(&"hearing") and p.talent_2d_level(&"hearing") == 1,
		"hearing unlocks after hp on survival branch")
	_check(p.buy_talent_2d(&"gun") and p.buy_talent_2d(&"reload"),
		"gun then reload unlock chain")
	_check(p.talent_2d_max(&"loading") == 1 and p.talent_2d_material(&"loading") == &"parts",
		"loading talent is a one-level parts unlock")
	_check(p.buy_talent_2d(&"magazine") and p.buy_talent_2d(&"loading")
		and p.talent_2d_level(&"loading") == 1,
		"loading talent unlocks after magazine")
	_check(p.talent_2d_max(&"armor") == 5 and p.talent_2d_max(&"magazine") == 5
		and p.talent_2d_max(&"reserve") == 5 and p.talent_2d_max(&"magnet") == 5
		and p.talent_2d_max(&"scavenge") == 5 and p.talent_2d_max(&"reload") == 5,
		"all stat talents use unified max level 5")

	p.data["resources"] = 1000
	while p.talent_2d_level(&"hp") < p.talent_2d_max(&"hp"):
		if not p.buy_talent_2d(&"hp"):
			break
	_check(p.talent_2d_level(&"hp") == 5, "hp reaches max level")
	_check(p.talent_2d_cost(&"hp") == -1 and not p.buy_talent_2d(&"hp"),
		"maxed node rejects further purchases")

	var saved_hp := int(p.talent_2d_level(&"hp"))
	var saved_move := int(p.talent_2d_level(&"move"))
	p.save_data()
	p.data = {}
	p.load_data()
	_check(p.talent_2d_level(&"hp") == saved_hp
		and p.talent_2d_level(&"move") == saved_move,
		"talent levels persist across reload")

	# ---- Main2D：本局属性应用（5% 倍数 × 等级 + 声纹双模式）----
	p.data["talents_2d"] = {
		"hp": 2, "gun": 2, "move": 2, "reload": 2, "scavenge": 3, "loading": 1,
		"armor": 2, "magazine": 2, "reserve": 2, "magnet": 2, "hearing": 0,
	}
	p.data["resources"] = 0
	p.data["xp"] = 0
	p.data["skill_level"] = 1

	var main = load("res://scenes/core/Main2D.tscn").instantiate()
	main.mouse_aim_enabled = false
	root.add_child(main)
	await process_frame
	await process_frame

	_check(main.doll.hp_max == 130 and main.doll.hp == 130,
		"hp talent raises max and current hp (+30%)")
	_check(main.hud.hp_label.text.contains("130"), "hud shows upgraded max hp")
	_check(_near(main.doll.walk_speed, 250.0 * 1.10) and _near(main.doll.sprint_speed, 380.0 * 1.10),
		"move talent raises walk and sprint speed (+10%)")
	_check(_near(main.talent_accuracy, 0.90), "gun talent accuracy multiplier (-10%)")
	_check(_near(main.talent_scavenge, 1.30), "scavenge talent multiplier (+30%)")
	_check(main.doll.weapon_rig != null
		and _near(main.doll.weapon_rig.reload_time_mul, 0.90),
		"reload talent applied to weapon rig (-10%)")
	_check(main.doll.weapon_rig.hold_reload_enabled,
		"loading talent unlocks hold-to-load on the weapon rig")
	_check(main.doll.armor_max == 140, "armor talent raises armor durability (+40%)")
	_check(main.doll.weapon_rig.data.mag_capacity == 20,
		"magazine talent raises magazine capacity (17 * 1.20 -> 20)")
	_check(int(main.doll.weapon_rig.reserve.get(&"light", -1)) == 151
		and int(main.doll.weapon_rig.reserve.get(&"shotgun", -1)) == 84,
		"reserve talent raises spare ammo (+40%)")
	_check(main.hearing != null and not main.hearing.is_acoustic_mode()
		and _near(main.hearing.hearing_range_meters(), 13.5),
		"hearing Lv.0 stays in classic ring mode at 13.5m")
	main.hearing.set_hearing_level(3)
	_check(main.hearing.is_acoustic_mode()
		and _near(main.hearing.hearing_range_meters(), 13.5 * 1.30),
		"hearing Lv.3 activates acoustic soundwave mode and +30% range")

	var pickup := LootPickup2D.new()
	pickup.setup("resource", &"parts", 1, Callable())
	root.add_child(pickup)
	await process_frame
	_check(is_equal_approx(pickup.get_magnet_radius(), 308.0),
		"magnet talent widens the pickup radius (+40%)")
	pickup.queue_free()

	var ammo = main.current_ammo()
	var base_spread: float = maxf(ammo.spread + main.doll.weapon_rig.data.base_spread, 0.004)
	_check(_near(main.get_aim_spread(), base_spread * 0.90),
		"aim spread includes gun talent (-10%)")

	# ---- 撤离结算：资源与 XP 写回 Progress ----
	main.resources = 4
	main._finish_run(true)
	_check(int(p.data["resources"]) == 26, "extraction banks scavenge-boosted resources")
	_check(int(p.data["xp"]) == 30 and int(p.data["skill_level"]) == 2,
		"extraction grants xp and skill level")
	_check(main.hud.result_detail.text.contains("+26") and main.hud.result_detail.text.contains("+30 XP"),
		"result panel shows meta rewards")

	main.queue_free()
	await process_frame

	# ---- 开始菜单：天赋树入口 / 购买 / ESC 关闭 ----
	p.data["resources"] = 100
	p.data["talents_2d"]["hp"] = 0
	var menu = load("res://scenes/ui/StartMenu2D.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	_check(menu.talents_button != null and menu.talents_button.text.contains("TALENTS"),
		"start menu has talents button")
	_check(menu.talents != null and not menu.talents.visible, "talent tree hidden at start")

	menu.talents_button.pressed.emit()
	await process_frame
	_check(menu.talents.visible, "talents button opens the tree")
	_check(menu.talents._summary.text.contains("信用点"), "tree summary reads credits and materials")
	_check(menu.talents._pan_hint.visible, "talent canvas shows the drag hint")
	menu.talents._set_pan(-300.0)
	_check(is_equal_approx(menu.talents._content.position.x, -300.0),
		"talent canvas pans horizontally")
	menu.talents._set_pan(-9999.0)
	var min_x: float = menu.talents._tree_area.size.x - menu.talents._content.size.x
	_check(menu.talents._content.position.x >= min_x - 0.5
		and menu.talents._content.position.x <= 0.0,
		"talent pan clamps to the canvas bounds")
	menu.talents._set_pan(0.0)

	menu.talents._buy(&"hp")
	_check(p.talent_2d_level(&"hp") == 1, "tree purchase writes progress")
	_check(menu.talents._feedback.text.contains("已强化"), "tree shows purchase feedback")
	var hp_gauge = menu.talents._cards[&"hp"]["gauge"]
	var load_gauge = menu.talents._cards[&"loading"]["gauge"]
	var hear_gauge = menu.talents._cards[&"hearing"]["gauge"]
	_check(hp_gauge != null and hp_gauge.max_level == 5 and hp_gauge.level == 1
		and load_gauge != null and load_gauge.max_level == 1
		and hear_gauge != null and hear_gauge.max_level == 5,
		"adaptive level gauges match per-node max levels (5 vs 1) and current progress")

	# 点击卡片：底部说明区展示背景与当前效果
	menu.talents._selected = &"hp"
	menu.talents._refresh()
	_check(menu.talents._detail_title.text.contains("生命强化")
		and menu.talents._detail_body.text.contains("生命上限"),
		"card selection fills the detail panel")

	# 单个重置：等级归零、依赖节点（含声纹感知）一起清空、投入全额返还
	p.data["talents_2d"] = {
		"hp": 2, "gun": 0, "move": 1, "hearing": 1,
		"reload": 0, "scavenge": 0, "loading": 0,
	}
	var credits_before: int = p.credits()
	var energy_before: int = p.material_count(&"energy")
	var refund: Dictionary = p.reset_talent_2d(&"hp")
	_check(p.talent_2d_level(&"hp") == 0 and p.talent_2d_level(&"move") == 0
		and p.talent_2d_level(&"hearing") == 0,
		"resetting a prerequisite clears dependent talents including hearing")
	_check(int(refund["credits"]) == 225 and p.credits() == credits_before + 225,
		"single reset refunds credits")
	_check(p.material_count(&"energy") == energy_before + 15, "single reset refunds materials")

	# 全部重置：二次确认后才清空
	p.data["talents_2d"]["gun"] = 1
	var credits_before_all: int = p.credits()
	menu.talents._on_reset_all()
	_check(menu.talents._confirm_layer.visible, "reset-all asks for confirmation")
	menu.talents._confirm_reset_all()
	_check(not menu.talents._confirm_layer.visible, "confirmation layer closes")
	_check(p.talent_2d_level(&"gun") == 0 and p.talent_2d_level(&"hp") == 0,
		"reset-all clears every talent")
	_check(p.credits() == credits_before_all + 45, "reset-all refunds invested credits")

	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	menu._unhandled_input(esc)
	_check(not menu.talents.visible, "ESC closes the tree")
	_check(not menu._closing, "ESC on the tree does not start the run")

	menu.queue_free()
	await process_frame
	print("\n=== talents 2d: %s (%d ok / %d fail) ===" % ["PASS" if _fail == 0 else "FAIL", _pass, _fail])
	quit()
