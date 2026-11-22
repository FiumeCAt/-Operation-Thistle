extends SceneTree
## 临时截图：新开始菜单、武器库、ESC 设置页。
## godot --path . --script res://tests/_capture_menu2.gd -- --save-path user://capture_menu2.json

func _initialize() -> void:
	call_deferred("_run")


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://" + path)


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var p = root.get_node_or_null("Progress")
	if p == null or not String(p.save_path).contains("capture_menu2"):
		push_error("refusing to capture without an isolated save path")
		quit(1)
		return
	p.data["resources"] = 120
	p.data["xp"] = 40
	p.data["skill_level"] = 3
	p.data["loadout_2d"] = ["m870", "g17"]
	p.data["advanced_2d"] = {
		"weapon_parts": 3, "electronic_core": 2,
		"high_energy_cell": 2, "military_alloy": 3,
	}
	p.data["weapon_mods_2d"]["m1014"] = {"magazine": "tube_long", "muzzle": "suppressor"}
	p.data["weapon_mods_2d"]["saiga12k"] = {"magazine": "mag_drum", "core": "auto"}
	p.data["weapon_mods_2d"]["g17"] = {"magazine": "mag_long", "core": "auto"}

	var menu = load("res://scenes/ui/StartMenu2D.tscn").instantiate()
	root.add_child(menu)
	for i in 30:
		await process_frame
	await _shot("screenshots/ui_start.png")

	menu._open_settings()
	for i in 15:
		await process_frame
	await _shot("screenshots/ui_settings_main.png")
	menu.settings_menu._set_fire_mode("rpm")
	for i in 5:
		await process_frame
	await _shot("screenshots/ui_settings_rpm.png")
	menu.settings_menu.close_menu()
	for i in 10:
		await process_frame

	menu._open_armory()
	for i in 20:
		await process_frame
	menu.armory._select(&"m1014")
	for i in 10:
		await process_frame
	await _shot("screenshots/ui_armory.png")
	# 悬浮窗：暂停跟随鼠标，手动摆到数据行右侧再截图。
	menu.armory._show_tip("弹匣容量")
	menu.armory.set_process(false)
	menu.armory._tip_panel.global_position = Vector2(120, 560)
	menu.armory._tip_label.global_position = Vector2(134, 570)
	for i in 5:
		await process_frame
	await _shot("screenshots/ui_tooltip.png")
	menu.armory._hide_tip()
	menu.armory.set_process(true)
	menu.armory._show_page("armor")
	for i in 10:
		await process_frame
	await _shot("screenshots/ui_armor.png")
	menu.armory._show_page("mods")
	menu.armory._select_mod_item("m870")
	for i in 10:
		await process_frame
	await _shot("screenshots/ui_mods.png")
	menu.armory._select_mod_item("saiga12k")
	menu.armory._select_mod_slot("core")
	for i in 10:
		await process_frame
	await _shot("screenshots/ui_mods_saiga.png")
	menu.armory._select_mod_item("g17")
	menu.armory._select_mod_slot("core")
	for i in 10:
		await process_frame
	await _shot("screenshots/ui_mods_g17.png")
	menu.armory._show_page("weapon")
	menu.armory._select(&"g17")
	for i in 5:
		await process_frame
	menu.armory._show_tip("射速")
	menu.armory.set_process(false)
	menu.armory._tip_panel.global_position = Vector2(80, 500)
	menu.armory._tip_label.global_position = Vector2(94, 510)
	for i in 5:
		await process_frame
	await _shot("screenshots/ui_tooltip.png")
	menu.armory._hide_tip()
	menu.armory.set_process(true)
	menu.armory.close_menu()
	menu._open_talents()
	for i in 15:
		await process_frame
	menu.talents._selected = &"hp"
	menu.talents._refresh()
	for i in 5:
		await process_frame
	await _shot("screenshots/ui_talents.png")
	menu.talents._set_pan(-9999.0)
	for i in 5:
		await process_frame
	await _shot("screenshots/ui_talents_panned.png")
	menu.talents._set_pan(0.0)
	menu.talents._on_reset_all()
	for i in 5:
		await process_frame
	await _shot("screenshots/ui_talents_confirm.png")
	menu.talents._confirm_layer.hide()
	menu.talents.close_tree()
	menu.queue_free()
	await process_frame

	var main = load("res://scenes/core/Main2D.tscn").instantiate()
	root.add_child(main)
	for i in 30:
		await process_frame
	for enemy in main.enemies:
		enemy.set_process(false)
		enemy.set_physics_process(false)
	main.pause_menu.open()
	main.pause_menu._open_settings()
	for i in 20:
		await process_frame
	await _shot("screenshots/ui_settings.png")

	print("menu2 capture done")
	quit()
