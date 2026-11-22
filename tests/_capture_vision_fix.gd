extends SceneTree
## 视野修复验收：玩家脚底可走、头部落在上方墙格时，前方敌人仍必须可见。
## godot --path . --script res://tests/_capture_vision_fix.gd

var main


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var p = root.get_node_or_null("Progress")
	if p != null:
		p.reset_for_test()
	main = load("res://scenes/core/Main2D.tscn").instantiate()
	main.mouse_aim_enabled = false
	root.add_child(main)
	for i in 40:
		await process_frame
	for enemy in main.enemies.duplicate():
		enemy.queue_free()
	main.enemies.clear()
	var tile: float = main.TILE
	var spot := Vector2.INF
	for y in range(20, main.level._nav_h - 1):
		for x in range(4, main.level._nav_w - 6):
			var feet := Vector2(x + 0.5, y + 0.5) * tile
			if not main.level.is_nav_walkable(feet):
				continue
			if main.level.is_nav_walkable(feet + Vector2(0, -82.0)):
				continue
			var clear := true
			for k in range(1, 5):
				if not main.level.is_nav_walkable(feet + Vector2(k * tile, 0)):
					clear = false
					break
			if clear:
				spot = feet
				break
		if spot != Vector2.INF:
			break
	if spot == Vector2.INF:
		push_error("no head-blocked spot found")
		quit(1)
		return
	main.doll.global_position = spot
	main.doll.aim_target = spot + Vector2.RIGHT * 600.0
	main.vision._aim_angle = 0.0
	var enemy := Enemy2D.new()
	enemy.setup(&"rifleman", spot + Vector2(4 * tile, 0), 1)
	main.sort_layer.add_child(enemy)
	enemy.set_physics_process(false)
	for i in 20:
		await process_frame
	main.vision.refresh_enemies()
	for i in 10:
		await process_frame
	print("spot=", spot, " head_blocked=",
		not main.level.is_nav_walkable(spot + Vector2(0, -82.0)),
		" enemy_tier=", main.vision.tier_at(enemy.global_position),
		" enemy_visible=", enemy.visible)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(
		"res://screenshots/_verify_vision_enemy_visible.png")
	print("vision fix capture done")
	quit()
