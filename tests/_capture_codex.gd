extends SceneTree
## 临时截图：主菜单图鉴按钮 + 敌人/物品图鉴页面。
## godot --path . --script res://tests/_capture_codex.gd

func _initialize() -> void:
	call_deferred("_run")


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://" + path)


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var menu = load("res://scenes/ui/StartMenu2D.tscn").instantiate()
	root.add_child(menu)
	for i in 30:
		await process_frame
	await _shot("screenshots/ui_start_codex.png")

	menu._open_codex()
	for i in 20:
		await process_frame
	await _shot("screenshots/ui_codex_enemy.png")

	menu.codex._enemy_index = 7
	menu.codex._refresh_entry()
	for i in 10:
		await process_frame
	await _shot("screenshots/ui_codex_goliath.png")

	menu.codex._show_page("item")
	for i in 10:
		await process_frame
	await _shot("screenshots/ui_codex_item_weapon.png")

	# 18 武器之后是弹药，30 之后是资源，36 是物品末页。
	menu.codex._item_index = 18
	menu.codex._refresh_entry()
	for i in 10:
		await process_frame
	await _shot("screenshots/ui_codex_item_ammo.png")

	menu.codex._item_index = 30
	menu.codex._refresh_entry()
	for i in 10:
		await process_frame
	await _shot("screenshots/ui_codex_item_resource.png")

	menu.codex._item_index = 36
	menu.codex._refresh_entry()
	for i in 10:
		await process_frame
	await _shot("screenshots/ui_codex_item_last.png")

	print("codex capture done")
	quit()
