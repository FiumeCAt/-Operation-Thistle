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

	# 弹道线条开关写入磁盘：模拟重启（重新读盘）后仍保持玩家选择。
	p.set_bullet_trail_enabled(false)
	p.load_data()
	_check(not bool(p.data["bullet_trail_enabled"]),
		"弹道线条关闭后重启仍为关闭")
	p.set_bullet_trail_enabled(true)
	p.load_data()
	_check(bool(p.data["bullet_trail_enabled"]),
		"弹道线条开启后重启仍为开启")

	print("\n=== settings 2d: %s (%d ok / %d fail) ===" % ["PASS" if _fail == 0 else "FAIL", _pass, _fail])
	quit()
