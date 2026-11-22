extends SceneTree
## 瞄具系统验收截图：PSO 新准星、准星切换、改枪页属性/准星栏、缩放联动。
## godot --path . --script res://tests/_capture_sight_system.gd

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
		print("FAIL Progress missing")
		quit(1)
		return
	p.reset_for_test()
	p.data["loadout_2d"] = ["m870", "g17"]
	p.data["weapon_mods_2d"]["m870"] = {"sight": "pso"}
	p.set_reticle_style("pso", "pso")

	# ---- 改枪页：10 个瞄具、瞄具属性摘要、准星样式栏 ----
	var menu = load("res://scenes/ui/StartMenu2D.tscn").instantiate()
	root.add_child(menu)
	for i in 20:
		await process_frame
	menu._open_armory()
	for i in 10:
		await process_frame
	menu.armory._show_page("mods")
	menu.armory._select_mod_item("m870")
	menu.armory._select_mod_slot("sight")
	for i in 10:
		await process_frame
	await _shot("screenshots/_verify_sight_ui.png")
	menu.queue_free()
	for i in 4:
		await process_frame

	# ---- 实机：PSO 新准星 / 准星切换 / 缩放联动 ----
	main = load("res://scenes/core/Main2D.tscn").instantiate()
	root.add_child(main)
	for i in 40:
		await process_frame
	for enemy in main.enemies.duplicate():
		enemy.queue_free()
	main.enemies.clear()
	main.doll.global_position = Vector2(39.5, 60.5) * main.TILE
	main.doll.weapon_rig.setup(&"m870")
	var probe_world: Vector2 = main.doll.global_position + Vector2(560, 0)
	main.doll.aim_target = probe_world
	var box := Probe.new()
	box.position = probe_world
	box.z_index = 600
	main.add_child(box)
	for i in 6:
		await process_frame
	for i in 4:
		var ct: Transform2D = main.get_viewport().get_canvas_transform()
		Input.warp_mouse(ct * probe_world)
		for f in 6:
			await process_frame
	Input.action_press("aim")
	for i in 36:
		await process_frame
	await _shot("screenshots/_verify_pso_new.png")

	# 切换到十字准星
	p.set_reticle_style("pso", "cross")
	main.doll.weapon_rig.setup(&"m870")
	for i in 36:
		await process_frame
	await _shot("screenshots/_verify_pso_cross.png")

	# 切回 PSO，并把玩家视角切到 40%：镜内实际放大应同步降到 1.6×
	p.set_reticle_style("pso", "pso")
	main.doll.weapon_rig.setup(&"m870")
	main._set_view_zoom(40.0)
	for i in 70:
		await process_frame
	print("view zoom=", main.view_zoom_scale(), " lens zoom=", main.scope_sight._cam.zoom.x)
	await _shot("screenshots/_verify_pso_zoom40.png")
	print("sight shots done")
	quit()


class Probe extends Node2D:
	func _draw() -> void:
		draw_rect(Rect2(-24, -24, 48, 48), Color(1.0, 0.2, 1.0, 0.25))
		draw_rect(Rect2(-24, -24, 48, 48), Color(1.0, 0.2, 1.0, 0.95), false, 2.0)
		draw_line(Vector2(-36, 0), Vector2(36, 0), Color(1.0, 0.2, 1.0, 0.9), 2.0)
		draw_line(Vector2(0, -36), Vector2(0, 36), Color(1.0, 0.2, 1.0, 0.9), 2.0)
