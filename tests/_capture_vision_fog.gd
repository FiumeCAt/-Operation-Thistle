extends SceneTree
## 临时截图：分层视野 / 视野迷雾与 F7 调试照明。
## godot --path . --script res://tests/_capture_vision_fog.gd

func _initialize() -> void:
	call_deferred("_run")


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://" + path)


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var p = root.get_node_or_null("Progress")
	if p != null:
		# 只改内存，不写盘，避免把截图状态留进玩家存档。
		p.data["run_mode"] = "raid"
		p.data["map_id"] = "facility"
	var main = load("res://scenes/core/Main2D.tscn").instantiate()
	main.mouse_aim_enabled = false
	root.add_child(main)
	for i in 30:
		await process_frame

	var origin: Vector2 = Vector2(39.5, 60.5) * main.TILE
	main.doll.global_position = origin
	main.doll.aim_target = origin + Vector2.UP * 900.0
	for enemy in main.enemies.duplicate():
		enemy.queue_free()
	main.enemies.clear()
	await process_frame

	var offsets := [Vector2.UP * 3.0, Vector2.UP * 5.0, Vector2.UP * 7.0, Vector2.DOWN * 1.5]
	for offset in offsets:
		var enemy := Enemy2D.new()
		enemy.setup(&"rifleman", origin + offset * main.TILE, 1)
		main.sort_layer.add_child(enemy)
		enemy.set_physics_process(false)
		main.enemies.append(enemy)
	for i in 24:
		await process_frame
	await _shot("screenshots/ui_vision_fog.png")

	# 转身：视野锥与墙后阴影跟着瞄准方向旋转。
	main.doll.aim_target = origin + Vector2.DOWN * 900.0
	for i in 40:
		await process_frame
	await _shot("screenshots/ui_vision_turned.png")

	main.debug_visual_mode = true
	main._apply_debug_visual_mode()
	for i in 6:
		await process_frame
	await _shot("screenshots/ui_vision_debug.png")
	main.queue_free()
	await process_frame

	# 空旷竞技场：没有墙体遮挡，三层视野（主锥/余光/近身黑暗）更直观。
	if p != null:
		p.data["run_mode"] = "waves"
		p.data["map_id"] = "goliath_arena"
	var arena = load("res://scenes/core/Main2D.tscn").instantiate()
	arena.mouse_aim_enabled = false
	root.add_child(arena)
	for i in 30:
		await process_frame
	var arena_origin: Vector2 = Vector2(50.0, 30.0) * arena.TILE
	arena.doll.global_position = arena_origin
	arena.doll.aim_target = arena_origin + Vector2.RIGHT * 900.0
	for offset in [Vector2(3, 0), Vector2(5, 0), Vector2(7, 0), Vector2(-2, 1)]:
		var enemy := Enemy2D.new()
		enemy.setup(&"goliath", arena_origin + offset * arena.TILE, 1)
		arena.sort_layer.add_child(enemy)
		enemy.set_physics_process(false)
	for i in 24:
		await process_frame
	await _shot("screenshots/ui_vision_arena.png")

	print("vision capture done")
	quit()
