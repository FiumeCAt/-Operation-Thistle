extends SceneTree
## 后坐力双轴显示 + 调试模式菜单 截图。
## godot --path . --script res://tests/_capture_debug_recoil.gd

func _initialize() -> void:
	call_deferred("_run")


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img != null:
		img.save_png("res://" + path)


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var p = root.get_node_or_null("Progress")
	if p == null:
		quit(1)
		return
	p.reset_for_test()
	p.data["loadout_2d"] = ["akm", "g17"]
	var menu = load("res://scenes/ui/StartMenu2D.tscn").instantiate()
	root.add_child(menu)
	for i in 20:
		await process_frame

	menu._open_settings()
	for i in 12:
		await process_frame
	await _shot("screenshots/_verify_settings_debug.png")
	menu.settings_menu._open_debug()
	for i in 10:
		await process_frame
	menu.settings_menu._debug_menu._set_enabled(true)
	var sliders: Dictionary = menu.settings_menu._debug_menu._sliders
	sliders["recoil_v"].value = 1.6
	sliders["recoil_h"].value = 1.4
	sliders["recoil_cap"].value = 1.8
	sliders["spread"].value = 1.5
	sliders["damage"].value = 2.0
	sliders["vision"].value = 1.3
	# 演示越界输入的自动修正与提示。
	menu.settings_menu._debug_menu._edits["damage"].text = "150"
	menu.settings_menu._debug_menu._apply_text("damage")
	for i in 8:
		await process_frame
	await _shot("screenshots/_verify_debug_menu.png")
	menu.settings_menu._debug_menu.close_menu()
	menu.settings_menu.close_menu()
	for i in 6:
		await process_frame
	p.set_debug_enabled(false)
	p.reset_debug()

	menu._open_armory()
	for i in 10:
		await process_frame
	menu.armory._show_page("weapon")
	menu.armory._select(&"akm")
	for i in 10:
		await process_frame
	await _shot("screenshots/_verify_recoil_rows.png")
	print("debug captures done")
	quit()
