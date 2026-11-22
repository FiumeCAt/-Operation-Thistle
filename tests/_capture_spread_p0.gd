extends SceneTree
## P0 散布修复验收：霰弹连续射击，把每颗弹丸的实际命中点画成持久标记。
## godot --path . --script res://tests/_capture_spread_p0.gd

var main = null
var dots: SpreadDots
var hits: Array[Vector2] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var p = root.get_node_or_null("Progress")
	if p == null:
		quit(1)
		return
	p.reset_for_test()
	p.data["loadout_2d"] = ["m1014", "g17"]
	main = load("res://scenes/core/Main2D.tscn").instantiate()
	root.add_child(main)
	for i in 40:
		await process_frame
	for enemy in main.enemies.duplicate():
		enemy.queue_free()
	main.enemies.clear()
	main.doll.global_position = Vector2(39.5, 60.5) * main.TILE
	main.doll.weapon_rig.setup(&"m1014")
	main.doll.weapon_rig.mag = 40
	var target: Vector2 = main.doll.global_position + Vector2(640, 0)
	main.mouse_aim_enabled = false
	main.doll.aim_target = target
	for i in 4:
		var ct: Transform2D = main.get_viewport().get_canvas_transform()
		Input.warp_mouse(ct * target)
		for f in 6:
			await process_frame
	for shot in 8:
		main.doll.weapon_rig.cooldown = 0.0
		var fired: bool = main.doll.weapon_rig.try_fire()
		if fired:
			var origin: Vector2 = main.last_shot_origin
			for dir in main.last_pellet_dirs:
				var hit: Dictionary = main._trace_pellet(origin, dir, 1200.0)
				if not hit.is_empty():
					hits.append(Vector2(hit["position"]))
		for f in 20:
			await process_frame
	dots = SpreadDots.new()
	dots.points = hits
	dots.z_index = 800
	main.add_child(dots)
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://screenshots/_verify_spread_p0.png")
	var max_dev := 0.0
	for shot_dir in main.last_pellet_dirs:
		max_dev = maxf(max_dev, absf(rad_to_deg(shot_dir.angle_to(main.last_shot_dir))))
	print("hits=", hits.size(), " last shot max dev=", max_dev)
	print("spread p0 capture done")
	quit()


class SpreadDots extends Node2D:
	var points: Array[Vector2] = []

	func _draw() -> void:
		for point in points:
			draw_circle(to_local(point), 3.5, Color(1.0, 0.85, 0.2, 0.95))
			draw_circle(to_local(point), 6.0, Color(1.0, 0.85, 0.2, 0.25))
