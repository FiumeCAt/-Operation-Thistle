extends SceneTree
## 基地武器库回归：武器数据展示、主/副武器配置、存档写入与开局携带。
## godot --headless --path . --script res://tests/armory_2d_test.gd

var _pass := 0
var _fail := 0
var _closed := false


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
	create_timer(30.0).timeout.connect(func() -> void: quit(2))
	root.size = Vector2i(1600, 900)
	await process_frame
	var p = root.get_node_or_null("Progress")
	if p == null:
		print("FAIL progress autoload missing")
		quit(1)
		return
	p.reset_for_test()
	p.data["loadout_2d"] = ["m870", "g17"]

	var menu = load("res://scenes/ui/StartMenu2D.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	_check(menu.armory_button != null and menu.armory_button.text.contains("ARSENAL"),
		"start menu has arsenal button")
	_check(menu.armory != null and not menu.armory.visible, "arsenal hidden at start")

	# 设置入口：射速单位切换写入存档，并影响武器数据页。
	_check(menu.settings_button != null and menu.settings_button.text.contains("SETTINGS"),
		"start menu has a settings button")
	menu._open_settings()
	await process_frame
	_check(menu.settings_menu != null and menu.settings_menu.visible, "settings overlay opens")
	menu.settings_menu._set_fire_mode("rpm")
	_check(p.data["fire_rate_display"] == "rpm", "fire rate display preference is saved")
	_check(menu.settings_menu._sliders.has("music"), "settings expose a music volume slider")
	var music_bus := AudioServer.get_bus_index("Music")
	_check(music_bus >= 0, "music bus exists")
	menu.settings_menu._sliders["music"].value = 40.0
	await process_frame
	_check(absf(AudioServer.get_bus_volume_db(music_bus) - linear_to_db(0.4)) < 0.05,
		"music slider controls the music bus")
	menu.settings_menu._set_ammo_display("numeric")
	_check(p.data["ammo_display"] == "numeric", "ammo display preference is saved")
	menu.settings_menu._set_ammo_display("both")
	menu.settings_menu._set_screen_shake(false)
	_check(p.data["screen_shake"] == false, "screen shake preference is saved")
	menu.settings_menu._set_screen_shake(true)
	menu.settings_menu._set_scope_blur(false)
	_check(p.data["scope_motion_blur"] == false, "scope motion blur preference is saved")
	menu.settings_menu._set_scope_blur(true)
	menu.settings_menu._set_scope_distortion(false)
	_check(p.data["scope_lens_distortion"] == false,
		"scope lens distortion preference is saved")
	menu.settings_menu._set_scope_distortion(true)
	_check(menu.settings_menu._debug_menu != null
		and menu.settings_menu._debug_menu._sliders.size() == 8,
		"debug mode exposes eight global tuning sliders")
	menu.settings_menu._debug_menu._set_enabled(true)
	_check(p.debug_enabled(), "debug mode can be enabled from the menu")
	var dm: DebugMenu2D = menu.settings_menu._debug_menu
	dm._on_slider_changed(2.0, "damage")
	_check(absf(p.debug_mul("damage") - 2.0) < 0.001,
		"debug slider changes the global multiplier")
	dm._edits["damage"].text = "150"
	dm._apply_text("damage")
	_check(absf(p.debug_value("damage") - 100.0) < 0.001
		and absf(dm._sliders["damage"].value - 100.0) < 0.001,
		"debug text input clamps to the 100x limit")
	_check(dm._message.text.contains("100"),
		"debug text input shows a correction message")
	dm._edits["damage"].text = "abc"
	dm._apply_text("damage")
	_check(absf(p.debug_value("damage") - 100.0) < 0.001
		and dm._message.text.contains("无效"),
		"invalid debug text input is rejected with a message")
	dm._edits["damage"].text = "-5"
	dm._apply_text("damage")
	_check(absf(p.debug_value("damage")) < 0.001,
		"debug text input clamps the lower bound to 0")
	dm._sliders["damage"].value = 2.0
	_check(dm._edits["damage"].text == "2.00"
		and absf(p.debug_value("damage") - 2.0) < 0.001,
		"debug slider and text input stay in sync")
	dm._set_enabled(false)
	_check(absf(p.debug_mul("damage") - 1.0) < 0.001,
		"debug multipliers stop applying when disabled")
	dm._sliders["damage"].value = 3.0
	_check(p.debug_enabled(), "editing a debug value enables debug automatically")
	p.set_debug_enabled(false)
	p.reset_debug()
	_check(absf(p.debug_mul("damage") - 1.0) < 0.001,
		"debug multipliers stop applying when disabled")
	menu.settings_menu._zoom_slider.value = 150.0
	await create_timer(0.5).timeout
	_check(int(p.data["view_zoom"]) == 150, "zoom preference is saved")
	menu.settings_menu._zoom_slider.value = 100.0
	await create_timer(0.5).timeout
	menu.settings_menu.close_menu()
	await process_frame
	_check(not menu.settings_menu.visible, "settings overlay closes")

	menu.armory.closed.connect(func() -> void: _closed = true)
	menu._open_armory()
	await process_frame
	_check(menu.armory.visible, "armory opens from the base menu")
	_check(menu.armory._weapon_buttons.size() == 18, "eighteen weapons listed")
	_check(menu.armory._category_buttons.size() == 7, "armory exposes seven weapon category filter tabs")
	_check(menu.armory._detail_title.text.contains("M870"), "primary weapon selected by default")
	# 装备定置：主/副武器固定在列表最前，并标注槽位。
	_check(menu.armory._weapon_list.get_child(0) == menu.armory._weapon_buttons[&"m870"]
		and menu.armory._weapon_list.get_child(1) == menu.armory._weapon_buttons[&"g17"],
		"equipped weapons are pinned to the top of the weapon list")
	_check(menu.armory._weapon_buttons[&"m870"].text.contains("[主]")
		and menu.armory._weapon_buttons[&"g17"].text.contains("[副]"),
		"weapon list marks the primary and secondary slots")
	_check(menu.armory._detail_values["弹匣容量"].text.contains("5"), "M870 magazine stat shown")
	_check(menu.armory._detail_values["射程"].text.contains("33"), "M870 range stat shown")
	_check(menu.armory._detail_values["子弹速度"].text == "400 m/s",
		"M870 bullet speed stat shown in m/s")
	_check(menu.armory._weapon_buttons[&"m870"].text.contains("弹速 400 m/s"),
		"weapon list shows bullet speed")
	_check(menu.armory._detail_values["枪声范围"].text.contains("20"), "M870 sound radius shown separately")
	_check(menu.armory._detail_values["弹药"].text == "鹿弹 ×8",
		"ammo row shows the ammo type only")
	_check(menu.armory._detail_values["伤害"].text == "8 × 8.0 = 64.0",
		"damage row shows the full calculation")
	_check(menu.armory._detail_values["射速"].text.contains("RPM"), "fire rate uses the RPM preference")
	_check(menu.armory._detail_icon.texture != null, "weapon icon texture is loaded")

	# 配件加成：实际数值 + 英文括号增减 + 悬浮来源。
	p.data["weapon_mods_2d"]["m870"] = {"magazine": "tube_long"}
	menu.armory._select(&"m870")
	_check(menu.armory._detail_values["弹匣容量"].text.contains("7"),
		"modded magazine shows the actual capacity")
	_check(menu.armory._detail_deltas["弹匣容量"].text.contains("(+2)"),
		"magazine gain is annotated in parentheses")
	_check(menu.armory._detail_deltas["弹匣容量"].get_theme_color("font_color") == PixelUI.OK,
		"gain annotation is green")
	_check(menu.armory._detail_deltas["换弹时间"].text.contains("(+0.03)")
		and menu.armory._detail_deltas["换弹时间"].get_theme_color("font_color") == PixelUI.DANGER,
		"longer reload is a red penalty")
	_check(menu.armory._detail_tips["弹匣容量"].contains("加长管仓"),
		"tooltip lists the mod source")
	menu.armory._show_tip("弹匣容量")
	_check(menu.armory._tip_panel.visible
		and menu.armory._tip_label.text.contains("加长管仓"),
		"custom tooltip panel renders the mod source")
	menu.armory._hide_tip()
	p.data["weapon_mods_2d"]["m870"] = {}
	p.set_fire_rate_display("interval")
	menu.armory._select(&"m870")

	# 护甲子页面：耐久 / RHA 防御 / 钝伤规则 / 穿深显示切换
	menu.armory._show_page("armor")
	_check(menu.armory._armor_page.visible and not menu.armory._weapon_page.visible,
		"armor tab switches to the armor page")
	_check(menu.armory._armor_values["耐久上限"].text.contains("100"),
		"armor page shows durability")
	_check(menu.armory._armor_values["防御等级"].text.contains("Lv.1")
		and menu.armory._armor_values["防御等级"].text.contains("30"),
		"armor page shows Lv.1 and 30 RHA value")
	_check(menu.armory._armor_values["基础减伤"].text.contains("5%"),
		"armor page shows non-pen blunt range")
	_check(menu.armory._armor_values["护甲吸收"].text.contains("+0%"),
		"armor page shows blunt reduction bonus")
	# 切换为 RHA 毫米显示：30 -> 3.0mm RHA
	p.set_armor_display("rha_mm")
	menu.armory._show_page("armor")
	_check(menu.armory._armor_values["防御等级"].text.contains("3.0mm RHA"),
		"armor page switches to mm RHA display")
	p.set_armor_display("value")
	# 护甲数据也要算上组件加成
	p.data["armor_mods_2d"] = {"plate": "ceramic", "liner": "gel"}
	menu.armory._show_page("armor")
	_check(menu.armory._armor_values["耐久上限"].text.contains("140"),
		"armor page includes plate durability bonus")
	_check(menu.armory._armor_values["护甲吸收"].text.contains("+5%"),
		"armor page includes liner blunt reduction bonus")
	p.data["armor_mods_2d"] = {}

	# 配件子页面：武器 / 护甲各三个槽位
	menu.armory._show_page("mods")
	_check(menu.armory._mods_page.visible and not menu.armory._armor_page.visible,
		"mods tab switches to the mods page")
	menu.armory._select_mod_item("m870")
	_check(menu.armory._mod_gun_view.visible and menu.armory._mod_slot_buttons.size() == 6,
		"weapon mod page shows the gun view with six slots")
	_check(menu.armory._mod_items.get_child(0) == menu.armory._mod_item_buttons["m870"]
		and menu.armory._mod_item_buttons["m870"].text.contains("[主]"),
		"mods list pins the equipped primary weapon with a slot mark")
	_check(menu.armory._mod_stat_values.has("recoil")
		and menu.armory._mod_stat_values.has("vision")
		and menu.armory._mod_stat_values.has("ads")
		and menu.armory._mod_stat_values.has("speed"),
		"mod stats panel exposes recoil, vision, aim speed and bullet speed")
	_check(menu.armory._mod_stat_values["speed"].text == "400 m/s",
		"mod stats panel shows the weapon's bullet speed")
	_check(menu.armory._mod_gun_tex != null and not menu.armory._mod_gun_anchors.is_empty(),
		"gun view loads the weapon texture and anchor points")
	menu.armory._select_mod_item("armor")
	_check(menu.armory._mod_slots_box.get_child_count() == 3,
		"armor mod page lists three slots")
	menu.armory._show_page("weapon")
	_check(menu.armory._weapon_page.visible and not menu.armory._armor_page.visible
		and not menu.armory._mods_page.visible,
		"weapon tab switches back")

	menu.armory._select(&"g17")
	_check(menu.armory._detail_title.text.contains("G17"), "selecting a weapon updates the detail panel")
	_check(menu.armory._detail_values["弹匣容量"].text.contains("17"), "G17 magazine stat shown")
	_check(menu.armory._detail_values["子弹速度"].text == "380 m/s",
		"G17 bullet speed stat shown in m/s")
	_check(menu.armory._weapon_buttons[&"g17"].text.contains("弹速 380 m/s"),
		"weapon list updates bullet speed per weapon")
	_check(menu.armory._loadout_label.text.contains("M870")
		and menu.armory._loadout_label.text.contains("G17"), "loadout line shows both slots")

	# 全自动改件：数据页与改枪数据窗的射速应同步为 600 RPM
	p.data["weapon_mods_2d"]["g17"] = {"core": "auto"}
	p.set_fire_rate_display("rpm")
	menu.armory._select(&"g17")
	_check(menu.armory._detail_values["射速"].text.contains("600"),
		"auto kit updates the weapon data fire rate")
	_check(menu.armory._detail_tips["射速"].contains("全自动改件"),
		"fire rate tooltip lists the auto kit as the source")
	menu.armory._show_page("mods")
	menu.armory._select_mod_item("g17")
	menu.armory._select_mod_slot("core")
	_check(menu.armory._mod_stat_values["rate"].text.contains("600"),
		"mod stats panel reflects the auto kit in real time")
	_check(menu.armory._mod_stat_values["mode"].text == "全自动",
		"mod stats panel shows the full-auto firing mode")
	menu.armory._show_page("weapon")
	p.data["weapon_mods_2d"]["g17"] = {}
	p.set_fire_rate_display("interval")
	menu.armory._select(&"g17")

	# 全武器一致性：详情、武器列表、数据字段三者必须完全一致。
	var speed_mismatch := ""
	for wid in WeaponDB.WEAPON_ORDER:
		menu.armory._select(wid)
		await process_frame
		var expect := "%d m/s" % int(round(float(WeaponDB.get_weapon(wid).bullet_speed_mps)))
		if menu.armory._detail_values["子弹速度"].text != expect \
				or not menu.armory._weapon_buttons[wid].text.contains("弹速 %s" % expect):
			speed_mismatch = "%s: %s / %s" % [String(wid),
				menu.armory._detail_values["子弹速度"].text, expect]
			break
	_check(speed_mismatch == "", "18 把武器的弹速显示与数据完全一致 %s" % speed_mismatch)

	menu.armory._select(&"g17")
	await process_frame
	menu.armory._equip(true)
	_check(p.loadout_2d() == ["g17", "m870"], "equipping G17 swaps it into the primary slot")
	menu.armory._select(&"m1014")
	menu.armory._equip(false)
	_check(p.loadout_2d() == ["g17", "m1014"], "equipping M1014 fills the secondary slot")
	_check(menu.armory._weapon_list.get_child(0) == menu.armory._weapon_buttons[&"g17"]
		and menu.armory._weapon_list.get_child(1) == menu.armory._weapon_buttons[&"m1014"],
		"pinned order follows the new loadout after equipping")

	# 分类标签筛选 + 改枪子页切回主武器 + 武器详情「去改枪」直达选中武器 + 消音器弹速绿标验证。
	menu.armory._select_category(&"sniper")
	var visible_sniper := 0
	for wid in WeaponDB.WEAPON_ORDER:
		if menu.armory._weapon_buttons[wid].visible:
			visible_sniper += 1
	_check(visible_sniper == 1 and menu.armory._weapon_buttons[&"awm"].visible
		and menu.armory._selected == &"awm",
		"sniper category tab isolates AWM and auto-selects it")
	# 直接点顶部「配件与组件」子页：强制切到当前主武器 (g17)。
	menu.armory._show_weapon_sub("mods")
	_check(menu.armory._mods_page.visible and menu.armory._mod_item == "g17",
		"switching directly to Mods sub-tab forces selecting the equipped primary weapon")
	# 回到「武器数据」页选中 AWM，点详细页底部的「去改枪」按钮：直达 AWM 改枪画布。
	menu.armory._show_weapon_sub("data")
	menu.armory._select(&"awm")
	_check(menu.armory._mod_shortcut_button != null and menu.armory._mod_shortcut_button.visible,
		"weapon detail page exposes a direct '去改枪' shortcut button")
	menu.armory._mod_shortcut_button.pressed.emit()
	_check(menu.armory._mods_page.visible and menu.armory._mod_item == "awm",
		"'去改枪' shortcut opens Mods sub-tab directly on the selected weapon")
	menu.armory._show_weapon_sub("data")
	menu.armory._select_category(&"all")
	p.data["weapon_mods_2d"]["akm"] = {"muzzle": "suppressor"}
	menu.armory._select(&"akm")
	_check(menu.armory._detail_deltas["子弹速度"].text.contains("(+43)")
		and menu.armory._detail_deltas["伤害"].text == "",
		"suppressor shows green bullet velocity boost and no damage penalty in detail panel")
	p.data["weapon_mods_2d"]["akm"] = {}

	menu.armory.close_menu()
	await process_frame
	_check(_closed and not menu.armory.visible, "armory closes and emits closed")

	menu._open_armory()
	await process_frame
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	menu._unhandled_input(esc)
	_check(not menu.armory.visible, "ESC closes the armory")

	menu.queue_free()
	await process_frame

	# 开局携带：主武器 G17，按 1/2 只在这两把之间切换。
	var main = load("res://scenes/core/Main2D.tscn").instantiate()
	main.mouse_aim_enabled = false
	root.add_child(main)
	await process_frame
	await physics_frame
	var rig = main.doll.weapon_rig
	_check(rig != null and rig.weapon_id == &"g17", "run starts with the configured primary")
	_check(rig.loadout.size() == 2 and rig.loadout.has(&"g17") and rig.loadout.has(&"m1014"),
		"weapon rig carries exactly two configured weapons")
	_check(not rig.switch_to(&"m870"), "weapons outside the loadout cannot be switched in")
	_check(rig.switch_to(&"m1014"), "secondary weapon can be switched in")

	main.queue_free()
	await process_frame
	print("\n=== armory 2d: %s (%d ok / %d fail) ===" % ["PASS" if _fail == 0 else "FAIL", _pass, _fail])
	quit()
