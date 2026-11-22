extends SceneTree
## 摆头检查：把瞄准点分别放到正前 / 右 / 左，各截一张图。
## godot --path . --script res://tests/capture_head.gd

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var main = load("res://scenes/core/Main2D.tscn").instantiate()
	root.add_child(main)
	main.mouse_aim_enabled = false
	for i in 20:
		await process_frame
	var doll = main.doll
	var center: Vector2 = doll.global_position
	for shot in [["center", Vector2(0, 120)], ["right", Vector2(220, 0)], ["left", Vector2(-220, 0)]]:
		doll.aim_target = center + shot[1]
		for i in 25:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://screenshots/head_%s.png" % shot[0])
	print("saved head shots")
	quit()
