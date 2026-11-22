extends SceneTree
## 截图：装饰容器（衣物 / 物料箱）靠近时显示搜刮提示。
## godot --path . --script res://tests/_capture_searchables.gd -- --save-path user://capture_searchables.json

const OUT_DIR := "D:/AI Game/temp_20261027_01/screenshots"


func _initialize() -> void:
	call_deferred("_run")


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)


func _run() -> void:
	root.size = Vector2i(1600, 900)
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var p = root.get_node_or_null("Progress")
	if p == null or not String(p.save_path).contains("capture_searchables"):
		push_error("refusing to capture without an isolated save path")
		quit(1)
		return
	p.reset_for_test()

	var main = load("res://scenes/core/Main2D.tscn").instantiate()
	main.mouse_aim_enabled = false
	root.add_child(main)
	for i in 25:
		await process_frame
	for enemy in main.enemies:
		enemy.set_physics_process(false)

	var cloth: Dictionary = {}
	var box: Dictionary = {}
	for entry in main.level.containers:
		if not bool(entry.get("keep_closed_art", false)):
			continue
		var art := String(entry.get("art", ""))
		if cloth.is_empty() and (art.contains("coat") or art.contains("jacket")
				or art.contains("hazmat")):
			cloth = entry
		if box.is_empty() and art == "material_case":
			box = entry
		if not cloth.is_empty() and not box.is_empty():
			break

	if not cloth.is_empty():
		main.doll.global_position = Vector2(cloth["position"]) + Vector2(-58, 52)
		main.camera.global_position = main.doll.global_position
		main.doll.aim_target = main.doll.global_position + Vector2(60, -40)
		for i in 25:
			await process_frame
		await _shot(OUT_DIR + "/searchable_clothes.png")

	if not box.is_empty():
		main.doll.global_position = Vector2(box["position"]) + Vector2(-58, 52)
		main.camera.global_position = main.doll.global_position
		main.doll.aim_target = main.doll.global_position + Vector2(60, -40)
		for i in 25:
			await process_frame
		await _shot(OUT_DIR + "/searchable_material_box.png")

	print("searchables capture done")
	quit()
