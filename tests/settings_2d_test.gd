extends SceneTree
## 设置菜单回归：暂停菜单与开始菜单共用同一套设置页、同一份存档；
## 音量滑杆实时作用于总线，暂停时 ESC 分层退出。
## godot --headless --path . --script res://tests/settings_2d_test.gd

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


func _near(a: float, b: float, eps := 0.01) -> bool:
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

	var pm := PauseMenu2D.new()
	root.add_child(pm)
	await process_frame
	_check(pm._settings_button != null and pm._settings_button.text.contains("SETTINGS"),
		"pause menu has settings button")
	pm.open()
	_check(pm.visible and paused, "pause menu pauses the tree")
	pm._open_settings()
	await process_frame
	var sm: SettingsMenu2D = pm.settings_menu
	_check(sm != null and sm.visible, "pause menu opens the shared settings page")
	_check(sm._sliders.has("master") and sm._sliders.has("sfx") and sm._sliders.has("music"),
		"pause settings expose all three volume sliders")
	_check(sm._ammo_buttons.size() == 3 and sm._interval_button != null and sm._zoom_slider != null,
		"pause settings expose every gameplay option")
	_check(_near(sm._sliders["master"].value, 80.0) and _near(sm._sliders["sfx"].value, 80.0),
		"sliders reflect saved volumes")
	_check(sm._hitstop_buttons.size() == 2 and sm._shake_scale_slider != null
		and sm._shake_scale_edit != null, "pause settings expose hitstop and shake scale")
	_check(sm._sample_buttons.size() == 2 and bool(p.data["sample_impacts"]),
		"sampled impact audio defaults to on")
	_check(sm._hit_fx_buttons.size() == 3 and int(p.data["hit_fx_level"]) == 1,
		"hit flash effect defaults to reduced")
	_check(sm._trail_buttons.size() == 2 and bool(p.data["bullet_trail_enabled"]),
		"弹道线条效果默认开启")
	_check(not bool(p.data["hitstop_enabled"]) and _near(float(p.data["shake_scale"]), 100.0),
		"hitstop defaults to off and shake to 100%")
	_check(_near(sm._shake_scale_slider.value, 100.0) and sm._shake_scale_edit.text == "100",
		"shake controls load the saved 100%")

	var sfx := root.get_node_or_null("Sfx")
	_check(sfx != null and AudioServer.get_bus_index("SFX") >= 0, "SFX bus exists")

	sm._sliders["master"].value = 40.0
	sm._sliders["sfx"].value = 55.0
	await process_frame
	_check(_near(AudioServer.get_bus_volume_db(0), linear_to_db(0.4)),
		"master slider changes the Master bus")
	_check(_near(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX")),
		linear_to_db(0.55)), "sfx slider changes the SFX bus")
	await create_timer(0.6).timeout
	_check(_near(float(p.data["volume"]), 0.4) and _near(float(p.data["sfx_volume"]), 0.55),
		"volumes are saved to progress")

	sm._sliders["master"].value = 0.0
	await process_frame
	_check(AudioServer.is_bus_mute(0), "zero master volume mutes the bus")
	sm._sliders["master"].value = 40.0
	await process_frame

	# 在暂停菜单里改完整套选项，开始菜单的同一面板必须读到相同值。
	sm._sliders["music"].value = 45.0
	sm._set_fire_mode("rpm")
	sm._set_armor_display("rha_mm")
	sm._set_ammo_display("numeric")
	sm._set_screen_shake(false)
	sm._set_bullet_trail(false)
	sm._zoom_slider.value = 150.0
	await create_timer(0.6).timeout
	_check(_near(float(p.data["music_volume"]), 0.45), "music volume saved from pause settings")
	_check(String(p.data["fire_rate_display"]) == "rpm"
		and String(p.data["armor_display"]) == "rha_mm"
		and String(p.data["ammo_display"]) == "numeric"
		and not bool(p.data["screen_shake"])
		and not bool(p.data["bullet_trail_enabled"])
		and _near(float(p.data["view_zoom"]), 150.0),
		"gameplay options saved from pause settings")

	# 顿帧开关与震动幅度：滑块和输入框双向同步，数值夹在 0–1000。
	sm._set_hitstop(true)
	_check(bool(p.data["hitstop_enabled"]), "hitstop toggle saved immediately")
	sm._set_sample_impacts(false)
	_check(not bool(p.data["sample_impacts"]), "sample impact toggle saved immediately")
	sm._set_hit_fx_level(0)
	_check(int(p.data["hit_fx_level"]) == 0, "hit flash effect can be turned off")
	sm._shake_scale_slider.value = 350.0
	await process_frame
	_check(sm._shake_scale_edit.text == "350", "slider updates the numeric field")
	sm._shake_scale_edit.text = "875"
	sm._commit_shake_scale()
	_check(_near(sm._shake_scale_slider.value, 875.0), "custom value moves the slider")
	sm._shake_scale_edit.text = "5000"
	sm._commit_shake_scale()
	_check(_near(sm._shake_scale_slider.value, 1000.0), "shake clamps to 1000%")
	sm._shake_scale_edit.text = "250"
	sm._commit_shake_scale()
	await create_timer(0.6).timeout
	_check(_near(float(p.data["shake_scale"]), 250.0), "custom shake value saved")

	var start_sm := SettingsMenu2D.new()
	root.add_child(start_sm)
	await process_frame
	start_sm.open()
	await process_frame
	_check(_near(start_sm._sliders["master"].value, 40.0)
		and _near(start_sm._sliders["music"].value, 45.0),
		"start menu reads the volumes changed in pause")
	_check(_near(start_sm._zoom_slider.value, 150.0)
		and start_sm._rpm_button.text.contains("▶")
		and start_sm._armor_display_buttons["rha_mm"].text.contains("▶")
		and start_sm._ammo_buttons["numeric"].text.contains("▶")
		and start_sm._shake_buttons[false].text.contains("▶")
		and start_sm._trail_buttons[false].text.contains("▶"),
		"start menu reads the gameplay options changed in pause")
	_check(start_sm._hitstop_buttons[true].text.contains("▶")
		and _near(start_sm._shake_scale_slider.value, 250.0)
		and start_sm._shake_scale_edit.text == "250",
		"start menu reads hitstop and shake scale changed in pause")
	_check(start_sm._sample_buttons[false].text.contains("▶"),
		"start menu reads the sampled impact toggle changed in pause")
	_check(start_sm._hit_fx_buttons[0].text.contains("▶"),
		"start menu reads the hit flash level changed in pause")
	start_sm.queue_free()
	await process_frame

	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	pm._unhandled_input(esc)
	_check(not sm.visible and pm.visible, "ESC closes settings before the pause menu")
	pm._unhandled_input(esc)
	_check(not pm.visible and not paused, "second ESC resumes the game")

	pm.queue_free()
	await process_frame

	# 弹道线条与小地图（形状/比例/缩放 + 实时预览窗 + 调试 3.0× 上下限）写入磁盘：模拟重启后仍保持玩家选择。
	sm = SettingsMenu2D.new()
	root.add_child(sm)
	await process_frame
	sm.open()
	_check(sm._minimap_preview != null and sm._minimap_preview.preview_mode,
		"settings menu embeds a live minimap preview widget")
	sm._set_minimap_shape("circle")
	sm._minimap_scale_slider.value = 125.0
	sm._minimap_zoom_slider.value = 160.0
	_check(sm._minimap_preview.map_shape == "circle"
		and _near(sm._minimap_preview.map_scale, 1.25)
		and _near(sm._minimap_preview.map_zoom, 1.6),
		"live minimap preview immediately mirrors shape, scale, and zoom")
	await create_timer(0.5).timeout
	sm.queue_free()
	await process_frame
	p.load_data()
	_check(p.minimap_shape() == "circle"
		and _near(p.minimap_scale(), 1.25)
		and _near(p.minimap_zoom(), 1.6),
		"minimap shape, scale, and zoom persist across reload")

	# 调试界面修改小地图最小/最大缩放上限（最高 3.0×），并同步放开设置页缩放滑杆。
	sm = SettingsMenu2D.new()
	root.add_child(sm)
	await process_frame
	sm.open()
	var dm: DebugMenu2D = sm._debug_menu
	_check(dm != null and dm._sliders.size() == 8
		and dm._minimap_zoom_min_slider != null and dm._minimap_zoom_max_slider != null,
		"debug menu exposes minimap zoom bounds without changing the 8 multiplier sliders")
	dm.open()
	dm._minimap_zoom_min_slider.value = 0.5
	dm._minimap_zoom_max_slider.value = 3.0
	dm.close_menu()
	await process_frame
	_check(_near(sm._minimap_zoom_slider.min_value, 50.0)
		and _near(sm._minimap_zoom_slider.max_value, 300.0),
		"settings minimap zoom slider dynamically adopts debug 0.5x-3.0x range")
	sm._minimap_zoom_slider.value = 300.0
	_check(_near(sm._minimap_preview.map_zoom, 3.0),
		"live minimap preview supports 3.0x zoom")
	await create_timer(0.45).timeout
	sm.queue_free()
	await process_frame
	p.load_data()
	_check(_near(p.minimap_zoom_min(), 0.5) and _near(p.minimap_zoom_max(), 3.0)
		and _near(p.minimap_zoom(), 3.0),
		"debug minimap zoom bounds and 3.0x zoom persist across reload")

	# 实验性打字机开关与速度调节持久化 + PixelUI 逐字播放驱动检查。
	sm = SettingsMenu2D.new()
	root.add_child(sm)
	await process_frame
	sm.open()
	_check(sm._typewriter_buttons.size() == 2 and sm._typewriter_speed_slider != null
		and sm._typewriter_preview != null and not p.typewriter_enabled(),
		"experimental typewriter defaults to off with speed slider and live preview")
	sm._set_typewriter_enabled(true)
	sm._typewriter_speed_slider.value = 85.0
	await process_frame
	_check(PixelUI.typewriter_enabled() and _near(PixelUI.typewriter_speed(), 85.0),
		"typewriter toggle and speed sync to PixelUI")
	var probe_lbl := Label.new()
	probe_lbl.text = "K-17 TACTICAL TYPEWRITER TEST"
	root.add_child(probe_lbl)
	PixelUI.play_typewriter(probe_lbl, false, 90.0)
	_check(probe_lbl.visible_characters >= 0 and probe_lbl.visible_characters < probe_lbl.text.length(),
		"typewriter starts revealing characters progressively without altering text")
	PixelUI.finish_typewriter(probe_lbl)
	_check(probe_lbl.visible_characters == -1, "finish_typewriter restores full visibility")
	probe_lbl.queue_free()
	await create_timer(0.45).timeout
	sm.queue_free()
	await process_frame
	p.load_data()
	_check(p.typewriter_enabled() and _near(p.typewriter_speed(), 85.0),
		"typewriter enabled state and speed persist across reload")

	p.set_typewriter_enabled(false)
	p.set_typewriter_speed(48.0)
	p.reset_debug()
	p.set_minimap_shape("square")
	p.set_minimap_scale(1.0)
	p.set_minimap_zoom(1.0)

	# 弹道线条开关写入磁盘：模拟重启（重新读盘）后仍保持玩家选择。
	p.set_bullet_trail_enabled(false)
	p.load_data()
	_check(not bool(p.data["bullet_trail_enabled"]),
		"弹道线条关闭后重启仍为关闭")
	p.set_bullet_trail_enabled(true)
	p.load_data()
	_check(bool(p.data["bullet_trail_enabled"]),
		"弹道线条开启后重启仍为开启")

	# 拾取合并窗口滑杆：默认 3.0s，支持 0.0s（关闭）至 10.0s 持久化。
	sm = SettingsMenu2D.new()
	root.add_child(sm)
	await process_frame
	sm.open()
	_check(sm._pickup_merge_slider != null and _near(sm._pickup_merge_slider.value, 3.0)
		and sm._pickup_merge_value.text == "3.0s",
		"pickup merge window defaults to 3.0s in settings menu")
	sm._pickup_merge_slider.value = 0.0
	_check(sm._pickup_merge_value.text == "关闭",
		"pickup merge window displays 关闭 at 0.0s")
	sm._pickup_merge_slider.value = 5.5
	_check(sm._pickup_merge_value.text == "5.5s",
		"pickup merge window displays formatted seconds at 5.5s")
	await create_timer(0.45).timeout
	sm.queue_free()
	await process_frame
	p.load_data()
	_check(_near(p.pickup_merge_window(), 5.5),
		"pickup merge window persists across save reload")
	p.set_pickup_merge_window(3.0)

	# 实验性「真实逐发弹匣」开关：默认关闭，在设置页开启后持久化且跨重启保留。
	sm = SettingsMenu2D.new()
	root.add_child(sm)
	await process_frame
	sm.open()
	_check(sm._ammo_exact_buttons.size() == 2 and not p.ammo_exact_rounds()
		and sm._ammo_exact_buttons[false].text.contains("▶"),
		"experimental exact-rounds magazine display defaults to off")
	sm._set_ammo_exact_rounds(true)
	_check(p.ammo_exact_rounds() and sm._ammo_exact_buttons[true].text.contains("▶"),
		"experimental exact-rounds toggle saves immediately when enabled")
	sm.queue_free()
	await process_frame
	p.load_data()
	_check(p.ammo_exact_rounds(), "experimental exact-rounds setting persists across reload")
	p.set_ammo_exact_rounds(false)

	print("\n=== settings 2d: %s (%d ok / %d fail) ===" % ["PASS" if _fail == 0 else "FAIL", _pass, _fail])
	quit()
