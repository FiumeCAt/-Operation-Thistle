extends SceneTree
## 后坐力验收截图：武器数据页的基础/上限显示 + 连射后的镜头与散布变化。
## godot --path . --script res://tests/_capture_recoil_2d.gd

var main = null


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

	# ---- 武器数据页：后坐抑制 / 后坐力（基础 / 上限）----
	var menu = load("res://scenes/ui/StartMenu2D.tscn").instantiate()
	root.add_child(menu)
	for i in 20:
		await process_frame
	menu._open_armory()
	for i in 10:
		await process_frame
	menu.armory._show_page("weapon")
	menu.armory._select(&"akm")
	for i in 10:
		await process_frame
	await _shot("screenshots/_verify_recoil_ui.png")
	menu.queue_free()
	for i in 4:
		await process_frame

	# ---- 实机连射：后坐力累积、镜头踢与散布变宽 ----
	main = load("res://scenes/core/Main2D.tscn").instantiate()
	root.add_child(main)
	for i in 40:
		await process_frame
	for enemy in main.enemies.duplicate():
		enemy.queue_free()
	main.enemies.clear()
	main.doll.global_position = Vector2(39.5, 60.5) * main.TILE
	main.doll.weapon_rig.setup(&"akm")
	var target: Vector2 = main.doll.global_position + Vector2(620, 0)
	var mark := Mark.new()
	mark.position = target
	main.add_child(mark)
	for i in 4:
		var ct: Transform2D = main.get_viewport().get_canvas_transform()
		Input.warp_mouse(ct * target)
		for f in 6:
			await process_frame
	await _shot("screenshots/_verify_recoil_before.png")
	var spread_before: float = main.get_aim_spread()
	for shot in 6:
		main.doll.weapon_rig.cooldown = 0.0
		main.doll.weapon_rig.try_fire()
		await process_frame
	for f in 8:
		await process_frame
	var spread_after: float = main.get_aim_spread()
	print("recoil offset=", main._recoil_offset, " cam=", main._recoil_cam,
		" roll=", main._recoil_roll)
	print("spread before=", rad_to_deg(spread_before), "deg after=",
		rad_to_deg(spread_after), "deg")
	await _shot("screenshots/_verify_recoil_after.png")
	print("recoil shots done")
	quit()


class Mark extends Node2D:
	func _draw() -> void:
		draw_rect(Rect2(-30, -30, 60, 60), Color(1.0, 0.2, 1.0, 0.22))
		draw_rect(Rect2(-30, -30, 60, 60), Color(1.0, 0.2, 1.0, 0.95), false, 2.0)
		draw_line(Vector2(-44, 0), Vector2(44, 0), Color(1.0, 0.2, 1.0, 0.9), 2.0)
		draw_line(Vector2(0, -44), Vector2(0, 44), Color(1.0, 0.2, 1.0, 0.9), 2.0)
