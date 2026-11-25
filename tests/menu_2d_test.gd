extends SceneTree
## 2D 菜单与左下血条布局回归。
## godot --headless --path . --script res://tests/menu_2d_test.gd

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
	create_timer(30.0).timeout.connect(func() -> void: quit(2))
	# 无头模式默认 64x64，HUD 的角落锚点需要真实窗口尺寸才能验证。
	root.size = Vector2i(1600, 900)
	await process_frame

	var menu = load("res://scenes/ui/StartMenu2D.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	_check(menu.start_button != null and menu.start_button.text.contains("开始"), "start menu has start button")
	_check(menu.talents_button != null and menu.talents_button.text.contains("TALENTS"), "start menu has talents button")
	_check(menu.stash_button != null and menu.stash_button.text.contains("STASH"), "start menu has stash button")
	_check(menu.quit_button != null and menu.quit_button.text.contains("退出"), "start menu has quit button")
	_check(menu.start_button.has_meta(&"ui_sfx"), "buttons carry ui sfx hooks")
	var sfx = root.get_node_or_null("Sfx")
	_check(sfx != null and sfx.get_stream("ui_hover") != null and sfx.get_stream("ui_click") != null,
		"ui hover/click streams exist")
	_check(menu.start_button.has_focus(), "start button grabs focus")

	# 仓库：只读展示信用点与全部资源库存。
	var p = root.get_node_or_null("Progress")
	if p != null:
		p.reset_for_test()
		p.data["materials_2d"] = {"electronics": 7, "energy": 5, "parts": 3}
		p.data["advanced_2d"] = {
			"weapon_parts": 2, "electronic_core": 0,
			"high_energy_cell": 1, "military_alloy": 0,
		}
	menu._open_stash()
	await process_frame
	_check(menu.stash.visible, "stash opens from the base menu")
	_check(menu.stash._counts["electronics"].text == "7"
		and menu.stash._counts["weapon_parts"].text == "2",
		"stash lists resource counts")
	_check(menu.stash._basic_total.text.contains("15")
		and menu.stash._advanced_total.text.contains("3"),
		"stash totals basic and rare resources")
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	menu._unhandled_input(esc)
	_check(not menu.stash.visible, "ESC closes the stash")

	_check(menu.deployment != null and not menu.deployment.visible, "deployment menu exists")
	_check(menu._bg_textures.size() == 3, "start menu loads all three tactical background slides")
	menu.select_bg_slide(2)
	_check(menu._bg_index == 2, "start menu background slide selector switches cleanly")
	_check(menu.theme_buttons.size() == 4 and menu.theme_picker != null,
		"start menu exposes four theme presets and custom color picker")
	if p != null:
		p.set_loadout_2d(&"akm", &"g17")
		menu._refresh_dossier()
		_check(menu._loadout_slots["primary"]["name"].text.contains("AKM")
			and menu._loadout_slots["secondary"]["name"].text.contains("G17"),
			"start menu loadout card shows equipped primary and secondary weapons")
		menu._select_theme_preset("cyan")
		_check(p.ui_theme() == "cyan" and PixelUI.theme_id() == "cyan"
			and PixelUI.theme_accent().is_equal_approx(Color.html("#52cac1"))
			and PixelUI.theme_accent_bright().is_equal_approx(Color.html("#34fcfe")),
			"selecting cyan theme applies updated #52cac1 / #34fcfe palette and saves to Progress")
		menu._select_theme_preset("terminal")
		_check(p.ui_theme() == "terminal" and PixelUI.theme_id() == "terminal"
			and PixelUI.theme_accent().is_equal_approx(Color.html("#04a82e"))
			and PixelUI.theme_accent_bright().is_equal_approx(Color.html("#00ff00")),
			"selecting terminal theme applies updated #04a82e / #00ff00 palette")
		menu._on_custom_theme_color(Color(0.85, 0.35, 0.95))
		_check(p.ui_theme() == "custom" and absf(p.ui_theme_color().r - 0.85) < 0.02,
			"custom theme color switches to custom mode and persists")
		menu._select_theme_preset("amber")
	menu._start()
	_check(menu.deployment.visible, "start opens the deployment screen")
	menu.deployment.close_menu()
	menu.queue_free()
	await process_frame

	var main = load("res://scenes/core/Main2D.tscn").instantiate()
	main.mouse_aim_enabled = false
	root.add_child(main)
	await process_frame
	await process_frame
	_check(main.pause_menu != null, "pause menu exists")
	_check(main.pause_menu.layer > main.hud.layer, "pause menu is above the HUD")
	var hp_rect: Rect2 = main.hud.hp_label.get_global_rect()
	var vp: Vector2 = root.get_visible_rect().size
	_check(hp_rect.position.x < vp.x * 0.5, "health bar sits on the left")
	_check(hp_rect.position.y > vp.y * 0.6, "health bar sits near the bottom")

	main.pause_menu.open()
	_check(paused and main.pause_menu.visible, "pause menu pauses the game and shows")
	_check(Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE, "pause menu shows the cursor")
	main.pause_menu.close()
	_check(not paused and not main.pause_menu.visible, "resume unpauses and hides the menu")

	# 暂停菜单改的画面设置必须立刻作用到本局，而不是等重开一局。
	main.pause_menu.open()
	main.pause_menu._open_settings()
	await process_frame
	main.pause_menu.settings_menu._zoom_slider.value = 160.0
	main.pause_menu.settings_menu._set_screen_shake(false)
	main.pause_menu.settings_menu._shake_scale_slider.value = 0.0
	main.pause_menu.settings_menu._set_hitstop(false)
	main.pause_menu.settings_menu.close_menu()
	await process_frame
	_check(is_equal_approx(main.view_zoom_pct, 160.0) and not main.screen_shake
		and is_zero_approx(main.shake_scale) and not main.hitstop_enabled,
		"closing pause settings applies zoom, shake scale and hitstop to the live run")
	main.add_shake(10.0)
	_check(is_zero_approx(main._shake), "0% shake scale disables camera kick")
	main.pause_menu.close()

	main.queue_free()
	await process_frame
	print("\n=== menu 2d: %s (%d ok / %d fail) ===" % ["PASS" if _fail == 0 else "FAIL", _pass, _fail])
	quit()
